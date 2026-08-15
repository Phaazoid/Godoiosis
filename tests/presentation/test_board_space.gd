# BoardSpace (#205): the 3D stack's one cell<->world convention, pinned at its
# contract — round-trips, the top-face standing point, the documented boundary
# rule (a position exactly on a face floors upward), and the floor-vs-int-cast
# trap on negative coordinates. CELL_SIZE and NO_CELL are conventions, not feel.
extends GdUnitTestSuite


func test_cell_center_round_trips_across_the_lattice() -> void:
	for x in range(-2, 4):
		for y in range(-1, 4):
			for z in range(-2, 4):
				var cell := Vector3i(x, y, z)
				assert_that(BoardSpace.cell_of(BoardSpace.cell_center(cell))).is_equal(cell)


func test_standing_point_is_the_top_face_center() -> void:
	# The look-dev sprites' authored positions are these values: ground cell -> y 1.0.
	assert_that(BoardSpace.standing_point(Vector3i(5, 0, 8))).is_equal(Vector3(5.5, 1.0, 8.5))
	assert_that(BoardSpace.standing_point(Vector3i(8, 2, 3))).is_equal(Vector3(8.5, 3.0, 3.5))


func test_boundary_rule_points_on_a_face_floor_upward() -> void:
	# Documented rule: standing_point sits exactly on the face between y and y+1,
	# so cell_of assigns it to the cell ABOVE. Volume queries use interior points.
	var cell := Vector3i(3, 0, 3)
	assert_that(BoardSpace.cell_of(BoardSpace.standing_point(cell))).is_equal(cell + Vector3i.UP)


func test_negative_coordinates_floor_not_truncate() -> void:
	# int-cast would give (0, 0, 0); floor must give (-1, 0, -1).
	assert_that(BoardSpace.cell_of(Vector3(-0.25, 0.5, -0.25))).is_equal(Vector3i(-1, 0, -1))


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


func test_a_flat_boards_top_level_is_one_cell_up_not_zero() -> void:
	# The y=0-vs-y=1 trap (#231). A level-0 cell sits at y-index 0, so the face things stand on
	# is FLAT_TOP_LEVEL cells up. A picker fallback plane at y=0 would be the slab's BOTTOM and
	# would resolve the wrong column at grazing angles.
	var cell := BoardSpace.of_cell(Vector2i(4, 7), 0)
	assert_that(BoardSpace.standing_point(cell).y) \
		.override_failure_message("the flat standing face moved off FLAT_TOP_LEVEL") \
		.is_equal(BoardSpace.FLAT_TOP_LEVEL * BoardSpace.CELL_SIZE)
	# The two spellings of that face must agree (#273): surface_y is what the mirrors read, and
	# FLAT_TOP_LEVEL is what the picker's fallback plane reads. Drift here puts units and the
	# pointer on different faces.
	assert_float(BoardSpace.surface_y(0)).is_equal(BoardSpace.FLAT_TOP_LEVEL * BoardSpace.CELL_SIZE)


func test_a_surface_sits_on_top_of_its_own_level() -> void:
	# A level-E block occupies [E .. E+1], so E's surface is E+1 — the arithmetic every column,
	# unit and overlay in the 3D stack is built on.
	assert_float(BoardSpace.surface_y(2)).is_equal(3.0 * BoardSpace.CELL_SIZE)
	assert_float(BoardSpace.surface_y(-1)).is_equal(0.0)   # a dip's floor, not a hole
	assert_float(BoardSpace.standing_point(BoardSpace.of_cell(Vector2i(1, 1), 3)).y) \
		.is_equal(BoardSpace.surface_y(3))


func test_a_ramp_stands_things_half_a_level_up_its_slope() -> void:
	# The one place presentation and rules deliberately disagree: the RULES call a ramp its low
	# side, and verticality.md rules the visual midpoint presentational. Anything standing on one
	# rides the slope rather than sinking into its low edge.
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(2, 2), 1, Terrain.RampRise.NONE)
	heights.set_cell(Vector2i(3, 2), 1, Terrain.RampRise.EAST)

	assert_float(BoardSpace.surface_point(Vector2i(2, 2), heights).y).is_equal(BoardSpace.surface_y(1))
	assert_float(BoardSpace.surface_point(Vector2i(3, 2), heights).y) \
		.is_equal(BoardSpace.surface_y(1) + BoardSpace.CELL_SIZE * 0.5)


func test_a_board_with_no_heights_wired_reads_as_flat() -> void:
	# The headless Play boards never set one, and every anchor still has to resolve.
	assert_float(BoardSpace.surface_point(Vector2i(4, 4), null).y).is_equal(BoardSpace.surface_y(0))
