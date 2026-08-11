# The pause card's own choices (#132, extended 2026-08-05 with Return to Title).
#
# Fired as real menu picks -- `chosen` is emitted on the live PauseMenu the way a button press
# would, never by setting game_state directly. game._open_pause_menu stashes the pre-pause state in
# a local and each arm has to leave the game in a coherent state on the way out; a test that skips
# the menu cannot see any of that (the REPORT arm shipped a bug of exactly that shape, pinned in
# test_report_flow.gd).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

var _main: Node
var game: Node2D


func before_test() -> void:
	# Redirected for EVERY case (#144 discipline, see test_save_slots.gd): the suite shares the
	# real user:// with the dev's own play saves. Before Main instantiates -- the boot title
	# screen reads any_save_exists().
	ScenarioManager.save_dir = TEST_SAVE_DIR
	_wipe_test_saves()
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
	_wipe_test_saves()
	ScenarioManager.save_dir = ScenarioManager.DEFAULT_SAVE_DIR
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


# ==============================================================================
#  Save and Load (#144). Redirected save_dir, same discipline as test_save_slots.gd:
#  these cases must never read or write the dev's real slots.
# ==============================================================================

const TEST_SAVE_DIR := "user://__test_saves_144_pause/"
const FAKE_MISSION := "res://Scenarios/missions/__pause_fixture.tres"   # a path, never a file


static func _wipe_test_saves() -> void:
	if not DirAccess.dir_exists_absolute(TEST_SAVE_DIR):
		return
	for file in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute(TEST_SAVE_DIR.path_join(file))
	DirAccess.remove_absolute(TEST_SAVE_DIR)


func _button_with_prefix(host: Node, prefix: String) -> Button:
	for node: Node in host.find_children("*", "Button", true, false):
		if (node as Button).text.begins_with(prefix):
			return node
	return null


func _save_load_screen() -> Node:
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		if node is SaveLoadScreen:
			return node
	return null


func test_save_rides_the_restart_gate_and_load_greys_with_a_reason() -> void:
	# Sandbox, no saves: Save hidden (no origin mission), Load present but greyed with a reason.
	game.spawn_sandbox()
	await await_idle_frame()
	game._open_pause_menu()
	await _frames(4)

	assert_object(_button_with_prefix(_menu(), "Save Game")).is_null()
	var load_row: Button = _button_with_prefix(_menu(), "Load Game")
	assert_object(load_row).is_not_null()
	assert_bool(load_row.disabled).is_true()
	assert_bool(load_row.tooltip_text.is_empty()).is_false()
	_menu().chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)

	# A mission loaded: Save appears, on the same gate as Restart.
	game.scenario_manager.last_loaded_path = FAKE_MISSION
	game._open_pause_menu()
	await _frames(4)
	assert_object(_button_with_prefix(_menu(), "Save Game")).is_not_null()
	_menu().chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)


func test_the_save_arm_restores_state_before_reopening() -> void:
	# The pinned re-entrancy trap (the REPORT arm shipped it): the arm must restore `prior`
	# BEFORE reopening, or the second menu stashes MENU and Resume locks the board for good.
	game.scenario_manager.last_loaded_path = FAKE_MISSION
	game.game_state = game.GameState.IDLE

	game._open_pause_menu()
	await _frames(4)
	_menu().chosen.emit(PauseMenu.Choice.SAVE_GAME)
	await _frames(4)

	var screen: Node = _save_load_screen()
	assert_object(screen).is_not_null()
	_button_with_prefix(screen, "Back").pressed.emit()
	await _frames(4)

	assert_object(_menu()).is_not_null()   # back on the pause menu, not the board
	_menu().chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)

	assert_int(game.game_state).is_equal(game.GameState.IDLE)
	assert_bool(game.can_process()).is_true()


func test_a_pause_load_lands_idle_without_reopening_the_menu() -> void:
	# Loading replaces the board, so the menu must NOT reopen over it (the falsified half), and
	# the end state must be playable IDLE. NB the arm's own IDLE-vs-prior choice is NOT visible
	# here: resume_from_slot -> clear_board -> exit_current_mode re-derives the state
	# synchronously either way, so that line is RESTART symmetry, not a pinnable behavior.
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 1))
	assert_object(unit).is_not_null()
	game.scenario_manager.last_loaded_path = FAKE_MISSION
	assert_bool(game.scenario_manager.save_to_slot(1)).is_true()

	# A prior DISTINGUISHABLE from IDLE, or "landed on IDLE, not prior" is asserted vacuously.
	game.game_state = game.GameState.TILE_SELECTED
	game._open_pause_menu()
	await _frames(4)
	_menu().chosen.emit(PauseMenu.Choice.LOAD_GAME)
	await _frames(4)

	_button_with_prefix(_save_load_screen(), "Slot 1").pressed.emit()
	await _frames(4)
	# The lost-progress confirm (pause-menu loads only): Yes.
	var confirm: Node = null
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		if node is ConfirmCard:
			confirm = node
	assert_object(confirm).is_not_null()
	_button_with_prefix(confirm, "Yes").pressed.emit()
	await _frames(6)

	assert_object(_menu()).is_null()
	assert_int(game.game_state).is_equal(game.GameState.IDLE)
	assert_int((game._all_units() as Array).size()).is_equal(1)
	assert_bool(game.can_process()).is_true()


func test_a_cancelled_load_returns_to_the_pause_menu() -> void:
	game.game_state = game.GameState.IDLE
	game._open_pause_menu()
	await _frames(4)
	_menu().chosen.emit(PauseMenu.Choice.LOAD_GAME)
	await _frames(4)

	_button_with_prefix(_save_load_screen(), "Back").pressed.emit()
	await _frames(4)

	assert_object(_menu()).is_not_null()
	_menu().chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)
	assert_int(game.game_state).is_equal(game.GameState.IDLE)
