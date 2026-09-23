# The squad's lines in play (#1070): hovering and choosing a move draw the tethers and the grey
# out-of-range tiles through the real doors, a refused click shakes instead of leaving, and Squad Up
# works from a leader and stays open. The geometry itself is test_squad_lines; this is the wire.
#
# The real game scene, because every claim here is about what a hover or a click DOES -- which mode it
# leaves the board in, which cache it reads -- and a case that set game_state directly would be blind to
# exactly that (#114). Fixture shape is test_squad_cohesion's.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
# MOV is 4 + Stats.dex_mov_band -- see test_squad_cohesion, whose constants these are.
const DEX_SLOW := 0     # MOV 3
const DEX_FAST := 10    # MOV 6
# The leash these boards are built around, DECLARED so a production default cannot move the geometry
# under the cases (test_squad_cohesion's FIXTURE_COH, for its reason).
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


func _om() -> OverlayManager:
	return game.overlay_manager


func _open_ground() -> void:
	for x in range(-12, 13):
		for y in range(-12, 13):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)


func _spawn(dex: int, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.DEX: dex}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	return unit


# A leader at the origin with one member per entry of `members` ({dex, cell}), and room for them all.
func _squad(leader_dex: int, members: Array) -> Dictionary:
	_open_ground()
	var leader := _spawn(leader_dex, Vector2i.ZERO)
	leader.unit_instance.stats[Stats.Stat.COH] = FIXTURE_COH
	leader.unit_instance.stats[Stats.Stat.LDR] = 8 * Squad.MEMBER_LDR_COST
	await await_idle_frame()
	var joined: Array[Unit] = []
	for entry: Dictionary in members:
		var member := _spawn(entry["dex"], entry["cell"])
		game.squad_manager.join_squad(member, leader.squad)
		joined.append(member)
	await await_idle_frame()
	return {"leader": leader, "members": joined}


func _sorted(cells: Array) -> Array:
	var out := cells.duplicate()
	out.sort()
	return out


func _states() -> Array:
	var out := []
	for entry: Dictionary in _om().squad_tether_chords:
		out.append(entry["state"])
	return out


# Which member a stored tether belongs to, by where its chord starts -- the member's own cell.
func _tether_state_of(member: Unit) -> int:
	for entry: Dictionary in _om().squad_tether_chords:
		var start: Vector3 = (entry["chord"] as PackedVector3Array)[0]
		if Vector2i(floori(start.x), floori(start.z)) == member.get_projected_destination():
			return entry["state"]
	return -1


func _move_for(unit: Unit) -> MoveAction:
	for action in unit.squad.action_queue:
		if action.actor == unit and action.action_type == BaseAction.ActionType.MOVE:
			return action as MoveAction
	return null


# --- One answer for "walkable, but not for the squad" -------------------------------------------

# The dev: "a squad leader, when hovered, shows his full move range. When move is selected, that move
# range is cut if squad mates can't follow. These two floodfills disagreeing is problematic." The
# hover and the Move mode now paint the SAME split, and the ring shows whatever hover drew.
func test_hovering_a_leader_splits_his_range_exactly_as_choosing_his_move_does() -> void:
	var board: Dictionary = await _squad(DEX_FAST, [{"dex": DEX_SLOW, "cell": Vector2i(-3, 0)}])
	var leader: Unit = board.leader
	game.selected_unit = leader
	game.enter_move_mode(leader)
	var move_grey := _sorted(_om().invalidmove_overlay.get_used_cells())
	var move_blue := _sorted(_om().move_overlay.get_used_cells())
	assert_bool(move_grey.is_empty()).override_failure_message(
			"fixture is vacuous: this leader strands nobody anywhere, so the two cannot disagree") \
		.is_false()
	game.exit_current_mode()

	game.hover_presenter.update_hover_visuals(leader.movement.cell)
	assert_that(_sorted(_om().invalidmove_overlay.get_used_cells())).override_failure_message(
			"hovering the leader greys different tiles from choosing his move").is_equal(move_grey)
	assert_that(_sorted(_om().move_overlay.get_used_cells())).override_failure_message(
			"hovering the leader paints different blue from choosing his move").is_equal(move_blue)


# Hovering a squad unit draws the squad's lines: one tether per member, and the stroke round the range.
func test_hovering_a_squad_unit_draws_its_tethers_and_its_range() -> void:
	var board: Dictionary = await _squad(5, [{"dex": 5, "cell": Vector2i(-1, 0)},
		{"dex": 5, "cell": Vector2i(0, 2)}])
	game.hover_presenter.update_hover_visuals(board.leader.movement.cell)
	assert_int(_om().squad_tether_chords.size()).override_failure_message(
			"not one tether per member").is_equal(2)
	assert_array(_states()).override_failure_message(
			"a tether at rest is not SOLID").contains_exactly([SquadLines2D.Strain.SOLID, SquadLines2D.Strain.SOLID])
	assert_bool(_om().squad_outline.is_empty()).override_failure_message(
			"the squad's range has no stroke round it").is_false()


# --- The strained tether, and the refused click -------------------------------------------------

# A member hovering a tile it could walk to but that is past its leader's range: its tether turns red,
# which is WHY the tile is grey, said where the player is already looking.
func test_a_members_tether_turns_red_over_a_tile_past_its_leaders_range() -> void:
	var board: Dictionary = await _squad(5, [{"dex": DEX_FAST, "cell": Vector2i(-1, 0)}])
	var member: Unit = board.members[0]
	var reach: Dictionary = game.compute_move_range(member)
	assert_bool(reach.squad_unreachable.is_empty()).override_failure_message(
			"fixture is vacuous: this member can reach nothing past its leader's range").is_false()
	var past: Vector2i = reach.squad_unreachable.keys()[0]
	var inside := GridUtils.NO_CELL
	for cell: Vector2i in reach.reachable.keys():
		if cell != member.movement.cell:
			inside = cell
			break

	game.selected_unit = member
	game.enter_move_mode(member)
	game.hover_presenter.update_hover_visuals(inside)
	assert_array(_states()).override_failure_message(
			"a tile inside the range strained the tether").contains_exactly([SquadLines2D.Strain.SOLID])
	game.hover_presenter.update_hover_visuals(past)
	assert_array(_states()).override_failure_message(
			"the tether did not turn red over a tile past the leader's range") \
		.contains_exactly([SquadLines2D.Strain.STRAIN])


# ...and CLICKING that tile answers back (dev: "if they try clicking, the tether gives a shake"): the
# strained tether is plucked and the pick STAYS OPEN, where it used to leave Move silently.
func test_clicking_a_tile_past_the_leaders_range_shakes_and_keeps_choosing() -> void:
	var board: Dictionary = await _squad(5, [{"dex": DEX_FAST, "cell": Vector2i(-1, 0)}])
	var member: Unit = board.members[0]
	var reach: Dictionary = game.compute_move_range(member)
	assert_bool(reach.squad_unreachable.is_empty()).override_failure_message(
			"fixture is vacuous: this member can reach nothing past its leader's range").is_false()
	var past: Vector2i = reach.squad_unreachable.keys()[0]
	game.selected_unit = member
	game.enter_move_mode(member)
	game.hover_presenter.update_hover_visuals(past)
	assert_int(_om().tether_shake_msec).override_failure_message(
			"fixture: a shake was already stamped before the click").is_equal(-1)

	game._click_choosing_move(past)

	assert_int(game.game_state).override_failure_message(
			"the refused click left Move -- the pick should stay open").is_equal(game.GameState.CHOOSING_MOVE)
	assert_object(_move_for(member)).override_failure_message(
			"a move past the leader's range was queued").is_null()
	assert_int(_om().tether_shake_msec).override_failure_message(
			"the refused click did not pluck the tether").is_not_equal(-1)


# A LEADER hovering a tile that would strand somebody: exactly the stranded members go red, and a
# member who could follow him there stays orange -- the red names WHO, not merely that.
func test_a_leaders_stranding_tile_strains_exactly_the_members_it_strands() -> void:
	var board: Dictionary = await _squad(DEX_FAST, [{"dex": DEX_SLOW, "cell": Vector2i(-3, 0)},
		{"dex": DEX_FAST, "cell": Vector2i(1, 0)}])
	var leader: Unit = board.leader
	var slow: Unit = board.members[0]
	var fast: Unit = board.members[1]
	game.selected_unit = leader
	game.enter_move_mode(leader)
	var target := GridUtils.NO_CELL
	for cell: Vector2i in game.leader_stranding:
		var stranded: Array = game.leader_stranding[cell]
		if stranded.size() == 1 and stranded[0] == slow:
			target = cell
			break
	assert_that(target).override_failure_message(
			"fixture is vacuous: no tile strands the slow member alone").is_not_equal(GridUtils.NO_CELL)

	game.hover_presenter.update_hover_visuals(target)
	assert_int(_tether_state_of(slow)).override_failure_message(
			"the member the leader would strand is not red").is_equal(SquadLines2D.Strain.STRAIN)
	assert_int(_tether_state_of(fast)).override_failure_message(
			"a member who could follow him there went red too").is_equal(SquadLines2D.Strain.SOLID)


# --- A grey tile says only why it is grey --------------------------------------------------------

# An enemy placed so its field covers tiles a squad's move can reach, and blocks none of them: the
# reach LINES are drawn only where an enemy's field covers the hovered tile, so without one the
# "no reach lines" half of the cases below could not fail.
func _enemy_at(cell: Vector2i) -> Unit:
	var enemy: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), cell)
	assert_object(enemy).is_not_null()
	game.drop_threat_field()
	return enemy


func _red() -> Array:
	return _sorted(_om().reach_overlay.get_used_cells())


# The dev (2026-09-22): hovering a tile the unit could walk to but the squad forbids "should not get
# most readouts... Having those appear sort of read the movement as valid, while it isn't." What stays
# is the ghost and the red tether -- the reason. The red reach, the enemies' reach lines and the path
# arrow all go, including the red the previous LEGAL tile drew, which is why the case hovers one first.
func test_a_tile_past_the_leaders_range_draws_the_ghost_and_the_tether_and_nothing_else() -> void:
	var board: Dictionary = await _squad(5, [{"dex": DEX_FAST, "cell": Vector2i(-1, 0)}])
	var member: Unit = board.members[0]
	_enemy_at(Vector2i(-9, 0))
	await await_idle_frame()
	var reach: Dictionary = game.compute_move_range(member)
	var past := GridUtils.NO_CELL
	for cell: Vector2i in reach.squad_unreachable.keys():
		if not game.threat_field().attackers_of(cell).is_empty():
			past = cell
			break
	assert_that(past).override_failure_message("fixture is vacuous: no enemy reaches a tile past "
			+ "the leader's range, so missing reach lines could not be seen").is_not_equal(GridUtils.NO_CELL)
	var inside := GridUtils.NO_CELL
	for cell: Vector2i in reach.reachable.keys():
		if cell != member.movement.cell:
			inside = cell
			break

	game.selected_unit = member
	game.enter_move_mode(member)
	game.hover_presenter.update_hover_visuals(inside)
	assert_bool(_red().is_empty()).override_failure_message(
			"fixture: a legal tile drew no red, so its clearing could not be seen").is_false()

	game.hover_presenter.update_hover_visuals(past)
	assert_array(_red()).override_failure_message(
			"a grey tile still shows the unit's attack range").is_empty()
	assert_int(_om().reach_line_marks.size()).override_failure_message(
			"a grey tile still shows who could hit you there").is_equal(0)
	assert_object(_om().hover_move_preview).override_failure_message(
			"a grey tile still draws a path arrow").is_null()
	assert_int(_om().hover_ghost_sprites.size()).override_failure_message(
			"the ghost the red tether runs to is missing").is_equal(1)
	assert_array(_states()).override_failure_message(
			"the tether saying WHY the tile is grey is not red").contains_exactly([SquadLines2D.Strain.STRAIN])


# ...and the same for a LEADER on a tile that would strand somebody, which drew its reach on purpose
# until the dev's ruling reversed it.
func test_a_leaders_stranding_tile_draws_no_reach_and_no_reach_lines() -> void:
	var board: Dictionary = await _squad(DEX_FAST, [{"dex": DEX_SLOW, "cell": Vector2i(-3, 0)}])
	var leader: Unit = board.leader
	_enemy_at(Vector2i(10, 0))
	await await_idle_frame()
	game.selected_unit = leader
	game.enter_move_mode(leader)
	var target := GridUtils.NO_CELL
	for cell: Vector2i in game.leader_stranding:
		# The cache names EVERY destination, a followable one with nobody stranded.
		if not (game.leader_stranding[cell] as Array).is_empty() 				and not game.threat_field().attackers_of(cell).is_empty():
			target = cell
			break
	assert_that(target).override_failure_message("fixture is vacuous: no enemy reaches a tile "
			+ "that strands somebody").is_not_equal(GridUtils.NO_CELL)
	var followable := GridUtils.NO_CELL
	for cell: Vector2i in game.leader_followable:
		if cell != leader.movement.cell:
			followable = cell
			break
	game.hover_presenter.update_hover_visuals(followable)
	assert_bool(_red().is_empty()).override_failure_message(
			"fixture: a legal tile drew no red, so its clearing could not be seen").is_false()

	game.hover_presenter.update_hover_visuals(target)
	assert_array(_red()).override_failure_message(
			"a stranding tile still shows the leader's attack range").is_empty()
	assert_int(_om().reach_line_marks.size()).override_failure_message(
			"a stranding tile still shows who could hit him there").is_equal(0)


# Group Move's stranding tile never drew a reach of its own -- but it left the one the last legal tile
# drew standing, which reads the same.
func test_a_group_moves_stranding_tile_clears_the_red_the_last_tile_drew() -> void:
	var board: Dictionary = await _squad(DEX_FAST, [{"dex": DEX_SLOW, "cell": Vector2i(-3, 0)}])
	var leader: Unit = board.leader
	game.selected_unit = leader
	game.enter_group_move_mode(leader)
	var followable := GridUtils.NO_CELL
	for cell: Vector2i in game.leader_followable:
		if cell != leader.movement.cell:
			followable = cell
			break
	game.hover_presenter.update_hover_visuals(followable)
	assert_bool(_red().is_empty()).override_failure_message(
			"fixture: a followable tile drew no red, so its clearing could not be seen").is_false()

	var stranding := GridUtils.NO_CELL
	for cell: Vector2i in game.leader_stranding:
		# The cache names EVERY destination, a followable one with nobody stranded.
		if not (game.leader_stranding[cell] as Array).is_empty():
			stranding = cell
			break
	assert_that(stranding).override_failure_message(
			"fixture is vacuous: no tile strands anybody").is_not_equal(GridUtils.NO_CELL)
	game.hover_presenter.update_hover_visuals(stranding)
	assert_array(_red()).override_failure_message(
			"a stranding tile left the last tile's attack range standing").is_empty()


# Off the whole range the red goes back to the unit's own tile -- what Move painted when it opened --
# where it used to stay wherever the last legal tile had put it.
func test_hovering_off_the_range_puts_the_red_back_where_move_opened_it() -> void:
	var board: Dictionary = await _squad(5, [{"dex": 5, "cell": Vector2i(-1, 0)}])
	var member: Unit = board.members[0]
	game.selected_unit = member
	game.enter_move_mode(member)
	var opened := _red()
	var reach: Dictionary = game.compute_move_range(member)
	var inside := GridUtils.NO_CELL
	for cell: Vector2i in reach.reachable.keys():
		if cell != member.movement.cell:
			game.hover_presenter.update_hover_visuals(cell)
			if _red() != opened:
				inside = cell
				break
	assert_that(inside).override_failure_message("fixture is vacuous: every legal tile draws the "
			+ "red Move opened with, so a stale one could not be told apart").is_not_equal(GridUtils.NO_CELL)
	var outside := Vector2i(12, 12)
	assert_bool(reach.reachable.has(outside) or reach.squad_unreachable.has(outside)) \
		.override_failure_message("fixture: the 'outside' tile is inside the range").is_false()

	game.hover_presenter.update_hover_visuals(outside)
	assert_array(_red()).override_failure_message(
			"off the range, the red still stands where the last legal tile put it").is_equal(opened)


# --- Squad Up from the leader, and a pick that stays open ---------------------------------------

# #1043: a friend tried to grow his squad from the leader and could not -- the verb vanished the moment
# the squad existed. It is offered to a leader now, draws a GHOST tether from every candidate, and the
# pick stays open until nobody is left (dev), so a squad is built in one gesture.
func test_a_leader_squads_up_and_the_pick_stays_open_until_nobody_is_left() -> void:
	var board: Dictionary = await _squad(5, [{"dex": 5, "cell": Vector2i(-1, 0)}])
	var leader: Unit = board.leader
	var first := _spawn(5, Vector2i(1, 0))
	var second := _spawn(5, Vector2i(0, 1))
	await await_idle_frame()
	assert_bool(game.squad_manager.can_create_any_squad(leader)).override_failure_message(
			"Squad Up is not offered to a leader").is_true()

	game.create_squad(leader)
	assert_int(game.game_state).is_equal(game.GameState.PICKING_TARGET)
	var ghosts := _states().filter(func(s: int) -> bool: return s == SquadLines2D.Strain.GHOST)
	assert_int(ghosts.size()).override_failure_message(
			"not one ghost tether per candidate").is_equal(2)

	game._click_picking_target(first.movement.cell)
	assert_bool(leader.squad.get_members().has(first)).override_failure_message(
			"the first pick did not join").is_true()
	assert_int(game.game_state).override_failure_message(
			"the pick closed with a candidate still left").is_equal(game.GameState.PICKING_TARGET)

	game._click_picking_target(second.movement.cell)
	assert_bool(leader.squad.get_members().has(second)).is_true()
	assert_int(game.game_state).override_failure_message(
			"the pick stayed open with nobody left to recruit").is_not_equal(game.GameState.PICKING_TARGET)


# --- The count beside the crown (#1070) ----------------------------------------------------------

# The dev: "as we start picking, there's no real way to know how many we can pick... we should have a
# 0/3 -> 1/3 etc over the squad leader's head, as we pick, only while picking like that." Then, on
# playing it: "how many people can be in the squad, total. So we'd always start with a 1/X, because of
# the leader." The squad's size over its capacity, and it moves one per pick.
func test_squad_up_counts_the_squad_against_its_capacity() -> void:
	var board: Dictionary = await _squad(5, [])
	var leader: Unit = board.leader
	var first := _spawn(5, Vector2i(1, 0))
	_spawn(5, Vector2i(0, 1))
	await await_idle_frame()
	var room: int = leader.squad.max_size()
	assert_int(room).override_failure_message("fixture: no room for the leader, both candidates and one more, so "
			+ "the pick would close on the first join").is_greater(3)

	game.create_squad(leader)
	assert_object(_om().squad_count_leader()).override_failure_message(
			"opening Squad Up put no count on the leader").is_same(leader)
	assert_str(_om().squad_count_text()).override_failure_message(
			"a solo leader's count does not start at 1 -- the leader is part of the squad").is_equal("1/%d" % room)

	game._click_picking_target(first.movement.cell)
	assert_str(_om().squad_count_text()).override_failure_message(
			"the count did not follow the pick").is_equal("2/%d" % room)
	assert_float(_om().squad_count_alpha).is_equal(1.0)


# A cancel changed nothing, so the count just goes -- no hold, no fade.
func test_a_cancelled_squad_up_takes_its_count_away_at_once() -> void:
	var board: Dictionary = await _squad(5, [])
	var leader: Unit = board.leader
	_spawn(5, Vector2i(1, 0))
	await await_idle_frame()
	game.create_squad(leader)
	assert_object(_om().squad_count_leader()).is_same(leader)

	var off := Vector2i(9, 9)
	assert_bool(game.target_pick_cells.has(off)).override_failure_message(
			"fixture: the 'off the set' cell is a candidate").is_false()
	game._click_picking_target(off)
	assert_int(game.game_state).override_failure_message(
			"fixture: clicking off the set did not cancel the pick").is_not_equal(game.GameState.PICKING_TARGET)
	assert_object(_om().squad_count_leader()).override_failure_message(
			"a cancelled Squad Up left its count standing").is_null()


# The dev: "It should hold a brief 3/3, then fade." The join that fills the squad closes the pick, and
# leaving the mode must not take the last number with it.
func test_the_join_that_fills_the_squad_holds_its_count_then_fades_it() -> void:
	var board: Dictionary = await _squad(5, [])
	var leader: Unit = board.leader
	leader.unit_instance.stats[Stats.Stat.LDR] = 2 * Squad.MEMBER_LDR_COST   # room for exactly two
	var first := _spawn(5, Vector2i(1, 0))
	var second := _spawn(5, Vector2i(0, 1))
	await await_idle_frame()
	assert_int(leader.squad.max_size() - 1).override_failure_message(
			"fixture: the squad is not sized for exactly two recruits").is_equal(2)
	var hold := OverlayManager.SQUAD_COUNT_HOLD
	var fade := OverlayManager.SQUAD_COUNT_FADE
	OverlayManager.SQUAD_COUNT_HOLD = 0.05
	OverlayManager.SQUAD_COUNT_FADE = 0.05

	game.create_squad(leader)
	game._click_picking_target(first.movement.cell)
	game._click_picking_target(second.movement.cell)
	assert_int(game.game_state).override_failure_message(
			"fixture: the pick stayed open on a full squad").is_not_equal(game.GameState.PICKING_TARGET)
	assert_object(_om().squad_count_leader()).override_failure_message(
			"closing the pick took the full count with it").is_same(leader)
	assert_str(_om().squad_count_text()).is_equal("3/3")
	assert_float(_om().squad_count_alpha).is_equal(1.0)

	await await_millis(400)
	assert_object(_om().squad_count_leader()).override_failure_message(
			"the full count never faded out").is_null()
	OverlayManager.SQUAD_COUNT_HOLD = hold
	OverlayManager.SQUAD_COUNT_FADE = fade
