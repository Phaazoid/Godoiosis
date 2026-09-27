# ZoneMarks (#955 part 1), pure: which sides of a zone's cells face out, where its emblem goes, and
# what each look's generated art does at an edge. Relationships only -- a knob moves every number
# here, so no value is pinned (#8's tuning razor).
extends GdUnitTestSuite

const N := ZoneMarks.Side.N
const E := ZoneMarks.Side.E
const S := ZoneMarks.Side.S
const W := ZoneMarks.Side.W


func before_test() -> void:
	Experiments.reset_for_test()
	ZoneMarks.restyle()


func _cells(list: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(list)
	return cells


func test_a_square_faces_out_on_its_rim_and_nowhere_inside() -> void:
	var masks := ZoneMarks.cell_masks(_cells([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]))
	assert_int(masks[Vector2i(0, 0)]).is_equal(N | W)
	assert_int(masks[Vector2i(1, 0)]).is_equal(N | E)
	assert_int(masks[Vector2i(0, 1)]).is_equal(S | W)
	assert_int(masks[Vector2i(1, 1)]).is_equal(S | E)


func test_an_l_notches_its_inner_corner() -> void:
	# (0,0) (0,1) (1,1): the corner cell (0,1) has zone on its north and east, and the diagonal between
	# them, (1,0), is outside -- so it owes the band a notch in its north-east corner.
	var masks := ZoneMarks.cell_masks(_cells([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]))
	assert_int(masks[Vector2i(0, 1)] & ZoneMarks.Side.NE).is_equal(ZoneMarks.Side.NE)
	assert_int(masks[Vector2i(0, 1)] & (N | E)).is_equal(0)


func test_a_lone_cell_faces_out_on_every_side() -> void:
	# Membership is the zone handed in, so a neighbour in ANOTHER zone is outside this one too.
	var masks := ZoneMarks.cell_masks(_cells([Vector2i(0, 0)]))
	assert_int(masks[Vector2i(0, 0)]).is_equal(N | E | S | W)


func test_the_emblem_sits_inside_its_zone() -> void:
	# An L's middle falls outside it; the emblem must still land on one of its own cells.
	var l := _cells([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)])
	assert_bool(l.has(ZoneMarks.emblem_cell(l))).is_true()
	var lone := _cells([Vector2i(4, 7)])
	assert_that(ZoneMarks.emblem_cell(lone)).is_equal(Vector2i(4, 7))


func test_every_kind_a_player_sees_has_an_emblem_and_a_colour() -> void:
	for kind: ZoneManager.Kind in ZoneManager.Kind.values():
		if ZoneManager.AUTHORING_KINDS.has(kind):
			continue
		assert_object(ZoneMarks.emblem_of(kind)).override_failure_message(
				"zone kind %s has no emblem" % ZoneManager.Kind.keys()[kind]).is_not_null()
		assert_float(ZoneMarks.colour_of(kind).a).is_equal(1.0)


# Texel row 0 is the NORTH edge. The painted edge is solid white against a north edge (past its
# outline) and the plain fill in the middle of the cell.
func test_the_painted_edge_is_solid_at_the_edge_and_the_fill_inside() -> void:
	var img := ZoneMarks.image(ZoneMarks.Look.PAINTED_EDGE, N)
	var size := img.get_height()
	var middle := img.get_pixel(size / 2, size / 2)
	var band_row := int(ceil(ZoneMarks.ZONE_EDGE_OUTLINE)) + 1
	var band := img.get_pixel(size / 2, band_row)
	assert_float(band.a).is_greater(middle.a)
	assert_that(band).override_failure_message("the band is not white -- it could not take a tint").is_equal(
			Color(1, 1, 1, band.a))
	assert_float(middle.a).is_equal_approx(ZoneMarks.ZONE_FILL_ALPHA, 0.01)
	# The south side faces nowhere, so it carries no band.
	assert_float(img.get_pixel(size / 2, size - 1 - band_row).a).is_equal_approx(ZoneMarks.ZONE_FILL_ALPHA, 0.01)


func test_the_soft_rim_fades_inward() -> void:
	var img := ZoneMarks.image(ZoneMarks.Look.SOFT_RIM, W)
	var size := img.get_width()
	var near := img.get_pixel(int(ceil(ZoneMarks.ZONE_EDGE_OUTLINE)) + 3, size / 2).a
	var further := img.get_pixel(size / 3, size / 2).a
	var middle := img.get_pixel(size - 2, size / 2).a
	assert_float(near).is_greater(further)
	assert_float(further).is_greater_equal(middle)


# Look C wears B's rim under its wall (dev, 2026-09-27), held as the two looks' art agreeing.
func test_the_light_wall_stands_on_the_soft_rim() -> void:
	for mask: int in [N, N | E, N | E | S | W, ZoneMarks.Side.NE]:
		var wall := ZoneMarks.image(ZoneMarks.Look.LIGHT_WALL, mask).get_data()
		var rim := ZoneMarks.image(ZoneMarks.Look.SOFT_RIM, mask).get_data()
		assert_bool(wall == rim).override_failure_message(
				"look C's ground art for mask %d is not B's rim" % mask).is_true()


# A hair off the point in every direction is still one of the zone's cells: inside, and off the border.
func _strictly_inside(point: Vector3, cells: Array[Vector2i]) -> bool:
	for dx: float in [-0.001, 0.001]:
		for dz: float in [-0.001, 0.001]:
			if not cells.has(Vector2i(floori(point.x + dx), floori(point.z + dz))):
				return false
	return true


# The wall stands just inside the zone, so it never shares a plane with a block face on the border (the
# z-fight #955's play found), and its ends meet at an outer corner, a straight run and an L's notch.
func test_the_wall_outline_stands_inside_its_zone_and_closes_round_the_notch() -> void:
	var shapes: Array = [_cells([Vector2i(0, 0)]), _cells([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)])]
	for listed: Array in shapes:
		var shape := _cells(listed)
		var strips := ZoneMarks.wall_outline(shape, null)
		assert_int(strips.size()).is_equal(OverlayManager.outline_segments(shape, null).size())
		var starts: Array[Vector3] = []
		for strip in strips:
			starts.append(strip[0])
		for strip in strips:
			for point in strip:
				assert_bool(_strictly_inside(point, shape)).override_failure_message(
						"a wall end at %s stands on or outside the zone %s" % [point, shape]).is_true()
			var end := strip[1]
			assert_bool(starts.any(func(start: Vector3) -> bool: return start.is_equal_approx(end))) \
					.override_failure_message("a strip ends at %s and none starts there: the ring is open" % end) \
					.is_true()


func test_a_knob_regenerates_the_art() -> void:
	var before := ZoneMarks.texture(ZoneMarks.Look.PAINTED_EDGE, N)
	var old := ZoneMarks.ZONE_BAND_WIDTH
	ZoneMarks.ZONE_BAND_WIDTH = old + 0.1
	ZoneMarks.restyle()
	var after := ZoneMarks.texture(ZoneMarks.Look.PAINTED_EDGE, N)
	ZoneMarks.ZONE_BAND_WIDTH = old
	ZoneMarks.restyle()
	assert_object(after).is_not_same(before)


func test_the_experiment_is_a_choice_the_look_reads() -> void:
	Experiments.set_choice(Experiments.Flag.ZONE_LOOK, ZoneMarks.Look.LIGHT_WALL)
	assert_int(ZoneMarks.look()).is_equal(ZoneMarks.Look.LIGHT_WALL)
	assert_int(Experiments.options_of(Experiments.Flag.ZONE_LOOK).size()).is_equal(ZoneMarks.Look.size())
