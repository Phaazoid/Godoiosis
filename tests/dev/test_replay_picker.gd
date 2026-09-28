# WHAT THE REPLAY TAB'S RUN LIST OFFERS (#925). The folder gains a run every time the dev opens a
# mission and leaves it, so most of what accumulates there is board swaps and F2s -- 34 of the 41
# runs on the dev's machine the day this was filed never reached round 2. There is nothing in one
# to replay, and they crowd out the handful worth looking at.
#
# THE RUNS ARE HAND-STAGED, which is a narrower fixture than test_replay_driver.gd's played mission
# and is the right one here: the filter reads the `round` stamped on each event line, so a file
# holding those lines exercises the whole wire this suite is about (refresh -> list_runs ->
# load_events -> is_one_turn -> add_item). That MissionLog stamps the round correctly is a different
# question, pinned where the recorder is.
#
# Persistence is aimed at a scratch folder for the ordinary reason -- the dev's own recorded runs
# are on this machine, and a suite that read them would pass or fail by how he last played.
#
# EVERY STAGED RUN IS SEALED. game.gd's boot calls MissionLog.sweep_unsealed(), so an unsealed
# fixture would be rewritten out from under the case that staged it.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH_ROOT := "user://__replay_picker_test/"
const SHORT_RUN := "2026-09-12_01-00-00_oneturn0"
const LONG_RUN := "2026-09-12_02-00-00_played00"
const NEWER_RUN := "2026-09-12_03-00-00_played01"
const NEWEST_RUN := "2026-09-12_04-00-00_played02"
const HIDE_BOX := "Hide one-turn runs"

var _main: Node
var game: Node2D
var overlay: DevOverlay


func before_test() -> void:
	TelemetryStore.reset_for_test()
	TelemetryStore.root = SCRATCH_ROOT
	TelemetryStore.persistence_enabled = true
	_wipe(SCRATCH_ROOT)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	overlay = game.dev_overlay
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	_wipe(SCRATCH_ROOT)
	TelemetryStore.reset_for_test()


# ==============================================================================
#  The filter
# ==============================================================================

func test_a_one_turn_run_is_kept_out_of_the_picker() -> void:
	_stage_run(SHORT_RUN, 1)
	_stage_run(LONG_RUN, 3)
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	# Non-vacuity: if the staged pair did not actually differ in rounds there is nothing to filter.
	assert_int(ReplayRun.load_events(LONG_RUN).rounds()).override_failure_message(
		"fixture: the long run never reached round 2, so this case cannot see the filter"
		).is_greater(1)
	assert_array(_listed(tool)).override_failure_message(
		"the one-turn run is still in the picker").is_equal([LONG_RUN])


func test_unticking_the_box_brings_the_one_turn_runs_back() -> void:
	_stage_run(SHORT_RUN, 1)
	_stage_run(LONG_RUN, 3)
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	assert_int(_listed(tool).size()).override_failure_message(
		"fixture: the filter never hid anything, so unticking cannot be seen").is_equal(1)

	# DRIVEN THROUGH THE REAL CHECKBOX, never by writing the flag: a box wired to nothing looks
	# exactly like a box wired correctly from the flag's side.
	_hide_box(tool).button_pressed = false

	assert_array(_listed(tool)).override_failure_message(
		"unticking the box did not put the one-turn run back -- it is bound to nothing"
		).is_equal([LONG_RUN, SHORT_RUN])


func test_a_run_that_reached_round_two_is_never_hidden() -> void:
	_stage_run(LONG_RUN, 2)
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	assert_array(_listed(tool)).override_failure_message(
		"round 2 is the first round that counts as more than one turn").is_equal([LONG_RUN])


# The box defaults to hiding, so this is the state the dev meets on opening the tab -- and the one
# where a stale "nothing recorded yet" would send him looking for a broken recorder.
func test_the_empty_list_says_runs_are_hidden_rather_than_absent() -> void:
	_stage_run(SHORT_RUN, 1)
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	assert_array(_listed(tool)).override_failure_message(
		"fixture: something was listed, so the message under test is not the empty one").is_empty()
	var said := _status_text(tool)
	assert_str(said).override_failure_message(
		"the tab claims nothing has been recorded while a run sits in the folder").contains("hidden")
	assert_str(said).contains("1")


func test_an_actually_empty_folder_still_says_so() -> void:
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	assert_array(_listed(tool)).is_empty()
	assert_str(_status_text(tool)).override_failure_message(
		"an empty folder reported hidden runs it does not have").contains("No recorded runs yet")


# ==============================================================================
#  The row (#939)
# ==============================================================================
#
# A row is a LABEL and the run id rides the item's metadata. These cases assert the FACTS a row
# carries, never the words around them.

func test_a_row_names_its_mission_and_ending_not_its_id() -> void:
	_stage_run(LONG_RUN, 3)
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	var labels := _labels(tool)
	assert_int(labels.size()).is_equal(1)
	assert_str(labels[0]).override_failure_message(
		"the row does not name its board: '%s'" % labels[0]).contains("Fixture")
	assert_str(labels[0]).override_failure_message(
		"the row does not say how the run ended: '%s'" % labels[0]).contains("ABANDONED")
	assert_str(labels[0]).override_failure_message(
		"the row is still the raw run id: '%s'" % labels[0]).not_contains(LONG_RUN.right(8))


# THE TRAP THE TICKET NAMED: a relabelled row that is still read back as the id loads nothing.
# Driven through the dropdown's own signal, so the wire is what is asserted.
func test_picking_a_row_loads_that_run() -> void:
	_stage_run(LONG_RUN, 3)
	_stage_run(NEWER_RUN, 3)
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	var list := _list(tool)
	assert_array(_listed(tool)).override_failure_message(
		"fixture: newest first, so index 1 is the older run").is_equal([NEWER_RUN, LONG_RUN])

	list.select(1)
	list.item_selected.emit(1)

	assert_object(tool._run).override_failure_message("picking a row loaded nothing").is_not_null()
	assert_str(tool._run.run_id).override_failure_message(
		"picking the second row loaded a different run").is_equal(LONG_RUN)


# A newer run arriving shifts every index down one, so a selection kept by INDEX -- or by a label
# compared against an id -- lands on the wrong run or falls back to the top.
func test_the_selection_survives_a_refresh_that_shifts_every_row() -> void:
	_stage_run(LONG_RUN, 3)
	_stage_run(NEWER_RUN, 3)
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	var list := _list(tool)
	list.select(1)

	_stage_run(NEWEST_RUN, 3)
	tool.refresh_on_show()

	assert_array(_listed(tool)).override_failure_message(
		"fixture: the newer run did not arrive at the top").is_equal([NEWEST_RUN, NEWER_RUN, LONG_RUN])
	assert_str(str(list.get_item_metadata(list.selected))).override_failure_message(
		"a refresh moved the selection off the run that was picked").is_equal(LONG_RUN)


# `dev_touched` is THREE-valued and the sweep writes null; `bool(null)` is a hard script error, which
# would drop the row from the list rather than fail loudly.
func test_a_swept_run_lists_and_carries_its_mark() -> void:
	_stage_run(LONG_RUN, 3, null)
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	var labels := _labels(tool)
	assert_int(labels.size()).override_failure_message(
		"a swept run vanished from the list -- its null flag was coerced").is_equal(1)
	assert_str(labels[0]).override_failure_message(
		"a swept run's row does not say so: '%s'" % labels[0]).contains("swept")


# The folder is the run's state (#852), so three runs identical but for where they sit must read
# differently -- which is all this asserts, not what each one says.
func test_where_a_run_sits_reaches_its_row() -> void:
	var owed := "2026-09-12_05-00-00_owedrun0"
	var sent := "2026-09-12_05-00-00_sentrun0"
	var held := "2026-09-12_05-00-00_heldrun0"
	for run_id: String in [owed, sent, held]:
		_stage_run(run_id, 3)
	assert_bool(TelemetryStore.mark_sent(sent)).is_true()
	assert_bool(TelemetryStore.mark_held(held)).is_true()
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	var labels := _labels(tool)
	assert_int(labels.size()).is_equal(3)
	assert_bool(labels[0] != labels[1] and labels[1] != labels[2] and labels[0] != labels[2]
		).override_failure_message(
			"runs in pending/, sent/ and held/ read the same: %s" % str(labels)).is_true()


# The stamp in a run id is UTC; the row shows it on the machine's clock. -240 is a UTC-4 offset,
# so 02:00 UTC reads as 22:00 the previous day.
func test_a_row_shows_the_time_on_the_local_clock() -> void:
	var head := {"run_id": "2026-09-12_02-00-00_played00", "scenario": "Fixture",
		"outcome": "ABANDONED", "rounds": 3, "sent": true}
	assert_str(ReplayTool.row_label(head, -240)).override_failure_message(
		"the row did not move the UTC stamp onto the local clock").contains("09-11 22:00")


# ==============================================================================
#  Fixture
# ==============================================================================

# A sealed run whose events reach `rounds`. One line per round plus the ending, which is the
# shape MissionLog leaves: every line carries the round it happened in.
func _stage_run(run_id: String, rounds: int, dev_touched: Variant = false) -> void:
	var dir := TelemetryStore.run_dir(run_id)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + ReplayRun.EVENTS_FILE, FileAccess.WRITE)
	f.store_line(JSON.stringify({
		"seq": 0, "t_ms": 0, "round": 1, "event": "mission_start",
		"scenario_name": "Fixture", "roster": []}))
	var seq := 1
	for r in range(1, rounds + 1):
		f.store_line(JSON.stringify({
			"seq": seq, "t_ms": seq * 10, "round": r, "event": "turn_start", "units": []}))
		seq += 1
	f.store_line(JSON.stringify({
		"seq": seq, "t_ms": seq * 10, "round": rounds, "event": "mission_end",
		"outcome": "ABANDONED", "dev_touched": dev_touched, "units": []}))
	f.close()


# The run ids the picker offers, in order -- read off the METADATA, since a row's text is a label
# for a person (#939). Every filter case above asserts through this.
func _listed(tool: ReplayTool) -> Array[String]:
	var out: Array[String] = []
	var list := _list(tool)
	for i in range(list.item_count):
		out.append(str(list.get_item_metadata(i)))
	return out


func _labels(tool: ReplayTool) -> Array[String]:
	var out: Array[String] = []
	var list := _list(tool)
	for i in range(list.item_count):
		out.append(list.get_item_text(i))
	return out


func _list(tool: ReplayTool) -> OptionButton:
	var list := _first_of(tool, "OptionButton") as OptionButton
	assert_object(list).override_failure_message("the picker has no dropdown").is_not_null()
	return list


func _status_text(tool: ReplayTool) -> String:
	for node in _descendants(tool):
		var label := node as Label
		if label != null and label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART:
			return label.text
	return ""


func _hide_box(tool: ReplayTool) -> CheckBox:
	for node in _descendants(tool):
		var box := node as CheckBox
		if box != null and box.text == HIDE_BOX:
			return box
	fail("the Replay tab has no '%s' checkbox" % HIDE_BOX)
	return null


func _first_of(root: Node, klass: String) -> Node:
	for node in _descendants(root):
		if node.is_class(klass):
			return node
	return null


func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir + sub + "/")
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + file)
	DirAccess.remove_absolute(dir)
