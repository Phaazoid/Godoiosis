# The Dialog & Tutorial page (#397). The tree-law suite already pins its LEAF (resolves, unique,
# tooltipped); what this suite pins is the page's contract with the stores: rows project
# ScenarioManager's lesson content, edits write it back, and every edit marks the header.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D
var tool_page: DialogTool


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	tool_page = game.dev_overlay.dialog_tool
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _beat_rows() -> int:
	var count := 0
	for child in tool_page._beat_list.get_children():
		if child is HBoxContainer and not child.is_queued_for_deletion():
			count += 1
	return count


func test_rows_project_the_stores() -> void:
	game.scenario_manager.current_dialog_beats.append(DialogBeat.new())
	var step := TutorialStep.new()
	step.text = "Do the thing."
	game.scenario_manager.current_tutorial_steps.append(step)
	tool_page.refresh()
	assert_int(_beat_rows()).is_equal(1)
	var texts: Array[String] = []
	for child in tool_page._step_list.get_children():
		for control in child.find_children("*", "LineEdit", true, false):
			texts.append((control as LineEdit).text)
	assert_array(texts).contains(["Do the thing."])


func test_add_beat_writes_the_store_and_marks_the_header() -> void:
	var header: ScenarioHeader = tool_page._header
	assert_object(header).is_not_null()
	tool_page._on_add_beat()
	assert_int(game.scenario_manager.current_dialog_beats.size()).is_equal(1)
	assert_int(_beat_rows()).is_equal(1)


func test_reorder_moves_the_authored_sequence() -> void:
	var first := TutorialStep.new()
	first.text = "first"
	var second := TutorialStep.new()
	second.text = "second"
	game.scenario_manager.current_tutorial_steps.append(first)
	game.scenario_manager.current_tutorial_steps.append(second)
	tool_page.refresh()
	tool_page._move_step(1, -1)
	assert_str(game.scenario_manager.current_tutorial_steps[0].text).is_equal("second")


# --- the #982 timeline editor ---
#
# NOTHING HERE WRITES res://. The page's Save does, which is exactly why these drive registration
# against a user:// copy of project.godot instead: a dev-tool case that can create or delete real
# Scenarios/dialog/ files is one mutant away from editing the dev's content.

const SCRATCH_SETTINGS := "user://test_dialog_tool_project.godot"
const SCRATCH_TIMELINE := "user://test_dialog_tool/scratch.dtl"

var _dtl_before := {}
var _dch_before := {}


func _snapshot_registries() -> void:
	_dtl_before = DialogicSource.directory("dtl").duplicate()
	_dch_before = DialogicSource.directory("dch").duplicate()
	var source := FileAccess.get_file_as_string("res://project.godot")
	var file := FileAccess.open(SCRATCH_SETTINGS, FileAccess.WRITE)
	file.store_string(source)
	file.close()


func _restore_registries() -> void:
	ProjectSettings.set_setting("dialogic/directories/dtl_directory", _dtl_before)
	ProjectSettings.set_setting("dialogic/directories/dch_directory", _dch_before)
	for key: String in ["dtl_directory", "dch_directory"]:
		if Engine.has_meta(key):
			Engine.remove_meta(key)
	for path: String in [SCRATCH_SETTINGS, SCRATCH_TIMELINE, SCRATCH_TIMELINE + ".uid"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _beat_timeline_names() -> PackedStringArray:
	game.scenario_manager.current_dialog_beats.append(DialogBeat.new())
	tool_page.refresh()
	var names := PackedStringArray()
	for child in tool_page._beat_list.get_children():
		if not child is HBoxContainer:
			continue
		for control in child.get_children():
			if control is OptionButton:
				var picker := control as OptionButton
				for i in picker.item_count:
					names.append(picker.get_item_text(i))
	return names


# THE WIRE: registering a timeline has to reach the picker in the SAME session. Dialogic caches a
# directory in Engine meta on first read and the page reads ProjectSettings, so a writer that only
# touched the committed file would leave both stale until relaunch.
func test_a_registered_timeline_reaches_the_beat_rows_dropdown() -> void:
	_snapshot_registries()
	DialogicSource.register("dtl", "zz_probe", "res://Scenarios/dialog/zz_probe.dtl", SCRATCH_SETTINGS)

	assert_str(", ".join(_beat_timeline_names())).contains("zz_probe")
	_restore_registries()


func test_a_registered_speaker_reaches_the_line_speaker_dropdown() -> void:
	_snapshot_registries()
	DialogicSource.register("dch", "zz_speaker", "res://Scenarios/dialog/characters/zz_speaker.dch",
		SCRATCH_SETTINGS)
	tool_page._on_add_line()

	var found := false
	for child in tool_page._line_list.get_children():
		if not child is HBoxContainer:
			continue
		for control in child.get_children():
			if control is OptionButton:
				var picker := control as OptionButton
				for i in picker.item_count:
					if picker.get_item_text(i) == "zz_speaker":
						found = true
	assert_bool(found).is_true()
	_restore_registries()


# A timeline this page cannot round-trip opens READ-ONLY: no line rows to edit, and a reason
# naming where to go instead. Saving one would flatten whatever it holds.
func test_a_timeline_this_page_cannot_write_back_opens_read_only() -> void:
	_snapshot_registries()
	DialogicSource.write(SCRATCH_TIMELINE, "torv: A line.\nlabel somewhere")
	DialogicSource.register("dtl", "zz_rich", SCRATCH_TIMELINE, SCRATCH_SETTINGS)
	tool_page.refresh()
	var index := -1
	for i in tool_page._timeline_picker.item_count:
		if tool_page._timeline_picker.get_item_text(i) == "zz_rich":
			index = i
	assert_int(index).is_greater(-1)

	tool_page._on_timeline_picked(index)

	assert_bool(tool_page._editable).is_false()
	assert_str(tool_page._status.text).contains("Dialogic")
	var rows := 0
	for child in tool_page._line_list.get_children():
		if child is HBoxContainer:
			rows += 1
	assert_int(rows).is_equal(0)
	_restore_registries()


# --- names and the picker (the bugs the dev found in play) ---

# The prefill used display_name(), which keeps the folder: "missions/Terraces" became a
# subdirectory under Scenarios/dialog/ and an empty twin that later won the registry name.
func test_the_suggested_name_carries_no_folder() -> void:
	game.scenario_manager.last_loaded_path = "res://Scenarios/missions/Terraces.tres"
	assert_str(tool_page._suggested_name()).is_equal("terraces_intro")


# Refused BEFORE anything is written, so a path-shaped name can never make a folder again.
func test_saving_under_a_path_shaped_name_is_refused_and_writes_nothing() -> void:
	tool_page._on_new_timeline()
	tool_page._name_field.text = "missions/zz_probe"
	tool_page._on_save_timeline()
	assert_str(tool_page._status.text).contains("slashes")
	assert_bool(FileAccess.file_exists("res://Scenarios/dialog/missions/zz_probe.dtl")).is_false()
	assert_bool(DirAccess.dir_exists_absolute("res://Scenarios/dialog/missions")).is_false()


# add_item auto-selects entry 0, so a select(-1) placed BEFORE the add loop is undone at once and
# the picker showed causeway_intro with nothing loaded.
func test_the_picker_selects_nothing_while_nothing_is_loaded() -> void:
	tool_page._loaded_name = ""
	tool_page.refresh()
	assert_int(tool_page._timeline_picker.item_count).is_greater(0)
	assert_int(tool_page._timeline_picker.selected).is_equal(-1)
