# The game scene with NO dev overlay -- the state a demo build ships in (#132).
#
# This fixture deliberately breaks the ritual test_game_scene_smoke.gd performs: it does NOT
# name the root "Main" and does NOT parent it under /root, so game.gd's absolute
# get_node_or_null("/root/Main/DevOverlay") returns null. Before #132 that killed
# ScenarioManager.clear_board() on `game.dev_overlay.unit_editor` -- the misdiagnosis #114
# untangled, which had read as "the game scene segfaults in the runner" for thirteen months.
#
# Falsify by reverting any one guard: clear_board() dies with "Invalid access on a base object
# of type Nil".
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "NotMain"   # the point of the fixture -- see the header
	add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	# See test_game_scene_smoke.gd's after_test: clear_board() leaves units parentless for one
	# frame by design, and gdUnit4 samples orphans after this hook. A real leak still reports.
	await await_idle_frame()
	remove_child(_main)
	_main.free()


func test_the_overlay_is_genuinely_absent() -> void:
	# Guards the fixture: if this fails the suite proves nothing, because the overlay resolved.
	assert_object(game.dev_overlay).is_null()


func test_clear_board_survives_a_missing_overlay() -> void:
	# The regression, and every mission load routes through it. Populate FIRST: asserting 0 on an
	# already-empty board passes whether or not clear_board ran at all, which is how a dropped
	# unit-removal loop hid behind a 955-case green run.
	game.spawn_sandbox()
	await await_idle_frame()
	assert_int(game.units_root.get_child_count()).is_greater(0)
	game.scenario_manager.clear_board()
	assert_int(game.units_root.get_child_count()).is_equal(0)


func test_set_dev_mode_does_not_crash_without_an_overlay() -> void:
	game.set_dev_mode(true)
	assert_int(game.game_state).is_equal(game.GameState.DEV_MODE)
	game.set_dev_mode(false)


func test_dev_mode_click_is_inert_without_an_overlay() -> void:
	# _click_dev_mode reaches for dev_overlay.unit_editor on any unit it finds.
	game.spawn_sandbox()
	await await_idle_frame()
	game.set_dev_mode(true)
	var unit: Unit = null
	for u: Unit in game._all_units():
		unit = u
		break
	assert_object(unit).is_not_null()
	game._on_left_click(unit.movement.cell)
