# TWO HOSTS, ONE MISSION (#46 slice 2). A saved mission is loaded by two loaders -- the game's
# ScenarioManager and the headless BoardBuilder -- and scored by one MissionState each host owns. Both
# loaders read a scenario's mission through MissionState.apply_scenario and each unit's placement
# through ScenarioUnitEntry.apply_placement; this is the law that keeps them honest: one mission,
# authored through the game's own capture, must come back the same in both, down to the clock, the
# captured zones, who the mission protects and what every squad was told to be.
#
# What it cannot see, by construction: a fault inside one of the two shared doors moves both hosts
# together and they still agree. test_mission_state and the headless scoring suite pin those.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const SCRATCH := "user://__mission_two_hosts.tres"
const TEST_SAVE_DIR := "user://__test_saves_mission_two_hosts/"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const WIDTH := 10
const HEIGHT := 4

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController
var _sess


func before_test() -> void:
	ScenarioManager.save_dir = TEST_SAVE_DIR
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
	ScenarioManager.save_dir = ScenarioManager.DEFAULT_SAVE_DIR
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).override_failure_message("precondition: nothing would spawn at %s" % cell).is_not_null()
	return unit


# A mission with every field the two doors carry set off its default, taken mid-battle, through the
# game's own capture, and saved where both hosts can load it.
func _author() -> String:
	for x in range(WIDTH):
		for y in range(HEIGHT):
			game.grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	game.zone_manager.paint_cell("North", ZoneManager.Kind.CAPTURE, Vector2i(2, 0))
	game.zone_manager.paint_cell("South", ZoneManager.Kind.CAPTURE, Vector2i(2, 3))
	for y in range(HEIGHT):
		game.zone_manager.paint_cell("Post", ZoneManager.Kind.PATROL, Vector2i(WIDTH - 2, y))

	var vip := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	vip.must_survive = true
	_spawn(Team.Faction.PLAYER, Vector2i(0, 2))
	var sentry := _spawn(Team.Faction.ENEMY, Vector2i(WIDTH - 1, 1))
	var lookout := _spawn(Team.Faction.ENEMY, Vector2i(WIDTH - 1, 2))
	game.squad_manager.join_squad(lookout, sentry.squad)
	assert_bool(sentry.is_leader()).override_failure_message("precondition: the sentry does not lead its squad").is_true()
	sentry.squad.squad_name = "Watch"
	sentry.squad.archetype = AIArchetype.Type.SENTRY
	sentry.squad.zone_name = "Post"

	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.CAPTURE]
	var lose: Array[MissionRules.LoseCondition] = [
			MissionRules.LoseCondition.ROUND_LIMIT, MissionRules.LoseCondition.PROTECTED_UNIT_LOST]
	mc.set_objectives(objectives)
	mc.set_lose_conditions(lose, 5)
	var ai: Array[Team.Faction] = [Team.Faction.ENEMY]
	game.ai_controller.set_ai_factions(ai)
	var taken: Array[String] = ["North"]
	mc.mission.restore(taken, true, 2)   # two rounds in, one zone claimed

	assert_int(ResourceSaver.save(sm.capture_scenario("mission_two_hosts"), SCRATCH)).is_equal(OK)
	return SCRATCH


func _open_both() -> void:
	var path := _author()
	sm.load_scenario(path)
	await await_idle_frame()
	var board := BoardBuilder.build(self, "MissionTwoHostsHeadless")
	auto_free(board.root)
	await BoardBuilder.load_scenario(board, path)
	_sess = PlaySession.new(board)


static func _mission_picture(mission: MissionState) -> Array:
	return [mission.objectives, mission.lose_conditions, mission.round_limit, mission.rounds_elapsed,
			mission.contested, mission.captured_zones]


# Per unit, in cell order: what apply_placement writes, read back off the unit and its squad.
static func _placement_picture(units: Array[Unit]) -> Array:
	var by_cell := {}
	for unit: Unit in units:
		var squad: Squad = unit.squad
		by_cell[unit.movement.cell] = [unit.movement.cell, unit.must_survive, unit.is_leader(),
				squad.squad_name, AIArchetype.Type.keys()[squad.archetype], squad.zone_name, squad.home_cell]
	var cells: Array = by_cell.keys()
	cells.sort()
	var rows: Array = []
	for cell in cells:
		rows.append(by_cell[cell])
	return rows


func _game_units() -> Array[Unit]:
	var units: Array[Unit] = []
	for child in game.units_root.get_children():
		if child is Unit:
			units.append(child)
	return units


func _agree(what: String, g: Variant, p: Variant) -> void:
	assert_str(str(p)).override_failure_message(
		"the hosts disagree about %s\n  game:     %s\n  headless: %s" % [what, str(g), str(p)]).is_equal(str(g))


# ==============================================================================

func test_both_hosts_load_the_same_mission() -> void:
	await _open_both()
	var g := _mission_picture(mc.mission)
	assert_int(mc.mission.rounds_elapsed).override_failure_message(
		"precondition: the game did not load the clock back, so agreement would be on defaults").is_equal(2)
	_agree("the mission", g, _mission_picture(_sess.mission))


func test_both_hosts_place_every_unit_the_same() -> void:
	await _open_both()
	var g := _placement_picture(_game_units())
	assert_str(str(g)).override_failure_message(
		"precondition: the game loaded no Sentry, so agreement would be on defaults").contains("SENTRY")
	assert_str(str(g)).override_failure_message(
		"precondition: the game loaded nobody it protects").contains("true")
	_agree("unit placement", g, _placement_picture(_sess.live_units()))
