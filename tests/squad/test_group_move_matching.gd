# Followable means a formation EXISTS (#1652). GroupMoveSolver.stranding used to count the cells the
# members could take against how many members there were, which passes when two members' only cell
# is the same one; and plan()'s greedy placement, having no backtracking, could miss a formation that
# did exist. Both now ask one matching (GroupMoveSolver._augment). These cases hold the overlay and the
# committing group move to the same answer. Headless, through the production board builder.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const GAP_LEADER := Vector2i(11, 6)
const GAP_ROCKS: Array[Vector2i] = [Vector2i(11, 5), Vector2i(12, 5), Vector2i(11, 7), Vector2i(12, 7)]
const GAP_WEST: Array[Vector2i] = [Vector2i(10, 5), Vector2i(10, 7)]
const GAP_EAST: Array[Vector2i] = [Vector2i(13, 5), Vector2i(13, 7)]


func _ctx(board: Dictionary) -> BoardContext:
	return board.squad_manager.board_source.call()


# A squad strung through a one-tile gap between two rock pairs (#1652's board): leader in the gap,
# two members either side, the eastern pair three tiles of path away through it. Returns the leader.
func _gap_squad(board: Dictionary) -> Unit:
	for x in 22:
		for y in 13:
			if not GAP_ROCKS.has(Vector2i(x, y)):
				BB.paint_cell(board.grid, Vector2i(x, y), BB.GRASS_ATLAS)
	var leader: Unit = BB.spawn(board, H.make_unit_data({Stats.Stat.COH: 3, Stats.Stat.LDR: 20},
			Team.Faction.PLAYER), GAP_LEADER)
	for cell in GAP_WEST + GAP_EAST:
		var member: Unit = BB.spawn(board, H.make_unit_data({}, Team.Faction.PLAYER), cell)
		board.squad_manager.join_squad(member, leader.squad)
	assert_int(leader.squad.get_members().size()).override_failure_message(
			"fixture: the gap squad did not form").is_equal(5)
	return leader


# A leader destination where every eastern member can follow ALONE but only to the same one cell.
func _shared_only_cell_destination(leader: Unit, board: BoardContext) -> Vector2i:
	var east: Array[Unit] = []
	for member in leader.squad.get_members():
		if GAP_EAST.has(member.movement.cell):
			east.append(member)
	for destination: Vector2i in RulesService.compute_move_range(leader, board).reachable.keys():
		var a := GroupMoveSolver.follow_cells(leader.squad, east[0], destination, board)
		var b := GroupMoveSolver.follow_cells(leader.squad, east[1], destination, board)
		if a.size() == 1 and a.keys() == b.keys():
			return destination
	return GridUtils.NO_CELL


func test_two_members_whose_only_cell_is_the_same_cannot_follow() -> void:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	var leader := _gap_squad(board)
	var ctx := _ctx(board)
	var destination := _shared_only_cell_destination(leader, ctx)
	assert_that(destination).override_failure_message(
			"fixture: no destination leaves both eastern members one shared cell").is_not_equal(GridUtils.NO_CELL)

	assert_bool(GroupMoveSolver.followable_destinations(leader.squad, ctx, [destination]).has(destination)) \
		.override_failure_message("%s was offered, but two members can only reach the same cell" % [destination]) \
		.is_false()
	assert_bool(board.squad_manager.queue_group_move(leader.squad, destination, ctx)).override_failure_message(
			"fixture: the group move to %s landed after all" % [destination]).is_false()


# The two answers agree on every destination of seeded random boards: followable exactly when the
# real group move lands. Seed 1652's first boards hold both failures this fixed -- a shared only cell
# (stranding said yes) and a formation the greedy placement missed (plan() dropped a member).
func test_followable_matches_the_group_move_on_random_boards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1652
	var checked := 0
	var disagreements: Array[String] = []
	for trial in 40:
		var board: Dictionary = BB.build(self)
		auto_free(board.root)
		var holes := {}
		for x in 9:
			for y in 9:
				if rng.randf() < 0.3 and Vector2i(x, y) != Vector2i(4, 4):
					holes[Vector2i(x, y)] = true
				else:
					BB.paint_cell(board.grid, Vector2i(x, y), BB.GRASS_ATLAS)
		var leader: Unit = BB.spawn(board, H.make_unit_data({Stats.Stat.COH: rng.randi_range(1, 3),
				Stats.Stat.LDR: 20, Stats.Stat.DEX: rng.randi_range(3, 9)}, Team.Faction.PLAYER), Vector2i(4, 4))
		var wanted := rng.randi_range(2, 5)
		for attempt in 40:
			if leader.squad.get_members().size() >= wanted:
				break
			var cell := Vector2i(rng.randi_range(1, 7), rng.randi_range(1, 7))
			if holes.has(cell) or _ctx(board).unit_at_cell(cell) != null:
				continue
			var member: Unit = BB.spawn(board, H.make_unit_data({Stats.Stat.DEX: rng.randi_range(2, 7)},
					Team.Faction.PLAYER), cell)
			board.squad_manager.join_squad(member, leader.squad)   # refused: it stays, as an obstacle
		if leader.squad.get_members().size() < 2:
			continue
		var ctx := _ctx(board)
		var destinations: Array = RulesService.compute_move_range(leader, ctx).reachable.keys()
		var followable := GroupMoveSolver.followable_destinations(leader.squad, ctx, destinations)
		for destination: Vector2i in destinations:
			checked += 1
			var landed: bool = board.squad_manager.queue_group_move(leader.squad, destination, ctx)
			board.squad_manager.cancel_squad_moves(leader.squad)
			if landed != followable.has(destination):
				disagreements.append("board %d, %s: followable %s, group move landed %s" % [
						trial, destination, followable.has(destination), landed])
	assert_int(checked).override_failure_message("fixture: no destination was checked").is_greater(0)
	assert_array(disagreements).override_failure_message(
			"followable and the group move disagree:\n  " + "\n  ".join(disagreements)).is_empty()
