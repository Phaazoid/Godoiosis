# The sight trace (#258): one trajectory function is both the LoS rule and the bead readout
# ("if the bead can find the target, the shot is valid" -- dev, 2026-08-20). Fixtures are
# hand-painted in the shape of the two bug-report boards (a ramp-less wall column between two
# ground units), never loaded content.
extends GdUnitTestSuite

const NO_UNITS: Array[Unit] = []


func _board_with(heights: BoardHeights) -> BoardContext:
	return BoardContext.new(null, NO_UNITS, null, null, null, heights)


# One wall cell at (1,0), everything else flat -- the report shape in miniature.
func _wall_board(height: int) -> BoardContext:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), height)
	return _board_with(heights)


func _shot(clearance: int, max_range: int = 3) -> AttackData:
	var attack := AttackData.new()
	attack.arc_clearance = clearance
	var pattern := ManhattanRangePattern.new()
	pattern.min_range = 1
	pattern.max_range = max_range
	attack.attack_pattern = pattern
	return attack


# The Noemie report: a flat shot (clearance 0) at a same-level target dies on the wall between.
func test_a_flat_shot_dies_on_a_wall() -> void:
	var trace := Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(2, 0), _wall_board(6))
	assert_bool(trace.blocked).is_true()
	assert_bool(trace.blocked_cell == Vector2i(1, 0)).is_true()
	assert_bool(Reach.vertical_aim_ok(_shot(0), Vector2i(0, 0), Vector2i(2, 0), _wall_board(6))).is_false()


# The Isaac report: a one-level lob arcs to eye + a level mid-flight -- a two-level wall stops it,
# a one-level wall does not. Heights and clearance are both in units (#427), so all four numbers
# doubled together and the geometry is unchanged.
func test_a_lob_clears_low_walls_and_dies_on_high_ones() -> void:
	assert_bool(Reach.sight_trace(_shot(4), Vector2i(0, 0), Vector2i(2, 0), _wall_board(8)).blocked).is_true()
	assert_bool(Reach.sight_trace(_shot(4), Vector2i(0, 0), Vector2i(2, 0), _wall_board(4)).blocked).is_false()


# Touch = blocked: a bead grazing a wall-top stops, so even a 1-high wall stops a flat shot
# (the dev's standing "1-block-tall blocks line of sight").
func test_a_one_high_wall_blocks_a_flat_shot() -> void:
	assert_bool(Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(2, 0), _wall_board(2)).blocked).is_true()


# The original slice-2 point survives: a gun up a ramp staircase hugs the rising line from below.
func test_a_flat_shot_up_a_ramp_staircase_is_clear() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 0), 2, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(3, 0), 4)
	var board := _board_with(heights)
	assert_bool(Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(3, 0), board).blocked).is_false()


# The eye offset (#218, now the sprite's CENTER -- dev, 2026-08-20): standing ON your cliff edge,
# the shot down clears, because the sightline starts half a level above your feet. One cell back,
# your own lip occludes the steep shot -- real lip occlusion; step forward to take it.
func test_shooting_down_from_the_lip_clears_and_one_back_is_occluded() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(0, 0), 4)   # the shooter stands ON the edge
	var board := _board_with(heights)
	assert_bool(Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(3, 0), board).blocked).is_false()

	heights.set_cell(Vector2i(1, 0), 4)   # now the edge is one cell ahead -- the lip occludes
	assert_bool(Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(3, 0), board).blocked).is_true()


# The sightline originates at the sprite's CENTER (dev): the trace's first point sits exactly half
# a level above the shooter's surface, at the cell's center. Pins EYE_HEIGHT through the READOUT --
# the drawn path is the rule, so this is the one number a player could measure off the screen.
func test_the_line_starts_at_the_sprites_center() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(0, 0), 4)
	var trace := Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(2, 0), _board_with(heights))
	var first: Vector3 = trace.points[0]
	# Height 4 plus EYE_HEIGHT (1 unit = half a level), in the trace's own unit.
	assert_float(first.y).is_equal_approx(5.0, 0.0001)
	assert_float(first.x).is_equal_approx(0.5, 0.0001)


# The rule IS the readout: wherever horizontal membership holds, can_hit_cell_from and the trace
# verdict must agree (the attack's tolerances are unlimited, so the trace is the only vertical
# clause in play).
func test_the_gate_and_the_trace_never_disagree() -> void:
	for wall_height in [0, 2, 4, 6, 8]:
		var board := _wall_board(wall_height)
		var shot := _shot(4)
		var hit: bool = Reach.can_hit_cell_from(null, Vector2i(0, 0), Vector2i(2, 0), shot, board)
		var clear: bool = not Reach.sight_trace(shot, Vector2i(0, 0), Vector2i(2, 0), board).blocked
		assert_bool(hit == clear) \
			.override_failure_message("gate and trace disagree at wall height %d" % wall_height) \
			.is_true()


# A blocked trace truncates its beads at the wall instead of drawing through it.
func test_a_blocked_trace_stops_at_the_wall() -> void:
	var trace := Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(3, 0), _wall_board(3))
	assert_bool(trace.blocked).is_true()
	assert_int(trace.points.size()).is_greater(1)
	var last: Vector3 = trace.points[trace.points.size() - 1]
	assert_bool(last.x <= 2.0).is_true()   # never past the wall cell's far edge (wall spans x 1..2)


# --- cells_crossed: the deterministic supercover walk the trace rides ---------------------------

func test_cells_crossed_walks_a_straight_line_endpoints_excluded() -> void:
	var expected: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	assert_that(GridUtils.cells_crossed(Vector2i(0, 0), Vector2i(3, 0))).is_equal(expected)


func test_cells_crossed_includes_both_cells_of_a_corner() -> void:
	# A one-step diagonal passes exactly through the shared corner: conservative supercover takes
	# BOTH side cells, so a shot can never thread a seam between two walls.
	var crossed := GridUtils.cells_crossed(Vector2i(0, 0), Vector2i(1, 1))
	assert_that(crossed).contains_exactly_in_any_order([Vector2i(1, 0), Vector2i(0, 1)])


func test_cells_crossed_of_an_oblique_line() -> void:
	var expected: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]
	assert_that(GridUtils.cells_crossed(Vector2i(0, 0), Vector2i(2, 1))).is_equal(expected)
