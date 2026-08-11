# The overwrite guards (dev call 2026-08-11, after an Update aimed at an unloaded scenario
# destroyed missions/Prolog): Update only fires at the LOADED file -- each tool's
# _update_block_reason is the one source for both the greyed button and the refused press
# (#166 shape) -- and Delete asks "Are you sure?" through DevWidgets.confirm_delete before a
# byte moves.
#
# No case writes to disk: refusal cases return before any save, the allowed direction is
# asserted at reason level (a real allowed Update would re-save a tracked scenario), and the
# Delete cases never emit `confirmed` at a tool (only cancel, or the helper wired to a flag).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const PROLOG := "missions/Prolog"

var _main: Node
var game: Node2D
var overlay: DevOverlay

func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	overlay = game.dev_overlay
	await await_idle_frame()

func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()

func _scenario_tool() -> ScenarioTool:
	return overlay.scenario_tool

func _find_dialog(host: Node) -> ConfirmationDialog:
	for child in host.get_children():
		if child is ConfirmationDialog:
			return child as ConfirmationDialog
	return null

# ==============================================================================
#  Update: the load gate
# ==============================================================================

func test_update_refuses_a_scenario_that_is_not_loaded() -> void:
	# The accident replayed: the live board is NOT Prolog, the dropdown says Prolog, Update pressed.
	var tool := _scenario_tool()
	tool.refresh_dropdown(PROLOG)

	tool.update_button.pressed.emit()

	assert_str(tool.status_label.text).is_not_empty()
	assert_str(game.scenario_manager.last_loaded_path).is_empty()   # no save ever happened

func test_update_allows_the_loaded_scenario() -> void:
	# Reason level only -- an actual allowed press would re-save the tracked file.
	var tool := _scenario_tool()
	game.scenario_manager.load_scenario(ScenarioManager.scenario_path(PROLOG))
	tool.refresh_dropdown(PROLOG)

	assert_str(tool._update_block_reason()).is_empty()
	assert_bool(tool.update_button.disabled).is_false()

func test_the_button_and_the_refusal_agree() -> void:
	var tool := _scenario_tool()
	tool.refresh_dropdown(PROLOG)   # not loaded -> blocked
	assert_bool(tool.update_button.disabled).is_true()

	game.scenario_manager.load_scenario(ScenarioManager.scenario_path(PROLOG))
	tool.refresh_dropdown(PROLOG)   # loaded -> allowed
	assert_bool(tool.update_button.disabled).is_false()

func test_a_cleared_board_has_no_loaded_scenario() -> void:
	# Without clear_board wiping last_loaded_path, a sandbox board still counts the previous
	# mission as loaded -- and the gate would wave the original accident through.
	game.scenario_manager.load_scenario(ScenarioManager.scenario_path(PROLOG))
	game.scenario_manager.clear_board()

	assert_str(game.scenario_manager.last_loaded_path).is_empty()
	var tool := _scenario_tool()
	tool.refresh_dropdown(PROLOG)
	tool.update_button.pressed.emit()
	assert_str(tool.status_label.text).is_not_empty()

func test_item_editor_refuses_an_unloaded_target() -> void:
	var tool: ItemEditorTool = overlay.get_node("%Item Editor")
	assert_int(tool.load_dropdown.item_count).is_greater(0)   # empty catalog would make this vacuous
	tool.load_dropdown.select(0)

	tool.update_button.pressed.emit()

	assert_str(tool.status_label.text).is_not_empty()

func test_item_editor_allows_the_loaded_entry() -> void:
	var tool: ItemEditorTool = overlay.get_node("%Item Editor")
	assert_int(tool.load_dropdown.item_count).is_greater(0)
	tool.load_dropdown.select(0)
	tool._on_load_pressed()

	assert_str(tool._update_block_reason()).is_empty()
	assert_bool(tool.update_button.disabled).is_false()

func test_showing_the_tab_aims_the_dropdown_at_the_loaded_scenario() -> void:
	# Dev ask 2026-08-11: an external load (Mission Select, F2) should pre-select its scenario, so
	# Update is aimed without hunting the list. Drives the real tab-entry hook.
	game.scenario_manager.load_scenario(ScenarioManager.scenario_path(PROLOG))
	var tool := _scenario_tool()
	tool.refresh_dropdown("Elemental")   # the dev wandered; the tab visit should re-aim

	tool.refresh_on_show()

	assert_str(DevWidgets.selected_name(tool.scenario_dropdown)).is_equal(PROLOG)
	assert_bool(tool.update_button.disabled).is_false()   # aimed AND the gate agrees

func test_showing_the_tab_with_nothing_loaded_leaves_the_selection_alone() -> void:
	var tool := _scenario_tool()
	tool.refresh_dropdown("Elemental")

	tool.refresh_on_show()

	assert_str(DevWidgets.selected_name(tool.scenario_dropdown)).is_equal("Elemental")

# ==============================================================================
#  Delete: the confirm dialog
# ==============================================================================

func test_delete_asks_before_deleting() -> void:
	var tool := _scenario_tool()
	tool.refresh_dropdown(PROLOG)

	tool.delete_button.pressed.emit()

	assert_object(_find_dialog(tool)).is_not_null()
	assert_bool(FileAccess.file_exists(ScenarioManager.scenario_path(PROLOG))).is_true()

func test_delete_cancel_deletes_nothing_and_the_dialog_frees() -> void:
	var tool := _scenario_tool()
	tool.refresh_dropdown(PROLOG)
	tool.delete_button.pressed.emit()
	var dialog := _find_dialog(tool)
	assert_object(dialog).is_not_null()

	dialog.canceled.emit()
	dialog.hide()
	await await_idle_frame()

	assert_bool(FileAccess.file_exists(ScenarioManager.scenario_path(PROLOG))).is_true()
	assert_object(_find_dialog(tool)).is_null()

func test_the_helper_confirm_wire_fires_the_callable() -> void:
	# The helper's own wire, against a flag -- never a real deletion.
	var hit := [false]
	var dialog := DevWidgets.confirm_delete(_scenario_tool(), "nothing real", func(): hit[0] = true)

	dialog.confirmed.emit()
	dialog.hide()
	await await_idle_frame()

	assert_bool(hit[0]).is_true()
	assert_object(_find_dialog(_scenario_tool())).is_null()
