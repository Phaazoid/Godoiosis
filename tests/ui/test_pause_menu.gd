# The pause card's own choices (#132, extended 2026-08-05 with Return to Title).
#
# Fired as real menu picks -- `chosen` is emitted on the live PauseMenu the way a button press
# would, never by setting game_state directly. game._open_pause_menu stashes the pre-pause state in
# a local and each arm has to leave the game in a coherent state on the way out; a test that skips
# the menu cannot see any of that (the REPORT arm shipped a bug of exactly that shape, pinned in
# test_report_flow.gd).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	# game._ready DEFERS open_mission_select, so the scene boots onto the title screen. These tests
	# start mid-mission, so dismiss it once it has landed -- otherwise "did Return to Title open
	# the menu" is answered yes before the menu is ever asked for.
	await await_idle_frame()
	game.mission_controller._close_mission_select()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	if is_instance_valid(game):
		game.process_mode = Node.PROCESS_MODE_INHERIT
	remove_child(_main)
	_main.free()


# ModalLock freezes the game subtree, so a pausable Timer (which is what gdUnit4's await_millis
# builds) is not a safe wait here. process_frame is emitted regardless.
func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _menu() -> Node:
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		if node is PauseMenu:
			return node
	return null


func _title_screen() -> Node:
	for node: Node in game.ui_layer.get_children():
		if node is MissionSelectScreen:
			return node
	return null


func test_return_to_title_lands_on_the_menu_with_the_game_thawed() -> void:
	game.spawn_sandbox()
	await await_idle_frame()
	assert_object(_title_screen()).is_null()

	game._open_pause_menu()
	await _frames(4)
	assert_object(_menu()).is_not_null()

	_menu().chosen.emit(PauseMenu.Choice.TITLE)
	await _frames(6)

	assert_object(_title_screen()).is_not_null()
	assert_int(game.game_state).is_equal(game.GameState.MENU)
	# The freeze must lift with the card even though the state stays locked -- MissionSelectScreen
	# is not a modal, and a game left DISABLED here would never run the mission picked next.
	assert_bool(game.can_process()).is_true()


func test_return_to_title_drops_the_stored_selection() -> void:
	# abandon_mission tidies the HUD rather than clearing the board (the next load_scenario does
	# that). What must not survive is a reference INTO the abandoned board: the next load frees
	# those Unit nodes, and game.selected_unit is stored rather than re-derived (#107).
	# clear_selection() only clears the overlays -- exit_current_mode is what nulls the reference,
	# so this fails if abandon_mission reaches for the obvious-looking one.
	game.spawn_sandbox()
	await await_idle_frame()
	var unit: Unit = game._all_units()[0]
	game._on_left_click(unit.movement.cell)
	await await_idle_frame()
	assert_object(game.selected_unit).is_not_null()

	game._open_pause_menu()
	await _frames(4)
	_menu().chosen.emit(PauseMenu.Choice.TITLE)
	await _frames(6)

	assert_object(game.selected_unit).is_null()


func test_resume_returns_to_the_state_escape_interrupted() -> void:
	game.game_state = game.GameState.IDLE
	game._open_pause_menu()
	await _frames(4)
	_menu().chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)

	assert_int(game.game_state).is_equal(game.GameState.IDLE)
	assert_bool(game._board_locked_for_player()).is_false()
	assert_bool(game.can_process()).is_true()


func test_restart_is_offered_only_when_there_is_a_file_to_reload() -> void:
	# A Sandbox board was never loaded from disk, so Restart would have nothing to reload. Return
	# to Title is the row that is offered unconditionally.
	game.spawn_sandbox()
	await await_idle_frame()
	assert_bool(game.mission_controller.can_restart()).is_false()

	game._open_pause_menu()
	await _frames(4)
	var labels: Array[String] = []
	for node: Node in _menu().find_children("*", "Button", true, false):
		labels.append((node as Button).text)

	assert_array(labels).contains(["Resume", "Return to Title", "Quit Game"])
	assert_bool(labels.has("Restart Mission")).is_false()

	_menu().chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)
