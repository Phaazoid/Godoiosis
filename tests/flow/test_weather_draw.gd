# The weather draw's WIRES (#1509), driven through the game's real doors: the two fresh starts draw,
# every restore replays the result, and nothing writes the draw back into the file. The rule itself is
# test_weather_draw_rule.gd's; the headless host's twin is test_play_session.gd's.
#
# Every expectation is the rule's own answer under the seed this suite hands MissionController, so no
# case asserts a frequency, and the set is the suite's own (the content razor). The scratch missions are
# authored in memory and saved to user://, test_pre_mission_restart.gd's setup for its reasons.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const K := Weather.Kind
const SCRATCH := "user://__weather_draw_1509.tres"
const TEST_SAVE_DIR := "user://__test_saves_1509/"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const ROW_WIDTH := 10
const ZONE_CELLS := 5
const CAP := 2
const SEED := 1509
const SEARCH := 200

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController


func before_test() -> void:
	ScenarioManager.save_dir = TEST_SAVE_DIR
	_wipe_saves()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	mc = game.mission_controller
	sm = game.scenario_manager
	mc._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	_wipe_saves()
	ScenarioManager.save_dir = ScenarioManager.DEFAULT_SAVE_DIR
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


static func _wipe_saves() -> void:
	if not DirAccess.dir_exists_absolute(TEST_SAVE_DIR):
		return
	for file in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute(TEST_SAVE_DIR + file)


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# Two weathers, neither of them the clear sky the board stands under, so a draw that never lands reads
# as CLEAR and cannot pass.
static func _two_weathers() -> Dictionary[Weather.Kind, int]:
	var odds: Dictionary[Weather.Kind, int] = {K.RAIN: 1, K.SNOW: 1}
	return odds


# What the rule draws under SEED: the expectation every fresh-start case checks the store against.
static func _drawn_under_seed() -> Weather.Kind:
	return WeatherDraw.draw(_two_weathers(), K.CLEAR, _rng(SEED))


# A roll whose next draw is NOT `weather`, so a door that drew again would show it.
func _a_roll_that_would_not_draw(weather: Weather.Kind) -> RandomNumberGenerator:
	for s in range(SEARCH):
		if WeatherDraw.draw(_two_weathers(), K.CLEAR, _rng(s)) != weather:
			return _rng(s)
	assert_bool(false).override_failure_message(
			"fixture: no seed under %d draws other than %s" % [SEARCH, Weather.name_of(weather)]).is_true()
	return _rng(0)


func _paint_row() -> void:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)


func _save(odds: Dictionary[Weather.Kind, int], standing: Weather.Kind) -> String:
	sm.current_weather = standing
	sm.current_weather_odds = odds
	var scenario := sm.capture_scenario("weather_draw_1509", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


# A battle board: one unit a side and no roster, so a fresh start goes straight to turn one.
func _author_battle(odds: Dictionary[Weather.Kind, int], standing := K.CLEAR) -> String:
	_paint_row()
	game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, Team.Faction.PLAYER), Vector2i(0, 0))
	game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, Team.Faction.ENEMY), Vector2i(ROW_WIDTH - 1, 0))
	return _save(odds, standing)


# The one roster on disk, or "" -- a content precondition, never an assertion (the content razor).
func _a_roster() -> String:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the phase cannot be exercised")
		return ""
	return names[0]


# A board whose whole player force is the roster's, so a fresh start opens the pre-mission phase.
func _author_phase(odds: Dictionary[Weather.Kind, int]) -> String:
	var roster := _a_roster()
	if roster == "":
		return ""
	_paint_row()
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = roster
	sm.current_deployment_cap = CAP
	return _save(odds, K.CLEAR)


# --- the fresh start ---

func test_a_fresh_start_draws_into_the_store_the_battle_reads() -> void:
	var path := _author_battle(_two_weathers())
	mc.weather_rng = _rng(SEED)
	mc.begin_mission(path)
	await await_idle_frame()

	var expected := _drawn_under_seed()
	assert_int(sm.current_weather).override_failure_message(
			"the mission started under %s; the draw says %s" % [Weather.name_of(sm.current_weather),
			Weather.name_of(expected)]).is_equal(expected)
	assert_int(game._board().weather).override_failure_message(
			"the board the resolver reads never saw the draw").is_equal(expected)


# Every board saved before #1509 is a locked one, and must start exactly as it did: under its own
# weather, with the roll never touched.
func test_a_locked_board_starts_under_its_own_weather_and_spends_no_roll() -> void:
	var none: Dictionary[Weather.Kind, int] = {}
	var path := _author_battle(none, K.RAIN)
	var rng := _rng(SEED)
	var state := rng.state
	mc.weather_rng = rng
	mc.begin_mission(path)
	await await_idle_frame()

	assert_int(sm.current_weather).is_equal(K.RAIN)
	assert_int(rng.state).override_failure_message("a locked board spent the roll").is_equal(state)


# THE ORDERING CASE: the draw is shown before the commit, so it has to land before the phase's screen
# reads the weather.
func test_the_pre_mission_screen_shows_the_draw_and_what_it_was_drawn_from() -> void:
	var path := _author_phase(_two_weathers())
	if path == "":
		return
	mc.weather_rng = _rng(SEED)
	mc.begin_mission(path)
	await await_idle_frame()
	assert_bool(mc.is_deploying()).override_failure_message(
			"fixture: the roster board never opened the phase").is_true()

	var screen: PreMissionScreen = mc._premission_screen
	assert_str(screen._weather_value.text).override_failure_message(
			"the pre-mission screen shows a weather other than the one drawn").is_equal(
			Weather.display_name(_drawn_under_seed()))
	assert_str(screen._weather_row.tooltip_text.replace("\n", " ")).override_failure_message(
			"the screen does not say the weather was drawn, or from what").contains(WeatherDraw.odds_text(_two_weathers()))


# --- the restart keeps it (ruling 2) ---

func test_a_restart_from_the_battle_keeps_the_draw() -> void:
	var path := _author_battle(_two_weathers())
	mc.weather_rng = _rng(SEED)
	mc.begin_mission(path)
	await await_idle_frame()
	var drawn := sm.current_weather

	mc.weather_rng = _a_roll_that_would_not_draw(drawn)
	mc.restart_mission()
	await await_idle_frame()

	assert_int(sm.current_weather).override_failure_message(
			"the restart drew the weather again").is_equal(drawn)


func test_reset_loadout_keeps_the_draw() -> void:
	var path := _author_phase(_two_weathers())
	if path == "":
		return
	mc.weather_rng = _rng(SEED)
	mc.begin_mission(path)
	await await_idle_frame()
	var drawn := sm.current_weather

	mc.weather_rng = _a_roll_that_would_not_draw(drawn)
	mc.restart_mission()   # from INSIDE the phase: Reset Loadout
	await await_idle_frame()

	assert_bool(mc.is_deploying()).is_true()
	assert_int(sm.current_weather).override_failure_message(
			"Reset Loadout drew the weather again").is_equal(drawn)
	assert_str(mc._premission_screen._weather_value.text).is_equal(Weather.display_name(drawn))


# ...and the converse: choosing the mission again is a fresh start, which draws.
func test_choosing_the_mission_again_draws_again() -> void:
	var path := _author_battle(_two_weathers())
	mc.weather_rng = _rng(SEED)
	mc.begin_mission(path)
	await await_idle_frame()
	var drawn := sm.current_weather

	var other := _a_roll_that_would_not_draw(drawn)
	var expected := WeatherDraw.draw(_two_weathers(), K.CLEAR, _rng(other.seed))
	mc.weather_rng = other
	mc.begin_mission(path)
	await await_idle_frame()

	assert_int(sm.current_weather).override_failure_message(
			"a fresh start from Mission Select kept the last attempt's weather").is_equal(expected)


# --- restores replay the RESULT ---

func test_a_resumed_save_stands_under_the_weather_it_was_saved_under() -> void:
	var path := _author_battle(_two_weathers())
	mc.weather_rng = _rng(SEED)
	mc.begin_mission(path)
	await await_idle_frame()
	var drawn := sm.current_weather
	assert_bool(sm.save_to_slot(1)).override_failure_message("fixture: the slot was not written").is_true()
	sm.clear_board()
	await await_idle_frame()

	mc.weather_rng = _a_roll_that_would_not_draw(drawn)
	mc.resume_from_slot(1)
	await await_idle_frame()

	assert_int(sm.current_weather).override_failure_message(
			"the resume drew a weather instead of replaying the saved one").is_equal(drawn)
	assert_int(game._board().weather).is_equal(drawn)


# --- nothing writes the draw back ---

# The file and the resource cache keep what the author wrote; an authored save of a drawing board writes
# no weather (so Update cannot bake the last draw in); a full capture -- a slot, a report, a telemetry
# board -- keeps the draw, which is how each of them replays the result.
func test_the_draw_lives_in_the_store_and_only_a_full_capture_keeps_it() -> void:
	var path := _author_battle(_two_weathers())
	mc.weather_rng = _rng(SEED)
	mc.begin_mission(path)
	await await_idle_frame()
	var drawn := sm.current_weather
	assert_int(drawn).override_failure_message("fixture: nothing was drawn").is_not_equal(K.CLEAR)

	var cached: ScenarioData = load(path)
	assert_int(cached.weather).override_failure_message(
			"the draw was written into the loaded resource").is_equal(K.CLEAR)
	assert_dict(cached.weather_odds).is_equal(_two_weathers())

	var authored := sm.capture_scenario("authored", true)
	assert_int(authored.weather).override_failure_message(
			"an authored save baked the draw into the board").is_equal(K.CLEAR)
	assert_dict(authored.weather_odds).is_equal(_two_weathers())
	assert_int(sm.capture_scenario("full", false).weather).override_failure_message(
			"a full capture lost the weather it was played under").is_equal(drawn)


func test_an_authored_save_of_a_locked_board_keeps_its_weather() -> void:
	var none: Dictionary[Weather.Kind, int] = {}
	var path := _author_battle(none, K.RAIN)
	mc.begin_mission(path)
	await await_idle_frame()

	var authored := sm.capture_scenario("authored", true)
	assert_int(authored.weather).is_equal(K.RAIN)
	assert_bool(authored.weather_odds.is_empty()).is_true()


# --- the Properties page (#1509 fork 5) ---

# One spelling per meaning: two weathers are odds, one is a locked board, none is a clear sky.
func test_the_set_editor_writes_odds_for_two_weathers_and_a_lock_for_one() -> void:
	var tool: ScenarioTool = game.dev_overlay.scenario_tool
	assert_int(sm.current_weather).override_failure_message("fixture: a cleared board is not clear").is_equal(K.CLEAR)

	(tool._weather_spins[K.RAIN] as SpinBox).value = 2
	var two: Dictionary[Weather.Kind, int] = {K.CLEAR: 1, K.RAIN: 2}
	assert_dict(sm.current_weather_odds).override_failure_message(
			"giving a locked clear board a second weather did not make it draw").is_equal(two)

	(tool._weather_spins[K.CLEAR] as SpinBox).value = 0
	assert_bool(sm.current_weather_odds.is_empty()).override_failure_message(
			"a set of one weather was kept as odds rather than a lock").is_true()
	assert_int(sm.current_weather).is_equal(K.RAIN)

	(tool._weather_spins[K.RAIN] as SpinBox).value = 0
	assert_bool(sm.current_weather_odds.is_empty()).is_true()
	assert_int(sm.current_weather).override_failure_message(
			"a board with every weather taken out is not a clear sky").is_equal(K.CLEAR)
