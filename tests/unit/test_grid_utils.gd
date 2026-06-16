# Tier-1 pure-logic harness check (no scene instantiation).
# Validates the gdUnit4 runner end-to-end against real GridUtils math.
extends GdUnitTestSuite

func test_manhattan_distance_basic() -> void:
	assert_int(GridUtils.manhattan_distance(Vector2i(0, 0), Vector2i(3, 2))).is_equal(5)

func test_manhattan_distance_symmetric() -> void:
	var a := Vector2i(-2, 4)
	var b := Vector2i(5, -1)
	assert_int(GridUtils.manhattan_distance(a, b)).is_equal(GridUtils.manhattan_distance(b, a))

func test_manhattan_distance_zero_when_same() -> void:
	assert_int(GridUtils.manhattan_distance(Vector2i(7, 7), Vector2i(7, 7))).is_equal(0)

func test_cardinal_direction_horizontal_on_tie() -> void:
	# |dx| >= |dy| resolves horizontal; the (2,2) tie must go horizontal
	assert_vector(GridUtils.cardinal_direction_between(Vector2i(0, 0), Vector2i(2, 2))).is_equal(Vector2(1, 0))

func test_cardinal_direction_vertical_when_dy_dominates() -> void:
	assert_vector(GridUtils.cardinal_direction_between(Vector2i(0, 0), Vector2i(1, 3))).is_equal(Vector2(0, 1))

func test_cardinal_direction_zero_when_same() -> void:
	assert_vector(GridUtils.cardinal_direction_between(Vector2i(4, 4), Vector2i(4, 4))).is_equal(Vector2.ZERO)

func test_cardinal_direction_negative_axis() -> void:
	assert_vector(GridUtils.cardinal_direction_between(Vector2i(0, 0), Vector2i(-5, 1))).is_equal(Vector2(-1, 0))

# Probe for the flagged latent bug: cells_within_manhattan_range names its parameter
# `range`, shadowing the built-in range() it then calls. The function is used all over
# the live game, so we expect GDScript to resolve the built-in at the call site and the
# shadow to be a cosmetic lint warning only. This test makes that explicit: if the
# shadow actually broke the call, the suite errors here instead of in mystery combat.
func test_cells_within_manhattan_range_radius_one() -> void:
	# Radius 1 = origin + 4 orthogonal neighbours (the diamond of Manhattan distance <= 1).
	var cells := GridUtils.cells_within_manhattan_range(Vector2i(0, 0), 1)
	assert_array(cells).contains_exactly_in_any_order([
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	])

func test_cells_within_manhattan_range_radius_zero_is_just_origin() -> void:
	assert_array(GridUtils.cells_within_manhattan_range(Vector2i(3, 4), 0)).contains_exactly([Vector2i(3, 4)])

func test_cells_within_manhattan_range_excludes_diagonal_corners() -> void:
	# (1,1) is Manhattan distance 2, so radius 1 must NOT include it.
	assert_array(GridUtils.cells_within_manhattan_range(Vector2i(0, 0), 1)).not_contains([Vector2i(1, 1)])
