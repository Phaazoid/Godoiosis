# The radial menu's hit test (#467), asserted as pure maths -- no scene, no widget.
#
# The property this suite exists for: the DRAWN wedge and the HIT sector are two different things.
# `slice_polygon` narrows a wedge to PAINT_FRACTION so a deeper ring reads lighter (dev call), and
# `selection_at` must not care -- every degree outside the dead zone still belongs to exactly one
# slice. The 360-degree sweep below is that claim in falsifiable form: teach selection_at about the
# paint fraction and it reds immediately, which is the mutant to check this suite with.
#
# Nothing here pins a tuned value. Radii are derived from DEAD_ZONE_RADIUS rather than typed in, so
# retuning the look cannot red a rule about angles.
extends GdUnitTestSuite

const AMC := preload("res://Classes/ui/ActionMenuController.gd")

const CENTRE := Vector2(400, 300)
const COUNTS: Array[int] = [1, 2, 3, 4, 5, 8, 11]


func _outside_radius() -> float:
	return AMC.DEAD_ZONE_RADIUS + 50.0


# ==============================================================================
#  The sweep: every angle belongs to exactly one slice
# ==============================================================================

func test_every_degree_outside_the_dead_zone_resolves_to_one_slice() -> void:
	var radius := _outside_radius()
	for count: int in COUNTS:
		var hits: Array[int] = []
		hits.resize(count)
		hits.fill(0)
		for degree in range(360):
			var point := AMC.point_at(CENTRE, radius, float(degree))
			var index := AMC.selection_at(point, CENTRE, count, 0.0)
			assert_bool(index >= 0 and index < count) \
				.override_failure_message("count %d, %d deg resolved to %d -- outside [0,%d)"
					% [count, degree, index, count]) \
				.is_true()
			hits[index] += 1
		var expected := 360 / count
		for i in range(count):
			assert_bool(absi(hits[i] - expected) <= 2) \
				.override_failure_message("count %d: slice %d owns %d degrees, expected about %d"
					% [count, i, hits[i], expected]) \
				.is_true()


# A far-away point is still a selection: the hit area is unbounded, which is the whole reason the
# scheme ports to a stick. Ten times the ring's own reach still lands on the same slice.
func test_distance_never_changes_which_slice_an_angle_picks() -> void:
	for count: int in COUNTS:
		for degree in range(0, 360, 7):
			var near := AMC.point_at(CENTRE, _outside_radius(), float(degree))
			var far := AMC.point_at(CENTRE, _outside_radius() * 10.0, float(degree))
			assert_int(AMC.selection_at(far, CENTRE, count, 0.0)) \
				.override_failure_message("count %d at %d deg: far point disagreed with near"
					% [count, degree]) \
				.is_equal(AMC.selection_at(near, CENTRE, count, 0.0))


func test_the_dead_zone_selects_nothing() -> void:
	assert_int(AMC.selection_at(CENTRE, CENTRE, 8, 0.0)).is_equal(-1)
	var just_inside := AMC.point_at(CENTRE, AMC.DEAD_ZONE_RADIUS * 0.5, 45.0)
	assert_int(AMC.selection_at(just_inside, CENTRE, 8, 0.0)).is_equal(-1)
	var just_outside := AMC.point_at(CENTRE, AMC.DEAD_ZONE_RADIUS + 1.0, 45.0)
	assert_int(AMC.selection_at(just_outside, CENTRE, 8, 0.0)) \
		.override_failure_message("a point past the dead zone selected nothing").is_equal(1)


# ==============================================================================
#  Angles, and where 12 o'clock is
# ==============================================================================

func test_twelve_oclock_is_zero_and_angles_run_clockwise() -> void:
	assert_float(AMC.angle_of(CENTRE + Vector2(0, -50), CENTRE)).is_equal_approx(0.0, 0.001)
	assert_float(AMC.angle_of(CENTRE + Vector2(50, 0), CENTRE)).is_equal_approx(90.0, 0.001)
	assert_float(AMC.angle_of(CENTRE + Vector2(0, 50), CENTRE)).is_equal_approx(180.0, 0.001)
	assert_float(AMC.angle_of(CENTRE + Vector2(-50, 0), CENTRE)).is_equal_approx(-90.0, 0.001)


func test_point_at_and_angle_of_round_trip() -> void:
	for degree in range(0, 360, 13):
		var point := AMC.point_at(CENTRE, 120.0, float(degree))
		assert_float(wrapf(AMC.angle_of(point, CENTRE), 0.0, 360.0)) \
			.override_failure_message("round trip lost %d deg" % degree) \
			.is_equal_approx(float(degree), 0.001)


func test_index_at_wraps_at_the_top_of_the_circle() -> void:
	assert_int(AMC.index_at(0.0, 4, 0.0)).is_equal(0)
	assert_int(AMC.index_at(359.99, 4, 0.0)).is_equal(3)
	assert_int(AMC.index_at(360.0, 4, 0.0)).is_equal(0)
	assert_int(AMC.index_at(-1.0, 4, 0.0)).is_equal(3)


# ==============================================================================
#  Rotation: a child ring is based from its parent (dev call)
# ==============================================================================

func test_a_rotated_ring_puts_its_first_slice_at_the_start_angle() -> void:
	assert_int(AMC.index_at(90.0, 4, 90.0)).is_equal(0)
	assert_int(AMC.index_at(180.0, 4, 90.0)).is_equal(1)
	# Past 360 and back around: a start angle near the top must not strand a slice.
	assert_int(AMC.index_at(10.0, 4, 350.0)).is_equal(0)
	assert_int(AMC.index_at(350.0, 4, 350.0)).is_equal(0)


# The bloom: the first child sits CENTRED on the parent's direction, so the pointer that opened the
# ring is inside child 0 rather than balanced on its boundary.
func test_a_child_ring_centres_its_first_slice_on_the_parent_direction() -> void:
	# Parent: 4 slices from 0 deg, so slice 1 spans 90..180 and points at 135.
	var start := AMC.child_start_deg(0.0, 1, 4, 5)
	assert_int(AMC.index_at(135.0, 5, start)) \
		.override_failure_message("the parent's own direction did not land on child 0").is_equal(0)
	# And a little either side of it stays on child 0 -- the jitter margin the centring buys.
	assert_int(AMC.index_at(135.0 + 20.0, 5, start)).is_equal(0)
	assert_int(AMC.index_at(135.0 - 20.0, 5, start)).is_equal(0)


func test_child_start_is_defined_for_degenerate_rings() -> void:
	assert_float(AMC.child_start_deg(0.0, 0, 0, 3)).is_equal(0.0)
	assert_float(AMC.child_start_deg(0.0, 0, 3, 0)).is_equal(0.0)


# ==============================================================================
#  The drawn shape stays inside the sector it owns
# ==============================================================================

# Thinning is a LOOK change and must never move a boundary: every painted vertex of slice i has to
# resolve back to slice i. This is the other half of the sweep -- the sweep says the hit test
# ignores the paint, this says the paint respects the hit test.
func test_a_painted_wedge_never_leaves_its_own_sector() -> void:
	var radii := Vector2(80.0, 110.0)
	for count: int in COUNTS:
		for fraction: float in [0.98, 0.86, 0.5, 0.2]:   # never exactly 1.0: that lands a vertex ON the boundary
			for i in range(count):
				var polygon := AMC.slice_polygon(CENTRE, radii.x, radii.y, i, count, 0.0, fraction)
				assert_int(polygon.size()).is_greater(0)
				for point: Vector2 in polygon:
					assert_int(AMC.index_at(AMC.angle_of(point, CENTRE), count, 0.0)) \
						.override_failure_message("count %d, fraction %s: slice %d painted into another sector"
							% [count, fraction, i]) \
						.is_equal(i)
