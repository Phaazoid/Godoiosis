# Every tooltip in Classes/ui/ must route its text through UiText.wrap (2026-07-29, found by
# feel-test: a long ability description ran off the right edge of the screen and was unreadable).
#
# This is a SOURCE-LEVEL law, which is unusual here and deliberate. Godot's built-in tooltip is a
# Label with autowrap OFF, and autowrap is a property rather than a theme item, so there is no
# global switch to flip -- the rule can only live at each site. And Classes/ui/ has ZERO runtime
# coverage because the game scene segfaults inside the runner (#114), so a forgotten wrap is
# invisible to every other test in the suite. Reading the files is the only pin available.
#
# Scope is game UI only: Classes/dev/ tooltips are short one-liners in their own OS window.
extends GdUnitTestSuite

const UI_DIR := "res://Classes/ui"

# The rule is per-FUNCTION, not per-line, because a correct site legitimately assigns raw text
# first: _limb_chip builds its tooltip through a match plus a `+=` append and wraps ONCE at the
# end, and _add_stat hoists the wrap into a local to share it across two labels. Both would look
# non-compliant line-by-line. Per-function still catches the failure that actually rots -- a new
# tooltip site added with no wrap anywhere in sight -- without flagging correct construction.
func _gd_files(dir_path: String, found: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_gd_files(full, found)
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _offenders() -> Array[String]:
	var files: Array[String] = []
	_gd_files(UI_DIR, files)
	var bad: Array[String] = []
	for path in files:
		for block in _function_blocks(FileAccess.get_file_as_string(path)):
			var body: String = block["body"]
			if not body.contains("tooltip_text"):
				continue
			if body.contains("UiText"):
				continue
			bad.append("%s  ->  %s" % [path, block["name"]])
	return bad


# Split a script into {name, body} per function. Everything before the first `func` is grouped as
# one pseudo-block so a top-level tooltip assignment can't slip through unscanned.
func _function_blocks(text: String) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var current := {"name": "<file scope>", "body": ""}
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("func ") or stripped.begins_with("static func "):
			blocks.append(current)
			current = {"name": stripped, "body": ""}
		else:
			current["body"] = str(current["body"]) + "\n" + line
	blocks.append(current)
	return blocks


func test_the_ui_dir_is_actually_being_scanned() -> void:
	# Guard against the law passing because the walk found nothing. If Classes/ui/ ever moves,
	# this fails loudly instead of the real assertion below going quietly vacuous.
	var files: Array[String] = []
	_gd_files(UI_DIR, files)
	assert_int(files.size()).is_greater(5)

	# Counted through _function_blocks, not the raw file text, so a broken splitter (empty bodies)
	# can't make the law above pass vacuously — that would be a green test pinning nothing.
	var tooltip_functions: Array[String] = []
	for path in files:
		for block in _function_blocks(FileAccess.get_file_as_string(path)):
			if str(block["body"]).contains("tooltip_text"):
				tooltip_functions.append("%s -> %s" % [path, block["name"]])
	assert_int(tooltip_functions.size()).override_failure_message(
		"_function_blocks found no function body containing tooltip_text — the splitter is broken, so the law test is pinning nothing. Blocks seen: %s" % str(tooltip_functions)
		).is_greater_equal(5)

	# And every one of them must be a real named function, not the file-scope catch-all.
	for entry in tooltip_functions:
		assert_str(entry).not_contains("<file scope>")


func test_every_ui_tooltip_routes_through_uitext() -> void:
	var bad := _offenders()
	assert_array(bad).override_failure_message(
		"These functions set tooltip_text but never call UiText.wrap — Godot will not wrap it, so a long line runs off-screen:\n  %s"
		% "\n  ".join(bad)).is_empty()


# --- the wrapper itself ---

func test_wrap_breaks_a_long_line_at_a_space() -> void:
	var out := UiText.wrap("aaaa bbbb cccc dddd", 9)
	assert_str(out).is_equal("aaaa bbbb\ncccc dddd")


func test_wrap_leaves_a_short_line_alone() -> void:
	assert_str(UiText.wrap("short", 56)).is_equal("short")


func test_wrap_preserves_newlines_the_caller_already_wrote() -> void:
	# Every builder in the UI composes with "\n".join(lines), so those breaks are meaningful
	# structure (DEF row, Requires row, flavour) and must survive wrapping as-is.
	assert_str(UiText.wrap("one\ntwo", 56)).is_equal("one\ntwo")


func test_wrap_wraps_each_line_independently() -> void:
	var out := UiText.wrap("aaaa bbbb\ncccc dddd", 9)
	assert_str(out).is_equal("aaaa bbbb\ncccc dddd")


func test_a_word_longer_than_the_width_overflows_rather_than_splitting() -> void:
	# Documented trade-off: readability beats strictness, and nothing authored is that long.
	assert_str(UiText.wrap("supercalifragilistic", 8)).is_equal("supercalifragilistic")


func test_an_overlong_word_does_not_swallow_the_words_after_it() -> void:
	assert_str(UiText.wrap("supercalifragilistic ok", 8)).is_equal("supercalifragilistic\nok")


func test_wrap_handles_empty_text_and_a_nonsense_width() -> void:
	assert_str(UiText.wrap("", 56)).is_equal("")
	assert_str(UiText.wrap("unchanged", 0)).is_equal("unchanged")


func test_a_real_authored_description_fits_the_default_width() -> void:
	# The actual regression: this is the content that ran off-screen. Asserts on the AUTHORED
	# resource, so re-authoring an over-long one-liner fails here rather than in a feel-test.
	var weave: ArmorData = ArmorCatalog.get_editable()["Insulated Weave"]
	for ability: AbilityData in weave.granted_abilities:
		for line in UiText.wrap(ability.description).split("\n"):
			assert_int(line.length()).is_less_equal(UiText.TOOLTIP_WIDTH)
	for line in UiText.wrap(weave.description).split("\n"):
		assert_int(line.length()).is_less_equal(UiText.TOOLTIP_WIDTH)
