# The Unit Editor's AI band dropdown (#1230): the one door for setting which profile a unit plays.
# Drives the REAL OptionButton and the REAL Save button in the built panel rather than the handler --
# a row that never draws looks exactly like a field nobody edits (#804).
#
# Fixture is tests/dev/test_unit_editor_lifecycle.gd's.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D
var _editor: UnitEditorTool


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(4):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	var overlay: DevOverlay = game.dev_overlay
	_editor = overlay.unit_editor
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn() -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(0, 0))
	assert_object(unit).is_not_null()
	return unit


# The OptionButton in the row whose label reads `label`, found by walking the built panel.
func _option(label: String) -> OptionButton:
	return _find_option(_editor, label)


func _find_option(node: Node, label: String) -> OptionButton:
	if node is HBoxContainer:
		var row := node as HBoxContainer
		var has_label := false
		for child in row.get_children():
			if child is Label and (child as Label).text == label:
				has_label = true
		if has_label:
			for child in row.get_children():
				if child is OptionButton:
					return child as OptionButton
	for child in node.get_children():
		var found := _find_option(child, label)
		if found != null:
			return found
	return null


func _save_button() -> Button:
	return _find_button(_editor, "Save")


func _find_button(node: Node, prefix: String) -> Button:
	if node is Button and (node as Button).text.begins_with(prefix) and not node is OptionButton:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, prefix)
		if found != null:
			return found
	return null


func _pick(option: OptionButton, text: String) -> void:
	for i in option.item_count:
		if option.get_item_text(i) == text:
			option.select(i)
			option.item_selected.emit(i)
			return
	fail("the dropdown offers no '%s'" % text)


func test_picking_a_band_and_saving_sets_the_units_profile() -> void:
	var unit := _spawn()
	_editor.edit_unit(unit)
	var option := _option("AI band")
	assert_object(option).override_failure_message("the Unit Editor draws no AI band row").is_not_null()
	if option == null:
		return
	assert_str(option.get_item_text(option.selected)).override_failure_message(
		"an unassigned unit should open on the default row").is_equal(UnitEditorTool.DEFAULT_PROFILE_LABEL)

	_pick(option, "Easy")
	assert_str(unit.ai_profile).override_failure_message("a staged pick must not reach the unit before Save") \
		.is_empty()
	var save := _save_button()
	assert_object(save).is_not_null()
	save.pressed.emit()
	assert_str(unit.ai_profile).is_equal("Easy")


func test_picking_the_default_row_clears_a_profile() -> void:
	var unit := _spawn()
	unit.ai_profile = "Easy"
	_editor.edit_unit(unit)
	var option := _option("AI band")
	assert_str(option.get_item_text(option.selected)).is_equal("Easy")
	_pick(option, UnitEditorTool.DEFAULT_PROFILE_LABEL)
	_save_button().pressed.emit()
	assert_str(unit.ai_profile).is_empty()


# Opening the editor on a unit whose profile file is gone must not quietly rewrite it to the default:
# the stale name stays selectable, so the lint still has something to report.
func test_a_stale_name_stays_selected_rather_than_being_rewritten() -> void:
	var unit := _spawn()
	unit.ai_profile = "NoSuchProfileEverExisted"
	_editor.edit_unit(unit)
	var option := _option("AI band")
	assert_str(option.get_item_text(option.selected)).is_equal("NoSuchProfileEverExisted")
	_save_button().pressed.emit()
	assert_str(unit.ai_profile).is_equal("NoSuchProfileEverExisted")
