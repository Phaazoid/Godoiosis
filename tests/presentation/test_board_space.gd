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


func test_flat_and_of_flat_bridge_the_flat_board_convention() -> void:
	assert_that(BoardSpace.flat(Vector3i(5, 2, 8))).is_equal(Vector2i(5, 8))
	assert_that(BoardSpace.of_flat(Vector2i(5, 8))).is_equal(Vector3i(5, 0, 8))
	assert_that(BoardSpace.flat(BoardSpace.of_flat(Vector2i(-3, 7)))).is_equal(Vector2i(-3, 7))


func test_flat_maps_the_no_cell_sentinel_onto_the_2d_one() -> void:
	# The injected pointer source hands HoverPresenter flat(_pointer_cell) raw — a 3D
	# miss must read as the 2D "no cell" by VALUE, never as a real coordinate.
	assert_that(BoardSpace.flat(BoardSpace.NO_CELL)).is_equal(GridUtils.NO_CELL)


func test_a_flat_boards_top_level_is_one_cell_up_not_zero() -> void:
	# The y=0-vs-y=1 trap (#231). of_flat parks every cell at y-index 0, so the face
	# things sit on is FLAT_TOP_LEVEL cells up. A picker fallback plane at y=0 would be
	# the slab's BOTTOM and would resolve the wrong column at grazing angles.
	var cell := BoardSpace.of_flat(Vector2i(4, 7))
	assert_that(BoardSpace.standing_point(cell).y) \
		.override_failure_message("the flat standing face moved off FLAT_TOP_LEVEL") \
		.is_equal(BoardSpace.FLAT_TOP_LEVEL * BoardSpace.CELL_SIZE)
	# The derivation, not a second literal: UnitMirror must not drift from the constant.
	assert_float(UnitMirror.COLUMN_TOP).is_equal(BoardSpace.FLAT_TOP_LEVEL * BoardSpace.CELL_SIZE)
