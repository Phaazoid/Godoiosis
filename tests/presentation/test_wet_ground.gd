# What the rain does to the ground's look (#1260): WetGround paints the two decals' textures. Water and
# holes stay untouched, and a puddle lies on flat, walkable, dry ground INSIDE its own cell -- the dev's
# report against the mockup was puddles "appearing past their tiles, over nothing" (2026-10-08), so
# every puddle pixel here is checked against the cell it sits in.
#
# The content razor: which weathers puddle, and how much, is authored (Resources/WeatherLooks/), so
# coverage and colour are passed in rather than read off a file.
extends GdUnitTestSuite

const BB := preload("res://play/board_builder.gd")
const HOLE_TILE := Vector2i(18, 2)
const WATER := Vector2i(1, 1)
const RAMP := Vector2i(2, 0)
const HOLE := Vector2i(3, 2)
const PX := WetGround.PX

var board: Dictionary


func before_test() -> void:
	board = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 5, 4))
	BB.paint_cell(board.grid, WATER, BB.WATER_ATLAS)
	board.grid.paint(HOLE, BB.GRASS_SOURCE, HOLE_TILE)
	(board.board_heights as BoardHeights).set_corners(RAMP, Vector4i(0, 2, 2, 0))


func _rect() -> Rect2i:
	return (board.grid as TileMapLayer).get_used_rect()


func _cell_of(pixel: Vector2i, rect: Rect2i) -> Vector2i:
	return rect.position + Vector2i(floori(float(pixel.x) / PX), floori(float(pixel.y) / PX))


func test_water_and_holes_stay_untouched_and_ground_is_wet() -> void:
	var rect := _rect()
	var image := WetGround.paint_wet(board.grid, rect, Color(0.1, 0.1, 0.1))
	for y in image.get_height():
		for x in image.get_width():
			var cell := _cell_of(Vector2i(x, y), rect)
			var wet := cell != WATER and cell != HOLE
			assert_float(image.get_pixel(x, y).a).override_failure_message(
					"%s cell %s %s" % ["ground" if wet else "water/hole", cell, "stayed dry" if wet else "was darkened"]) \
					.is_equal(1.0 if wet else 0.0)


func test_every_puddle_pixel_lies_inside_its_own_cell() -> void:
	var rect := _rect()
	var cells := WetGround.puddle_cells(board.grid, board.board_heights, rect, 1.0)
	assert_int(cells.size()).override_failure_message("fixture: no cell can hold a puddle").is_greater(3)
	var image := WetGround.paint_puddles(board.grid, board.board_heights, rect, 1.0, Color(0.3, 0.4, 0.5, 0.8))
	var drawn := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= 0.0:
				continue
			drawn += 1
			var cell := _cell_of(Vector2i(x, y), rect)
			assert_bool(cells.has(cell)).override_failure_message(
					"a puddle pixel at %s lies over %s, which holds no puddle" % [Vector2i(x, y), cell]).is_true()
			var inside := Vector2i(x % PX, y % PX)
			assert_bool(inside.x >= WetGround.INSET and inside.y >= WetGround.INSET
					and inside.x < PX - WetGround.INSET and inside.y < PX - WetGround.INSET) \
					.override_failure_message("a puddle pixel reaches the edge of its tile at %s" % inside).is_true()
	assert_int(drawn).override_failure_message("no puddle was drawn at full coverage").is_greater(0)


func test_no_puddle_on_water_a_slope_or_a_hole() -> void:
	var cells := WetGround.puddle_cells(board.grid, board.board_heights, _rect(), 1.0)
	assert_bool(cells.has(WATER)).override_failure_message("a puddle on a water tile").is_false()
	assert_bool(cells.has(RAMP)).override_failure_message("a puddle on a slope").is_false()
	assert_bool(cells.has(HOLE)).override_failure_message("a puddle over a hole").is_false()
	assert_bool(cells.has(Vector2i(0, 0))).override_failure_message(
			"fixture: flat grass holds no puddle even at full coverage").is_true()


# The cell seed policy: the same board puddles in the same places at every rebuild, and a lower
# coverage is a SUBSET of a higher one, so a slider adds and removes puddles rather than reshuffling.
func test_puddles_are_fixed_per_cell() -> void:
	var rect := _rect()
	var some := WetGround.puddle_cells(board.grid, board.board_heights, rect, 0.4)
	assert_array(WetGround.puddle_cells(board.grid, board.board_heights, rect, 0.4)).is_equal(some)
	var more := WetGround.puddle_cells(board.grid, board.board_heights, rect, 0.8)
	for cell in some:
		assert_bool(more.has(cell)).override_failure_message(
				"raising the coverage moved a puddle off %s" % cell).is_true()
