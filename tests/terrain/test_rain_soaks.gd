# Rain soaks (#1260): under a weather whose rules name a state, a unit gains it when ITS faction's turn
# ends -- steam's soak (#508 PR 3), from the sky instead of a cell, riding the same phase, the same
# list and the same one composition (TileHitAction.soaks).
#
# The content razor applies: which weathers soak, and with what, is AUTHORED (Resources/WeatherRules/),
# so the weather under test is whichever one the files say soaks, and every expectation reads the
# state off WeatherRules.for_kind rather than naming WET or RAIN.
#
# Needs the real game scene: the pass is OrderExecutor.apply_end_of_turn_tiles, the forecast is the
# squad manager's resolve through game._board(), and the weather reaches both from
# ScenarioManager.current_weather.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const CELL := Vector2i(1, 0)

var _main: Node
var game: Node2D
var sky: Weather.Kind
var rules: WeatherRules


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()
	sky = Weather.Kind.CLEAR
	for kind: Weather.Kind in Weather.Kind.values():
		var authored := WeatherRules.for_kind(kind)
		if authored != null and authored.state != Elemental.State.NONE:
			sky = kind
			rules = authored
			break
	assert_int(sky).override_failure_message(
			"fixture: no weather's rules name a state, so nothing here can soak").is_not_equal(Weather.Kind.CLEAR)


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(cell: Vector2i, faction: Team.Faction) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


func _weather_rows(hits: Array[TileHitAction]) -> Array[TileHitAction]:
	var rows: Array[TileHitAction] = []
	for hit in hits:
		if hit.weather >= 0:
			rows.append(hit)
	return rows


func _plan_for(unit: Unit) -> ResolvedPlan:
	return game.squad_manager.resolve_plan(unit.squad, game._board())


# ==============================================================================
#  What the pass does
# ==============================================================================

func test_the_weather_soaks_the_faction_whose_turn_ends_and_nobody_else() -> void:
	var mine := _spawn(CELL, Team.Faction.PLAYER)
	var theirs := _spawn(CELL + Vector2i(3, 0), Team.Faction.ENEMY)
	game.scenario_manager.current_weather = sky

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_bool(mine.element_states.has(rules.state)).override_failure_message(
			"a unit out in %s ended its turn without the state" % Weather.display_name(sky)).is_true()
	assert_bool(theirs.element_states.has(rules.state)).override_failure_message(
			"the player's turn end soaked an enemy unit too").is_false()


func test_clear_skies_soak_nobody() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	game.scenario_manager.current_weather = Weather.Kind.CLEAR

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_bool(unit.element_states.has(rules.state)).override_failure_message(
			"a clear board soaked a unit").is_false()


# Law #2: the queue's END OF TURN row is what the pass lands, built by the one composition.
func test_the_forecast_names_the_soak_the_pass_lands() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	game.scenario_manager.current_weather = sky

	var forecast := _weather_rows(_plan_for(unit).tile_hits)
	var live := _weather_rows(TurnBoundary.tile_hits(game._all_units(), game.terrain_states,
			game.gas_field, game.scenario_manager.current_weather, Team.Faction.PLAYER))

	assert_int(forecast.size()).override_failure_message(
			"the queue forecast no soak for a unit out in the weather").is_equal(1)
	assert_int(live.size()).override_failure_message(
			"the end-of-turn pass would land a different number of soaks than the queue forecast").is_equal(forecast.size())
	if forecast.is_empty() or live.is_empty():
		return
	assert_array(forecast[0].resolved.states_added).is_equal(live[0].resolved.states_added)
	assert_int(forecast[0].weather).is_equal(sky)
	assert_bool(forecast[0].resolved.reads_hp).override_failure_message(
			"a soak row printed an HP arrow; nobody is hit").is_false()


# A row says what CHANGED: a unit already holding the state grows none, and neither does one holding
# a state that keeps it off (Elemental.OVERRIDES) -- the gate every other door asks.
func test_a_unit_already_holding_the_state_or_its_blocker_grows_no_row() -> void:
	var held := _spawn(CELL, Team.Faction.PLAYER)
	held.add_element_state(rules.state)
	var blocked := _spawn(CELL + Vector2i(3, 0), Team.Faction.PLAYER)
	var blocker := Elemental.State.NONE
	for winner: Elemental.State in Elemental.OVERRIDES:
		if Elemental.OVERRIDES[winner] == rules.state:
			blocker = winner
	if blocker != Elemental.State.NONE:
		blocked.add_element_state(blocker)
	game.scenario_manager.current_weather = sky

	assert_int(_weather_rows(_plan_for(held).tile_hits).size()).override_failure_message(
			"the queue forecast a soak onto a unit that already holds the state").is_equal(0)
	if blocker != Elemental.State.NONE:
		assert_int(_weather_rows(_plan_for(blocked).tile_hits).size()).override_failure_message(
				"the queue forecast a soak a held state keeps off").is_equal(0)


# Steam and rain giving one state: ONE row, the gas's, not two (TileHitAction.soaks threads what the
# gas adds before it asks the sky). Two would show the player the same soak twice and play it twice.
func test_steam_and_rain_that_give_one_state_give_one_row() -> void:
	var steam := GasRules.for_kind(Gas.Kind.STEAM)
	if steam == null or steam.state != rules.state:
		return   # the authored files no longer overlap; nothing to double-count
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	game.gas_field.set_level(CELL, Gas.Kind.STEAM, steam.state_from)
	game.scenario_manager.current_weather = sky

	var rows := _plan_for(unit).tile_hits
	assert_int(rows.size()).override_failure_message(
			"steam in the rain forecast %d soak rows for one state" % rows.size()).is_equal(1)
	if rows.size() == 1:
		assert_int(rows[0].gas).override_failure_message("the steam's row should be the one kept").is_equal(Gas.Kind.STEAM)


# ==============================================================================
#  The board carries it
# ==============================================================================

# The weather is a rule input, so it travels as the board does: a save writes it, a load restores it
# into the store game._board() reads, and a cleared board (the sandbox's door) drops it.
func test_the_weather_saves_loads_and_clears_with_the_board() -> void:
	_spawn(CELL, Team.Faction.PLAYER)
	game.scenario_manager.current_weather = sky
	var saved: ScenarioData = game.scenario_manager.capture_scenario("rain")
	assert_int(saved.weather).override_failure_message("a save dropped the weather").is_equal(sky)

	game.scenario_manager.clear_board()
	assert_int(game.scenario_manager.current_weather).override_failure_message(
			"a cleared board kept the last board's weather").is_equal(Weather.Kind.CLEAR)

	game.scenario_manager.apply_scenario(saved)
	await await_idle_frame()
	assert_int(game.scenario_manager.current_weather).override_failure_message(
			"a load dropped the weather").is_equal(sky)
	var board: BoardContext = game._board()
	assert_int(board.weather).override_failure_message(
			"the rules' board does not see the loaded weather").is_equal(sky)


# The forecast that settles a pass on the ground its own attacks changed (#367) asks a COPY of the
# board -- a copy without the weather would settle a rainy pass as a dry one.
func test_a_board_with_deposits_keeps_the_weather() -> void:
	game.scenario_manager.current_weather = sky
	var board: BoardContext = game._board()
	var none: Array[ResolvedCellEffect] = []
	assert_int(board.with_deposits(none).weather).is_equal(sky)
