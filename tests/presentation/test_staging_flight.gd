# WHEN each torn-out tile leaves and lands (#521 slice B) -- the schedule both sides of the
# transition agree through.
#
# NO SCENE HERE, and that is the point of StagingFlight being its own class: the executor awaits a
# total and the 3D host draws a progress, both off one plan, and the plan is arithmetic. So these
# cases state a cell list and a set of knobs and read the answer, with no board, no viewport and no
# waiting on frames -- the split CardSheet made for the same reason one ticket earlier.
#
# The knobs are SET by each case rather than assumed, because they are tuned values the dev moves:
# a case that pinned today's stagger would go red the first time he liked a different one. What is
# asserted is the RELATIONSHIP -- capped here, derived there -- which survives any value.
extends GdUnitTestSuite

var _arrival := 0.0
var _cap := 0.0
var _flight := 0.0
var _slam := 0.0
var _lead := 0.0


func before_test() -> void:
	# Statics outlive a suite (#449), so what a case writes has to be handed back.
	_arrival = Pacing.TEAR_OUT_ARRIVAL
	_cap = Pacing.TEAR_OUT_STAGGER_MAX
	_flight = Pacing.TEAR_OUT_FLIGHT
	_slam = Pacing.TEAR_OUT_SLAM
	_lead = Pacing.TEAR_OUT_EMPTY_SKY


func after_test() -> void:
	Pacing.TEAR_OUT_ARRIVAL = _arrival
	Pacing.TEAR_OUT_STAGGER_MAX = _cap
	Pacing.TEAR_OUT_FLIGHT = _flight
	Pacing.TEAR_OUT_SLAM = _slam
	Pacing.TEAR_OUT_EMPTY_SKY = _lead


func test_tiles_leave_in_the_order_their_owners_act() -> void:
	# The order is the caller's -- BeatSheet appends cells in playback order -- so all this must do
	# is not disturb it. Asserted as a strictly ascending start time rather than as a list of cells,
	# because what the ticket asks for is that the FIRST to act is the first to land.
	var cells: Array[Vector2i] = [Vector2i(4, 4), Vector2i(1, 1), Vector2i(9, 2), Vector2i(0, 7)]
	var plan := StagingFlight.schedule(cells)
	assert_int(plan.size()).is_equal(4)
	for i in plan.size():
		assert_vector(plan[i]["cell"]).is_equal(cells[i])
		if i > 0:
			assert_bool(float(plan[i]["start"]) > float(plan[i - 1]["start"])) \
				.override_failure_message("tile %d does not leave after tile %d" % [i, i - 1]).is_true()


func test_a_big_fight_costs_no_more_than_the_window_it_is_given() -> void:
	# The whole reason the gap is derived. A fixed per-tile stagger reads fine on four cells and
	# costs seconds on twenty, and this plays on EVERY Execute.
	Pacing.TEAR_OUT_ARRIVAL = 0.5
	Pacing.TEAR_OUT_STAGGER_MAX = 1.0   # far above the derived value, so the derivation is what acts
	Pacing.TEAR_OUT_FLIGHT = 0.0
	var many: Array[Vector2i] = []
	for i in 20:
		many.append(Vector2i(i, 0))
	assert_float(StagingFlight.total(StagingFlight.schedule(many))) \
		.override_failure_message("twenty tiles overran the window they were given") \
		.is_less_equal(0.5 + 0.0001)


func test_a_small_fight_still_gets_a_punchy_gap() -> void:
	# The other arm: with only two tiles the derived gap would be the WHOLE window, smearing two
	# tiles across half a second. The cap is what keeps a skirmish crisp.
	Pacing.TEAR_OUT_ARRIVAL = 0.5
	Pacing.TEAR_OUT_STAGGER_MAX = 0.07
	Pacing.TEAR_OUT_FLIGHT = 0.0
	var plan := StagingFlight.schedule([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	assert_float(float(plan[1]["start"])).is_equal_approx(0.07, 0.0001)


func test_a_single_tile_waits_for_nobody() -> void:
	Pacing.TEAR_OUT_FLIGHT = 0.3
	var plan := StagingFlight.schedule([Vector2i(2, 2)] as Array[Vector2i])
	assert_float(float(plan[0]["start"])).is_equal(0.0)
	assert_float(StagingFlight.total(plan)).is_equal_approx(0.3, 0.0001)


func test_a_tile_is_partway_home_partway_through() -> void:
	# PINNED AT A MIDDLE VALUE, deliberately. Progress is a ramp between two endpoints, and every
	# plausible implementation agrees at 0 and 1 -- a case that only checked those would pass on a
	# step function, on the wrong duration, and on reading the wrong end of the entry.
	var entry := {"cell": Vector2i.ZERO, "start": 1.0, "land": 3.0}
	assert_float(StagingFlight.progress_at(entry, 0.5)).is_equal(0.0)
	assert_float(StagingFlight.progress_at(entry, 1.5)).is_equal_approx(0.25, 0.0001)
	assert_float(StagingFlight.progress_at(entry, 2.0)).is_equal_approx(0.5, 0.0001)
	assert_float(StagingFlight.progress_at(entry, 9.0)).is_equal(1.0)


func test_the_slam_bends_the_travel_without_moving_its_ends() -> void:
	# A tile must still leave when it leaves and land when it lands whatever the curve is doing, or
	# the shape knob would quietly desync the drawing from the schedule the executor awaited.
	Pacing.TEAR_OUT_SLAM = 3.0
	assert_float(StagingFlight.slam(0.0)).is_equal(0.0)
	assert_float(StagingFlight.slam(1.0)).is_equal(1.0)
	assert_float(StagingFlight.slam(0.5)).override_failure_message(
			"the slam is not holding the tile back; at exponent 3 half way in is far from half way there"
			).is_less(0.3)
	Pacing.TEAR_OUT_SLAM = 1.0
	assert_float(StagingFlight.slam(0.5)).override_failure_message(
			"at exponent 1 the travel should be constant speed").is_equal_approx(0.5, 0.0001)


func test_a_lead_in_delays_every_tile_without_reordering_them() -> void:
	# The empty-sky beat: the camera has cut ahead and the white-out is playing, and NOTHING has
	# arrived yet. Expressed as a lead on the schedule rather than as a wait before it, because the
	# white-out is drawn off this same clock -- stopping the clock would stop the flash with it.
	Pacing.TEAR_OUT_ARRIVAL = 0.5
	Pacing.TEAR_OUT_STAGGER_MAX = 0.1
	Pacing.TEAR_OUT_FLIGHT = 0.2
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var plain := StagingFlight.schedule(cells)
	var led := StagingFlight.schedule(cells, 1.25)

	assert_float(float(led[0]["start"])).override_failure_message(
			"the first tile did not wait out the lead").is_equal_approx(1.25, 0.0001)
	# Everything shifts by the same amount: a lead is a delay, not a re-stagger.
	for i in cells.size():
		assert_float(float(led[i]["start"]) - float(plain[i]["start"])).is_equal_approx(1.25, 0.0001)
		assert_float(float(led[i]["land"]) - float(plain[i]["land"])).is_equal_approx(1.25, 0.0001)
	assert_float(StagingFlight.total(led) - StagingFlight.total(plain)).override_failure_message(
			"the lead did not reach the total the executor awaits, so the pass would resume early"
			).is_equal_approx(1.25, 0.0001)


func test_no_lead_is_asked_for_by_default() -> void:
	# The exit passes none: the diorama is already there, and its own held beat is AFTERMATH. A
	# default that silently read the knob would double up with it.
	Pacing.TEAR_OUT_EMPTY_SKY = 99.0
	var plan := StagingFlight.schedule([Vector2i(0, 0)] as Array[Vector2i])
	assert_float(float(plan[0]["start"])).override_failure_message(
			"schedule() read the empty-sky knob on its own instead of being handed a lead"
			).is_equal(0.0)
