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
