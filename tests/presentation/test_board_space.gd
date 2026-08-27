# BoardSpace (#205): the 3D stack's one cell<->world convention, pinned at its
# contract — round-trips, the top-face standing point, the documented boundary
# rule (a position exactly on a face floors upward), and the floor-vs-int-cast
# trap on negative coordinates. CELL_SIZE and NO_CELL are conventions, not feel.
#
# The vertical index is a ROW of one height UNIT since #427 slice 2, so every case below states
# which of the two it means: a rule HEIGHT goes through top_row_of, a row is passed raw.
extends GdUnitTestSuite


func test_cell_center_round_trips_across_the_lattice() -> void:
	for x in range(-2, 4):
		for y in range(-1, 4):
			for z in range(-2, 4):
				var cell := Vector3i(x, y, z)
				assert_that(BoardSpace.cell_of(BoardSpace.cell_center(cell))).is_equal(cell)


func test_standing_point_is_the_top_face_center() -> void:
	# The look-dev sprites' authored positions are these values: a GROUND cell -> y 1.0, which is
	# what a slab one LEVEL deep is worth however many rows that is.
	var ground := BoardSpace.of_cell(Vector2i(5, 8), BoardSpace.top_row_of(0))
	assert_that(BoardSpace.standing_point(ground)).is_equal(Vector3(5.5, 1.0, 8.5))
	var raised := BoardSpace.of_cell(Vector2i(8, 3), BoardSpace.top_row_of(2 * Terrain.UNITS_PER_LEVEL))
	assert_that(BoardSpace.standing_point(raised)).is_equal(Vector3(8.5, 3.0, 3.5))


func test_boundary_rule_points_on_a_face_floor_upward() -> void:
	# Documented rule: standing_point sits exactly on the face between y and y+1,
	# so cell_of assigns it to the cell ABOVE. Volume queries use interior points.
	var cell := Vector3i(3, 0, 3)
	assert_that(BoardSpace.cell_of(BoardSpace.standing_point(cell))).is_equal(cell + Vector3i.UP)


func test_negative_coordinates_floor_not_truncate() -> void:
	# int-cast would give (0, ., 0); floor must give (-1, ., -1). The y is incidental to the trap
	# but stated exactly: 0.5 world is a whole row up now, not half of one.
	assert_that(BoardSpace.cell_of(Vector3(-0.25, 0.5, -0.25))).is_equal(Vector3i(-1, 1, -1))


func test_no_cell_sits_outside_any_real_board() -> void:
	assert_bool(BoardSpace.NO_CELL.y < -100).is_true()


func test_flat_and_of_cell_bridge_the_sim_and_mirror_conventions() -> void:
	assert_that(BoardSpace.flat(Vector3i(5, 2, 8))).is_equal(Vector2i(5, 8))
	assert_that(BoardSpace.of_cell(Vector2i(5, 8), 0)).is_equal(Vector3i(5, 0, 8))
	assert_that(BoardSpace.flat(BoardSpace.of_cell(Vector2i(-3, 7), 0))).is_equal(Vector2i(-3, 7))


func test_flat_maps_the_no_cell_sentinel_onto_the_2d_one() -> void:
	# The injected pointer source hands HoverPresenter flat(_pointer_cell) raw — a 3D
	# miss must read as the 2D "no cell" by VALUE, never as a real coordinate.
	assert_that(BoardSpace.flat(BoardSpace.NO_CELL)).is_equal(GridUtils.NO_CELL)


func test_a_flat_boards_top_face_is_one_level_up_not_zero() -> void:
	# The y=0-vs-y=1 trap (#231). A height-0 cell's slab reaches down UNITS_PER_LEVEL rows, so the
	# face things stand on is FLAT_TOP_ROW rows up. A picker fallback plane at y=0 would be the
	# slab's BOTTOM and would resolve the wrong column at grazing angles.
	var cell := BoardSpace.of_cell(Vector2i(4, 7), BoardSpace.top_row_of(0))
	assert_that(BoardSpace.standing_point(cell).y) \
		.override_failure_message("the flat standing face moved off FLAT_TOP_ROW") \
		.is_equal(BoardSpace.FLAT_TOP_ROW * BoardSpace.ROW_HEIGHT)
	# The two spellings of that face must agree (#273): surface_y is what the mirrors read, and
	# FLAT_TOP_ROW is what the picker's fallback plane reads. Drift here puts units and the
	# pointer on different faces.
	assert_float(BoardSpace.surface_y(BoardSpace.top_row_of(0))) \
		.is_equal(BoardSpace.FLAT_TOP_ROW * BoardSpace.ROW_HEIGHT)


func test_a_surface_sits_on_top_of_its_own_row() -> void:
	# A row-R block occupies [R .. R+1] * ROW_HEIGHT, so R's surface is R+1 — the arithmetic every
	# column, unit and overlay in the 3D stack is built on.
	assert_float(BoardSpace.surface_y(2)).is_equal(3.0 * BoardSpace.ROW_HEIGHT)
	assert_float(BoardSpace.surface_y(-1)).is_equal(0.0)   # a dip's floor, not a hole
	assert_float(BoardSpace.standing_point(BoardSpace.of_cell(Vector2i(1, 1), 3)).y) \
		.is_equal(BoardSpace.surface_y(3))


# The re-metric's own contract (#427 slice 2): a ROW is one height unit, and a slab is still one
# LEVEL deep — which together are why every world position survived the change. Derived from the
# constants rather than from 0.5, so re-basing the unit again cannot leave this passing by luck.
func test_one_row_is_one_height_unit_and_a_slab_is_one_level() -> void:
	assert_float(BoardSpace.ROW_HEIGHT * Terrain.UNITS_PER_LEVEL) \
		.override_failure_message("UNITS_PER_LEVEL rows no longer make one cell of height") \
		.is_equal(BoardSpace.CELL_SIZE)
	# One unit of rule height is one row of world height, at every height.
	for height in [-3, -1, 0, 1, 2, 5]:
		assert_float(BoardSpace.surface_y(BoardSpace.top_row_of(height))) \
			.override_failure_message("height %d does not sit one level above its own floor" % height) \
			.is_equal_approx(float(height) * BoardSpace.ROW_HEIGHT + BoardSpace.CELL_SIZE, 0.0001)


func test_a_ramp_stands_things_half_its_climb_up_its_slope() -> void:
	# The one place presentation and rules deliberately disagree: the RULES call a ramp its low
	# side, and verticality.md rules the visual midpoint presentational. Anything standing on one
	# rides the slope rather than sinking into its low edge — and how far it rides is the ramp's
	# OWN climb since slice 2, so the gentle slope lifts half as much.
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(2, 2), 2, Terrain.RampRise.NONE)
	heights.set_cell(Vector2i(3, 2), 2, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(4, 2), 2, Terrain.RampRise.EAST, 1)
	var shelf := BoardSpace.surface_y(BoardSpace.top_row_of(2))

	assert_float(BoardSpace.surface_point(Vector2i(2, 2), heights).y).is_equal(shelf)
	assert_float(BoardSpace.surface_point(Vector2i(3, 2), heights).y) \
		.is_equal(shelf + Terrain.UNITS_PER_LEVEL * BoardSpace.ROW_HEIGHT * 0.5)
	assert_float(BoardSpace.surface_point(Vector2i(4, 2), heights).y) \
		.override_failure_message("a gentle ramp lifts as if it were a 45 degree one") \
		.is_equal(shelf + BoardSpace.ROW_HEIGHT * 0.5)


func test_a_board_with_no_heights_wired_reads_as_flat() -> void:
	# The headless Play boards never set one, and every anchor still has to resolve.
	assert_float(BoardSpace.surface_point(Vector2i(4, 4), null).y) \
		.is_equal(BoardSpace.surface_y(BoardSpace.top_row_of(0)))
	assert_that(BoardSpace.surface_transform(Vector2i(4, 4), null).basis).is_equal(Basis.IDENTITY)


# surface_height_at (#259 rework round 2): the plane a sliding sprite sticks to. Asserted as
# CONTINUITY -- a ramp's plane meets its own edges at the heights the ramp joins, so a tumble
# crossing cell borders never steps -- plus the flat constant and the null-heights fallback.
func test_surface_height_under_a_position_is_continuous_across_a_ramp() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(2, 2), 2, Terrain.RampRise.NONE)   # the top shelf
	heights.set_cell(Vector2i(3, 2), 2, Terrain.RampRise.EAST)   # rises toward east: high edge east
	# The ramp's centre is its surface_point; its EAST edge (x=4.0) meets the height it climbs TO,
	# its WEST edge (x=3.0) meets its own -- the two heights the ramp joins (#281's own geometry).
	var mid := BoardSpace.surface_point(Vector2i(3, 2), heights)
	assert_float(BoardSpace.surface_height_at(Vector2i(3, 2), mid.x, mid.z, heights)).is_equal_approx(mid.y, 0.0001)
	assert_float(BoardSpace.surface_height_at(Vector2i(3, 2), 4.0, 2.5, heights)) \
			.is_equal_approx(BoardSpace.surface_y(BoardSpace.top_row_of(2 + Terrain.UNITS_PER_LEVEL)), 0.0001)
	assert_float(BoardSpace.surface_height_at(Vector2i(3, 2), 3.0, 2.5, heights)) \
			.is_equal_approx(BoardSpace.surface_y(BoardSpace.top_row_of(2)), 0.0001)
	# A flat cell is constant everywhere on it; no heights resolves like every other anchor.
	assert_float(BoardSpace.surface_height_at(Vector2i(2, 2), 2.1, 2.9, heights)) \
			.is_equal_approx(BoardSpace.surface_y(BoardSpace.top_row_of(2)), 0.0001)
	assert_float(BoardSpace.surface_height_at(Vector2i(4, 4), 4.2, 4.8, null)) \
			.is_equal_approx(BoardSpace.surface_y(BoardSpace.top_row_of(0)), 0.0001)


# --- How markup LIES on a surface (#281) --------------------------------------------

# Markup on a ramp has to reach the two heights the ramp CONNECTS -- its low edge at its own, its
# high edge at the one it climbs to. Asserted as that geometry rather than as an angle, so it stays
# true of whatever the wedge's profile is and cannot be satisfied by a quad that merely tilts
# (one rotated but unstretched would fall short of both edges).
#
# Every rise is checked because "no sideways entry" means each one connects a DIFFERENT pair of
# neighbours, and a sign error shows up in exactly one of the four. Every CLIMB is checked because
# steepness is authored since #427 slice 2, and a gentle ramp whose markup spanned a full level
# would hang a whole unit off its own high edge.
func test_markup_on_a_ramp_spans_the_two_heights_the_ramp_joins() -> void:
	for climb in [1, Terrain.UNITS_PER_LEVEL]:
		for rise: Terrain.RampRise in [Terrain.RampRise.NORTH, Terrain.RampRise.SOUTH,
				Terrain.RampRise.EAST, Terrain.RampRise.WEST]:
			var cell := Vector2i(3, 2)
			var heights := BoardHeights.new()
			heights.set_cell(cell, 2, rise, climb)
			var xform := BoardSpace.surface_transform(cell, heights)
			var label := "%s rising %d" % [Terrain.RampRise.keys()[rise], climb]

			# The quad's own uphill/downhill edge midpoints, in ITS local frame: half a cell either
			# way along whichever local axis the slope runs on.
			var dir := Terrain.rise_direction(rise)
			var edge := Vector3(dir.x, 0.0, dir.y) * 0.5 * BoardSpace.CELL_SIZE
			var high := xform * edge
			var low := xform * -edge

			assert_float(high.y).override_failure_message(
					"%s: the high edge misses the height above" % label) \
				.is_equal_approx(BoardSpace.surface_y(BoardSpace.top_row_of(2 + climb)), 0.0001)
			assert_float(low.y).override_failure_message(
					"%s: the low edge misses the ramp's own height" % label) \
				.is_equal_approx(BoardSpace.surface_y(BoardSpace.top_row_of(2)), 0.0001)

			# ...and it still covers exactly its own cell in plan view, or it would spill onto a
			# neighbour.
			var span := Vector2(high.x - low.x, high.z - low.z).length()
			assert_float(span).override_failure_message(
					"%s: the footprint is not one cell wide" % label) \
				.is_equal_approx(BoardSpace.CELL_SIZE, 0.0001)


func test_markup_lies_flat_where_there_is_no_ramp() -> void:
	# The pair to the above: an unrotated basis on ordinary ground, and the height the cell states.
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(2, 2), 4, Terrain.RampRise.NONE)
	var xform := BoardSpace.surface_transform(Vector2i(2, 2), heights)
	assert_that(xform.basis).is_equal(Basis.IDENTITY)
	assert_float(xform.origin.y).is_equal(BoardSpace.surface_y(BoardSpace.top_row_of(4)))


func test_lie_on_takes_the_row_it_is_given_rather_than_looking_one_up() -> void:
	# The fill path resolves the row itself (of_cell's rule) and asks only the SHAPE question here.
	# Were this to re-derive elevation, a caller's stated row would be silently overridden.
	var flat := BoardSpace.lie_on(BoardSpace.of_cell(Vector2i(6, 6), 3), Vector4i.ZERO)
	assert_float(flat.origin.y).is_equal(BoardSpace.surface_y(3))
	assert_that(flat.basis).is_equal(Basis.IDENTITY)


# --- corner cells: where markup lies and where things stand (#427 slice 4 follow-up) --

# Every legal form, composed the way Terrain composes them. Mask 15 is excluded by the round-trip
# rather than by a listed exception: all four corners raised IS a flat cell at that height, so it
# has no corner form to answer for.
func _legal_forms() -> Array[Vector4i]:
	var forms: Array[Vector4i] = []
	for climb in [1, Terrain.UNITS_PER_LEVEL]:
		for mask in range(16):
			var corners := Terrain.corners_of_form(0, mask, climb)
			if Terrain.is_legal_corners(corners) and Terrain.corner_mask(corners) == mask:
				forms.append(corners)
	return forms


func test_where_a_thing_stands_is_the_surface_under_it_on_every_form() -> void:
	# The two answers that had DRIFTED. surface_point read the corners' mean (the best-fit plane's
	# centre) while surface_height_at read Terrain.height_at_uv (the surface), and on a corner form
	# they differ by a quarter of the climb -- so a unit, a flame or a prop floated. They are now one
	# function evaluated at one point, which is what surface_transform's own comment always claimed.
	var heights := BoardHeights.new()
	var cell := Vector2i(3, 5)
	var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * BoardSpace.CELL_SIZE
	for corners in _legal_forms():
		heights.set_corners(cell, corners)
		assert_float(BoardSpace.surface_point(cell, heights).y).override_failure_message(
				"%s: what stands here is not on the surface here" % corners).is_equal_approx(
				BoardSpace.surface_height_at(cell, centre.x, centre.y, heights), 0.0001)


func test_no_planar_form_moves_at_all() -> void:
	# The scope guard: flat ground and every cardinal ramp must be bit-identical to before, which is
	# what makes this a corner-cell fix rather than a re-tune of every board that exists. Spelled
	# from the rule (low side plus half the climb, tilt about the cross-slope axis) rather than
	# captured from the code, so it checks the claim and not the implementation against itself.
	var heights := BoardHeights.new()
	var cell := Vector2i(2, 2)
	for climb in [1, Terrain.UNITS_PER_LEVEL]:
		for rise in [Terrain.RampRise.NORTH, Terrain.RampRise.EAST,
				Terrain.RampRise.SOUTH, Terrain.RampRise.WEST]:
			heights.set_cell(cell, 4, rise, climb)
			var xform := BoardSpace.surface_transform(cell, heights)
			assert_float(xform.origin.y).override_failure_message(
					"rise %d climb %d: a ramp's centre left its midpoint" % [rise, climb]) \
				.is_equal_approx(BoardSpace.world_y_of_height(4.0 + float(climb) * 0.5), 0.0001)
			assert_bool(xform.basis.is_equal_approx(Basis.IDENTITY)).override_failure_message(
					"rise %d climb %d: a ramp lost its tilt" % [rise, climb]).is_false()


func test_a_corner_cell_gets_no_tilt_because_no_transform_could_carry_one() -> void:
	# lie_on says so rather than approximating. An affine transform maps a plane to a plane, and a
	# corner cell's four surface points are not coplanar -- the best-fit plane CROSSES the ground by
	# a quarter of the climb at every corner, which is the z-fighting this fixed. The fold is the
	# renderer's to carry, in the marker's mesh.
	var heights := BoardHeights.new()
	var cell := Vector2i(1, 1)
	for corners in _legal_forms():
		heights.set_corners(cell, corners)
		if Terrain.is_planar_form(corners):
			continue
		assert_that(BoardSpace.surface_transform(cell, heights).basis).override_failure_message(
				"%s: a corner form was handed a tilt it cannot honour" % corners) \
			.is_equal(Basis.IDENTITY)


# --- the side-on camera yaw (#520 diff 2a) ----------------------------------------------------

# The property, not the number: from the yaw the rig would be at, the camera's own offset direction
# must be PERPENDICULAR to the pair's line -- that is what "side-on" means, and it is what stays
# true if the rig's parking axis is ever re-authored. The rig orbits about Y with the camera at
# local +Z, so yaw t puts it at (sin t, cos t).
func test_the_side_on_yaw_looks_across_the_pair_not_along_it() -> void:
	var pairs := [
		[Vector2i(0, 0), Vector2i(3, 0)],    # along +x
		[Vector2i(0, 0), Vector2i(0, 3)],    # along +z
		[Vector2i(4, 1), Vector2i(1, 4)],    # a diagonal
		[Vector2i(2, 5), Vector2i(7, 3)],    # something off both axes
	]
	for pair: Array in pairs:
		var from: Vector2i = pair[0]
		var to: Vector2i = pair[1]
		var yaw := BoardSpace.side_on_yaw(from, to, 0.0)
		var offset := Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw)))
		var along := Vector2(to.x - from.x, to.y - from.y).normalized()
		assert_float(offset.dot(along)).override_failure_message(
				"%s -> %s: yaw %.2f looks along the pair, not across it" % [from, to, yaw]) \
			.is_equal_approx(0.0, 0.001)


# TWO yaws see a pair side-on, 180 apart. Which one is returned is what makes the shot a SPIN
# rather than a lurch: from either baseline the answer is the near one, so the camera always takes
# the short way round. Driven from both sides of the same pair, since one baseline could pass by
# the function simply always returning the same yaw.
func test_the_side_on_yaw_takes_the_near_side() -> void:
	var from := Vector2i(0, 0)
	var to := Vector2i(3, 0)
	for baseline: float in [0.0, 90.0, 180.0, 270.0, -45.0, 400.0]:
		var yaw := BoardSpace.side_on_yaw(from, to, baseline)
		var near := absf(rad_to_deg(angle_difference(deg_to_rad(baseline), deg_to_rad(yaw))))
		var far := absf(rad_to_deg(angle_difference(deg_to_rad(baseline), deg_to_rad(yaw + 180.0))))
		assert_bool(near <= far).override_failure_message(
				"baseline %.0f took the far side: %.1f away vs %.1f" % [baseline, near, far]) \
			.is_true()


# A pair with no direction cannot be seen side-on, and NAN is the one float that cannot be mistaken
# for a legal yaw -- every real angle is one, so a numeric sentinel would be a shot the camera could
# actually take.
func test_a_pair_on_one_cell_has_no_side_to_be_seen_from() -> void:
	assert_bool(is_nan(BoardSpace.side_on_yaw(Vector2i(2, 2), Vector2i(2, 2), 0.0))).is_true()
