# Where rain lands (#1260): WeatherMask's texel per cell, decoded the way the rain and splash shaders
# decode it, must name the SAME surface BoardSpace.surface_height_at does -- on flat ground, a ramp and
# a corner form, where the two triangulations of a cell disagree -- and VOID over a hole and off the
# board, so a drop there falls on out of the frame. A staged cell is rained on where it stands.
#
# The shader itself cannot run headless; WeatherMask.surface_at is its GDScript twin, and the
# include's header names this suite as what keeps the two in step.
extends GdUnitTestSuite

const BB := preload("res://play/board_builder.gd")
const HOLE_TILE := Vector2i(18, 2)   # the authored VOID tile ("hole") in TestTiles
const RAMP := Vector2i(1, 0)
const CORNER := Vector2i(2, 1)
const HOLE := Vector2i(3, 2)
const SAMPLES: Array[Vector2] = [Vector2(0.1, 0.1), Vector2(0.9, 0.2), Vector2(0.5, 0.5),
		Vector2(0.2, 0.85), Vector2(0.8, 0.9), Vector2(0.45, 0.05)]

var board: Dictionary


func before_test() -> void:
	board = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 4, 3))
	board.grid.paint(HOLE, BB.GRASS_SOURCE, HOLE_TILE)
	var heights: BoardHeights = board.board_heights
	heights.set_corners(RAMP, Vector4i(0, 2, 2, 0))      # rises east
	heights.set_corners(CORNER, Vector4i(2, 2, 2, 0))    # three high, one low: not a plane


func _rect() -> Rect2i:
	return (board.grid as TileMapLayer).get_used_rect()


func test_the_mask_names_the_surface_the_board_does() -> void:
	var heights: BoardHeights = board.board_heights
	assert_bool(Terrain.is_planar_form(heights.corners_at(CORNER))).override_failure_message(
			"fixture: the corner cell is a plane, so it cannot tell the triangulations apart").is_false()
	var rect := _rect()
	var image := WeatherMask.build(board.grid, heights, rect, Callable())
	var checked := 0
	for y in rect.size.y:
		for x in rect.size.x:
			var cell := rect.position + Vector2i(x, y)
			if cell == HOLE:
				continue
			for uv in SAMPLES:
				var wx := float(cell.x) + uv.x
				var wz := float(cell.y) + uv.y
				var expected := BoardSpace.surface_height_at(cell, wx, wz, heights)
				assert_float(WeatherMask.surface_at(image, rect, wx, wz)).override_failure_message(
						"the mask lands a drop at the wrong height over %s at %s" % [cell, uv]) \
						.is_equal_approx(expected, 0.0001)
				checked += 1
	assert_int(checked).is_greater(40)


func test_a_hole_and_beyond_the_board_are_void() -> void:
	var rect := _rect()
	var image := WeatherMask.build(board.grid, board.board_heights, rect, Callable())
	assert_float(WeatherMask.surface_at(image, rect, HOLE.x + 0.5, HOLE.y + 0.5)).override_failure_message(
			"a hole stopped the rain; a drop over it should fall on out of the frame").is_equal(WeatherMask.VOID)
	assert_float(WeatherMask.surface_at(image, rect, -3.5, 1.5)).is_equal(WeatherMask.VOID)
	assert_float(WeatherMask.surface_at(image, rect, 1.5, 40.5)).is_equal(WeatherMask.VOID)


# The tear-out lifts cells onto the stage (#521); the rain must end on them up there.
func test_a_staged_cell_is_rained_on_where_it_stands() -> void:
	var lift := Vector3(0.0, 40.0, 0.0)
	var staged := Vector2i(0, 1)
	var offset_of := func(cell: Vector2i) -> Vector3: return lift if cell == staged else Vector3.ZERO
	var rect := _rect()
	var image := WeatherMask.build(board.grid, board.board_heights, rect, offset_of)
	var expected := BoardSpace.surface_height_at(staged, 0.5, 1.5, board.board_heights) + lift.y
	assert_float(WeatherMask.surface_at(image, rect, 0.5, 1.5)).is_equal_approx(expected, 0.0001)
	var beside := BoardSpace.surface_height_at(Vector2i(0, 0), 0.5, 0.5, board.board_heights)
	assert_float(WeatherMask.surface_at(image, rect, 0.5, 0.5)).override_failure_message(
			"the lift leaked onto a cell that is not staged").is_equal_approx(beside, 0.0001)


# The water basin (#654) draws a water cell below its rules surface, and every reader that lays
# something on water subtracts the drop: a drop over a basin lands on the water you see.
func test_a_basin_cell_is_rained_on_at_its_drawn_surface() -> void:
	var cell := Vector2i(0, 2)
	BoardSpace.mark_basin(cell, true)
	var drop := BoardSpace.basin_drop(cell)
	var offset := WeatherMirror.drawn_offset(cell)
	BoardSpace.mark_basin(cell, false)
	assert_float(drop).override_failure_message("fixture: the basin drops nothing").is_greater(0.0)
	assert_float(offset.y).is_equal_approx(-drop, 0.0001)
