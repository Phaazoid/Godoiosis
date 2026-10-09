# What the snow does to the ground's look (#1269, #1278): SnowGround paints the cover decal's texture
# and its relief. The dev's rule from the rain carries over -- nothing past its tile or over nothing --
# so every pixel is checked against the cell it sits in, and water and holes take none. A slope keeps
# less of the cover than flat ground, and the relief stands the snow up off the ground.
#
# The content razor: how much each strength covers is authored (Resources/WeatherLooks/), so the
# strengths are measured against the painter itself -- a higher cover is a superset of a lower one --
# rather than against any number.
extends GdUnitTestSuite

const BB := preload("res://play/board_builder.gd")
const HOLE_TILE := Vector2i(18, 2)
const WATER := Vector2i(1, 1)
const HOLE := Vector2i(3, 2)
const RAMP := Vector2i(1, 3)
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


func _paint(cover: float, frost := 0.0, flecks := 0.0, rect := Rect2i(), slope_cover := 1.0) -> Image:
	return SnowGround.paint_cover(board.grid, board.board_heights, rect if rect.has_area() else _rect(), cover,
			slope_cover, frost, flecks, WHITE)


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


# Snow slides off a slope (#1278): a ramp keeps less of the cover at a low slope_cover than at 1, and
# no other cell changes. Alpha alone is compared, since a patch's rim colour reads the pixel below it.
func test_a_slope_sheds_snow_and_flat_ground_keeps_it() -> void:
	(board.board_heights as BoardHeights).set_corners(RAMP, Vector4i(2, 2, 0, 0))
	var rect := _rect()
	var kept := _paint(0.9, 0.0, 0.0, Rect2i(), 1.0)
	var shed := _paint(0.9, 0.0, 0.0, Rect2i(), 0.2)
	var on_ramp_kept := 0
	var on_ramp_shed := 0
	for y in kept.get_height():
		for x in kept.get_width():
			var a_kept := kept.get_pixel(x, y).a >= 1.0
			var a_shed := shed.get_pixel(x, y).a >= 1.0
			if _cell_of(Vector2i(x, y), rect) == RAMP:
				on_ramp_kept += 1 if a_kept else 0
				on_ramp_shed += 1 if a_shed else 0
				assert_bool(a_kept or not a_shed).override_failure_message(
						"the ramp shed snow at %s that it kept at full cover" % Vector2i(x, y)).is_true()
			else:
				assert_bool(a_kept == a_shed).override_failure_message(
						"flat ground at %s changed with the slopes' share" % Vector2i(x, y)).is_true()
	assert_int(on_ramp_kept).override_failure_message("fixture: the ramp took no snow at all").is_greater(0)
	assert_int(on_ramp_shed).override_failure_message(
			"the ramp kept %d of %d snow pixels at a fifth of the cover" % [on_ramp_shed, on_ramp_kept]) 			.is_less(on_ramp_kept)


# A block of snow, columns [0, edge) under snow and the rest bare.
func _cover_block(size: Vector2i, edge: int) -> Image:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 0, edge, size.y), WHITE)
	return image


func _tilt(normal_map: Image, at: Vector2i) -> float:
	var c := normal_map.get_pixel(at.x, at.y)
	return Vector2(c.r - 0.5, c.g - 0.5).length()


# Smooth snow with no edge in reach faces straight up; its edge tilts, and harder at a stronger relief.
func test_relief_stands_the_snow_up_at_its_edge() -> void:
	var size := Vector2i(32, 32)
	var cover := _cover_block(size, 16)
	var soft := SnowGround.relief(cover, Vector2i.ZERO, 3.0, 1.0, 0.0, 5.0)
	var hard := SnowGround.relief(cover, Vector2i.ZERO, 12.0, 1.0, 0.0, 5.0)
	assert_vector(Vector2(soft.get_size())).override_failure_message("the relief is not the cover's size") 			.is_equal(Vector2(size))
	var interior := Vector2i(6, 16)
	var edge := Vector2i(15, 16)
	assert_float(_tilt(soft, interior)).override_failure_message("flat snow does not face up").is_less(0.02)
	assert_float(_tilt(soft, edge)).override_failure_message("the snow's edge does not tilt").is_greater(0.05)
	assert_float(_tilt(hard, edge)).override_failure_message("a stronger relief tilts the edge no harder") 			.is_greater(_tilt(soft, edge))


# Lumps roughen the top, keyed by BOARD position: the same ground lumps the same in a wider cut, and
# the same input gives the same map.
func test_lumps_roughen_the_top_and_follow_the_board() -> void:
	var size := Vector2i(24, 24)
	var cover := _cover_block(size, size.x)
	var origin := Vector2i(40, 16)
	var map := SnowGround.relief(cover, origin, 6.0, 0.0, 0.5, 5.0)
	var again := SnowGround.relief(cover, origin, 6.0, 0.0, 0.5, 5.0)
	assert_bool(map.get_data() == again.get_data()).override_failure_message("the same snow made two reliefs") 			.is_true()
	var tilted := 0
	for y in range(2, size.y - 2):
		for x in range(2, size.x - 2):
			tilted += 1 if _tilt(map, Vector2i(x, y)) > 0.02 else 0
	assert_int(tilted).override_failure_message("lumps left the top of the snow flat").is_greater(0)
	var wide := SnowGround.relief(_cover_block(size + Vector2i(8, 8), size.x + 8), origin - Vector2i(4, 4), 6.0,
			0.0, 0.5, 5.0)
	for y in range(0, size.y - 1):
		for x in range(0, size.x - 1):
			assert_bool(map.get_pixel(x, y).is_equal_approx(wide.get_pixel(x + 4, y + 4))) 					.override_failure_message("pixel %s lumped differently in a wider cut" % Vector2i(x, y)).is_true()
