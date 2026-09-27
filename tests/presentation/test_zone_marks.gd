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
