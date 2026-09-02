# The Info page is a PROJECTION, and this is the wire (#690).
#
# `test_dev_tree` already pins that the leaf resolves and explains itself, and
# `test_dev_window_fit` that its rows fit -- and NEITHER can see the failure that matters here:
# an unbuilt page has no rows, so it resolves fine and fits perfectly. Deleting
# `dev_info.init(game)` from DevOverlay._ready leaves both green. So this suite asserts the
# visible thing: every registry entry reaches a label, and the machine section reads the real
# path off the thing that owns it rather than a string of its own.
#
# It does NOT pin wording. What an entry SAYS is edited freely; that it ARRIVES is the law.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var overlay: DevOverlay


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	var game := _main.get_node("GameContainer/GameView/Game")
	overlay = game.dev_overlay
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# Every Label text under a node, so a case asserts on what the page SHOWS rather than on the
# container shape it happens to have been built with.
func _labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	var label := node as Label
	if label != null:
		out.append(label.text)
	for child in node.get_children():
		out.append_array(_labels(child))
	return out


func test_every_registry_entry_reaches_the_page() -> void:
	var shown: Array[String] = _labels(overlay.dev_info)
	var missing: Array[String] = []
	for entry: Dictionary in Controls.ENTRIES:
		var key: String = entry["key"]
		if not shown.has(key):
			missing.append(key)
	assert_array(missing).override_failure_message(
		"Controls entries that never reached the Info page: %s (page shows %d labels)"
			% [", ".join(missing), shown.size()]).is_empty()


func test_the_page_names_the_real_report_folder_on_this_machine() -> void:
	var shown: Array[String] = _labels(overlay.dev_info)
	var expected: String = ProjectSettings.globalize_path(BugReporter.REPORT_DIR)
	assert_bool(shown.has(expected)).override_failure_message(
		"The Info page does not show the globalized report folder '%s' -- the machine section is the half no doc could hold"
			% expected).is_true()


# The checkout can change under a running game, so the machine rows are re-read on show rather
# than snapshotted at wiring. Rebuilding must not DUPLICATE them, which is what a rebuild that
# forgets to clear looks like -- and it reads as a working page until you switch pages twice.
func test_showing_the_page_again_rereads_without_duplicating() -> void:
	var expected: String = ProjectSettings.globalize_path(BugReporter.REPORT_DIR)
	overlay.dev_info.refresh_on_show()
	overlay.dev_info.refresh_on_show()
	await await_idle_frame()
	var shown: Array[String] = _labels(overlay.dev_info)
	var hits := 0
	for text: String in shown:
		if text == expected:
			hits += 1
	assert_int(hits).override_failure_message(
		"The report folder appears %d times after two refreshes -- the rebuild is not clearing" % hits) \
		.is_equal(1)
