# Squad cohesion: how far a squadmate may end from its leader, and what Group Move does when the
# leader outruns one (built 2026-08-04, from bug-reports/2026-08-04_17-54-30).
#
# The rule is strict — a squadmate must end inside the leader's projected COH bubble (#142) — and
# Group Move splits into two outcomes around it:
#   Case 1  the member falls BEHIND but still lands inside the bubble. Legal; its arrow draws green
#           (MoveAction.is_trailing).
#   Case 2  the member cannot reach the bubble at all. The destination is refused, and painted red
#           before the click by GroupMoveSolver.followable_destinations.
#
# The overlay and the refusal must agree, because the reported bug was a click that looked like it
# queued a ghost order: the tile was green, the plan was authored, the validator refused it, the
# rollback undid it, and the squad was left active on a queue of hold rows.
#
# The real game scene, not play/board_builder.gd: the hold-position filler is queued by game.gd's
# squad_became_active handler, and `active_squad` — what keeps the queue panel open — is state a
# headless board never grows. Fixture is tests/ui/test_game_scene_smoke.gd's; the instanced root
# MUST be named "Main" under /root or game.gd's absolute /root/Main/DevOverlay lookup is null (#114).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const F := preload("res://tests/support/job_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const WATER_ATLAS := Vector2i(5, 6)   # walkable=false (Waterwalk-only) in TestTiles.tres

# MOV is 4 + Stats.dex_mov_band: DEX 0-3 -> 3 | 4-5 -> 4 | 6-8 -> 5 | 9+ -> 6. Named rather than
# inlined so a band retune fails the assertion in _squad(), not silently the whole file.
const DEX_SLOW := 0     # MOV 3
const DEX_FAST := 10    # MOV 6

# The leash every _squad() board is built around, DECLARED rather than inherited from
# Stats.STAT_DEFAULTS[COH]. These boards are geometry — which cells fall in and out of the bubble IS
# the thing under test — so a production default moving must not quietly turn a Case 2 board into a
# Case 1 board or make an out-of-range order legal. It did exactly that when the default went 3 -> 4
# (2026-08-06), and the same fixtures had been one point away from silent all along.
const FIXTURE_COH := 3

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# ------------------------------------------------------------------------------
#  Fixtures
# ------------------------------------------------------------------------------

# Open ground, a leader at the origin and one member at `member_offset`.
func _squad(leader_dex: int, member_dex: int, member_offset: Vector2i) -> Dictionary:
	for x in range(-12, 13):
		for y in range(-12, 13):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)

	var leader: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.DEX: leader_dex}, Team.Faction.PLAYER), Vector2i.ZERO)
	var member: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.DEX: member_dex}, Team.Faction.PLAYER), member_offset)
	assert_object(leader).is_not_null()
	assert_object(member).is_not_null()
	leader.unit_instance.stats[Stats.Stat.COH] = FIXTURE_COH
	await await_idle_frame()
	game.squad_manager.join_squad(member, leader.squad)
	# The MOV premise belongs to each test, not here — one of them wants an EQUAL pair.
	return {"leader": leader, "member": member, "squad": leader.squad}


# Through the real door: enter_group_move_mode is what builds game.group_move_followable, and the
# click reads it. Setting game_state directly skips that and refuses everything (#114's lesson —
# a test that skips the ordering is blind to it).
func _group_move_to(leader: Unit, destination: Vector2i) -> void:
	game.selected_unit = leader
	game.enter_group_move_mode(leader)
	game._click_choosing_group_move(destination)


func _move_for(unit: Unit) -> MoveAction:
	for action in unit.squad.action_queue:
		if action.actor == unit and action.action_type == BaseAction.ActionType.MOVE:
			return action as MoveAction
	return null


# Queue an individual move the way _click_choosing_move does, and report whether the gate took it.
func _order_move(unit: Unit, destination: Vector2i) -> bool:
	var reach := RulesService.compute_move_range(unit, game._board())
	assert_bool(reach.reachable.has(destination) or reach.squad_unreachable.has(destination)) \
		.override_failure_message("fixture: %s cannot physically reach %s" % [unit.get_unit_name(), str(destination)]) \
		.is_true()
	var move := MoveAction.new()
	move.init(unit, RulesService.reconstruct_path(reach.came_from, unit.movement.cell, destination),
		GridUtils.get_terrain_icon_at_cell(game.grid, destination))
	return game.squad_manager.queue_action(unit.squad, move)


# ------------------------------------------------------------------------------
#  Case 1 — falls behind, stays in range
# ------------------------------------------------------------------------------

# The narrowest Case 1 the authorable stat range allows: a default-statline leader (MOV 4) and one
# DEX<=3 member (MOV 3), the member one tile away, the leader stepping its full move directly away.
# Falsified by pinning is_trailing to false in GroupMoveSolver: the green-arrow assertion fails and
# the two gap bounds still pass, so this case really does test the marking and not just the geometry.
func test_a_member_that_falls_behind_but_stays_in_range_is_legal() -> void:
	var board: Dictionary = await _squad(5, DEX_SLOW, Vector2i(-1, 0))
	var destination := Vector2i(0, -4)
	assert_int(board.leader.get_mov()).override_failure_message("fixture: the leader cannot outrun anyone") \
		.is_greater(board.member.get_mov())

	_group_move_to(board.leader, destination)

	assert_bool(game.squad_manager.squad_has_invalid_actions(board.squad)) \
		.override_failure_message("Case 1 was refused").is_false()

	var member_move := _move_for(board.member)
	assert_object(member_move).override_failure_message("the member was given no order").is_not_null()

	var was := GridUtils.manhattan_distance(Vector2i(-1, 0), Vector2i.ZERO)
	var now := GridUtils.manhattan_distance(member_move.get_destination(), destination)
	assert_int(now).override_failure_message("the member kept up — this is not Case 1").is_greater(was)
	assert_int(now).override_failure_message("the member fell OUT of range — this is Case 2") \
		.is_less_equal(board.squad.get_max_squad_range())
	assert_bool(member_move.is_trailing) \
		.override_failure_message("falling behind did not mark the arrow").is_true()


# A member that keeps formation must NOT go green, or the signal means nothing.
func test_a_member_that_keeps_up_is_not_marked_as_trailing() -> void:
	var board: Dictionary = await _squad(DEX_FAST, DEX_FAST, Vector2i(-1, 0))
	assert_int(board.leader.get_mov()).override_failure_message("fixture: the pair is not equally fast") \
		.is_equal(board.member.get_mov())

	_group_move_to(board.leader, Vector2i(0, -4))

	var member_move := _move_for(board.member)
	assert_object(member_move).is_not_null()
	assert_bool(member_move.is_trailing) \
		.override_failure_message("a member that kept formation was marked as trailing").is_false()


# ------------------------------------------------------------------------------
#  Case 2 — cannot reach the bubble at all
# ------------------------------------------------------------------------------

func _case_two() -> Dictionary:
	# MOV 6 leader, MOV 3 member three tiles behind: nothing within the leader's COH of (0,-6) is inside
	# the member's move, so the whole squad cannot go there.
	var board: Dictionary = await _squad(DEX_FAST, DEX_SLOW, Vector2i(0, 3))
	board["destination"] = Vector2i(0, -6)

	assert_int(board.leader.get_mov()).override_failure_message("fixture: the leader cannot outrun anyone") \
		.is_greater(board.member.get_mov())
	assert_int(RulesService.compute_move_range(board.member, game._board(), board.destination).reachable.size()) \
		.override_failure_message("fixture: the member CAN reach cohesion range — this is Case 1") \
		.is_equal(0)
	return board


# The overlay's own question. enter_group_move_mode paints anything missing from this set red.
func test_an_unfollowable_destination_is_not_offered() -> void:
	var board: Dictionary = await _case_two()
	var followable: Dictionary = GroupMoveSolver.followable_destinations(
		board.squad, game._board(), [board.destination])
	assert_bool(followable.has(board.destination)) \
		.override_failure_message("a destination the squad cannot follow to was painted green").is_false()


# The reported bug: the click authored a plan, the validator refused it, and the squad was left
# holding. Clicking a red tile must queue nothing at all and leave the panel closed.
func test_clicking_an_unfollowable_destination_queues_nothing() -> void:
	var board: Dictionary = await _case_two()

	_group_move_to(board.leader, board.destination)

	assert_int(board.squad.action_queue.size()) \
		.override_failure_message("a refused group move left orders behind").is_equal(0)
	assert_object(game.squad_manager.active_squad) \
		.override_failure_message("squad left active behind a hold-only queue: no X, no Execute").is_null()
	assert_that(board.leader.movement.cell).is_equal(Vector2i.ZERO)


# The leader's own reach still offers plenty — Case 2 must cost the squad that ONE destination, not
# the button. Without this, refusing everything would pass every assertion above.
func test_a_case_two_board_still_offers_followable_destinations() -> void:
	var board: Dictionary = await _case_two()
	var destinations: Array = game.get_move_range(
		RulesService.compute_move_range(board.leader, game._board()), board.leader)
	var followable: Dictionary = GroupMoveSolver.followable_destinations(
		board.squad, game._board(), destinations)
	assert_int(followable.size()).override_failure_message("the whole move range was refused").is_greater(0)
	assert_int(followable.size()).override_failure_message("nothing was refused — fixture is not Case 2") \
		.is_less(destinations.size())


# ------------------------------------------------------------------------------
#  Individual moves are strict, whatever the leader is doing
# ------------------------------------------------------------------------------

# The hole found in play 2026-08-04: relaxing cohesion for Group Move let a squadmate be ORDERED
# out of the leader's range on its own, and the order queued and executed. A leader running off is
# not permission for the member to wander. Falsified by restoring the `may_trail` allowance.
func test_a_member_cannot_be_individually_ordered_outside_the_leader_range() -> void:
	var board: Dictionary = await _squad(DEX_FAST, DEX_SLOW, Vector2i(0, 3))

	assert_bool(_order_move(board.leader, Vector2i(0, -6))) \
		.override_failure_message("the leader's own move was refused").is_true()

	# (0,1) closes the gap to the leader's projected cell from 9 to 7 — still far outside
	# the leader's COH, and exactly the move the relaxed rule wrongly accepted.
	assert_bool(_order_move(board.member, Vector2i(0, 1))) \
		.override_failure_message("a squadmate was ordered outside its leader's range").is_false()


# A hold is the absence of an order, so it is judged the same as any other destination: the squad
# simply cannot author a plan that strands a member. This is #103's mechanism and it stays.
func test_a_leader_may_not_strand_a_member_by_moving_alone() -> void:
	var board: Dictionary = await _squad(DEX_FAST, DEX_SLOW, Vector2i(0, 3))

	assert_bool(_order_move(board.leader, Vector2i(0, -6))).is_true()
	game.squad_manager.setup_hold_move_actions(board.squad)
	game.squad_manager.validate_squad_plan(board.squad)

	assert_bool(game.squad_manager.squad_has_invalid_actions(board.squad)) \
		.override_failure_message("a leader walked out of cohesion and the plan stayed legal").is_true()


# ------------------------------------------------------------------------------
#  The rule itself
# ------------------------------------------------------------------------------

func test_cohesion_is_the_leader_range_on_open_ground() -> void:
	# On unobstructed ground, path distance == Manhattan distance, so the leash edge sits exactly
	# where it always did. The wall test below is where the two metrics part company.
	var board: Dictionary = await _squad(DEX_FAST, DEX_SLOW, Vector2i(0, 3))
	var squad: Squad = board.squad
	var member: Unit = board.member
	var leader_cell := Vector2i.ZERO

	var reach := squad.get_max_squad_range()
	assert_bool(SquadCohesion.in_range(squad, leader_cell, member, Vector2i(0, reach), game._board())).is_true()
	assert_bool(SquadCohesion.in_range(squad, leader_cell, member, Vector2i(0, reach + 1), game._board())).is_false()
	# Closing the gap from outside is NOT an exemption — that allowance was the bug above.
	assert_bool(SquadCohesion.in_range(squad, leader_cell, member, Vector2i(0, 9), game._board())).is_false()


# THE RULE (#151): walls block cohesion. A cell Manhattan-adjacent to the leader but on the far
# side of solid rock is NOT in the squad — you cannot order someone through a wall you can't see
# or hear through. Falsify by reverting SquadCohesion.field to the Manhattan form: this goes red
# while the open-ground test above stays green.
func test_a_wall_blocks_cohesion() -> void:
	var board: Dictionary = await _squad(DEX_FAST, DEX_SLOW, Vector2i(0, 3))
	var squad: Squad = board.squad
	var member: Unit = board.member
	var leader_cell := Vector2i.ZERO

	# A wall column just right of the leader, tall enough that no path within COH rounds it.
	var reach := squad.get_max_squad_range()
	for y in range(-(reach + 1), reach + 2):
		game.grid.erase_cell(Vector2i(1, y))

	assert_bool(SquadCohesion.in_range(squad, leader_cell, member, Vector2i(2, 0), game._board())) \
		.override_failure_message("a cell Manhattan-2 away THROUGH A WALL counted as in the squad").is_false()
	# The same side as the leader is unaffected.
	assert_bool(SquadCohesion.in_range(squad, leader_cell, member, Vector2i(0, 2), game._board())).is_true()


# PER-MEMBER (#151, the #115 shape in cohesion form): traversal is per-unit, so a Waterwalker's
# bubble crosses water its plain squadmate's does not. One rule, two subjects, two answers.
func test_a_waterwalkers_cohesion_bubble_crosses_water() -> void:
	var scout: JobData = JobCatalog.get_job("scout")
	var snap: Dictionary = F.snapshot(scout)
	var ability := AbilityData.new()
	ability.id = Abilities.Id.WATERWALK
	scout.ability_pool = [ability]

	var board: Dictionary = await _squad(DEX_FAST, DEX_SLOW, Vector2i(0, 3))
	var squad: Squad = board.squad
	var plain: Unit = board.member
	var walker: Unit = board.leader   # any unit serves as the walking SUBJECT; squad only sets COH
	walker.unit_instance.add_job("scout")
	var leader_cell := Vector2i.ZERO

	# A water column just right of the leader, too tall to round within COH.
	var reach := squad.get_max_squad_range()
	for y in range(-(reach + 1), reach + 2):
		game.grid.set_cell(Vector2i(1, y), GRASS_SOURCE, WATER_ATLAS)

	var across := Vector2i(2, 0)
	assert_bool(SquadCohesion.in_range(squad, leader_cell, plain, across, game._board())) \
		.override_failure_message("water counted as squad-transparent for a plain member").is_false()
	assert_bool(SquadCohesion.in_range(squad, leader_cell, walker, across, game._board())) \
		.override_failure_message("a Waterwalker's bubble stopped at the shore").is_true()

	F.restore(scout, snap)


# ------------------------------------------------------------------------------
#  Loss-of-contact ejection (#151's backstop)
# ------------------------------------------------------------------------------

# Movement can no longer AUTHOR a split (the validator refuses it), but displacement nobody chose
# still can: a shove around a corner, ice melting under a formation. A member out of path-contact
# with its leader leaves into a solo squad at the next settle point.
func test_a_member_out_of_contact_is_ejected_to_a_solo_squad() -> void:
	var board: Dictionary = await _squad(DEX_FAST, DEX_SLOW, Vector2i(0, 3))
	var squad: Squad = board.squad
	var member: Unit = board.member
	var reach := squad.get_max_squad_range()

	member.movement.set_cell(Vector2i(0, reach + 4))   # displaced, as a shove or a melt would
	game.squad_manager.enforce_contact()

	assert_bool(squad.get_members().has(member)) \
		.override_failure_message("an out-of-contact member stayed in the squad").is_false()
	assert_bool(member.is_leader()) \
		.override_failure_message("the ejected member did not land in a solo squad").is_true()


# THE WIRE: enforce_contact must actually fire when a pass settles — a backstop nobody calls is
# the #103 lesson again. Any squad's execution sweeps EVERY squad, which is the point: the split
# member's own squad can't execute (its plan reads invalid), so someone else's pass heals it.
func test_a_resolution_pass_ejects_an_out_of_contact_member() -> void:
	var board: Dictionary = await _squad(DEX_FAST, DEX_SLOW, Vector2i(0, 3))
	var squad: Squad = board.squad
	var member: Unit = board.member
	var bystander: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(6, 0))
	var reach := squad.get_max_squad_range()

	member.movement.set_cell(Vector2i(0, reach + 4))
	await game.order_executor.execute_orders(bystander)

	assert_bool(squad.get_members().has(member)) \
		.override_failure_message("the settle sweep did not run on pass end").is_false()


# THE WIRE (#142): editing COH must move the GATE, not just the getter. A getter returning 5 while
# the gate still walks to a hardcoded 3 would pass every assertion above — the fixture's
# leader sits at FIXTURE_COH, so only a non-default COH can tell the two apart.
func test_editing_the_leaders_coh_moves_the_cohesion_gate() -> void:
	var board: Dictionary = await _squad(DEX_FAST, DEX_SLOW, Vector2i(0, 3))
	var squad: Squad = board.squad
	var member: Unit = board.member
	var leader_cell := Vector2i.ZERO
	var leader: Unit = board.leader
	var was := squad.get_max_squad_range()

	# Exactly what UnitEditorTool._apply does on Save.
	leader.unit_instance.stats[Stats.Stat.COH] = was + 2

	assert_int(squad.get_max_squad_range()).is_equal(was + 2)
	# The tile that was one step too far is now legal, and the new edge+1 is not.
	assert_bool(SquadCohesion.in_range(squad, leader_cell, member, Vector2i(0, was + 1), game._board())) \
		.override_failure_message("a widened COH did not reach the gate").is_true()
	assert_bool(SquadCohesion.in_range(squad, leader_cell, member, Vector2i(0, was + 3), game._board())) \
		.override_failure_message("the widened gate has no upper edge").is_false()


# The two FORMS of the cohesion rule must accept the same set. `in_range` decides (validator, solver,
# squad-up gates) and `cells` draws and iterates (the SQUADRANGE overlay, the squad-up overlays, the
# solver's dilation) -- so a disagreement means the board paints a tile the validator refuses, or a
# recruit shows as joinable and then isn't. They were nine hand-rolled copies before the #151 prep
# consolidated them onto SquadCohesion; this is what stops them drifting apart again, and it is the
# thing most likely to break when the metric goes path-based.
func test_the_drawn_bubble_and_the_enforced_bubble_are_the_same_set() -> void:
	var board: Dictionary = await _squad(DEX_FAST, DEX_SLOW, Vector2i(0, 3))
	var squad: Squad = board.squad
	var member: Unit = board.member
	var leader_cell := Vector2i(6, 6)

	# A wall segment inside the sweep window, so the invariant is checked where the path metric
	# actually bends -- on open ground the two forms could agree by accident of both being diamonds.
	for y in range(4, 9):
		game.grid.erase_cell(Vector2i(8, y))

	var drawn := {}
	for cell in SquadCohesion.cells(squad, leader_cell, member, game._board()):
		drawn[cell] = true

	# Sweep a window comfortably wider than the bubble, so both an omission and an over-draw fail.
	var reach := squad.get_max_squad_range()
	var margin := reach + 2
	var checked := 0
	for x in range(leader_cell.x - margin, leader_cell.x + margin + 1):
		for y in range(leader_cell.y - margin, leader_cell.y + margin + 1):
			var cell := Vector2i(x, y)
			checked += 1
			assert_bool(drawn.has(cell)) \
				.override_failure_message("drawn/enforced disagree at %s" % cell) \
				.is_equal(SquadCohesion.in_range(squad, leader_cell, member, cell, game._board()))
	assert_int(checked).is_greater(reach * reach)   # the sweep really covered the bubble and past it


# ------------------------------------------------------------------------------
#  Assignment contention — the overlay must not promise a formation the solver drops
# ------------------------------------------------------------------------------

# Placement is first-come-first-served with no backtracking, so a member with ONE option must pick
# before members with several, or it finds its cell taken and lands outside cohesion — refusing a
# destination that had a perfectly good formation. Found on Castle Assault 2026-08-04, where member
# order left 6 of one squad's 16 green destinations unplaceable. Minimised here:
#
#   corridor x=0 from y=3 down to y=-4, plus one side cell (1,-2). Leader (0,0) -> (0,-4).
#   An allied non-squadmate plugs (0,-3): bodies do not block traversal, but compute_move_range
#   drops their cells as DESTINATIONS, which is what pushes the near members onto (0,-2)/(0,-1).
#
#   M1 (0,1): (0,-1) (0,-2) (1,-2)      M2 (0,2): (0,-1) (0,-2)      M3 (0,3): (0,-1)
#
# Three members, three cells — a matching exists. Member order gives (0,-2) to M1 and (0,-1) to M2,
# and M3 is left with nothing.
func _contention_board() -> Dictionary:
	for y in range(-4, 4):
		game.grid.set_cell(Vector2i(0, y), GRASS_SOURCE, GRASS_ATLAS)
	game.grid.set_cell(Vector2i(1, -2), GRASS_SOURCE, GRASS_ATLAS)

	var destination := Vector2i(0, -4)
	var far_slot := Vector2i(0, -1)   # the ONE cell the furthest member can both reach and legally hold

	var leader: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 6}, Team.Faction.PLAYER), Vector2i.ZERO)
	# DECLARED, not inherited: the board only demonstrates contention while the far member has exactly
	# one slot, which is true iff the leash reaches from the destination to far_slot and no further.
	# It rode on Stats.STAT_DEFAULTS[COH] being 3 until that moved to 4 and (0,0) became a second
	# option (2026-08-06). Derived from the geometry above, so moving either cell re-derives it.
	leader.unit_instance.stats[Stats.Stat.COH] = GridUtils.manhattan_distance(destination, far_slot)

	var members: Array[Unit] = []
	for y in [1, 2, 3]:
		members.append(game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(0, y)))
	game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(0, -3))   # the plug
	await await_idle_frame()
	for member in members:
		game.squad_manager.join_squad(member, leader.squad)

	var board: Dictionary = {"leader": leader, "squad": leader.squad, "destination": destination,
		"near": members[0], "mid": members[1], "far": members[2]}

	# The premise: the far member has exactly one option, and three distinct cells exist for three
	# members. Without both, this board proves nothing about contention.
	var options: Dictionary = RulesService.compute_move_range(board.far, game._board(), board.destination).reachable
	assert_int(options.size()).override_failure_message(
		"fixture: the far member has %d options, not 1 — %s" % [options.size(), str(options.keys())]).is_equal(1)
	var union := {}
	for member in members:
		for cell in RulesService.compute_move_range(member, game._board(), board.destination).reachable.keys():
			union[cell] = true
	assert_int(union.size()).override_failure_message(
		"fixture: %d cells for 3 members — no matching exists, so this is refusal, not contention" % union.size()) \
		.is_greater_equal(3)
	return board


# Falsified by sorting `order` back into member order in GroupMoveSolver.plan: the far member is
# left unplaced, its hold is out of cohesion, and the whole group move is refused.
func test_a_constrained_member_is_placed_before_members_with_more_options() -> void:
	var board: Dictionary = await _contention_board()

	var placed := {}
	for move in GroupMoveSolver.plan(board.squad, board.destination, game._board()):
		placed[move.actor] = move.get_destination()

	for member in board.squad.get_members():
		if member == board.leader:
			continue
		assert_bool(placed.has(member)).override_failure_message(
			"%s @ %s was left unplaced — a formation existed" % [member.get_unit_name(), str(member.movement.cell)]) \
			.is_true()

	# Distinct cells, or "everyone was placed" would pass on a solver that stacked them.
	var cells := {}
	for member in placed:
		cells[placed[member]] = true
	assert_int(cells.size()).override_failure_message("two members were sent to the same cell").is_equal(placed.size())


# The whole point of the ordering fix: the destination stays GREEN and clicking it works. Before it,
# followable_destinations said green and the click queued nothing — the original ghost-order bug.
func test_a_contended_destination_stays_green_and_queues() -> void:
	var board: Dictionary = await _contention_board()

	var followable: Dictionary = GroupMoveSolver.followable_destinations(
		board.squad, game._board(), [board.destination])
	assert_bool(followable.has(board.destination)) \
		.override_failure_message("a destination with a valid formation was painted red").is_true()

	_group_move_to(board.leader, board.destination)

	assert_bool(game.squad_manager.squad_has_invalid_actions(board.squad)) \
		.override_failure_message("the contended formation was refused").is_false()
	assert_int(board.squad.action_queue.size()).override_failure_message(
		"a green destination queued nothing — the overlay is lying again").is_greater(0)


# ------------------------------------------------------------------------------
#  Genuine infeasibility — a corridor that collapses the squad onto one cell
# ------------------------------------------------------------------------------

# The other half: sometimes no formation exists at all, and then the tile really must be red. A
# one-wide hallway with the far side plugged leaves both members able to reach exactly ONE bubble
# cell between them, so no ordering saves it. followable_destinations catches this by counting
# distinct reachable cells against the member count.
#
# Falsified by removing that union check: the destination goes green and the click queues nothing.
func test_a_corridor_that_collapses_the_squad_onto_one_cell_is_refused() -> void:
	for x in range(0, 13):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)

	var leader: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 6}, Team.Faction.PLAYER), Vector2i(5, 0))
	var a: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.DEX: DEX_SLOW}, Team.Faction.PLAYER), Vector2i(2, 0))
	var b: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.DEX: DEX_SLOW}, Team.Faction.PLAYER), Vector2i(3, 0))
	game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(6, 0))   # allied plug
	await await_idle_frame()
	game.squad_manager.join_squad(a, leader.squad)
	game.squad_manager.join_squad(b, leader.squad)

	var squad: Squad = leader.squad
	var destination := Vector2i(8, 0)
	# The single cell both slow members collapse onto — the leader's own, which it vacates. DECLARED
	# rather than inherited from Stats.STAT_DEFAULTS[COH]: the corridor only collapses while the
	# leash reaches from the destination back to exactly this cell and no further, which quietly
	# stopped being true when the default moved 3 -> 4 (2026-08-06).
	var collapse_cell := Vector2i(5, 0)
	leader.unit_instance.stats[Stats.Stat.COH] = GridUtils.manhattan_distance(destination, collapse_cell)

	assert_bool(RulesService.compute_move_range(leader, game._board()).reachable.has(destination)) \
		.override_failure_message("fixture: the leader cannot reach the destination at all").is_true()

	# The premise: one cell, two members. No assignment exists, however it is ordered.
	var union := {}
	for member in [a, b]:
		for cell in RulesService.compute_move_range(member, game._board(), destination).reachable.keys():
			union[cell] = true
	assert_int(union.size()).override_failure_message(
		"fixture: %d cells for 2 members — this corridor does not collapse them" % union.size()).is_equal(1)

	assert_bool(GroupMoveSolver.followable_destinations(squad, game._board(), [destination]).has(destination)) \
		.override_failure_message("an impossible destination was painted green").is_false()

	_group_move_to(leader, destination)
	assert_int(squad.action_queue.size()).override_failure_message("a refused destination queued orders").is_equal(0)
