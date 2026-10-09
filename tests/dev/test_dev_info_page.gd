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
const SCRATCH_TELEMETRY := "user://__dev_info_telemetry_test/"

var _main: Node
var overlay: DevOverlay
var _prior_telemetry_root := ""


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	var game := _main.get_node("GameContainer/GameView/Game")
	overlay = game.dev_overlay
	_prior_telemetry_root = TelemetryStore.root
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()
	TelemetryStore.root = _prior_telemetry_root
	_wipe_dir(SCRATCH_TELEMETRY)


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


# #855: whether telemetry ever LEFT the machine, read off the folders that are its state. Counts
# distinct enough that no other row on the page carries all three by accident; the words around
# them are not pinned. A swap of two counts within the row is visible only as wording -- declared.
func test_the_page_counts_the_runs_in_each_telemetry_folder() -> void:
	TelemetryStore.root = SCRATCH_TELEMETRY
	_make_runs(TelemetryStore.pending_dir(), "owed", 7)
	_make_runs(TelemetryStore.sent_dir(), "sent", 11)
	_make_runs(TelemetryStore.held_dir(), "held", 13)
	overlay.dev_info.refresh_on_show()
	await await_idle_frame()

	var shown: Array[String] = _labels(overlay.dev_info)
	var folder: String = ProjectSettings.globalize_path(SCRATCH_TELEMETRY)
	assert_bool(shown.has(folder)).override_failure_message(
		"The Info page does not show the telemetry folder '%s'" % folder).is_true()
	assert_bool(_a_label_shows([7, 11, 13])).override_failure_message(
		"No row shows 7 owed / 11 sent / 13 held -- the counts are not reaching the page").is_true()

	# A run moving folders under a running game is what the page exists to notice.
	var moved := "owed_00"
	assert_int(DirAccess.rename_absolute(TelemetryStore.pending_dir() + moved,
		TelemetryStore.held_dir() + moved)).is_equal(OK)
	overlay.dev_info.refresh_on_show()
	await await_idle_frame()
	assert_bool(_a_label_shows([6, 11, 14])).override_failure_message(
		"After a run moved from pending/ to held/, no row shows 6 / 11 / 14 -- the counts are not re-read on show").is_true()


# Whole numbers only (\b), so a commit hash's digits cannot make up a match.
func _a_label_shows(counts: Array[int]) -> bool:
	var re := RegEx.create_from_string("\\b\\d+\\b")
	for text: String in _labels(overlay.dev_info):
		var found: Array[int] = []
		for m: RegExMatch in re.search_all(text):
			found.append(int(m.get_string()))
		var all_there := true
		for n: int in counts:
			if not found.has(n):
				all_there = false
		if all_there:
			return true
	return false


# Named per folder: a rename onto a folder that already exists fails.
func _make_runs(dir: String, prefix: String, count: int) -> void:
	for i in range(count):
		DirAccess.make_dir_recursive_absolute(dir + "%s_%02d" % [prefix, i])


# Recursive: DirAccess.remove fails silently on a non-empty folder (#846).
func _wipe_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_wipe_dir(path + sub + "/")
		dir.remove(sub)
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)
