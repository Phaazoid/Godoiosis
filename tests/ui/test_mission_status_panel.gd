# The mission-status HUD (#134), read at the RENDERED labels rather than the controller behind
# them (the #166 catalogue-rows doctrine: assert on what the player sees). The wire cases drive
# the real refresh path — MissionController's write points calling game.refresh_mission_status()
# — so a dropped refresh call goes red here, not just a wrong count.
#
# Fixture is test_mission_controller's: a real game scene (root MUST be named "Main" under /root),
# boards built cell by cell so each case states its own situation.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

var _main: Node
var game: Node2D
var mc: MissionController
var panel: MissionStatusPanel


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	mc = game.mission_controller
	panel = game.mission_status_panel
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


func _paint(zone_name: String, kind: ZoneManager.Kind, cells: Array) -> void:
	for cell: Vector2i in cells:
		game.zone_manager.paint_cell(zone_name, kind, cell)


func _objectives(list: Array) -> void:
	var typed: Array[MissionRules.Objective] = []
	typed.assign(list)
	mc.set_objectives(typed)


func _row_texts() -> Array[String]:
	var texts: Array[String] = []
	for child in panel._rows.get_children():
		var label: Label = child as Label
		texts.append(label.text)
	return texts


# ==============================================================================
#  Visibility
# ==============================================================================

func test_a_board_with_no_objectives_hides_the_panel() -> void:
	# The sandbox rule: no declared objectives, nothing to say. clear_board ran in before_test.
	assert_bool(panel._panel.visible).is_false()


func test_clearing_the_board_hides_a_showing_panel() -> void:
	_paint("Point", ZoneManager.Kind.CAPTURE, [Vector2i(2, 2)])
	_objectives([MissionRules.Objective.CAPTURE])
	assert_bool(panel._panel.visible).is_true()

	game.scenario_manager.clear_board()   # routes through mission_controller.reset()
	assert_bool(panel._panel.visible).is_false()


# ==============================================================================
#  The rows
# ==============================================================================

func test_declared_objectives_render_one_row_each_with_their_counts() -> void:
	_paint("North", ZoneManager.Kind.CAPTURE, [Vector2i(2, 2)])
	_paint("South", ZoneManager.Kind.CAPTURE, [Vector2i(6, 6)])
	_paint("Exit", ZoneManager.Kind.EXTRACTION, [Vector2i(1, 1), Vector2i(1, 2)])
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))   # inside the exit
	_spawn(Team.Faction.PLAYER, Vector2i(5, 5))   # still outside
	_spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	_spawn(Team.Faction.ENEMY, Vector2i(7, 7))
	_objectives([MissionRules.Objective.ROUT, MissionRules.Objective.CAPTURE, MissionRules.Objective.EXTRACT])

	assert_bool(panel._panel.visible).is_true()
	var rows := _row_texts()
	assert_int(rows.size()).override_failure_message("Expected header + 3 rows, got %s" % [rows]).is_equal(4)
	assert_str(rows[0]).is_equal("OBJECTIVES")
	assert_str(rows[1]).is_equal("Rout — 2 foes remain")
	assert_str(rows[2]).is_equal("Capture — 0/2 zones")
	assert_str(rows[3]).is_equal("Extract — 1/2 in the zone")


func test_a_declared_but_unpainted_objective_row_says_so() -> void:
	# Never omitted: the map really is unwinnable (canon). Direct assign, as the controller suite
	# does for this case — set_objectives would push_error, and the dev checkbox writes this way.
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	mc.objectives.assign([MissionRules.Objective.CAPTURE] as Array[MissionRules.Objective])
	game.refresh_mission_status()

	assert_array(_row_texts()).contains(["Capture — no zone painted"])


# ==============================================================================
#  The wires — a state change reaches the labels with no extra call
# ==============================================================================

func test_capturing_a_zone_updates_the_row_through_the_real_wire() -> void:
	_paint("North", ZoneManager.Kind.CAPTURE, [Vector2i(2, 2)])
	_paint("South", ZoneManager.Kind.CAPTURE, [Vector2i(6, 6)])
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(4, 4))   # rout stays pending, so no banner interferes
	_objectives([MissionRules.Objective.ROUT, MissionRules.Objective.CAPTURE])

	mc.capture("North")
	assert_array(_row_texts()).contains(["Capture — 1/2 zones"])
	mc.capture("South")
	assert_array(_row_texts()).contains(["✓ Capture"])


func test_loading_a_board_reads_extraction_off_the_finished_board() -> void:
	# The reported bug (2026-08-12): apply_scenario's set_objectives refreshes the HUD mid-load,
	# BEFORE units spawn, so extraction read 0/0 off the empty board as everyone-extracted and
	# "✓ Extract" stuck until the first turn event. Drives the REAL load path -- capture a board,
	# apply it, read the rendered labels; a load must end with the HUD reading the finished board.
	_paint("Exit", ZoneManager.Kind.EXTRACTION, [Vector2i(1, 1)])
	_spawn(Team.Faction.PLAYER, Vector2i(5, 5))   # outside the zone
	_spawn(Team.Faction.ENEMY, Vector2i(7, 7))
	_objectives([MissionRules.Objective.EXTRACT])
	var snapshot: ScenarioData = game.scenario_manager.capture_scenario("load_repro")

	game.scenario_manager.apply_scenario(snapshot)
	await await_idle_frame()   # lets clear_board's queue_free of the pre-capture units process

	assert_array(_row_texts()).contains(["Extract — 0/1 in the zone"])


func test_a_kill_updates_the_rout_count_when_the_board_settles() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var standing := _spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	_spawn(Team.Faction.ENEMY, Vector2i(7, 7))
	_objectives([MissionRules.Objective.ROUT])
	assert_array(_row_texts()).contains(["Rout — 2 foes remain"])

	standing.die()
	mc.check()   # the settle point every kill funnels to
	assert_array(_row_texts()).contains(["Rout — 1 foe remains"])


func test_the_final_state_stays_readable_after_the_mission_ends() -> void:
	_paint("Point", ZoneManager.Kind.CAPTURE, [Vector2i(2, 2)])
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	_objectives([MissionRules.Objective.CAPTURE])
	mc.check()            # latches contested while both stand
	mc.capture("Point")   # the objective is met
	mc.check()            # VICTORY — banner up, board locked

	assert_bool(mc.is_over()).is_true()
	assert_bool(panel._panel.visible).is_true()
	assert_array(_row_texts()).contains(["✓ Capture"])


# ==============================================================================
#  The version stamp + layout
# ==============================================================================

func test_the_version_stamp_reads_the_one_build_source() -> void:
	# Interpolated, never a pinned literal — the version string is content and free to move.
	assert_str(panel._version_label.text).is_equal("v" + Build.version())
	assert_bool(panel._version_label.visible).is_true()
	# The store must actually be set: an unset project.godot field reads the "dev" fallback.
	assert_str(Build.version()).is_not_equal("dev")


func test_the_panel_stays_inside_the_viewport() -> void:
	_paint("North", ZoneManager.Kind.CAPTURE, [Vector2i(2, 2)])
	_paint("Exit", ZoneManager.Kind.EXTRACTION, [Vector2i(1, 1)])
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	_objectives([MissionRules.Objective.ROUT, MissionRules.Objective.CAPTURE, MissionRules.Objective.EXTRACT])
	await await_idle_frame()

	var viewport_rect := Rect2(Vector2.ZERO, game.get_viewport().get_visible_rect().size)
	var panel_rect: Rect2 = panel._panel.get_global_rect()
	assert_bool(viewport_rect.encloses(panel_rect)) \
		.override_failure_message("Objective panel runs off the viewport: %s vs %s" % [panel_rect, viewport_rect]) \
		.is_true()
	var version_rect: Rect2 = panel._version_label.get_global_rect()
	assert_bool(viewport_rect.encloses(version_rect)) \
		.override_failure_message("Version stamp runs off the viewport: %s vs %s" % [version_rect, viewport_rect]) \
		.is_true()


# ==============================================================================
#  The instruction row (#182): the tutorial's "do this now", riding the same panel
# ==============================================================================

func _steps(list: Array[TutorialStep]) -> void:
	game.scenario_director.set_steps(list)
	game.scenario_director.mission_started()   # content is inert until armed (the solo-squad spawn guard)


func _step(done_when: DialogBeat.Trigger, text: String, unit_name := "", squad_size := 0) -> TutorialStep:
	var step := TutorialStep.new()
	step.done_when = done_when
	step.text = text
	step.unit_name = unit_name
	step.squad_size = squad_size
	return step


func test_an_instruction_shows_without_objectives_and_without_their_header() -> void:
	_steps([_step(DialogBeat.Trigger.SQUAD_FORMED, "Form a squad.")])
	assert_bool(panel._panel.visible).is_true()
	assert_array(_row_texts()).contains_exactly(["> Form a squad."])


func test_clearing_the_board_hides_an_instruction_only_panel() -> void:
	# The reset-order trap: mc.reset() re-renders the panel mid-teardown, so the director must
	# already be reset or the dying board keeps its instruction row.
	_steps([_step(DialogBeat.Trigger.SQUAD_FORMED, "Form a squad.")])
	game.scenario_manager.clear_board()
	assert_bool(panel._panel.visible).is_false()


func test_clicking_the_named_unit_advances_the_row_through_the_real_click_path() -> void:
	var torv_data := H.make_unit_data({}, Team.Faction.PLAYER)
	torv_data.display_name = "Torv"
	var torv: Unit = game.spawn_unit(torv_data, Vector2i(3, 3))
	assert_object(torv).is_not_null()
	_steps([
		_step(DialogBeat.Trigger.UNIT_SELECTED, "Select Torv.", "Torv"),
		_step(DialogBeat.Trigger.SQUAD_FORMED, "Squad up."),
	])
	assert_array(_row_texts()).contains_exactly(["> Select Torv."])
	game._click_idle(Vector2i(3, 3))   # the one select write point -- the emitter itself is under test
	assert_array(_row_texts()).contains_exactly(["> Squad up."])


func test_joining_through_the_real_door_advances_at_the_authored_size() -> void:
	var torv: Unit = _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var second: Unit = _spawn(Team.Faction.PLAYER, Vector2i(5, 5))
	var third: Unit = _spawn(Team.Faction.PLAYER, Vector2i(4, 4))
	var squad: Squad = torv.squad   # spawn_unit already wrapped torv in a solo squad (invariant I7)
	_steps([_step(DialogBeat.Trigger.SQUAD_MEMBER_ADDED, "Bring everyone.", "", 3)])
	game.squad_manager.join_squad(second, squad)   # 2 of 3: not yet
	assert_array(_row_texts()).contains_exactly(["> Bring everyone."])
	game.squad_manager.join_squad(third, squad)    # 3 of 3: the emitter fires and the lesson ends
	assert_bool(panel._panel.visible).is_false()
