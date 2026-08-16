# Dev mode survives what used to kill it (2026-08-11): DEV_MODE lived only in game_state, and any
# board reload from the dev window (Load / F2 / Mission Select -> clear_board -> exit_current_mode
# -> clear_selection) reset it to IDLE while the DevModeToggle stayed visibly ON -- every
# DEV_MODE-gated behavior (brush, spawn, click-to-edit, can_control) died until F1 re-toggled.
# The intent now lives in game.dev_mode_enabled (written only by set_dev_mode) and every
# "return to normal" write rests the board on _base_state().
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const PROLOG_PATH := "res://Scenarios/missions/Prolog.tres"

var _main: Node
var game: Node2D

func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()

func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()

func test_a_scenario_load_keeps_dev_mode() -> void:
	# The bug replay: Load runs clear_board -> exit_current_mode -> clear_selection.
	game.set_dev_mode(true)

	game.scenario_manager.load_scenario(PROLOG_PATH)

	assert_int(game.game_state).is_equal(game.GameState.DEV_MODE)

func test_an_f2_reload_keeps_dev_mode() -> void:
	game.scenario_manager.load_scenario(PROLOG_PATH)
	game.set_dev_mode(true)

	game.scenario_manager.reload_current()

	assert_int(game.game_state).is_equal(game.GameState.DEV_MODE)

func test_dev_mode_off_rests_idle() -> void:
	game.set_dev_mode(true)
	game.set_dev_mode(false)

	game.scenario_manager.load_scenario(PROLOG_PATH)

	assert_int(game.game_state).is_equal(game.GameState.IDLE)

func test_the_turn_handoff_returns_to_dev_mode() -> void:
	game.set_dev_mode(true)

	await game.start_faction_turn(Team.Faction.PLAYER)

	assert_int(game.game_state).is_equal(game.GameState.DEV_MODE)

# The dev window's banner FOLLOWS the intent. set_dev_mode pushed straight into the overlay until
# the 3D badge needed the same fact; it emits dev_mode_changed now and both listeners connect, so
# this is a WIRE case -- drop DevOverlay's connect and the toggle silently stops tracking F1 while
# every other case above still passes. The text is asserted only for the WORD, since the switch
# graphic alone is what the dev could not read; nothing here pins wording beyond ON/OFF.
func test_the_dev_window_banner_follows_the_toggle() -> void:
	var overlay: DevOverlay = game.dev_overlay
	assert_object(overlay).is_not_null()

	game.set_dev_mode(true)

	assert_bool(overlay.dev_mode_toggle.button_pressed).is_true()
	assert_str(overlay.dev_mode_toggle.text).contains("ON")

	game.set_dev_mode(false)

	assert_bool(overlay.dev_mode_toggle.button_pressed).is_false()
	assert_str(overlay.dev_mode_toggle.text).contains("OFF")
