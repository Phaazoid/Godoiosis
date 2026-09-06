# The AI side of Guard and Overwatch (#751). Both shipped NEVER on every archetype when #413/#414
# landed, deferred whole; Hold and Sentry may take them now (dev, 2026-09-04).
#
# BOTH ARE PREPARATIONS, so both are RULES rather than score terms -- the ward absorbs and the watch
# fires on somebody ELSE'S turn, which `_score_plan` structurally cannot reach because it prices this
# turn's plan. That is #726's doctrine reaching its second application; see ai-tactics.md.
#
# Board-backed rather than grid-free (unlike test_main_action_chooser.gd): the watch aim walks a real
# route from the enemy's side and the Guard rule runs a real move range, so a bare fixture would send
# every walk down its unreachable fallback and measure nothing.
extends GdUnitTestSuite

const P := preload("res://tests/support/pattern_fixtures.gd")

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const WATCH_ONLY: Array = [BaseAction.ActionType.OVERWATCH]
const GUARD_ONLY: Array = [BaseAction.ActionType.GUARD]


func _board_of(size := Rect2i(0, 0, 8, 8)) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, size)
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, armed := true) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data({}, faction), cell)
	if armed:
		unit.equipped_weapon = H.make_weapon()
	return unit


func _context(board: Dictionary) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	# The heights the builder made, not a flat stand-in: a watch aim reads the terrain since #756.
	return BoardContext.new(board.grid, units, board.squad_manager, null, null, board.board_heights)


# A weapon carrying a watchable extra -- what a Carbine is, without depending on that content.
# The line defaults to length 1 so the footprint is exactly the aimed cell and a case can name it.
# A case about the LANE (#769 -- what a facing covers, not the cell in front) passes a longer one.
func _watch_weapon(length := 1) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CARBINE
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 3
	var watch := WeaponAttackData.new()
	watch.display_name = "Watch"
	watch.power = 3
	watch.can_overwatch = true
	watch.attack_pattern = P.line(length)
	var extras: Array[WeaponAttackData] = [watch]
	template.extra_attacks = extras
	return WeaponInstance.make(template)


func _queued_watch(unit: Unit) -> OverwatchAction:
	for action in unit.squad.action_queue:
		if action.action_type == BaseAction.ActionType.OVERWATCH:
			return action as OverwatchAction
	return null


func _queued_guard(unit: Unit) -> GuardAction:
	for action in unit.squad.action_queue:
		if action.action_type == BaseAction.ActionType.GUARD:
			return action as GuardAction
	return null


# --- Overwatch ----------------------------------------------------------------------------------

# A DUD AIM MUST NEVER BE QUEUED, and nothing downstream would catch one. A hint that yields no
# cardinal direction makes a self-anchored AttackPattern answer with no cells; from there the failure is silent
# all the way down -- the resolver arms nothing, Unit.arm_watch refuses an empty footprint, and no
# queue gate inspects an OverwatchAction at all. The unit would have spent its main action on air
# behind a legal-looking row, so the assertion is on the FOOTPRINT, never on the row.
func test_a_queued_watch_always_has_a_real_footprint() -> void:
	var board := _board_of()
	var watcher: Unit = _spawn(board, PLAYER, Vector2i(4, 4))
	watcher.equipped_weapon = _watch_weapon()
	_spawn(board, ENEMY, Vector2i(4, 0))

	assert_bool(AITactics.queue_main_action(watcher, _context(board), board.squad_manager, WATCH_ONLY)) \
		.override_failure_message("the watcher declined to watch at all").is_true()

	var watch := _queued_watch(watcher)
	assert_object(watch).is_not_null()
	if watch == null:
		return
	assert_vector(watch.target_cell).override_failure_message(
			"the watch aimed at its own cell -- that footprint is empty and arms nothing"
			).is_not_equal(watcher.movement.cell)
	assert_int(watch.watched_cells_from(watcher.movement.cell, _context(board)).size()).override_failure_message(
			"the queued watch covers no cells, so arm_watch will silently refuse it").is_greater(0)


# THE WAY YOU'LL COME, not the way you are (dev, 2026-09-04). The route is walked from the ENEMY'S
# side with its own traversal and occupancy on, which is what makes the rule true around a wall --
# column 5 is unpainted except at the top, so the enemy due EAST has to come the long way and arrive
# from the NORTH. A straight-line facing reads (5, 4) and is what the mutant does.
func test_a_watcher_faces_the_route_in_not_the_straight_line() -> void:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 5, 8))    # west block, includes the watcher
	BB.paint_rect(board.grid, Rect2i(6, 0, 3, 8))    # east block, includes the enemy
	BB.paint_rect(board.grid, Rect2i(5, 0, 1, 1))    # the one gap, at the top of column 5

	var watcher: Unit = BB.spawn(board, H.make_unit_data({}, PLAYER), Vector2i(4, 4))
	watcher.equipped_weapon = _watch_weapon()
	BB.spawn(board, H.make_unit_data({}, ENEMY), Vector2i(6, 4))

	assert_bool(AITactics.queue_main_action(watcher, _context(board), board.squad_manager, WATCH_ONLY)).is_true()

	var watch := _queued_watch(watcher)
	assert_object(watch).is_not_null()
	if watch == null:
		return
	assert_vector(watch.target_cell).override_failure_message(
			"the watch faced the straight line to the enemy instead of the route it must actually walk"
			).is_equal(Vector2i(4, 3))


# A WATCH IT COULD NOT FIRE IS A DUD AIM, and since #756 the terrain is one of the things that can
# make it one: a watcher in a pit, with a weapon that reaches nothing above it, has no facing whose
# footprint survives — so it must decline and spend its main action on something else, exactly as it
# declines a facing that yields no cells at all. The rim is a real plateau the enemy stands on, so
# every facing still passes the ROUTE test the case above is about; only the shot is refused.
func _pit_board(rim_height: int) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 8, 8))
	for x in range(8):
		for y in range(8):
			if Vector2i(x, y) != Vector2i(4, 4):
				board.board_heights.set_cell(Vector2i(x, y), rim_height)
	return board


func _pit_watcher(board: Dictionary) -> Unit:
	var watcher: Unit = BB.spawn(board, H.make_unit_data({}, PLAYER), Vector2i(4, 4))
	watcher.equipped_weapon = _watch_weapon()
	# Reaches nothing above its own footing, so a raised rim is out of the shot's range.
	for attack in (watcher.equipped_weapon as WeaponInstance).template.extra_attacks:
		attack.up_tolerance = 0
	BB.spawn(board, H.make_unit_data({}, ENEMY), Vector2i(6, 4))
	return watcher


func test_a_watcher_declines_when_the_terrain_cuts_every_facing() -> void:
	var board := _pit_board(4)   # a rim two levels up, all the way round
	var watcher := _pit_watcher(board)

	assert_bool(AITactics.queue_main_action(watcher, _context(board), board.squad_manager, WATCH_ONLY)) \
		.override_failure_message("the watcher queued a watch whose shot cannot leave the pit") \
		.is_false()


# Non-vacuity twin: the identical fixture on flat ground DOES watch, so the case above is measuring
# the terrain rather than a broken setup.
func test_the_same_watcher_on_flat_ground_still_watches() -> void:
	var board := _pit_board(0)
	var watcher := _pit_watcher(board)

	assert_bool(AITactics.queue_main_action(watcher, _context(board), board.squad_manager, WATCH_ONLY)) \
		.is_true()


# A CORPSE CAN NEVER ARRIVE, and this is #720's pathology one door over. `nearest_enemy` ranks a body
# as an ordinary target and it wins on route, but PlanResolver._watch_triggered_by refuses a
# non-ACTIVE entrant and a body never moves -- so a watcher that took the unfiltered answer would aim
# at a corpse's approach every quiet turn for the rest of the battle. The mutant is `active_only`
# dropped, which faces the adjacent body at (5, 4) instead of the living enemy to the north.
func test_a_watcher_ignores_a_corpse_and_faces_the_living() -> void:
	var board := _board_of()
	var watcher: Unit = _spawn(board, PLAYER, Vector2i(4, 4))
	watcher.equipped_weapon = _watch_weapon()
	var body: Unit = _spawn(board, ENEMY, Vector2i(5, 4), false)
	body.force_down()
	_spawn(board, ENEMY, Vector2i(4, 0))

	assert_bool(AITactics.queue_main_action(watcher, _context(board), board.squad_manager, WATCH_ONLY)).is_true()

	var watch := _queued_watch(watcher)
	assert_object(watch).is_not_null()
	if watch == null:
		return
	assert_vector(watch.target_cell).override_failure_message(
			"the watch is aimed at the approach of a body that can never enter it").is_equal(Vector2i(4, 3))


# THE LANE, NOT THE CELL IN FRONT (#769). A watch fires when an enemy enters ANY cell it covers, so
# a facing whose near cell is merely OCCUPIED is still a facing -- and since path_hops walks from the
# ENEMY'S side with occupancy on, the unit blocking it is usually the watcher's own squadmate.
# Squads move as clusters, so this is the ordinary case rather than the exotic one.
#
# The mutant is the old read: rank on `origin + dir` alone and the north facing is refused outright,
# leaving a 5-hop tie between west and east that CARDINAL_DIRECTIONS breaks westward.
func test_a_watcher_takes_the_facing_its_own_squadmate_stands_in_front_of() -> void:
	var board := _board_of()
	var watcher: Unit = _spawn(board, PLAYER, Vector2i(4, 4))
	watcher.equipped_weapon = _watch_weapon(2)
	_spawn(board, PLAYER, Vector2i(4, 3))   # standing in the near cell of the facing that matters
	_spawn(board, ENEMY, Vector2i(4, 0))

	assert_bool(AITactics.queue_main_action(watcher, _context(board), board.squad_manager, WATCH_ONLY)).is_true()

	var watch := _queued_watch(watcher)
	assert_object(watch).is_not_null()
	if watch == null:
		return
	assert_vector(watch.target_cell).override_failure_message(
			"the watcher gave up the lane the enemy walks down because its own squadmate stood in the first cell"
			).is_equal(Vector2i(4, 3))


# A CUT LANE IS NOT A WHOLE ONE. #756 truncates a spread at the first cell its shot cannot reach, so
# a facing can survive as a stub -- and read at the near cell alone, a stub of one ranks exactly like
# an intact lane of three. Coverage breaks that tie: the enemy is one hop from both, and only the
# east lane still covers anywhere it might go next.
#
# THE CUT LANE IS NORTH ON PURPOSE. CARDINAL_DIRECTIONS puts UP first, so the old read takes it on
# the strict less-than and this case fails against unfixed code; with the orientation reversed the
# fixture would agree with the bug and pass either way.
func test_an_intact_lane_outranks_one_the_terrain_cut_to_a_stub() -> void:
	var board := _board_of()
	board.board_heights.set_cell(Vector2i(4, 2), 2)   # the ledge that ends the north lane
	var watcher: Unit = _spawn(board, PLAYER, Vector2i(4, 4))
	watcher.equipped_weapon = _watch_weapon(3)
	# Reaches nothing above its own footing, so the ledge is out of the shot's range.
	for attack in (watcher.equipped_weapon as WeaponInstance).template.extra_attacks:
		attack.up_tolerance = 0
	_spawn(board, ENEMY, Vector2i(5, 3))

	assert_bool(AITactics.queue_main_action(watcher, _context(board), board.squad_manager, WATCH_ONLY)).is_true()

	var watch := _queued_watch(watcher)
	assert_object(watch).is_not_null()
	if watch == null:
		return
	assert_vector(watch.target_cell).override_failure_message(
			"the watch took the lane a ledge had cut to one cell over the intact lane beside it"
			).is_equal(Vector2i(5, 4))


# A DIAGONAL APPROACH COLLAPSES TO CARDINAL ORDER, with no terrain and nobody in the way. Every
# facing's near cell is the same few hops from an enemy coming in diagonally, so the old read tied on
# all of them and Law #1 broke the tie -- the watcher aimed NORTH while the enemy walked in from the
# EAST. Read down the lane, east is one hop away and north is four.
#
# This is the plainest statement of what the rule always claimed to say, which is why it needs
# neither terrain nor a blocker to show it.
func test_a_watcher_faces_a_diagonal_approach_instead_of_north() -> void:
	var board := _board_of(Rect2i(0, 0, 10, 8))
	var watcher: Unit = _spawn(board, PLAYER, Vector2i(4, 4))
	watcher.equipped_weapon = _watch_weapon(4)
	_spawn(board, ENEMY, Vector2i(8, 3))

	assert_bool(AITactics.queue_main_action(watcher, _context(board), board.squad_manager, WATCH_ONLY)).is_true()

	var watch := _queued_watch(watcher)
	assert_object(watch).is_not_null()
	if watch == null:
		return
	assert_vector(watch.target_cell).override_failure_message(
			"the watch aimed north on a cardinal tie-break while the enemy approached from the east"
			).is_equal(Vector2i(5, 4))


# --- Guard --------------------------------------------------------------------------------------

# WARD WHOEVER IS MOST EXPOSED (dev, 2026-09-04): the ally the most enemies could reach and hit, not
# the weakest, so a shield is spent where a blow is actually coming.
#
# The board does the discriminating rather than the numbers: the ally to the NORTH is walled in on
# three sides, and its only remaining firing cell is the one the guard itself occupies -- which
# `is_standable_for` refuses to a non-squadmate -- so nobody can reach it and its exposure is zero.
# The ally to the SOUTH stands in the open with an enemy that can walk up to it.
#
# THE SHELTERED ONE IS NORTH ON PURPOSE. `guard_candidates` walks cells_within_manhattan_range, which
# yields the north neighbour first, so a mutant that ignores exposure and wards `candidates[0]` picks
# the WRONG ally and this case reds. With the two swapped it survived -- the case was measuring
# candidate order, not the rule, and only the mutant said so.
func test_a_guard_wards_the_ally_the_most_enemies_can_reach() -> void:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(4, 3, 1, 7))    # one column: sheltered ally, guard, exposed ally, then open ground

	var guard: Unit = BB.spawn(board, H.make_unit_data({}, PLAYER), Vector2i(4, 4))
	guard.equipped_weapon = H.make_weapon()
	var sheltered: Unit = BB.spawn(board, H.make_unit_data({}, PLAYER), Vector2i(4, 3))
	var exposed: Unit = BB.spawn(board, H.make_unit_data({}, PLAYER), Vector2i(4, 5))
	board.squad_manager.join_squad(exposed, guard.squad)
	board.squad_manager.join_squad(sheltered, guard.squad)
	var foe: Unit = BB.spawn(board, H.make_unit_data({}, ENEMY), Vector2i(4, 8))
	foe.equipped_weapon = H.make_weapon()

	assert_bool(AITactics.queue_main_action(guard, _context(board), board.squad_manager, GUARD_ONLY)) \
		.override_failure_message("the guard declined to ward anybody").is_true()

	var ward := _queued_guard(guard)
	assert_object(ward).is_not_null()
	if ward == null:
		return
	assert_object(ward.target).override_failure_message(
			"the guard shielded %s, who nobody can reach, instead of %s" % [
				str(sheltered.movement.cell), str(exposed.movement.cell)]).is_same(exposed)


# ZERO EXPOSURE REFUSES. "Most exposed" presumes exposure above zero -- without the refusal a Guard
# would pre-empt INTIMIDATE (the verb directly below it) with a purposeless ward every time an ally
# happened to be standing next to it. Same board, no enemy on it at all.
func test_a_guard_refuses_when_nobody_can_be_reached() -> void:
	var board := _board_of()
	var guard: Unit = _spawn(board, PLAYER, Vector2i(4, 4))
	var ally: Unit = _spawn(board, PLAYER, Vector2i(4, 3))
	board.squad_manager.join_squad(ally, guard.squad)

	assert_bool(AITactics.queue_main_action(guard, _context(board), board.squad_manager, GUARD_ONLY)) \
		.override_failure_message("the guard warded an ally nothing threatens, spending an action on nothing"
			).is_false()
	assert_object(_queued_guard(guard)).is_null()
