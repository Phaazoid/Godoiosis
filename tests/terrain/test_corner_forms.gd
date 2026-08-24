# The corner-form vocabulary (#427 slice 3): a cell's shape is a MASK of raised corners plus a
# climb, and every reading the rules and the renderers get is derived from those four heights.
#
# Pure statics, no scene -- this is the layer everything else in the slice is built on, so it is
# pinned where it is cheapest to run.
#
# The masks are named rather than spelled as integers throughout. A case asserting `mask == 3` would
# be restating the bit layout it is supposed to be checking.
extends GdUnitTestSuite

const NW := Terrain.CORNER_NW
const NE := Terrain.CORNER_NE
const SE := Terrain.CORNER_SE
const SW := Terrain.CORNER_SW
const LEVEL := Terrain.UNITS_PER_LEVEL

# Every form the model allows, by family. Written out rather than generated: the point of the list is
# to say which shapes are LEGAL, and a generator would derive that from the predicate under test.
const OUTER: Array[int] = [NW, NE, SE, SW]
const INNER: Array[int] = [NW | NE | SE, NE | SE | SW, SE | SW | NW, SW | NW | NE]
const CARDINAL: Array[int] = [NW | NE, NE | SE, SE | SW, SW | NW]
const SADDLE: Array[int] = [NW | SE, NE | SW]


# --- the mask round-trips ------------------------------------------------------------

func test_every_legal_form_reads_back_the_mask_it_was_composed_from() -> void:
	# One table composes and one reading reads; a form that composed one way and read back another
	# would be silently wrong for a whole family at a time.
	for climb in [1, LEVEL]:
		for mask in OUTER + INNER + CARDINAL:
			var corners := Terrain.corners_of_form(3, mask, climb)
			assert_int(Terrain.corner_mask(corners)).override_failure_message(
					"mask %d at climb %d composed to %s and read back %d"
					% [mask, climb, corners, Terrain.corner_mask(corners)]).is_equal(mask)
			assert_int(Terrain.climb_of_corners(corners)).override_failure_message(
					"mask %d lost its climb" % mask).is_equal(climb)
			assert_int(Terrain.low_of_corners(corners)).override_failure_message(
					"mask %d moved the cell's own height" % mask).is_equal(3)


func test_flat_ground_is_mask_zero_and_only_mask_zero() -> void:
	# A mask names corners strictly ABOVE the cell's low one, and a cell always has a low one -- so
	# "all four raised" is unreachable and flat has exactly one spelling. Worth pinning because 15
	# looks like a gap in the table rather than an impossibility.
	assert_int(Terrain.corner_mask(Terrain.corners_of_form(3, 0))).is_equal(0)
	assert_int(Terrain.corner_mask(Vector4i(5, 5, 5, 5))).override_failure_message(
			"four equal corners read as something other than flat").is_equal(0)
	assert_int(Terrain.corner_mask(Terrain.corners_of_form(3, NW | NE | SE | SW))).override_failure_message(
			"raising every corner should be flat ground one level up, not a form").is_equal(0)


func test_a_cardinal_ramp_is_one_member_of_the_family() -> void:
	# The dividend #263 collected for wall facings, collected again: RampRise does not name a
	# separate kind of thing, it names four of the sixteen masks.
	for rise: Terrain.RampRise in [Terrain.RampRise.NORTH, Terrain.RampRise.SOUTH,
			Terrain.RampRise.EAST, Terrain.RampRise.WEST]:
		var corners := Terrain.corners_of_ramp(4, rise)
		assert_bool(CARDINAL.has(Terrain.corner_mask(corners))).override_failure_message(
				"%s is not one of the four adjacent-pair masks" % rise).is_true()
		assert_int(Terrain.rise_of_corners(corners)).override_failure_message(
				"%s did not read back through the mask table" % rise).is_equal(rise)


func test_a_corner_form_is_a_shape_RampRise_cannot_name() -> void:
	# It answers NONE rather than erroring, which is the slice-3 migration itself: the push_error
	# existed to find readers that would quietly treat a corner as flat, and they now ask the
	# corners. What survives is the honest question "is this one of the four cardinal ramps?".
	for mask in OUTER + INNER:
		assert_int(Terrain.rise_of_corners(Terrain.corners_of_form(2, mask))) \
				.override_failure_message("mask %d claimed to be a cardinal ramp" % mask) \
				.is_equal(Terrain.RampRise.NONE)


# --- what ground may BE -------------------------------------------------------------

func test_flat_cardinal_and_corner_forms_are_legal_ground() -> void:
	assert_bool(Terrain.is_legal_corners(Terrain.corners_of_form(0, 0))).is_true()
	for climb in [1, LEVEL]:
		for mask in OUTER + INNER + CARDINAL:
			assert_bool(Terrain.is_legal_corners(Terrain.corners_of_form(1, mask, climb))) \
					.override_failure_message("mask %d at climb %d was refused" % [mask, climb]) \
					.is_true()


func test_a_saddle_is_refused_ground() -> void:
	# "no saddles" (dev, 2026-08-23) -- two OPPOSITE raised corners is not a legal form.
	for mask in SADDLE:
		assert_bool(Terrain.is_legal_corners(Terrain.corners_of_form(1, mask))) \
				.override_failure_message("the saddle %d was accepted as ground" % mask).is_false()


func test_steeper_than_45_degrees_is_refused() -> void:
	# "steepness cap at 45 is good" -- one level of rise over one cell of run is the most a form may
	# span, and the cap needs no constant of its own because that IS the unit.
	assert_bool(Terrain.is_legal_corners(Terrain.corners_of_form(0, NW, LEVEL))).is_true()
	assert_bool(Terrain.is_legal_corners(Terrain.corners_of_form(0, NW, LEVEL + 1))) \
			.override_failure_message("a corner steeper than 45 degrees was accepted").is_false()


func test_three_distinct_heights_is_not_a_form_at_all() -> void:
	# A form is a mask plus a climb, which is the RCT model the reframe asks for: a low corner and a
	# raised set, nothing between. Refused here rather than left to render as something -- the
	# corner-drag tool is meant to be structurally unable to author one.
	assert_bool(Terrain.is_legal_corners(Vector4i(2, 1, 0, 1))).override_failure_message(
			"a cell with three corner heights was accepted as a form").is_false()


# --- one edge, named from either side -----------------------------------------------

func test_an_edge_reads_the_same_two_points_from_both_of_its_cells() -> void:
	# THE property the whole rules layer now rests on. Two cells share one physical edge; each names
	# it by a different direction, and the pair has to come back in the same SPATIAL order or
	# comparing them is not a test of whether the surfaces meet.
	#
	# Built as one continuous slope across two cells: a north-rising ramp at height 0 and the flat
	# cell above it, which genuinely DO meet along the shared edge.
	var ramp := Terrain.corners_of_ramp(0, Terrain.RampRise.NORTH)
	var above := Terrain.corners_of_form(LEVEL, 0)

	assert_vector(Terrain.edge_of_corners(ramp, Vector2i.UP)).override_failure_message(
			"the ramp's high edge and its neighbour's low edge disagree, so a step that should "
			+ "connect cannot").is_equal(Terrain.edge_of_corners(above, Vector2i.DOWN))


func test_a_sideways_edge_does_not_meet_its_flat_neighbour() -> void:
	# The no-sideways-entry rule, falling out of the same comparison rather than needing a clause:
	# a north-rising ramp's east edge is (high, low) against a flat neighbour's (low, low).
	var ramp := Terrain.corners_of_ramp(0, Terrain.RampRise.NORTH)
	var beside := Terrain.corners_of_form(0, 0)

	assert_bool(Terrain.edge_of_corners(ramp, Vector2i.RIGHT)
			== Terrain.edge_of_corners(beside, Vector2i.LEFT)).override_failure_message(
			"a ramp's SIDE met its flat neighbour, so a unit could walk onto the slope sideways"
			).is_false()


func test_two_parallel_ramps_DO_meet_along_the_slope() -> void:
	# The dev's 2026-08-23 ruling ("let's allow it. I'll feel test that afterwards"): where two
	# adjacent slopes genuinely touch along their shared edge, the step is legal. Pinned as its own
	# case because the two older sideways cases both use a ramp beside FLAT ground and keep passing
	# under the new rule -- so without this one, nothing can see the ruling at all.
	var west := Terrain.corners_of_ramp(0, Terrain.RampRise.NORTH)
	var east := Terrain.corners_of_ramp(0, Terrain.RampRise.NORTH)

	assert_vector(Terrain.edge_of_corners(west, Vector2i.RIGHT)).override_failure_message(
			"two ramps rising the same way do not meet along the slope between them").is_equal(
			Terrain.edge_of_corners(east, Vector2i.LEFT))


func test_the_two_sides_of_an_edge_are_listed_in_the_SAME_SPATIAL_ORDER() -> void:
	# The ordering rule on all four axes, and the only cases that can SEE it: every pair here meets
	# along an edge whose two ends are at DIFFERENT heights, so a transposed pairing compares
	# (high, low) against (low, high) and dies. The cases above all use edges that are level end to
	# end, which a transposition passes.
	#
	# Each pair is one raised corner meeting its mirror image across the shared seam.
	var pairs := [
		[Terrain.corners_of_form(0, NW, LEVEL), Vector2i.UP, Terrain.corners_of_form(0, SW, LEVEL)],
		[Terrain.corners_of_form(0, SW, LEVEL), Vector2i.DOWN, Terrain.corners_of_form(0, NW, LEVEL)],
		[Terrain.corners_of_form(0, NE, LEVEL), Vector2i.RIGHT, Terrain.corners_of_form(0, NW, LEVEL)],
		[Terrain.corners_of_form(0, NW, LEVEL), Vector2i.LEFT, Terrain.corners_of_form(0, NE, LEVEL)],
	]
	for pair in pairs:
		var here: Vector4i = pair[0]
		var dir: Vector2i = pair[1]
		var there: Vector4i = pair[2]
		var mine := Terrain.edge_of_corners(here, dir)
		assert_bool(mine.x != mine.y).override_failure_message(
				"the %s fixture is level end to end, so this case cannot see a transposition" % dir
				).is_true()
		assert_vector(mine).override_failure_message(
				"stepping %s: this cell reads its edge as %s and its neighbour reads the SAME edge "
				% [dir, mine] + "as %s -- the two are not listed in one spatial order"
				% Terrain.edge_of_corners(there, -dir)).is_equal(
				Terrain.edge_of_corners(there, -dir))


# --- the surface between the corners -------------------------------------------------

func test_the_surface_meets_every_corner_exactly() -> void:
	# u is east across the cell and v south down it, so (0,0) is NW and (1,1) is SE. If the two ever
	# transposed, a cardinal ramp would still look right and every corner form would face wrong.
	for mask in OUTER + INNER + CARDINAL:
		var corners := Terrain.corners_of_form(1, mask)
		var at := {Vector2(0, 0): corners.x, Vector2(1, 0): corners.y,
			Vector2(1, 1): corners.z, Vector2(0, 1): corners.w}
		for uv: Vector2 in at:
			assert_float(Terrain.height_at_uv(corners, uv.x, uv.y)).override_failure_message(
					"mask %d: the surface at %s is not the corner height stored there" % [mask, uv]
					).is_equal_approx(float(at[uv]), 0.001)


func test_an_outer_corner_has_a_FLAT_half() -> void:
	# The diagonal is real geometry, not a tie-break: joining the two EQUAL corners gives an outer
	# corner a flat half and a sloped half, which is the RCT shape. Take the other diagonal and it
	# becomes a hip roof -- both meet the corners, so only a point INSIDE can tell them apart.
	var corners := Terrain.corners_of_form(0, NW, LEVEL)   # NW raised, the other three at 0

	# Deep in the SE triangle, which the NE--SW diagonal cuts off from the raised corner entirely.
	assert_float(Terrain.height_at_uv(corners, 0.9, 0.9)).override_failure_message(
			"an outer corner's far half is not flat, so the cell was split on the wrong diagonal"
			).is_equal_approx(0.0, 0.001)
	# ...and the raised half genuinely slopes.
	assert_float(Terrain.height_at_uv(corners, 0.25, 0.25)).override_failure_message(
			"an outer corner's near half does not slope").is_greater(0.1)


func test_an_inner_corner_has_a_FLAT_half_at_the_TOP() -> void:
	# The inner corner is the outer one's complement, and it splits on the same diagonal -- so its
	# flat half is the raised one. A single hardcoded diagonal gets one of the two families wrong.
	var corners := Terrain.corners_of_form(0, NW | NE | SW, LEVEL)   # only SE is low

	assert_float(Terrain.height_at_uv(corners, 0.1, 0.1)).override_failure_message(
			"an inner corner's raised half is not flat, so it was split on the wrong diagonal"
			).is_equal_approx(float(LEVEL), 0.001)


func test_a_cardinal_ramp_is_planar_whichever_diagonal_is_taken() -> void:
	# Flat and cardinal forms have no equal-corner diagonal to prefer, so the split is arbitrary for
	# them -- and it has to be, because a plane is a plane. Sampled across the cell rather than at
	# the corners, which any split reproduces.
	var corners := Terrain.corners_of_ramp(0, Terrain.RampRise.NORTH, LEVEL)
	for v in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for u in [0.1, 0.5, 0.9]:
			# North is -v, so the surface falls linearly from LEVEL at v=0 to 0 at v=1.
			assert_float(Terrain.height_at_uv(corners, u, v)).override_failure_message(
					"a north ramp is not planar at (%s, %s)" % [u, v]).is_equal_approx(
					float(LEVEL) * (1.0 - v), 0.001)


func test_the_gradient_is_cardinal_for_a_ramp_and_diagonal_for_a_corner() -> void:
	# What the tilt and the markup read. A cardinal ramp must have no cross-slope at all, or every
	# arrow on it skews; a corner form must have both components, which is the whole reason
	# lie_on could not keep taking a RampRise.
	var north := Terrain.corners_of_ramp(0, Terrain.RampRise.NORTH, LEVEL)
	assert_float(Terrain.gradient_of_corners(north).x).override_failure_message(
			"a north ramp slopes east-west").is_equal_approx(0.0, 0.001)
	assert_float(Terrain.gradient_of_corners(north).y).override_failure_message(
			"a north ramp does not fall southward by its own climb").is_equal_approx(
			-float(LEVEL), 0.001)

	var corner := Terrain.corners_of_form(0, NW, LEVEL)
	var diagonal := Terrain.gradient_of_corners(corner)
	assert_float(absf(diagonal.x)).override_failure_message(
			"an outer corner has no east-west slope, so its downhill is not diagonal").is_greater(0.1)
	assert_float(absf(diagonal.y)).override_failure_message(
			"an outer corner has no north-south slope, so its downhill is not diagonal").is_greater(0.1)


func test_the_centre_height_is_where_the_corners_average() -> void:
	# Where anything lying on the surface pivots. For a cardinal ramp it is the low side plus half
	# the climb, which is exactly what lie_on has always used -- so the generalisation cannot move
	# markup on the boards that already exist.
	var north := Terrain.corners_of_ramp(4, Terrain.RampRise.NORTH, LEVEL)
	assert_float(Terrain.centre_height_of_corners(north)).override_failure_message(
			"a ramp's centre is no longer its low side plus half its climb").is_equal_approx(
			4.0 + float(LEVEL) * 0.5, 0.001)
	assert_float(Terrain.centre_height_of_corners(Terrain.corners_of_form(4, 0))).is_equal_approx(
			4.0, 0.001)
