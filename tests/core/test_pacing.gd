# Guard for Classes/core/Pacing (#118). ONE property: a playback beat costs a headless run
# nothing. That matters because OrderExecutor.execute_orders is awaited directly by nine test call
# sites -- a beat that actually waited would put real wall clock on every case that resolves a plan,
# and the symptom would be a suite that just got slower, which nothing else here would catch.
#
# Deliberately asserts NOTHING about what any of the table's constants are: they are tuned by feel, and
# tuning them must never turn the suite red. Measured in FRAMES rather than seconds for the same
# reason -- a duration threshold would be a hard-coded number pretending to be a rule.
#
# Falsified: delete the DisplayServer headless check in Pacing.beat and this goes red (a real
# SceneTreeTimer burns hundreds of frames at the duration below).
extends GdUnitTestSuite

# Far longer than any authored beat, so the case cannot pass by the value happening to be small.
const ABSURD_BEAT := 30.0

func test_a_beat_does_not_wait_in_a_headless_run() -> void:
	# The premise: everything below is only true because nobody is watching. If the suite ever runs
	# headed, this case is measuring something else entirely and should say so.
	assert_str(DisplayServer.get_name()).is_equal("headless")

	var before := Engine.get_process_frames()
	await Pacing.beat(self, ABSURD_BEAT)
	assert_int(Engine.get_process_frames() - before) \
		.override_failure_message("Pacing.beat waited in a headless run -- the suite is paying wall clock for every beat") \
		.is_equal(0)

func test_a_zero_beat_never_waits() -> void:
	# The other escape, and the one PLAYER_ACTION currently rides: a zero is returned on, not handed
	# to create_timer (which would still cost a frame).
	var before := Engine.get_process_frames()
	await Pacing.beat(self, 0.0)
	assert_int(Engine.get_process_frames() - before).is_equal(0)
