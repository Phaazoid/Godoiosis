# A unit standing in open water when a battle begins is Wet (#1653). Every other soak is an ENTRY (a
# wade's step, a shove's landing, a sink), so a unit the board placed in shallows stood there for
# rounds, dry. Dev ruling 2026-11-11: it is Wet at the mission's start, not at its first end of turn.
#
# Each case drives a real fresh-start door (begin_mission, restart_mission, commit_deployment) and asks
# the board; the expectation is RulesService.wets_in's, never restated. A resume is the control: a load
# restores what it saved and must not re-wet a unit that was dry.
#
# The scratch mission is authored in memory and saved to user://, never into Scenarios/
# (test_pre_mission_restart.gd's setup, for its reasons).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH := "user://__battle_begins_wet_1653.tres"
const TEST_SAVE_DIR := "user://__test_saves_1653/"
const SLOT := 0

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const SHALLOW_WATER := Vector2i(6, 6)   # TestTiles' wadeable water (#116)
const ROW_WIDTH := 10
const WET_CELL := Vector2i(1, 0)
const DRY_CELL := Vector2i(3, 0)
const FOE_CELL := Vector2i(8, 0)

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


# A grass row with one shallow cell, `roster` drawn into a deployment zone over the row's left half when
# one is named, or else a player standing in the water and one on grass. An enemy far off keeps the
# mission from ending on load.
func _author(roster := "") -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	game.grid.paint(WET_CELL, GRASS_SOURCE, SHALLOW_WATER)
	game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), FOE_CELL)
	if roster == "":
		game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), WET_CELL)
		game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), DRY_CELL)
	else:
		for x in range(DRY_CELL.x + 1):
			game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
		sm.current_roster = roster
		sm.current_deployment_cap = 1
	var scenario := sm.capture_scenario("battle_begins_wet_1653", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	sm.clear_board()
	return SCRATCH


func _unit_at(cell: Vector2i) -> Unit:
	for unit: Unit in game.units_root.get_children():
		if unit.movement.cell == cell:
			return unit
	return null


func _is_wet(unit: Unit) -> bool:
	return unit.element_states.has(Elemental.State.WET)


func _soaks_at(unit: Unit) -> bool:
	return RulesService.wets_in(unit.movement.cell, unit.state, game._board())


# Every unit on the board holds Wet exactly when its cell soaks it, and the water case is not vacuous.
func _assert_soaked_as_the_ground_says(door: String) -> void:
	var stander := _unit_at(WET_CELL)
	assert_object(stander).override_failure_message("fixture: nobody stands in the water").is_not_null()
	assert_bool(_soaks_at(stander)).override_failure_message(
			"fixture: the shallow cell does not soak (wets_in) -- the case is vacuous").is_true()
	for unit: Unit in game.units_root.get_children():
		assert_bool(_is_wet(unit)).override_failure_message(
				"after %s, %s at %s: Wet is %s, but its ground says %s" % [door, unit.get_unit_name(),
				unit.movement.cell, _is_wet(unit), _soaks_at(unit)]).is_equal(_soaks_at(unit))


func test_a_unit_placed_in_water_starts_the_mission_wet() -> void:
	mc.begin_mission(_author(), false)
	await await_idle_frame()
	_assert_soaked_as_the_ground_says("begin_mission")


func test_a_restart_soaks_the_stander_again() -> void:
	mc.begin_mission(_author(), false)
	await await_idle_frame()
	_unit_at(WET_CELL).remove_element_state(Elemental.State.WET)
	mc.restart_mission()
	await await_idle_frame()
	_assert_soaked_as_the_ground_says("restart_mission")


# The control: a load restores. A unit dried while standing in the water is saved dry and resumes dry.
func test_a_resume_restores_a_dry_stander_dry() -> void:
	mc.begin_mission(_author(), false)
	await await_idle_frame()
	var stander := _unit_at(WET_CELL)
	stander.remove_element_state(Elemental.State.WET)
	assert_bool(sm.save_to_slot(SLOT)).override_failure_message("fixture: the save was refused").is_true()
	mc.resume_from_slot(SLOT)
	await await_idle_frame()
	stander = _unit_at(WET_CELL)
	assert_object(stander).override_failure_message("the resume lost the stander").is_not_null()
	assert_bool(_soaks_at(stander)).override_failure_message("fixture: the water does not soak").is_true()
	assert_bool(_is_wet(stander)).override_failure_message(
			"a resume re-wet a unit saved dry -- a load must restore, never start the battle again").is_false()


# Placed into the water during the pre-mission phase: dry while deploying, Wet once Begin is pressed.
func test_a_unit_deployed_into_water_is_wet_once_the_battle_begins() -> void:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the phase cannot be exercised")
		return
	mc.begin_mission(_author(names[0]))
	await await_idle_frame()
	if not mc.is_deploying():
		push_warning("the roster board did not open its phase; nothing to commit")
		return
	var placed: Unit = null
	for unit: Unit in mc.roster_units():
		if game.is_deployed(unit):
			placed = unit
	assert_object(placed).override_failure_message("fixture: the draw placed nobody").is_not_null()
	if placed.movement.cell != WET_CELL:
		assert_bool(mc.reposition(placed, WET_CELL)).override_failure_message(
				"fixture: the phase refused the shallow cell").is_true()
	assert_bool(_is_wet(placed)).override_failure_message(
			"Wet while still deploying -- the soak belongs to the battle's start").is_false()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()
	_assert_soaked_as_the_ground_says("commit_deployment")
