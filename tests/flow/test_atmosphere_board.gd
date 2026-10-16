# The air's reading travels with the board (#1324): a save writes it, a load restores it into the store
# game._board() reads, the squad manager's board source hands it to every resolve, and a cleared board
# (the sandbox's door) drops it. The weather's shape exactly (test_rain_soaks.gd), and needs the real
# game scene for the same reason: the wire is game._board(), which a hand-built BoardContext skips.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

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


# A reading off Normal in every substance, derived from the constants so a retune never reds it.
func _reading() -> Dictionary[String, int]:
	var reading: Dictionary[String, int] = {}
	for id: String in Atmosphere.SUBSTANCES:
		reading[id] = int(Atmosphere.NORMAL[id]) + int(Atmosphere.STEP[id])
	return reading


func test_the_air_saves_loads_and_clears_with_the_board() -> void:
	var reading := _reading()
	game.scenario_manager.current_atmosphere = reading.duplicate()
	var saved: ScenarioData = game.scenario_manager.capture_scenario("air")
	for id: String in reading:
		assert_int(int(saved.atmosphere.get(id, -1))).override_failure_message(
				"a save dropped the air's %s" % id).is_equal(reading[id])

	game.scenario_manager.clear_board()
	assert_bool(Atmosphere.is_normal(game.scenario_manager.current_atmosphere)).override_failure_message(
			"a cleared board kept the last board's air").is_true()

	game.scenario_manager.apply_scenario(saved)
	await await_idle_frame()
	var board: BoardContext = game.squad_manager.board_source.call()
	for id: String in reading:
		assert_int(Atmosphere.percent_of(id, board.atmosphere)).override_failure_message(
				"the board every resolve reads does not see the loaded air's %s" % id).is_equal(reading[id])


# Editing the live air must not write into the scenario it was loaded from: that resource is the
# cache's, and a second load of the same file would come back already edited.
func test_editing_the_live_air_leaves_the_loaded_scenario_alone() -> void:
	var reading := _reading()
	game.scenario_manager.current_atmosphere = reading.duplicate()
	var saved: ScenarioData = game.scenario_manager.capture_scenario("air")
	game.scenario_manager.apply_scenario(saved)
	await await_idle_frame()
	game.scenario_manager.current_atmosphere.clear()
	assert_int(saved.atmosphere.size()).override_failure_message(
			"clearing the live air emptied the scenario it came from").is_equal(reading.size())


# The pass that settles on its own deposits (#367) asks a COPY of the board, which must keep the air.
func test_a_board_with_deposits_keeps_the_air() -> void:
	game.scenario_manager.current_atmosphere = _reading()
	var board: BoardContext = game._board()
	var none: Array[ResolvedCellEffect] = []
	assert_int(board.with_deposits(none).atmosphere.size()).is_equal(Atmosphere.SUBSTANCES.size())
