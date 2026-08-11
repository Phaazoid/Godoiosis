# Player save slots (#144): where they live, what they carry, and the resume wire.
#
# EVERY case runs against a REDIRECTED save_dir and wipes it in teardown -- the suite shares the
# real user:// with the dev's own play saves, and a falsification run against the live dir is how
# tracked files have been destroyed before (the dev-tool overwrite-guard lesson). The redirect
# happens BEFORE Main.tscn instantiates, because the boot title screen reads any_save_exists().
#
# Real game scene (the #114 fixture -- root named "Main"); boards built by spawning, never loaded.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const TEST_SAVE_DIR := "user://__test_saves_144/"
const FAKE_MISSION := "res://Scenarios/missions/__resume_fixture.tres"   # a path, never a file

var _main: Node
var game: Node2D


func before_test() -> void:
	ScenarioManager.save_dir = TEST_SAVE_DIR
	_wipe_test_saves()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	await await_idle_frame()
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	_wipe_test_saves()
	ScenarioManager.save_dir = ScenarioManager.DEFAULT_SAVE_DIR
	get_tree().root.remove_child(_main)
	_main.free()


static func _wipe_test_saves() -> void:
	if not DirAccess.dir_exists_absolute(TEST_SAVE_DIR):
		return
	for file in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute(TEST_SAVE_DIR.path_join(file))
	DirAccess.remove_absolute(TEST_SAVE_DIR)


# A one-unit PLAYER board whose squad has ACTED, standing in for a mission in progress.
func _stand_up_mission_board() -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 1))
	assert_object(unit).is_not_null()
	var manager: SquadManager = game.squad_manager
	manager.set_has_acted(unit.squad, true)
	var tm: TurnManager = game.turn_manager
	tm.set_active_faction(Team.Faction.PLAYER)
	game.scenario_manager.last_loaded_path = FAKE_MISSION
	return unit


func test_slots_live_under_user_never_scenarios() -> void:
	# The test_report_flow pin, copied for saves: anything under Scenarios/ becomes a selectable
	# board via Mission Select's scan and #9's suite, and res:// is read-only once exported.
	assert_bool(ScenarioManager.DEFAULT_SAVE_DIR.begins_with("user://")).is_true()
	assert_bool(ScenarioManager.DEFAULT_SAVE_DIR.contains("Scenarios")).is_false()


func test_save_refuses_without_a_loaded_mission() -> void:
	# The handler is the real gate; the hidden pause-menu row is only its surface.
	var manager: ScenarioManager = game.scenario_manager
	assert_str(manager.last_loaded_path).is_empty()
	assert_bool(manager.save_to_slot(1)).is_false()
	assert_bool(ScenarioManager.slot_exists(1)).is_false()


func test_a_slot_round_trips_the_board_and_its_metadata() -> void:
	var _unit := _stand_up_mission_board()
	var manager: ScenarioManager = game.scenario_manager

	assert_bool(manager.save_to_slot(1)).is_true()
	assert_bool(ScenarioManager.slot_exists(1)).is_true()

	var save: SaveGame = manager.load_slot(1)
	assert_object(save).is_not_null()
	assert_str(save.mission_path).is_equal(FAKE_MISSION)
	assert_bool(save.saved_at > 0).is_true()
	assert_str(save.version).is_equal(Build.version())
	assert_int(save.scenario.unit_entries.size()).is_equal(1)
	# authored=false is load-bearing (#177): a reference entry carries NO state, so a cast unit
	# would resume at full HP with every state gone.
	assert_bool(save.scenario.unit_entries[0].state_saved).is_true()


func test_slot_existence_answers_track_the_disk() -> void:
	assert_bool(ScenarioManager.slot_exists(1)).is_false()
	assert_bool(ScenarioManager.any_save_exists()).is_false()

	var _unit := _stand_up_mission_board()
	assert_bool(game.scenario_manager.save_to_slot(2)).is_true()

	assert_bool(ScenarioManager.slot_exists(2)).is_true()
	assert_bool(ScenarioManager.slot_exists(1)).is_false()
	assert_bool(ScenarioManager.any_save_exists()).is_true()


func test_an_unreadable_slot_reads_as_null_not_a_crash() -> void:
	# Two corruption shapes, both must answer null so the UI can grey the row with a reason
	# (#166), never null-deref mid-build: a wrong resource type, and a SaveGame with no board.
	var wrong := ScenarioData.new()
	assert_bool(DevWidgets.save_over(wrong, ScenarioManager.slot_path(3))).is_true()
	assert_object(game.scenario_manager.load_slot(3)).is_null()

	var boardless := SaveGame.new()
	assert_bool(DevWidgets.save_over(boardless, ScenarioManager.slot_path(2))).is_true()
	assert_object(game.scenario_manager.load_slot(2)).is_null()


func test_a_player_save_snapshots_cast_units() -> void:
	# THE #177 trap: authored=true saves a cast unit as a bare reference with NO state, so a
	# resumed fight would stand Celest up at full HP. save_to_slot must capture with
	# authored=false -- and only a CAST unit can see this, an ad-hoc one snapshots either way.
	var celest: UnitData = load("res://Resources/Units/Celest.tres")
	var unit: Unit = game.spawn_unit(celest, Vector2i(1, 1))
	assert_object(unit).is_not_null()
	game.scenario_manager.last_loaded_path = FAKE_MISSION

	assert_bool(game.scenario_manager.save_to_slot(1)).is_true()

	var save: SaveGame = game.scenario_manager.load_slot(1)
	assert_bool(save.scenario.unit_entries[0].state_saved) \
		.override_failure_message("a cast unit saved as a reference -- the resume would discard its battle state") \
		.is_true()


func test_resume_aims_restart_at_the_origin_mission_not_the_slot() -> void:
	var _unit := _stand_up_mission_board()
	var manager: ScenarioManager = game.scenario_manager
	assert_bool(manager.save_to_slot(1)).is_true()
	manager.clear_board()
	assert_str(manager.last_loaded_path).is_empty()

	var mc: MissionController = game.mission_controller
	mc.resume_from_slot(1)
	await await_idle_frame()

	assert_str(manager.last_loaded_path).is_equal(FAKE_MISSION)
	assert_bool(mc.can_restart()).is_true()


func test_resume_preserves_has_acted_through_the_full_menu_path() -> void:
	# THE #144 wire: capture round-trips has_acted (#87) and _begin_turn no longer resets it
	# (test_turn_handoff_reset.gd pins the mechanism) -- this case drives the two together
	# through resume_from_slot, exactly the path the pause menu and title door use.
	var _unit := _stand_up_mission_board()
	assert_bool(game.scenario_manager.save_to_slot(1)).is_true()
	game.scenario_manager.clear_board()
	await await_idle_frame()

	game.mission_controller.resume_from_slot(1)
	await await_idle_frame()

	var units: Array = game._all_units()
	assert_int(units.size()).is_equal(1)
	var restored: Unit = units[0]
	assert_bool(restored.squad.has_acted) \
		.override_failure_message("resume handed an acted squad its actions back -- the menu path reset has_acted") \
		.is_true()
