# Where fog may stand (#1285): FogGround's field, one texel per cell, R the edge fade and G the pooled
# depth. The dev's rulings it carries: fog thins before the board's edge and a hole rather than hanging
# over nothing, and pooled fog never stands as a box over a drop -- it is a depth over each cell's OWN
# ground, never a level the low ground fills up to.
#
# The content razor: how much each strength pools is authored (Resources/WeatherLooks/), so nothing
# here pins a look's numbers; the cases measure the field against its own parameters.
extends GdUnitTestSuite

const BB := preload("res://play/board_builder.gd")
const HOLE_TILE := Vector2i(18, 2)
const HOLE := Vector2i(6, 3)
const DEPTH := 0.4

var board: Dictionary


func before_test() -> void:
	board = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 9, 7))
	board.grid.paint(HOLE, BB.GRASS_SOURCE, HOLE_TILE)


func _rect() -> Rect2i:
	return (board.grid as TileMapLayer).get_used_rect()


func _heights() -> BoardHeights:
	return board.board_heights


func _field(share: float, edge_fade := 2.0, depth := DEPTH) -> Image:
	return FogGround.field(board.grid, _heights(), _rect(), share, depth, edge_fade)


func _at(image: Image, cell: Vector2i) -> Color:
	var rect := _rect()
	return image.get_pixel(cell.x - rect.position.x, cell.y - rect.position.y)


# Three tiers: columns 0-2 low, 3-5 a level up, 6-8 two levels up (the hole sits in the top tier).
func _terrace() -> void:
	for y in 7:
		for x in range(3, 9):
			var up := 2 if x < 6 else 4
			_heights().set_corners(Vector2i(x, y), Vector4i(up, up, up, up))


# A cell beside the board's edge or a hole is thinner than one well inside, and the hole holds none.
func test_fog_thins_before_the_edge_and_a_hole() -> void:
	var image := _field(1.0)
	var inside := _at(image, Vector2i(3, 3)).r
	assert_float(inside).override_failure_message("fixture: the middle of the board took no fog").is_greater(0.0)
	assert_float(_at(image, Vector2i(0, 3)).r).override_failure_message(
			"a cell on the board's edge is as thick as one inside").is_less(inside)
	assert_float(_at(image, HOLE + Vector2i.LEFT).r).override_failure_message(
			"a cell beside a hole is as thick as one inside").is_less(inside)
	assert_float(_at(image, HOLE + Vector2i(-1, -1)).r).override_failure_message(
			"a cell diagonal to a hole is as thick as one inside").is_less(inside)
	var hole := _at(image, HOLE)
	assert_bool(hole.r == 0.0 and hole.g == 0.0).override_failure_message("fog stands over a hole: %s" % hole).is_true()


# No fade asked for: every cell with ground is full.
func test_no_edge_fade_leaves_every_cell_full() -> void:
	var image := _field(1.0, 0.0)
	assert_float(_at(image, Vector2i(0, 0)).r).override_failure_message(
			"an edge fade of 0 still thinned the board's corner").is_equal(1.0)


# Fog pools on the low ground and not on the high ground above the pool level.
func test_fog_pools_on_the_low_ground_only() -> void:
	_terrace()
	var image := _field(0.3)
	assert_float(_at(image, Vector2i(1, 3)).g).override_failure_message("the low ground pooled no fog").is_greater(0.0)
	assert_float(_at(image, Vector2i(7, 3)).g).override_failure_message(
			"the high terrace stands in pooled fog").is_equal(0.0)


# The ruling, as a property: whatever share counts as low, no cell's pooled fog stands deeper than
# pool_depth over its own ground -- with the low share spanning all three tiers, filling up to a level
# would stand two levels of fog over the lowest one.
func test_pooled_fog_never_stands_deeper_than_its_depth() -> void:
	_terrace()
	var image := _field(1.0)
	var rect := _rect()
	var pooled := 0
	for y in image.get_height():
		for x in image.get_width():
			var g := image.get_pixel(x, y).g
			if g > 0.0:
				pooled += 1
			assert_float(g).override_failure_message("cell %s stands %.2f of fog over its own ground, past %.2f" % [
					rect.position + Vector2i(x, y), g, DEPTH]).is_less_equal(DEPTH + 0.0001)
	assert_int(pooled).override_failure_message("fixture: nothing pooled at all").is_greater(0)


# A larger share pools everywhere a smaller one does, and more -- so the dial grows the pool rather
# than reshuffling it.
func test_a_larger_share_pools_on_a_superset() -> void:
	_terrace()
	var low := _field(0.3)
	var high := _field(0.9)
	var grew := false
	for y in low.get_height():
		for x in low.get_width():
			var a := low.get_pixel(x, y).g > 0.0
			var b := high.get_pixel(x, y).g > 0.0
			assert_bool(not a or b).override_failure_message("a larger share left (%d, %d) dry" % [x, y]).is_true()
			grew = grew or (b and not a)
	assert_bool(grew).override_failure_message("the larger share pooled nowhere new").is_true()
