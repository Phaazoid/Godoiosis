# THE QUIT RECORD (#53 slice 4b). A run whose process died still has to arrive as a COMPLETE
# record: the summary line is the row that gets indexed, so a ragequit without one uploads as a
# fragment with no outcome, no duration and no metrics.
#
# Persistence is ON, aimed at a scratch folder, because every case here is about what is on DISK
# after a process that is not around any more. An in-memory fixture would be a run this sweep
# could never meet.
#
# THE DEATH IS SIMULATED BY DROPPING THE HANDLE, never by hand-writing a file. Every line is
# store_line + flush()ed as the battle goes, so what a kill leaves behind is exactly the file minus
# the seal's own two lines -- and the cases spell that both ways: one drops the live recorder's
# handle mid-run, one replants a sealed run's own bytes with those two lines removed. The second is
# what makes the equivalence case a comparison of one run against itself rather than against a
# lookalike.
#
# WHAT THIS SUITE CANNOT SEE, said out loud rather than left to be found. The pause menu's Quit arm
# calls get_tree().quit(), which would end the test run, so the seal on THAT door rides the dev's
# play-check. The close-request handler is driven here through Object.notification; what stays
# unmeasured is only the engine's own propagation down into the SubViewport, which is read off
# Window::_propagate_window_notification rather than measured.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const SCRATCH_ROOT := "user://__quit_record_test/"

var _main: Node
var game: Node2D
var mc: MissionController
var mission_log: MissionLog


func before_test() -> void:
	TelemetryStore.reset_for_test()
	TelemetryStore.root = SCRATCH_ROOT
	TelemetryStore.persistence_enabled = true
	_wipe()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	mc = game.mission_controller
	mission_log = game.mission_log
	mc._close_mission_select()
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(4):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	game.scenario_manager.last_loaded_path = "res://tests/telemetry/not_a_real_file.tres"
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	remove_child(_main)
	_main.free()
	_wipe()
	TelemetryStore.reset_for_test()


# ==============================================================================
#  The sweep
# ==============================================================================

func test_a_run_the_process_never_sealed_is_finished_at_the_next_launch() -> void:
	var run_id := await _record_a_mission()
	_die()

	var before := ReplayRun.load_run(run_id)
	assert_str(str(before.headline().get("outcome"))).override_failure_message(
		"fixture: the run was sealed after all -- there is nothing to sweep").is_equal("UNSEALED")

	assert_int(MissionLog.sweep_unsealed()).is_equal(1)

	var after := ReplayRun.load_run(run_id)
	var end := after.first("mission_end")
	assert_bool(end.is_empty()).override_failure_message(
		"the sweep left the run with no ending: %s" % str(after.problems)).is_false()
	assert_str(str(end.get("outcome"))).is_equal("CRASHED")
	assert_bool(bool(end.get("swept", false))).is_true()
	# The flag lived in memory and died with the process. Null, never false.
	assert_bool(end.get("dev_touched") == null).override_failure_message(
		"a swept run cannot know whether a dev tool touched it").is_true()

	var summary: Dictionary = after.first("summary").get("summary", {})
	assert_bool(summary.is_empty()).override_failure_message(
		"the ending is not the row that gets indexed -- the summary is").is_false()
	assert_bool(bool(summary.get("swept", false))).override_failure_message(
		"the summary must carry `swept` too, or a query cannot separate an inferred ending"
		).is_true()
	assert_str(str(summary.get("outcome"))).is_equal("CRASHED")


# THE WIRE FROM THE SWEPT ROW TO THE RUN LIST, and it was missing for the whole of #53's life. The
# case above asserts the sweep WRITES null; this asserts the run list can READ one. Between them
# sat `bool(end.get("dev_touched", false))`, which is a hard script error on a stored null -- so
# clicking a crashed run in the Replay tab froze the game on it (#925). Slice 4 wrote the reader,
# slice 4b wrote the null 65 minutes later, and nothing ever called headline() on a swept run.
#
# THE `has` ASSERTION IS THE LOAD-BEARING ONE: a script error aborts headline() and hands back null,
# and a case that only compared the value would read null out of the failure and call it a pass.
func test_the_run_list_can_headline_a_swept_run() -> void:
	var run_id := await _record_a_mission()
	_die()
	assert_int(MissionLog.sweep_unsealed()).is_equal(1)

	var head: Dictionary = ReplayRun.load_run(run_id).headline()
	assert_bool(head.has("dev_touched")).override_failure_message(
		"headline() did not survive the swept run -- it built no row at all").is_true()
	assert_bool(head.get("dev_touched") == null).override_failure_message(
		"the swept run's 'we do not know' was flattened into 'no dev tool was used'").is_true()
	assert_str(str(head.get("outcome"))).is_equal("CRASHED")


# THE EQUIVALENCE CASE, and it is a comparison of one run against ITSELF: the swept half is the
# sealed half's own bytes with the seal's two lines removed, which is exactly what the process
# would have left had it died there.
#
# It works because this fixture ends on a TURN BOUNDARY. A sealed run's final vitals are read off
# the live board; a swept run's are copied from the last turn_start. They are the same rows only
# while nothing has happened between that snapshot and the seal -- so the equality below is a
# property of the fixture as much as of the sweep, and moving the fixture past end_turn breaks it.
func test_a_swept_summary_matches_the_sealed_one_field_for_field() -> void:
	var sealed_id := await _record_a_mission()
	mission_log.seal(MissionLog.Ending.ABANDONED)
	var lines := _read_lines(sealed_id)
	assert_int(lines.size()).override_failure_message(
		"fixture: too few lines to strip a seal from").is_greater(3)

	var swept_id := _plant_run(lines.slice(0, lines.size() - 2))
	assert_int(MissionLog.sweep_unsealed()).override_failure_message(
		"the sealed run must be left alone and the planted one finished").is_equal(1)

	var expected := _summary_of(sealed_id)
	var actual := _summary_of(swept_id)

	# The three fields that MUST differ, asserted rather than quietly skipped.
	assert_str(str(expected.get("outcome"))).is_equal("ABANDONED")
	assert_str(str(actual.get("outcome"))).is_equal("CRASHED")
	assert_bool(bool(expected.get("swept", true))).is_false()
	assert_bool(bool(actual.get("swept", false))).is_true()
	# The seal reads the clock; the sweep freezes at the last line's t_ms, which is earlier.
	assert_float(float(actual.get("seconds", -1.0))).is_greater_equal(0.0)
	assert_float(float(actual.get("seconds", -1.0))).is_less_equal(float(expected.get("seconds", 0.0)))

	for key: String in ["outcome", "swept", "seconds"]:
		expected.erase(key)
		actual.erase(key)
	assert_dict(actual).override_failure_message(
		"a swept summary must agree with a sealed one about everything it CAN know"
		).is_equal(expected)


func test_a_second_sweep_changes_nothing() -> void:
	var run_id := await _record_a_mission()
	_die()
	assert_int(MissionLog.sweep_unsealed()).is_equal(1)
	var once := FileAccess.get_file_as_string(TelemetryStore.events_path(run_id))
	assert_int(once.length()).override_failure_message("fixture: the swept file is empty").is_greater(0)

	assert_int(MissionLog.sweep_unsealed()).override_failure_message(
		"a run that now has an ending must be left alone").is_equal(0)
	assert_str(FileAccess.get_file_as_string(TelemetryStore.events_path(run_id))
		).override_failure_message("the second sweep rewrote the file").is_equal(once)


# THE SURVIVING LINES COME BACK VERBATIM, AND A MUTANT IS WHAT SAID SO. Dropping them entirely --
# writing a file holding nothing but the synthesized ending and summary -- passed every other case
# in this suite, because the summary is projected from the PARSED events before anything is
# written, so a run whose whole log had been destroyed still carried a correct-looking ending.
#
# A PREFIX compare rather than a line count, because it also pins the other half: JSON has one
# number type, so a parse and a re-encode would turn every `"seq": 0` in the file into `"seq": 0.0`.
func test_the_sweep_hands_back_the_lines_it_read_untouched() -> void:
	var run_id := await _record_a_mission()
	_die()
	var before := FileAccess.get_file_as_string(TelemetryStore.events_path(run_id))
	assert_int(before.length()).override_failure_message("fixture: nothing was recorded").is_greater(0)

	assert_int(MissionLog.sweep_unsealed()).is_equal(1)

	var after := FileAccess.get_file_as_string(TelemetryStore.events_path(run_id))
	assert_bool(after.begins_with(before)).override_failure_message(
		"the sweep rewrote or dropped the run it was finishing -- it may only ADD to what it read"
		).is_true()
	assert_int(after.length()).override_failure_message(
		"the sweep added nothing").is_greater(before.length())


func test_a_sealed_run_is_never_touched() -> void:
	var run_id := await _record_a_mission()
	mission_log.seal(MissionLog.Ending.VICTORY)
	var before := FileAccess.get_file_as_string(TelemetryStore.events_path(run_id))

	assert_int(MissionLog.sweep_unsealed()).is_equal(0)
	assert_str(FileAccess.get_file_as_string(TelemetryStore.events_path(run_id))
		).override_failure_message("the sweep rewrote a run somebody had already sealed"
		).is_equal(before)


# A KILL CAN LAND MID-LINE, and this is the case the rewrite exists for. Appending an ending after
# a partial line would put it somewhere ReplayRun -- the real reader -- structurally cannot reach,
# because load_run stops at the first line that will not parse.
func test_a_run_truncated_mid_line_comes_back_readable() -> void:
	var sealed_id := await _record_a_mission()
	mission_log.seal(MissionLog.Ending.ABANDONED)
	var lines := _read_lines(sealed_id)
	var kept := lines.slice(0, lines.size() - 2)
	kept.append('{"seq": 99, "t_ms": 12, "even')   # the process died writing this one
	var run_id := _plant_run(kept)

	var before := ReplayRun.load_run(run_id)
	assert_int(before.problems.size()).override_failure_message(
		"fixture: the reader did not see a truncated line").is_greater(0)

	assert_int(MissionLog.sweep_unsealed()).is_equal(1)

	var after := ReplayRun.load_run(run_id)
	# A planted run has no board.tres, so `problems` is not empty -- the claim is narrower and is
	# about the LINE: the reader must no longer stop part-way through the events.
	for problem: String in after.problems:
		assert_bool(problem.contains("truncated")).override_failure_message(
			"the partial line survived the rewrite: %s" % problem).is_false()
	assert_str(str(after.first("mission_end").get("outcome"))).override_failure_message(
		"the ending is unreachable -- it was written behind the broken line").is_equal("CRASHED")
	assert_bool(after.first("summary").is_empty()).is_false()


func test_the_board_snapshot_survives_the_rewrite() -> void:
	var run_id := await _record_a_mission()
	_die()
	assert_int(MissionLog.sweep_unsealed()).is_equal(1)
	var run := ReplayRun.load_run(run_id)
	assert_object(run.board).override_failure_message(
		"the rewrite took board.tres with it -- the run can no longer be replayed").is_not_null()
	assert_bool(run.can_replay()).is_true()


func test_the_sweep_writes_nothing_while_persistence_is_off() -> void:
	var run_id := await _record_a_mission()
	_die()
	var before := FileAccess.get_file_as_string(TelemetryStore.events_path(run_id))
	TelemetryStore.persistence_enabled = false
	assert_int(MissionLog.sweep_unsealed()).override_failure_message(
		"89 suites boot this scene headless -- the sweep must not go walking a real folder"
		).is_equal(0)
	TelemetryStore.persistence_enabled = true
	assert_str(FileAccess.get_file_as_string(TelemetryStore.events_path(run_id))).is_equal(before)


# ==============================================================================
#  The close-request seal
# ==============================================================================

# ALT-F4. Driven through Object.notification, which is the dispatch the engine's own propagation
# ends in; the walk down into the SubViewport is the half the play-check confirms.
func test_the_window_close_request_seals_the_run_as_quit() -> void:
	var run_id := await _record_a_mission()
	assert_bool(mission_log.is_open()).is_true()

	mission_log.notification(NOTIFICATION_WM_CLOSE_REQUEST)

	assert_bool(mission_log.is_open()).override_failure_message(
		"the close request left the run open -- a sweep would label this CRASHED").is_false()
	var run := ReplayRun.load_run(run_id)
	var end := run.first("mission_end")
	assert_str(str(end.get("outcome"))).is_equal("QUIT")
	assert_bool(bool(end.get("swept", false))).override_failure_message(
		"we watched this one end -- it is not an inference").is_false()
	# A real seal reads the LIVE board, where a swept one can only copy a snapshot.
	var live: Array[Unit] = game._all_units()
	assert_int((end.get("units", []) as Array).size()).is_equal(live.size())
	assert_str(str(run.first("summary").get("summary", {}).get("outcome"))).is_equal("QUIT")


func test_a_close_request_with_no_open_run_does_nothing() -> void:
	assert_bool(mission_log.is_open()).is_false()
	mission_log.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_array(Array(ReplayRun.list_runs())).override_failure_message(
		"a close request outside a mission minted a run").is_empty()


# ==============================================================================
#  Fixture
# ==============================================================================

# A real mission, played through the doors a player uses, ENDING ON A TURN BOUNDARY -- which the
# equivalence case above depends on and says so.
func _record_a_mission() -> String:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var foe := _spawn(Team.Faction.ENEMY, Vector2i(3, 0))
	hero.equipped_weapon = H.make_weapon(4)
	foe.unit_instance.stats[Stats.Stat.MHP] = 200
	foe.set_current_hp(200)
	mc._begin_turn()
	var run_id: String = mission_log.run_id()

	var move := _build_move(hero, Vector2i(2, 0))
	assert_bool(game.squad_manager.queue_action(hero.squad, move)).override_failure_message(
		"fixture: the move never queued").is_true()
	await game.order_executor.execute_orders(hero)

	var attack := AttackAction.declare(hero, hero.movement.cell, foe.movement.cell)
	assert_bool(game.squad_manager.queue_action(hero.squad, attack)).override_failure_message(
		"fixture: the attack never queued").is_true()
	await game.order_executor.execute_orders(hero)

	await game.end_turn()
	assert_bool(FileAccess.file_exists(TelemetryStore.events_path(run_id))).override_failure_message(
		"fixture: nothing was written to disk").is_true()
	return run_id


# THE PROCESS DIES. There is no public door for this by construction, so the three fields a kill
# would take with it are dropped by hand: the file handle (or Windows refuses to replace the file
# out from under it), and the in-memory run that would otherwise go on recording.
func _die() -> void:
	var file: FileAccess = mission_log._file
	if file != null:
		file.close()
	mission_log._file = null
	mission_log._open = false


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


func _build_move(unit: Unit, dest: Vector2i) -> MoveAction:
	var range_info: Dictionary = RulesService.compute_move_range(unit, game._board())
	var path: Array[Vector2i] = RulesService.reconstruct_path(range_info.came_from, unit.movement.cell, dest)
	var move := MoveAction.new()
	move.init(unit, path, GridUtils.get_terrain_icon_at_cell(game.grid, dest))
	return move


func _read_lines(run_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var file := FileAccess.open(TelemetryStore.events_path(run_id), FileAccess.READ)
	while file != null and not file.eof_reached():
		var raw := file.get_line()
		if raw.strip_edges() != "":
			out.append(raw)
	if file != null:
		file.close()
	return out


# A run folder holding exactly these lines, under a fresh id. No board.tres: the cases that plant
# one are asking about the event file.
func _plant_run(lines: PackedStringArray) -> String:
	var run_id := "planted_" + TelemetryStore.new_id().substr(0, 8)
	DirAccess.make_dir_recursive_absolute(TelemetryStore.run_dir(run_id))
	var file := FileAccess.open(TelemetryStore.events_path(run_id), FileAccess.WRITE)
	assert_object(file).override_failure_message("fixture: could not plant a run").is_not_null()
	for text: String in lines:
		file.store_line(text)
	file.close()
	return run_id


func _summary_of(run_id: String) -> Dictionary:
	return ReplayRun.load_run(run_id).first("summary").get("summary", {})


func _wipe() -> void:
	_wipe_dir(SCRATCH_ROOT)


# RECURSIVE, and that is not tidiness: a run is a folder inside `pending/` inside the root, so a
# one-level sweep leaves `pending/` non-empty, its remove() fails SILENTLY, and every case after
# the first inherits the last one's runs -- which is exactly what a sweep case cannot survive.
func _wipe_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_wipe_dir(path + sub + "/")
		dir.remove(sub)
	for file: String in dir.get_files():
		dir.remove(file)
