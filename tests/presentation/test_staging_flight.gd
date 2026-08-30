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
var _whiteout := 0.0
var _whiteout_hold := 0.0
var _camera_hold := 0.0


func before_test() -> void:
	# Statics outlive a suite (#449), so what a case writes has to be handed back.
	_arrival = Pacing.TEAR_OUT_ARRIVAL
	_cap = Pacing.TEAR_OUT_STAGGER_MAX
	_flight = Pacing.TEAR_OUT_FLIGHT
	_slam = Pacing.TEAR_OUT_SLAM
	_lead = Pacing.TEAR_OUT_EMPTY_SKY
	_whiteout = Pacing.TEAR_OUT_WHITEOUT
	_whiteout_hold = Pacing.TEAR_OUT_HOLD
	_camera_hold = Pacing.TEAR_OUT_CAMERA_HOLD


func after_test() -> void:
	Pacing.TEAR_OUT_ARRIVAL = _arrival
	Pacing.TEAR_OUT_STAGGER_MAX = _cap
	Pacing.TEAR_OUT_FLIGHT = _flight
	Pacing.TEAR_OUT_SLAM = _slam
	Pacing.TEAR_OUT_EMPTY_SKY = _lead
	Pacing.TEAR_OUT_WHITEOUT = _whiteout
	Pacing.TEAR_OUT_HOLD = _whiteout_hold
	Pacing.TEAR_OUT_CAMERA_HOLD = _camera_hold


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


# --- the flash and the cut (#602 round 5) -------------------------------------------------------
#
# One rule, both directions: the cut sits at the flash's first full-white frame, and the flash
# anchors to the transition's cut-ward end (dev, 2026-08-29: "the white out should always be tied
# to the last thing that happens, the teleport, no matter what"). Pinned here because this class
# is the artifact both sides read -- the driver draws the level, the driver moves the camera, the
# executor awaits the total, and three derivations of one timeline is how the exit's flash came to
# play over nothing while its teleport ran bare.

func _flash_knobs() -> void:
	Pacing.TEAR_OUT_WHITEOUT = 0.3
	Pacing.TEAR_OUT_HOLD = 0.4
	Pacing.TEAR_OUT_FLIGHT = 1.0
	Pacing.TEAR_OUT_STAGGER_MAX = 0.5
	Pacing.TEAR_OUT_ARRIVAL = 2.0


func test_the_exit_flash_is_dark_while_a_tile_still_flies() -> void:
	# The dev watches the blocks fall -- deliberately bare -- and the flash belongs to the drop
	# after them. An exit flash anchored at zero (the entry's clock, the round-4 bug) lights up
	# here and this reds.
	_flash_knobs()
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var plan := StagingFlight.schedule(cells)
	var total := StagingFlight.total(plan)
	var anchor := StagingFlight.flash_anchor(false, true, total)
	for elapsed in [0.0, total * 0.3, total * 0.7, total - 0.01]:
		assert_float(StagingFlight.whiteout_level(elapsed, anchor)).override_failure_message(
				"the exit flash is lit at %s with tiles still in the air -- it is riding the "
				% elapsed + "entry's clock again").is_equal(0.0)


func test_the_exit_camera_comes_down_at_the_flashs_first_full_frame() -> void:
	_flash_knobs()
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var plan := StagingFlight.schedule(cells)
	var total := StagingFlight.total(plan)
	var ramp := Pacing.TEAR_OUT_WHITEOUT
	var anchor := StagingFlight.flash_anchor(false, false, total)
	assert_bool(StagingFlight.cut_over(total + ramp - 0.01, false, total)) \
		.override_failure_message("the camera dropped before the flash reached full white") \
		.is_false()
	assert_bool(StagingFlight.cut_over(total + ramp, false, total)).override_failure_message(
			"the flash is full and the camera still has not come down").is_true()
	assert_float(StagingFlight.whiteout_level(total + ramp, anchor)).override_failure_message(
			"the cut's own frame is not at full white -- the teleport shows").is_equal(1.0)


func test_the_entry_cut_waits_for_full_white_too() -> void:
	# The entry used to cut at zero with the flash only beginning -- decent, never tied. Now the
	# same rule as the exit, one ramp in.
	_flash_knobs()
	var cells: Array[Vector2i] = [Vector2i(0, 0)]
	var plan := StagingFlight.schedule(cells, 1.1)
	var total := StagingFlight.total(plan)
	var ramp := Pacing.TEAR_OUT_WHITEOUT
	var anchor := StagingFlight.flash_anchor(true, true, total)
	assert_bool(StagingFlight.cut_over(ramp - 0.01, true, total)).override_failure_message(
			"the camera teleported up before the flash could hide it").is_false()
	assert_bool(StagingFlight.cut_over(ramp, true, total)).is_true()
	assert_float(StagingFlight.whiteout_level(ramp, anchor)).override_failure_message(
			"the entry cut's own frame is not at full white").is_equal(1.0)


func test_an_exit_costs_its_travel_plus_the_whole_flash() -> void:
	# The executor awaits exactly this; awaiting bare total tears the driver down with the screen
	# still white and the camera still up, which un-ties the very thing this round tied.
	_flash_knobs()
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var plan := StagingFlight.schedule(cells)
	var flash := Pacing.TEAR_OUT_WHITEOUT + Pacing.TEAR_OUT_HOLD + Pacing.TEAR_OUT_WHITEOUT
	assert_float(StagingFlight.exit_total(plan)).override_failure_message(
			"the exit's await does not cover its own flash") \
		.is_equal_approx(StagingFlight.total(plan) + flash, 0.001)


func test_a_knob_shrunken_entry_still_pays_for_its_own_flash() -> void:
	# Insurance, not pacing: the shipped entry already contains its flash, but a zeroed flight and
	# lead could end the driver mid-flash with the camera already up -- a hard white cut-off.
	_flash_knobs()
	Pacing.TEAR_OUT_FLIGHT = 0.0
	var cells: Array[Vector2i] = [Vector2i(0, 0)]
	var plan := StagingFlight.schedule(cells)
	var flash := Pacing.TEAR_OUT_WHITEOUT + Pacing.TEAR_OUT_HOLD + Pacing.TEAR_OUT_WHITEOUT
	assert_float(StagingFlight.entry_total(plan)).override_failure_message(
			"an entry shorter than its flash is torn down mid-white").is_greater_equal(flash)


func test_the_travel_entrys_flash_still_waits_for_its_camera_hold() -> void:
	# The travel arm has no cut -- its flash covers an eased rise after the hold that watches the
	# tiles leave. The arm forks the ANCHOR, never the arithmetic.
	_flash_knobs()
	Pacing.TEAR_OUT_CAMERA_HOLD = 0.95
	var anchor := StagingFlight.flash_anchor(true, false, 5.0)
	assert_float(anchor).override_failure_message(
			"the travel entry's flash no longer waits for the camera hold") \
		.is_equal_approx(Pacing.TEAR_OUT_CAMERA_HOLD, 0.001)
