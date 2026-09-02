# The camera's black box (#669): the ring, the two verbs, and the rate limit that is the whole
# reason the ring spans a pass instead of two seconds.
#
# PURE -- no scene, no rig, no frames. CameraTrace takes now_msec from its caller (the
# recovered()/Pacing.beat idiom: the caller owns the headless escape), so every case here drives
# the clock by hand and asserts the timing decision itself rather than sleeping through it. A
# suite that had to wait 200 ms per assertion would be pinning frame scheduling, not the rule.
extends GdUnitTestSuite


# One channel snapshot, shaped like CameraRig3D._trace_channels() but written out here on purpose:
# a fixture that called the rig's composer would go green if the composer stopped composing.
func _channels(drop := 0.0, dist := 14.0) -> Dictionary:
	return {
		"aim": Vector2(4.0, 4.0),
		"lift": 0.0, "lift_target": 0.0,
		"drop": drop, "drop_target": drop,
		"dist": dist, "dist_target": dist,
		"dolly": 0.0,
		"yaw": 90.0,
		"pitch": -40.0,
		"borrowed": false,
		"tscale": 1.0,
	}


func test_a_named_moment_always_lands() -> void:
	var trace := CameraTrace.new()

	trace.note("playback lock ACQUIRED", _channels(), 1000)
	trace.note("stage published (3 cells)", _channels(), 1000)

	# Same millisecond, same channels, and BOTH must be there: the named moments are what a
	# sequence is read off, and two events in one frame is the ordinary case at a phase boundary.
	assert_int(trace._entries.size()).override_failure_message(
			"a named moment was dropped -- two events in one frame is the normal shape of a "
			+ "phase boundary, and the pair is the sequence").is_equal(2)


func test_the_heartbeat_says_nothing_while_nothing_moves() -> void:
	var trace := CameraTrace.new()
	trace.sample(_channels(), 1000)

	# Well past the interval, so only the "did anything move" arm can be what stops this.
	trace.sample(_channels(), 5000)
	trace.sample(_channels(), 9000)

	assert_int(trace._entries.size()).override_failure_message(
			"an idle camera wrote to the trace -- the ring fills with nothing and evicts the "
			+ "moments it exists to hold").is_equal(1)


func test_the_heartbeat_holds_its_floor_even_when_the_camera_is_moving() -> void:
	# THE CASE THE TICKET TURNS ON. Under playback the mirror re-drives the aim, the drop and the
	# lift EVERY FRAME, so "has anything moved" is true on essentially every frame of every pass.
	# Without the floor the ring holds ~2 s at 60 fps and the named moments are gone.
	var trace := CameraTrace.new()
	trace.sample(_channels(0.0), 1000)

	trace.sample(_channels(1.0), 1050)
	trace.sample(_channels(2.0), 1100)
	trace.sample(_channels(3.0), 1150)

	assert_int(trace._entries.size()).override_failure_message(
			"the heartbeat ignored its floor -- a moving camera writes 60 rows a second and the "
			+ "ring stops spanning a pass").is_equal(1)


func test_the_heartbeat_lands_once_the_floor_has_passed() -> void:
	var trace := CameraTrace.new()
	trace.sample(_channels(0.0), 1000)
	trace.sample(_channels(5.0), 1000 + CameraTrace.SAMPLE_INTERVAL_MSEC)

	# Not vacuous by way of the floor alone: the ease has to be VISIBLE, or the trace shows named
	# moments with no motion between them and a stuck channel reads exactly like a settled one.
	assert_int(trace._entries.size()).is_equal(2)
	var last: Dictionary = trace._entries[-1]["channels"]
	assert_float(last["drop"]).is_equal_approx(5.0, 0.001)


func test_a_named_moment_never_spends_the_heartbeats_budget() -> void:
	# Notes and samples are on separate clocks by design: a burst of events must not blind the
	# ease that follows it, which is the exact shape of the round-8 sequence.
	var trace := CameraTrace.new()
	trace.sample(_channels(0.0), 1000)
	trace.note("trained release DEFERRED (death show)", _channels(0.0), 1100)

	trace.sample(_channels(9.0), 1000 + CameraTrace.SAMPLE_INTERVAL_MSEC)

	assert_int(trace._entries.size()).override_failure_message(
			"a note pushed the heartbeat's floor out -- an event burst would blind the ease "
			+ "after it").is_equal(3)


func test_a_note_rebases_what_the_next_heartbeat_compares_against() -> void:
	# A note carries a snapshot too, so the door that fired it and the heartbeat behind it must not
	# both record the same moment.
	var trace := CameraTrace.new()
	trace.note("zoom -> 11.0", _channels(0.0, 11.0), 1000)

	trace.sample(_channels(0.0, 11.0), 1000 + CameraTrace.SAMPLE_INTERVAL_MSEC)

	assert_int(trace._entries.size()).override_failure_message(
			"the heartbeat re-recorded the moment a note had just taken").is_equal(1)


func test_the_ring_evicts_the_oldest_rather_than_growing() -> void:
	var trace := CameraTrace.new()
	trace.note("THE FIRST MOMENT", _channels(), 0)
	for i in range(CameraTrace.MAX_ENTRIES + 40):
		trace.note("event %d" % i, _channels(), i + 1)

	assert_int(trace._entries.size()).override_failure_message(
			"the ring grew past its cap -- an unbounded buffer in a shipping build").is_equal(
			CameraTrace.MAX_ENTRIES)
	assert_str(trace.render(9999)).override_failure_message(
			"the oldest entry survived eviction, so the ring drops the NEWEST instead -- "
			+ "backwards, and it loses the moment the report was filed about").not_contains(
			"THE FIRST MOMENT")


func test_the_render_says_how_much_time_it_actually_covers() -> void:
	# The ring is bounded by COUNT, so the span it holds varies with how busy the pass was. Saying
	# the real span is what stops a reader assuming a quiet ten seconds before the first row.
	var trace := CameraTrace.new()
	trace.note("playback lock ACQUIRED", _channels(), 1000)
	trace.note("stage published (3 cells)", _channels(), 4000)

	var text := trace.render(4000)
	assert_str(text).contains("2 moments")
	assert_str(text).contains("3.0 s")
	assert_str(text).contains("playback lock ACQUIRED")


func test_an_untouched_camera_says_so_rather_than_rendering_a_blank() -> void:
	# The NO_3D_VIEW idiom: a section that renders empty reads as a broken dump, and the honest
	# sentence is a fact worth having (nothing moved the camera at all this run).
	assert_str(CameraTrace.new().render(1000)).contains("nothing recorded")


func test_a_channel_still_in_flight_is_rendered_as_a_pair() -> void:
	# The gap between live and target IS the diagnosis for the three eased channels (#602 rounds 7
	# and 8), so a settled channel collapsing to one number must not also collapse a moving one.
	var trace := CameraTrace.new()
	var mid := _channels()
	mid["drop"] = 1.0
	mid["drop_target"] = 5.0
	trace.note("mid-ease", mid, 1000)

	var text := trace.render(1000)
	assert_str(text).override_failure_message(
			"a channel still easing rendered as a single number -- the live/target gap is the "
			+ "whole of what rounds 7 and 8 were read off").contains("1.0->5.0")
