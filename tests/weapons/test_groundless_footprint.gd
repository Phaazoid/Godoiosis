# A footprint lists only cells with a SURFACE, and an aim that would touch none is a dud (#1228).
#
# A real TestTiles board through play/board_builder.gd, because the rule is about the GRID: a cell
# off the board's painted rect has no tile, and an erased cell inside it is a hole. The gridless
# BoardContext the geometry suites use answers "every cell has ground", so it cannot see any of this.
# Every expectation is derived from cells this file paints and erases itself.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")

const EAST := Vector2i.RIGHT
const WEST := Vector2i.LEFT
# The painted strip: x 0..7, y 0..2. A shooter at its west edge faces off the board to the west.
const STRIP := Rect2i(0, 0, 8, 3)
const EDGE := Vector2i(0, 1)

var _board: Dictionary
var _shooter: Unit


func before_test() -> void:
	_board = BoardBuilder.build(self, "GroundlessRoot")
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, STRIP)
	_shooter = BoardBuilder.spawn(_board, H.make_unit_data({}, Team.Faction.PLAYER), EDGE)


func _rules() -> BoardContext:
	var units: Array[Unit] = [_shooter]
	return BoardContext.new(_board.grid, units, _board.squad_manager)


# An interior cell with its ground erased: inside the board's rect, so a hole rather than the edge.
func _dig(cell: Vector2i) -> void:
	(_board.grid as BoardGrid).erase(cell)
	assert_bool(_rules().is_void_at(cell)).override_failure_message(
		"fixture: %s did not read as a hole once erased" % str(cell)).is_true()


func _line(length: int) -> AttackData:
	return P.line(AttackData.new(), length)


func _footprint(attack: AttackData, origin: Vector2i, aim: Vector2i) -> Array[Vector2i]:
	return Reach.get_affected_cells_from(_shooter, origin, aim, attack, _rules())


# A path-shaped (single-target swing) attack walking `length` cells straight ahead.
func _path_line(length: int) -> AttackData:
	var cells: Array[Vector2i] = []
	for f in range(1, length + 1):
		cells.append(Vector2i(0, -f))
	var paths: Array[Array] = [cells]
	var attack := AttackData.new()
	attack.max_range = 0
	attack.attack_shape = P.pathed(paths)
	attack.swing = true
	return attack


# --- the footprint ---------------------------------------------------------------------------------

func test_a_line_facing_off_the_board_watches_nothing_and_cannot_be_aimed() -> void:
	var attack := _line(3)
	assert_array(_footprint(attack, EDGE, EDGE + WEST)).override_failure_message(
		"a line facing off the board's edge still listed cells").is_empty()
	assert_bool(Reach.can_aim_at(_shooter, EDGE, EDGE + WEST, attack, _rules())).override_failure_message(
		"a facing with nothing under it was accepted as an aim").is_false()
	# The twin: the same line facing onto the board lands and is aimable.
	assert_array(_footprint(attack, EDGE, EDGE + EAST)).contains_exactly(
		[EDGE + EAST, EDGE + EAST * 2, EDGE + EAST * 3])
	assert_bool(Reach.can_aim_at(_shooter, EDGE, EDGE + EAST, attack, _rules())).is_true()


func test_a_line_half_off_the_edge_keeps_its_cells_on_the_board_in_order() -> void:
	var last := Vector2i(STRIP.end.x - 2, EDGE.y)   # two cells short of the far edge
	var cells := _footprint(_line(3), last, last + EAST)
	assert_array(cells).override_failure_message(
		"the footprint kept cells past the edge, or lost the one on it: %s" % str(cells)).contains_exactly(
		[last + EAST])


# The trim runs on the FINISHED footprint: a hole is dropped from it, and the cells beyond the hole
# are kept, because a shot crosses a chasm.
func test_a_line_across_a_hole_still_reaches_the_far_bank() -> void:
	_dig(EDGE + EAST * 2)
	assert_array(_footprint(_line(3), EDGE, EDGE + EAST)).override_failure_message(
		"a line across a hole either listed the hole or stopped at it").contains_exactly(
		[EDGE + EAST, EDGE + EAST * 3])


# The point form (#1228's "shooting attacks too"): a one-cell aim at a hole hits nothing and is
# refused, while a blast at the same hole still has ground to land on and keeps only that ground.
func test_a_point_aim_at_a_hole_is_refused_unless_its_blast_reaches_ground() -> void:
	var hole := EDGE + EAST * 2
	_dig(hole)
	var shot := P.point(AttackData.new(), 2)
	assert_bool(Reach.can_aim_at(_shooter, EDGE, hole, shot, _rules())).override_failure_message(
		"a one-cell shot into a hole was accepted").is_false()

	var cross: Array[Vector2i] = [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT]
	var blast := P.stamped(AttackData.new(), 2, cross)
	assert_bool(Reach.can_aim_at(_shooter, EDGE, hole, blast, _rules())).override_failure_message(
		"a blast whose splash reaches ground was refused for landing on a hole").is_true()
	assert_array(_footprint(blast, EDGE, hole)).contains_exactly([hole + WEST, hole + EAST])


# A single-target swing walks PATHS, and a path's step is its index: the hole stays in the walk, so
# the tile past it keeps its step, while what the attack STRIKES (the cells that take a deposit or
# drop a payload) and what it draws both skip it.
func test_a_path_attack_strikes_no_hole_and_keeps_its_timing() -> void:
	var hole := EDGE + EAST * 2
	_dig(hole)
	var attack := _path_line(3)
	attack.targets = EquippableData.TargetMode.MAP

	var sweep := Conduction.sweep(_shooter, EDGE, EDGE + EAST, attack, _rules())
	assert_array(sweep.struck).override_failure_message(
		"the path struck the hole or lost the far bank: %s" % str(sweep.struck)).contains_exactly(
		[EDGE + EAST, EDGE + EAST * 3])
	assert_bool(sweep.steps.has(hole)).override_failure_message(
		"the hole was timed as a tile the attack reached").is_false()
	assert_array(sweep.steps.get(EDGE + EAST * 3, [])).override_failure_message(
		"the tile past the hole lost its step").contains_exactly([2])
	assert_array(_footprint(attack, EDGE, EDGE + EAST)).contains_exactly([EDGE + EAST, EDGE + EAST * 3])


# --- a watch ---------------------------------------------------------------------------------------

func test_a_watch_facing_off_the_board_watches_nothing() -> void:
	var probe := OverwatchAction.new()
	probe.init(_shooter, EDGE + WEST, _line(3))
	assert_array(probe.watched_paths_from(EDGE, _rules())).override_failure_message(
		"a watch facing off the board still watched cells").is_empty()


func test_a_path_watch_across_a_hole_watches_only_ground() -> void:
	var hole := EDGE + EAST * 2
	_dig(hole)
	var probe := OverwatchAction.new()
	probe.init(_shooter, EDGE + EAST, _path_line(3))
	var paths := probe.watched_paths_from(EDGE, _rules())
	assert_int(paths.size()).is_equal(1)
	if paths.size() != 1:
		return
	assert_array(paths[0]).override_failure_message(
		"the watch's path listed the hole: %s" % str(paths[0])).contains_exactly([EDGE + EAST, EDGE + EAST * 3])


# --- the reach overlay -----------------------------------------------------------------------------

# A cell with no surface is no facing's, but it is not the terrain cutting a lane either, so the
# hatch leaves it alone and the reach looks as it did before the trim.
func test_the_hatch_never_marks_a_cell_with_no_surface() -> void:
	var attack := _line(3)
	var board := _rules()
	var union := Reach.get_all_attack_cells_from(_shooter, EDGE, attack)
	assert_bool(union.any(func(cell: Vector2i) -> bool: return not board.has_surface(cell))) \
		.override_failure_message("fixture: the reach never leaves the board, so this case proves nothing") \
		.is_true()
	for cell in Reach.blocked_cells_from(_shooter, EDGE, attack, board):
		assert_bool(board.has_surface(cell)).override_failure_message(
			"the hatch marked %s, which has no surface" % str(cell)).is_true()
