# Registry tripwire (action-registry refactor, 2026-07-20): every ActionType must be either
# one of the fixed-pipeline types (MOVE / ATTACK / COUNTER_ATTACK — hardcoded phases in
# execute_orders and the resolver) or registered in BaseAction.SIDE_CHANNEL_ORDER. A type in
# neither would queue but never execute, display, or reach the Play API — the exact silent
# failure the registry exists to kill. A miss here is fixed by REGISTERING the type, not by
# editing this suite.
extends GdUnitTestSuite

const FIXED_PIPELINE: Array[BaseAction.ActionType] = [
	BaseAction.ActionType.MOVE,
	BaseAction.ActionType.ATTACK,
	BaseAction.ActionType.COUNTER_ATTACK,
]

func test_every_action_type_is_exactly_one_of_pipeline_or_side_channel() -> void:
	for value in BaseAction.ActionType.values():
		var type_name: String = BaseAction.ActionType.keys()[value]
		var in_pipeline: bool = FIXED_PIPELINE.has(value)
		var in_side_channel: bool = BaseAction.SIDE_CHANNEL_ORDER.has(value)
		assert_bool(in_pipeline or in_side_channel) \
			.override_failure_message("ActionType.%s is unregistered — add it to SIDE_CHANNEL_ORDER (or the fixed pipeline) or it will queue but never execute/display" % type_name) \
			.is_true()
		assert_bool(in_pipeline and in_side_channel) \
			.override_failure_message("ActionType.%s is registered in BOTH the fixed pipeline and SIDE_CHANNEL_ORDER" % type_name) \
			.is_false()

func test_registry_lists_have_no_duplicates() -> void:
	var seen_side: Dictionary = {}
	for type in BaseAction.SIDE_CHANNEL_ORDER:
		assert_bool(seen_side.has(type)) \
			.override_failure_message("duplicate SIDE_CHANNEL_ORDER entry: %s" % BaseAction.ActionType.keys()[type]) \
			.is_false()
		seen_side[type] = true
	var seen_main: Dictionary = {}
	for type in BaseAction.MAIN_ACTION_TYPES:
		assert_bool(seen_main.has(type)) \
			.override_failure_message("duplicate MAIN_ACTION_TYPES entry: %s" % BaseAction.ActionType.keys()[type]) \
			.is_false()
		seen_main[type] = true

# Every side-channel verb must declare how long its beat holds (#520, dev 2026-08-26). The tail is
# played one order at a time and each one is a CODA beat, so a verb Pacing.coda_hold has no arm for
# gets no emphasis at all -- which is invisible in play and indistinguishable from a deliberate 0.
# The sentinel is what makes it visible: coda_hold answers -1.0 for a verb it does not know.
# A miss here is fixed by adding the hold (and its Game-tab knob), not by editing this suite.
func test_every_side_channel_verb_declares_a_beat_hold() -> void:
	for type in BaseAction.SIDE_CHANNEL_ORDER:
		assert_float(Pacing.coda_hold(type)) \
			.override_failure_message("side-channel %s has no Pacing hold — add HOLD_<VERB>, an arm in coda_hold, and a GameKnobs Playback row, or it plays with no emphasis" % BaseAction.ActionType.keys()[type]) \
			.is_greater_equal(0.0)

func test_side_channels_are_main_actions_today() -> void:
	# Every current side-channel is a main action. If a deliberate non-main side-channel ever
	# lands (a "free" minor action), retire this test consciously rather than coding around it.
	for type in BaseAction.SIDE_CHANNEL_ORDER:
		assert_bool(BaseAction.MAIN_ACTION_TYPES.has(type)) \
			.override_failure_message("side-channel %s is not in MAIN_ACTION_TYPES — if intentional, retire this test" % BaseAction.ActionType.keys()[type]) \
			.is_true()
