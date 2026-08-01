# UiText.wrap -- the HUD's text shaper, as a pure function. Split out of the old
# tests/law/test_tooltip_wrapping.gd (2026-08-01, suite audit): these cases need no scene, and
# leaving them in the scene-driven suite would have made each one pay a full Main.tscn
# instantiation in before_test for nothing.
#
# The RULE that every rendered tooltip is already wrapped is enforced at runtime by
# tests/ui/test_tooltip_rendering.gd. This file is only the wrapper's own behaviour, plus a guard
# on the authored content that first exposed the need for it.
#
# It also lives in ui/ rather than law/ now. It is presentation, not a cross-cutting invariant, and
# law/ is in run_tests.ps1's `fast` tier -- so this was running on every inner-loop check.
extends GdUnitTestSuite

func test_wrap_breaks_a_long_line_at_a_space() -> void:
	assert_str(UiText.wrap("aaaa bbbb cccc dddd", 9)).is_equal("aaaa bbbb\ncccc dddd")


func test_wrap_leaves_a_short_line_alone() -> void:
	assert_str(UiText.wrap("short", 56)).is_equal("short")


func test_wrap_preserves_newlines_the_caller_already_wrote() -> void:
	# Every builder in the UI composes with "\n".join(lines), so those breaks are meaningful
	# structure (DEF row, Requires row, flavour) and must survive wrapping as-is.
	assert_str(UiText.wrap("one\ntwo", 56)).is_equal("one\ntwo")


func test_wrap_wraps_each_line_independently() -> void:
	assert_str(UiText.wrap("aaaa bbbb\ncccc dddd", 9)).is_equal("aaaa bbbb\ncccc dddd")


func test_a_word_longer_than_the_width_overflows_rather_than_splitting() -> void:
	# Documented trade-off: readability beats strictness, and nothing authored is that long.
	assert_str(UiText.wrap("supercalifragilistic", 8)).is_equal("supercalifragilistic")


func test_an_overlong_word_does_not_swallow_the_words_after_it() -> void:
	assert_str(UiText.wrap("supercalifragilistic ok", 8)).is_equal("supercalifragilistic\nok")


func test_wrap_handles_empty_text_and_a_nonsense_width() -> void:
	assert_str(UiText.wrap("", 56)).is_equal("")
	assert_str(UiText.wrap("unchanged", 0)).is_equal("unchanged")


func test_wrap_is_idempotent() -> void:
	# The property tests/ui/test_tooltip_rendering.gd's whole law rests on: it asserts
	# `wrap(t) == t` to mean "t is already display-safe", which is only a valid reading if
	# re-wrapping never changes wrapped text. Includes the overflow case, where wrap() must leave
	# its own output alone rather than churning on the unbreakable word.
	for sample: String in [
			"aaaa bbbb cccc dddd",
			"short",
			"one\ntwo",
			"supercalifragilistic ok",
			"",
	]:
		var once := UiText.wrap(sample, 9)
		assert_str(UiText.wrap(once, 9)).override_failure_message(
			"wrap() is not idempotent for %s -- the display-safety law in test_tooltip_rendering.gd is unsound." % JSON.stringify(sample)
			).is_equal(once)


func test_every_line_of_wrapped_text_fits_unless_it_is_one_long_word() -> void:
	# The guarantee the law depends on, stated directly rather than via idempotence.
	var text := "the quick brown fox jumps over the lazy dog and keeps on running well past the margin"
	for line in UiText.wrap(text, 20).split("\n"):
		assert_int(line.length()).is_less_equal(20)


func test_a_real_authored_description_fits_the_default_width() -> void:
	# The actual regression content: this is what ran off the right edge of the screen. Asserting on
	# the AUTHORED resource means re-authoring an over-long unbreakable one-liner fails here rather
	# than in a feel-test -- wrap() cannot save a single word wider than the tooltip.
	var weave: ArmorData = ArmorCatalog.get_editable()["Insulated Weave"]
	for ability: AbilityData in weave.granted_abilities:
		for line in UiText.wrap(ability.description).split("\n"):
			assert_int(line.length()).is_less_equal(UiText.TOOLTIP_WIDTH)
	for line in UiText.wrap(weave.description).split("\n"):
		assert_int(line.length()).is_less_equal(UiText.TOOLTIP_WIDTH)
