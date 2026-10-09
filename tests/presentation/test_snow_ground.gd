# What the snow does to the ground's look (#1269): SnowGround paints the cover decal's texture. The
# dev's rule from the rain carries over -- nothing past its tile or over nothing -- so every pixel is
# checked against the cell it sits in, and water and holes take none.
#
# The content razor: how much each strength covers is authored (Resources/WeatherLooks/), so the
# strengths are measured against the painter itself -- a higher cover is a superset of a lower one --
# rather than against any number.
extends GdUnitTestSuite

const BB := preload("res://play/board_builder.gd")
const HOLE_TILE := Vector2i(18, 2)
const WATER := Vector2i(1, 1)
const HOLE := Vector2i(3, 2)
const PX := SnowGround.PX
const WHITE := Color(0.95, 0.96, 1.0)

var board: Dictionary


func before_test() -> void:
	board = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 6, 5))
	BB.paint_cell(board.grid, WATER, BB.WATER_ATLAS)
	board.grid.paint(HOLE, BB.GRASS_SOURCE, HOLE_TILE)


func _rect() -> Rect2i:
	return (board.grid as TileMapLayer).get_used_rect()


func _paint(cover: float, frost := 0.0, flecks := 0.0, rect := Rect2i()) -> Image:
	return SnowGround.paint_cover(board.grid, rect if rect.has_area() else _rect(), cover, frost, flecks, WHITE)


func _cell_of(pixel: Vector2i, rect: Rect2i) -> Vector2i:
	return rect.position + Vector2i(floori(float(pixel.x) / PX), floori(float(pixel.y) / PX))


# Full cover, full frost, every fleck: every ground pixel is painted and nothing over water or a hole.
func test_snow_lies_on_ground_only_and_never_past_its_cell() -> void:
	var rect := _rect()
	var image := _paint(1.0, 1.0, 1.0)
	for y in image.get_height():
		for x in image.get_width():
			var cell := _cell_of(Vector2i(x, y), rect)
			var ground := cell != WATER and cell != HOLE
			var a := image.get_pixel(x, y).a
			assert_bool(a > 0.0).override_failure_message("%s cell %s %s" % [
					"ground" if ground else "water/hole", cell, "took no snow" if ground else "took snow"]) \
					.is_equal(ground)


# Cover alone (no frost, no flecks): a higher cover lies everywhere a lower one does, and more -- so the
# dusting, the patches and the full cover are three settings of one field, and a slider grows patches
# rather than reshuffling them.
func test_more_cover_is_a_superset_of_less() -> void:
	var counts: Array[int] = []
	var last: Image = null
	for cover: float in [0.1, 0.5, 0.9]:
		var image := _paint(cover)
		var count := 0
		for y in image.get_height():
			for x in image.get_width():
				var on := image.get_pixel(x, y).a >= 1.0
				if on:
					count += 1
				if last != null and last.get_pixel(x, y).a >= 1.0:
					assert_bool(on).override_failure_message(
							"cover %.1f lost a pixel at %s that a lower cover had" % [cover, Vector2i(x, y)]).is_true()
		counts.append(count)
		last = image
	assert_int(counts[1]).override_failure_message("patches cover no more than a dusting: %s" % [counts]) \
			.is_greater(counts[0])
	assert_int(counts[2]).override_failure_message("full cover is no more than patches: %s" % [counts]) \
			.is_greater(counts[1])


func test_no_cover_frost_or_flecks_paints_nothing() -> void:
	var image := _paint(0.0)
	assert_bool(image.is_invisible()).override_failure_message("a snow with nothing set painted the ground") \
			.is_true()


# Keyed by BOARD position: the same ground snows the same however the rect around it is cut.
func test_the_same_ground_snows_the_same_in_a_wider_rect() -> void:
	var rect := _rect()
	var wide := rect.grow(2)
	var image := _paint(0.5, 0.3, 0.05)
	var wider := _paint(0.5, 0.3, 0.05, wide)
	var shift := (rect.position - wide.position) * PX
	for y in image.get_height():
		for x in image.get_width():
			assert_bool(image.get_pixel(x, y).is_equal_approx(wider.get_pixel(x + shift.x, y + shift.y))) \
					.override_failure_message("pixel %s snowed differently in a wider rect" % Vector2i(x, y)).is_true()
