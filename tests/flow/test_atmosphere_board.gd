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


# --- the weather's nudge (#1324) ----------------------------------------------------------
# Which weather moves the air is authored, so the sky under test is whichever one the files say moves
# something, and every expectation is Atmosphere.effective's.

func _moving_weather() -> Weather.Kind:
	for kind: Weather.Kind in Weather.Kind.values():
		if not WeatherRules.air_of(kind).is_empty():
			return kind
	fail("fixture: no weather's rules move the air")
	return Weather.Kind.CLEAR


func test_the_board_every_resolve_reads_carries_the_weathers_nudge() -> void:
	var sky := _moving_weather()
	var reading := _reading()
	game.scenario_manager.current_atmosphere = reading.duplicate()
	game.scenario_manager.current_weather = sky
	var expected := Atmosphere.effective(reading, sky)
	assert_dict(expected).override_failure_message("fixture: %s moves nothing in this reading"
			% Weather.name_of(sky)).is_not_equal(reading)
	var board: BoardContext = game.squad_manager.board_source.call()
	for id: String in Atmosphere.SUBSTANCES:
		assert_int(Atmosphere.percent_of(id, board.atmosphere)).override_failure_message(
				"the board every resolve reads has %s at %d, not the weather's %d"
				% [id, Atmosphere.percent_of(id, board.atmosphere), Atmosphere.percent_of(id, expected)]) \
			.is_equal(Atmosphere.percent_of(id, expected))
	assert_dict(game.scenario_manager.air_reading()).is_equal(expected)


# A save writes what the board AUTHORS: baking the weather in would add the nudge again on every load.
func test_a_save_keeps_the_authored_air_and_not_the_weathers() -> void:
	var sky := _moving_weather()
	var reading := _reading()
	game.scenario_manager.current_atmosphere = reading.duplicate()
	game.scenario_manager.current_weather = sky
	var saved: ScenarioData = game.scenario_manager.capture_scenario("air")
	assert_dict(saved.atmosphere).override_failure_message(
			"the save wrote the air as played, so a reload nudges it twice").is_equal(reading)
	game.scenario_manager.apply_scenario(saved)
	await await_idle_frame()
	assert_dict(game.scenario_manager.air_reading()).is_equal(Atmosphere.effective(reading, sky))


# The bug report's sky line reads the air as played, naming the weather beside what it moved.
func test_the_bug_report_reads_the_air_as_played() -> void:
	var sky := _moving_weather()
	game.scenario_manager.current_weather = sky
	var air: Dictionary[String, int] = game.scenario_manager.air_reading()
	var note: String = game.bug_reporter._weather_note()
	var named := 0
	for id: String in Atmosphere.off_normal(air):
		if not Atmosphere.weather_moves(id, sky):
			continue
		named += 1
		assert_str(note).contains("%s %s (%s)" % [SubstanceCatalog.name_of(id),
				Atmosphere.percent_text(id, air), Weather.display_name(sky)])
	assert_int(named).override_failure_message(
			"fixture: %s moves nothing off Normal on a Normal board" % Weather.name_of(sky)).is_greater(0)
