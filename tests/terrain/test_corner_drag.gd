# The vertex layer (#427 slice 4): what the corner-drag tool addresses, and the clamp that keeps it
# structurally unable to author ground the model refuses.
#
# Pure statics plus the store, no scene. The tool's own wiring is pinned in tests/dev; this is the
# layer it stands on, so it is pinned where it is cheapest to run.
extends GdUnitTestSuite

const NW := Terrain.CORNER_NW
const NE := Terrain.CORNER_NE
const SE := Terrain.CORNER_SE
const SW := Terrain.CORNER_SW
const LEVEL := Terrain.UNITS_PER_LEVEL

# Every mask the model allows, spelled out rather than generated -- a generator would derive
# legality from the predicate these cases exist to check.
const LEGAL_MASKS: Array[int] = [
	0,
	NW, NE, SE, SW,
	NW | NE, NE | SE, SE | SW, SW | NW,
	NW | NE | SE, NE | SE | SW, SE | SW | NW, SW | NW | NE
]


# --- the weld ------------------------------------------------------------------------

func test_a_vertex_writes_the_matching_corner_in_all_four_touching_cells() -> void:
	# The whole gesture: one point moves in four tiles at once, and WHICH corner it is differs in
	# each. A case that checked only the cell under the cursor would pass with the table transposed.
	var heights := BoardHeights.new()
	heights.set_vertex(Vector2i(3, 5), 1)
	assert_int(Terrain.corner_height(heights.corners_at(Vector2i(3, 5)), NW)) \
		.is_equal(1).override_failure_message("the vertex is its own cell's NW corner")
	assert_int(Terrain.corner_height(heights.corners_at(Vector2i(2, 5)), NE)) \
		.is_equal(1).override_failure_message("and the west neighbour's NE corner")
	assert_int(Terrain.corner_height(heights.corners_at(Vector2i(3, 4)), SW)) \
		.is_equal(1).override_failure_message("and the north neighbour's SW corner")
	assert_int(Terrain.corner_height(heights.corners_at(Vector2i(2, 4)), SE)) \
		.is_equal(1).override_failure_message("and the north-west neighbour's SE corner")


func test_the_weld_leaves_every_other_corner_of_those_cells_alone() -> void:
	# A drag moves a POINT, not a tile: the three corners it does not name must not follow it.
	var heights := BoardHeights.new()
	heights.set_vertex(Vector2i(1, 1), 1)
	assert_object(heights.corners_at(Vector2i(1, 1))).is_equal(Vector4i(1, 0, 0, 0))
	assert_object(heights.corners_at(Vector2i(0, 0))).is_equal(Vector4i(0, 0, 1, 0))


func test_a_ground_gate_skips_the_cells_that_have_none() -> void:
	# Height goes with the ground (#245). Dragging a point at the board edge must not leave heights
	# in cells with no tile -- invisible, and riding every save.
	var heights := BoardHeights.new()
	var painted := [Vector2i(0, 0), Vector2i(0, -1)]
	heights.set_vertex(Vector2i(0, 0), 1, func(cell: Vector2i) -> bool: return painted.has(cell))
	assert_int(Terrain.corner_height(heights.corners_at(Vector2i(0, 0)), NW)).is_equal(1)
	assert_int(Terrain.corner_height(heights.corners_at(Vector2i(0, -1)), SW)).is_equal(1)
	assert_array(heights.painted_cells()).contains_exactly_in_any_order(painted)


# --- the clamp -----------------------------------------------------------------------

func test_no_reachable_drag_can_author_illegal_ground() -> void:
	# The exhaustive sweep, and the case that makes "structurally unable to author a saddle" true
	# rather than intended: every legal starting shape, every corner, every target height in and
	# beyond range. It is the tool's version of the equivalence dump slice 3 shipped.
	var checked := 0
	for mask in LEGAL_MASKS:
		for climb in [1, LEVEL]:
			var start := Terrain.corners_of_form(0, mask, climb)
			for bit in [NW, NE, SE, SW]:
				for target in range(-2 * LEVEL, 2 * LEVEL + 1):
					var shaped := Terrain.corner_toward(start, bit, target)
					assert_bool(Terrain.is_legal_corners(shaped)).is_true() \
						.override_failure_message("%s corner %d to %d gave %s"
							% [start, bit, target, shaped])
					checked += 1
	assert_int(checked).is_greater(0).override_failure_message("the sweep swept nothing")


func test_the_clamp_lands_on_the_nearest_legal_height_it_can_reach() -> void:
	# A refused target must not snap far. Flat ground around one corner: every height within a level
	# is legal, so the clamp is the range boundary and nothing short of it.
	var flat := Vector4i.ZERO
	assert_int(Terrain.corner_height(Terrain.corner_toward(flat, NW, 9), NW)).is_equal(LEVEL)
	assert_int(Terrain.corner_height(Terrain.corner_toward(flat, NW, -9), NW)).is_equal(-LEVEL)
	assert_int(Terrain.corner_height(Terrain.corner_toward(flat, NW, 1), NW)).is_equal(1)


func test_a_target_that_would_make_a_saddle_falls_back_rather_than_snapping_to_the_floor() -> void:
	# The refusal with no interval behind it: raising SE on a NW-raised cell is the saddle the dev
	# refused, and the only legal answer is the height SE already has. It must land THERE and not
	# somewhere arbitrary -- and the corner's own cell keeps its shape.
	var outer := Terrain.corners_of_form(0, NW, LEVEL)
	assert_object(Terrain.corner_toward(outer, SE, LEVEL)).is_equal(outer)


func test_setting_a_vertex_twice_equals_setting_it_once() -> void:
	# The property the ABSOLUTE ruling exists to buy: _paint() re-fires on every motion event while
	# the button is held, so a drag is the same write dozens of times over.
	var once := BoardHeights.new()
	once.set_vertex(Vector2i(2, 2), LEVEL)
	var twice := BoardHeights.new()
	twice.set_vertex(Vector2i(2, 2), LEVEL)
	twice.set_vertex(Vector2i(2, 2), LEVEL)
	twice.set_vertex(Vector2i(2, 2), LEVEL)
	assert_dict(twice.to_corner_dict()).is_equal(once.to_corner_dict())


func test_a_clamped_drag_is_idempotent_too() -> void:
	# The clamp reads the corner's CURRENT height, so a repeat of a clamped write starts from the
	# clamped value. If that walked further each time, holding still would sink the point.
	var heights := BoardHeights.new()
	for i in 5:
		heights.set_vertex(Vector2i(0, 0), 9)
	assert_int(Terrain.corner_height(heights.corners_at(Vector2i(0, 0)), NW)).is_equal(LEVEL)


func test_a_corner_already_at_the_target_is_left_exactly_alone() -> void:
	var ramp := Terrain.corners_of_ramp(0, Terrain.RampRise.NORTH, LEVEL)
	assert_object(Terrain.corner_toward(ramp, NW, LEVEL)).is_equal(ramp)


# --- the vertex under the pointer -----------------------------------------------------

func test_a_point_in_a_cell_answers_the_corner_it_is_nearest() -> void:
	# One derivation, because the flat view and the 3D pick reach it from opposite directions and
	# must not disagree about which corner the cursor has hold of.
	var cell := Vector2i(4, 7)
	assert_object(Terrain.vertex_near(cell, 0.1, 0.1)).is_equal(cell)
	assert_object(Terrain.vertex_near(cell, 0.9, 0.1)).is_equal(cell + Vector2i(1, 0))
	assert_object(Terrain.vertex_near(cell, 0.9, 0.9)).is_equal(cell + Vector2i(1, 1))
	assert_object(Terrain.vertex_near(cell, 0.1, 0.9)).is_equal(cell + Vector2i(0, 1))


func test_a_grazing_pick_outside_the_cell_still_answers_that_cell_s_nearer_edge() -> void:
	# Naturally saturating rather than clamped: a ray hit a hair off the cell is a real outcome on a
	# sloped surface, and it must not answer a vertex two cells away.
	var cell := Vector2i.ZERO
	assert_object(Terrain.vertex_near(cell, -0.4, 1.4)).is_equal(Vector2i(0, 1))


func test_the_four_offsets_name_four_different_corners_of_four_different_cells() -> void:
	# The table is read in one direction only, so a transposition is invisible everywhere except
	# here and in the weld above.
	var cells: Array[Vector2i] = []
	var bits: Array[int] = []
	for offset: Vector2i in Terrain.VERTEX_CORNERS:
		cells.append(offset)
		bits.append(Terrain.VERTEX_CORNERS[offset])
	assert_int(cells.size()).is_equal(4)
	assert_array(bits).contains_exactly_in_any_order([NW, NE, SE, SW])
