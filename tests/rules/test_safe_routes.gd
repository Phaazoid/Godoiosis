# The route a move walks (#920; ruling 8 on #117): RulesService.route_to takes the fewest hostile
# watches set off, then the cheapest -- and never changes which cells a unit can reach.
#
# A watch fires ONCE, so a route that clips three cells of one watch wakes one watch, and an entry
# into a cell two watches cover wakes only the first (arm order), as the resolve does. Both are
# pinned below against the obvious wrong metric, per-cell metering, which would detour around them.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _build_board(size: Rect2i) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, size)
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, stats := {}) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data(stats, faction), cell)
	unit.equipped_weapon = H.make_weapon(3)
	return unit


func _ctx(board: Dictionary) -> BoardContext:
	return board.squad_manager.board_source.call()


# A watch over `cells`, held by a player unit standing at `post` (off the routes being asked about).
func _watch(board: Dictionary, post: Vector2i, cells: Array[Vector2i]) -> Watch:
	var watcher := _spawn(board, PLAYER, post, {Stats.Stat.MHP: 40})
	var attack: AttackData = (watcher.get_equipped_weapon() as WeaponInstance).template.main_attack
	watcher.watch = Watch.arm(watcher, post, cells[0], cells, attack)
	return watcher.watch


func _route(mover: Unit, board: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var ctx := _ctx(board)
	return RulesService.route_to(mover, RulesService.compute_move_range(mover, ctx), goal, ctx)


func _crosses(path: Array[Vector2i], cells: Array[Vector2i]) -> bool:
	for i in range(1, path.size()):
		if cells.has(path[i]):
			return true
	return false


# --- The detour ------------------------------------------------------------------------------------

# Column 2 is watched below the top row; the straight walk along row 1 crosses it, the top row does not.
func test_a_route_detours_around_a_watch_when_a_safe_way_exists() -> void:
	var board := _build_board(Rect2i(0, 0, 7, 5))
	var mover := _spawn(board, ENEMY, Vector2i(0, 1), {Stats.Stat.DEX: 30})
	var lane: Array[Vector2i] = [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)]
	_watch(board, Vector2i(6, 4), lane)

	var path := _route(mover, board, Vector2i(4, 1))

	assert_that(path.back()).is_equal(Vector2i(4, 1))
	assert_bool(_crosses(path, lane)).override_failure_message(
			"the route walked through the watch: %s" % [path]).is_false()


# --- Watches, not cells ----------------------------------------------------------------------------

# Row 1, the straight walk, lies in ONE watch for three cells. Every way round crosses column 1 and
# column 3 in two OTHER watches. One watch woken beats two, however many cells the one covers.
func test_three_cells_of_one_watch_cost_less_than_one_cell_each_of_two() -> void:
	var board := _build_board(Rect2i(0, 0, 6, 4))
	var mover := _spawn(board, ENEMY, Vector2i(0, 1), {Stats.Stat.DEX: 30})
	var row: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
	var west: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 2), Vector2i(1, 3)]
	var east: Array[Vector2i] = [Vector2i(3, 0), Vector2i(3, 2), Vector2i(3, 3)]
	_watch(board, Vector2i(5, 3), row)
	_watch(board, Vector2i(5, 2), west)
	_watch(board, Vector2i(5, 0), east)

	var path := _route(mover, board, Vector2i(4, 1))

	assert_bool(_crosses(path, west) or _crosses(path, east)).override_failure_message(
			"the route paid two watches to dodge cells of one: %s" % [path]).is_false()


# One cell two watches cover wakes only the first of them. The straight walk enters that cell; the
# way round is longer and wakes one watch of its own. Equal watches woken, so the shorter wins.
func test_a_cell_two_watches_cover_wakes_only_one() -> void:
	var board := _build_board(Rect2i(0, 0, 6, 4))
	var mover := _spawn(board, ENEMY, Vector2i(0, 1), {Stats.Stat.DEX: 30})
	var crossing: Array[Vector2i] = [Vector2i(2, 1)]
	_watch(board, Vector2i(5, 3), crossing)
	_watch(board, Vector2i(4, 3), crossing)
	# Everything off row 1 between the two ends is watched by a third, so any detour wakes one.
	var around: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 2), Vector2i(2, 3)]
	_watch(board, Vector2i(5, 0), around)

	var path := _route(mover, board, Vector2i(4, 1))

	assert_bool(path.has(Vector2i(2, 1))).override_failure_message(
			"the route took the long way, counting both watches over one cell: %s" % [path]).is_true()


# --- The range never changes -----------------------------------------------------------------------

# Every cell the unit can reach has a route to it that is a real walk: it starts on the unit, steps
# one neighbour at a time, and costs no more than its MOV -- watches or not.
func test_every_reachable_cell_has_a_walkable_route() -> void:
	var board := _build_board(Rect2i(0, 0, 8, 6))
	var mover := _spawn(board, ENEMY, Vector2i(0, 2))
	var lane: Array[Vector2i] = [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 2)]
	_watch(board, Vector2i(7, 5), lane)
	var other: Array[Vector2i] = [Vector2i(1, 4), Vector2i(1, 0)]
	_watch(board, Vector2i(7, 0), other)
	var ctx := _ctx(board)
	var reach := RulesService.compute_move_range(mover, ctx)
	var goals: Array = reach.reachable.keys() + reach.squad_unreachable.keys()
	assert_int(goals.size()).override_failure_message("fixture: the unit must reach somewhere").is_greater(4)

	for goal: Vector2i in goals:
		var path := RulesService.route_to(mover, reach, goal, ctx)
		assert_that(path.front()).is_equal(mover.movement.cell)
		assert_that(path.back()).is_equal(goal)
		var cost := 0
		for i in range(1, path.size()):
			assert_int(GridUtils.manhattan_distance(path[i - 1], path[i])).is_equal(1)
			cost += RulesService.movement_cost(path[i - 1], path[i], mover, ctx)
		assert_int(cost).override_failure_message("the route to %s costs more than MOV" % [goal]) \
			.is_less_equal(mover.get_mov())


func test_with_no_watch_the_route_is_the_range_s_own() -> void:
	var board := _build_board(Rect2i(0, 0, 8, 6))
	var mover := _spawn(board, ENEMY, Vector2i(0, 2))
	var ctx := _ctx(board)
	var reach := RulesService.compute_move_range(mover, ctx)
	for goal: Vector2i in reach.reachable:
		assert_array(RulesService.route_to(mover, reach, goal, ctx)) \
			.is_equal(RulesService.reconstruct_path(reach.came_from, mover.movement.cell, goal))


# --- Every caller rides it -------------------------------------------------------------------------

# The AI's and Group Move's door: the leader's queued walk takes the detour too.
func test_a_group_move_walks_the_safe_route() -> void:
	var board := _build_board(Rect2i(0, 0, 7, 5))
	var mover := _spawn(board, ENEMY, Vector2i(0, 1), {Stats.Stat.DEX: 30})
	var lane: Array[Vector2i] = [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)]
	_watch(board, Vector2i(6, 4), lane)

	assert_bool(board.squad_manager.queue_group_move(mover.squad, Vector2i(4, 1), _ctx(board))).is_true()

	var walk: MoveAction = mover.get_move_action()
	assert_object(walk).is_not_null()
	assert_bool(_crosses(walk.path, lane)).override_failure_message(
			"the group move walked through the watch: %s" % [walk.path]).is_false()
