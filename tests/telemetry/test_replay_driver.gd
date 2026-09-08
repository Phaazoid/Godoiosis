# THE REPLAY HARNESS (#53 slice 4), and the round-trip case is the point of the file: record a real
# mission, feed the recorded run back through the driver, and assert the replay produced the SAME
# outcomes. That is the sufficiency proof slice 2 could not write -- its own PR said only a harness
# proves a log is replayable, and that the first one should expect to find a gap.
#
# Persistence is ON, aimed at a scratch folder, because the round trip has to go through the real
# file and the real board.tres: an in-memory shortcut would prove the recorder can talk to itself.
#
# The DIVERGENCE cases matter as much as the clean one. A harness that cannot report a difference is
# worse than none -- it would certify anything -- so a deliberately corrupted run must come back
# with a named divergence.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const SCRATCH_ROOT := "user://__replay_test/"

var _main: Node
var game: Node2D
var mc: MissionController
var mission_log: MissionLog
var driver: ReplayDriver


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
	driver = ReplayDriver.new()
	driver.game = game
	add_child(driver)
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	if is_instance_valid(driver):
		remove_child(driver)
		driver.free()
	remove_child(_main)
	_main.free()
	_wipe()
	TelemetryStore.reset_for_test()


# ==============================================================================
#  The round trip
# ==============================================================================

func test_a_recorded_run_replays_with_no_divergence() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	assert_bool(run.can_replay()).override_failure_message(
		"fixture: the recorded run is not replayable -- %s" % str(run.problems)).is_true()

	assert_bool(driver.seed(run)).is_true()
	await driver.play()

	assert_array(driver.unbindable).override_failure_message(
		"every unit in the roster must re-bind: %s" % str(driver.unbindable)).is_empty()
	assert_int(driver.divergences.size()).override_failure_message(
		"the replay diverged from the run: %s" % str(driver.divergences)).is_equal(0)


func test_the_run_is_bound_by_starting_cell_not_by_recorded_id() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	assert_bool(driver.seed(run)).is_true()
	# Every id in the recorded roster belongs to a unit of the PREVIOUS board, all of which were
	# freed by apply_scenario. Nothing could have matched by id; the cells are what bound them.
	var recorded_ids: Array = []
	for entry: Dictionary in run.first("mission_start").get("roster", []):
		recorded_ids.append(int(entry.get("id", 0)))
	assert_int(recorded_ids.size()).is_greater(0)
	for live: Unit in game.units_root.get_children():
		assert_bool(recorded_ids.has(live.get_instance_id())).override_failure_message(
			"a live unit reused a recorded instance id -- this case proves nothing").is_false()
	assert_array(driver.unbindable).is_empty()


# THE CASE ABOVE IS NOT ENOUGH, and a mutant is what said so: binding by roster INDEX instead of by
# cell passes it, because the recorded roster and the seeded board are both walks of units_root at
# the same moment and so agree on order. The two answers are only distinguishable when that order
# breaks -- which is exactly the situation cell-binding exists to survive, and index-binding does
# not. So break it on purpose.
func test_binding_does_not_depend_on_the_order_units_sit_in() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	assert_bool(driver.seed(run)).is_true()
	var before: Dictionary = driver._by_recorded_id.duplicate()
	assert_int(before.size()).override_failure_message("fixture: nothing was bound").is_greater(1)

	# Same units, same cells, different child order. A bind that reads an index now answers
	# differently; one that reads the recorded cell cannot.
	var kids: Array[Node] = game.units_root.get_children()
	game.units_root.move_child(kids[0], kids.size() - 1)
	driver._by_recorded_id.clear()
	driver.unbindable.clear()
	driver._bind_units()

	assert_array(driver.unbindable).is_empty()
	assert_int(driver._by_recorded_id.size()).is_equal(before.size())
	for recorded_id in before:
		assert_object(driver._by_recorded_id.get(recorded_id)).override_failure_message(
			"reordering the board moved a binding -- it is reading position, not the recorded cell"
			).is_same(before[recorded_id])


# A harness that cannot report a difference would certify anything.
func test_a_corrupted_outcome_is_reported_as_a_divergence() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	var touched := false
	for e: Dictionary in run.events:
		if e.get("event") == "pass":
			for hit: Dictionary in e.get("hits", []):
				hit["damage"] = int(hit.get("damage", 0)) + 999
				touched = true
	assert_bool(touched).override_failure_message("fixture: the run recorded no hit to corrupt").is_true()

	assert_bool(driver.seed(run)).is_true()
	await driver.play()
	assert_int(driver.divergences.size()).override_failure_message(
		"a corrupted damage number must be reported").is_greater(0)


func test_replaying_writes_no_new_run() -> void:
	var run_id := await _record_a_mission()
	var before := ReplayRun.list_runs().size()
	var run := ReplayRun.load_run(run_id)
	assert_bool(driver.seed(run)).is_true()
	await driver.play()
	assert_int(ReplayRun.list_runs().size()).override_failure_message(
		"a replay must not look like a new playtest run").is_equal(before)
	# ...but it DID record, in memory, which is what the diff is measured against.
	assert_int(mission_log.events().size()).is_greater(0)


func test_a_run_with_no_board_refuses_to_seed_and_says_why() -> void:
	var run_id := await _record_a_mission()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		TelemetryStore.run_dir(run_id) + ReplayRun.BOARD_FILE))
	var run := ReplayRun.load_run(run_id)
	assert_bool(run.can_replay()).is_false()
	assert_bool(driver.seed(run)).is_false()
	assert_int(driver.notes.size()).is_greater(0)


func test_a_run_folder_is_listed_and_headlined() -> void:
	var run_id := await _record_a_mission()
	assert_array(Array(ReplayRun.list_runs())).contains([run_id])
	var head := ReplayRun.load_run(run_id).headline()
	assert_str(str(head.get("run_id"))).is_equal(run_id)
	assert_int(int(head.get("rounds", 0))).is_greater(0)


# ==============================================================================
#  Fixture
# ==============================================================================

# A real mission, played: two units, a move, an attack, a resolved pass, a turn hand-over, sealed.
# Driven through the same doors a player uses, because a run assembled by hand would be a run this
# driver has never had to reproduce.
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
	mission_log.seal(MissionLog.Ending.ABANDONED)
	assert_bool(FileAccess.file_exists(TelemetryStore.run_dir(run_id) + ReplayRun.EVENTS_FILE)).override_failure_message(
		"fixture: nothing was written to disk").is_true()
	return run_id


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


func _wipe() -> void:
	var dir := DirAccess.open(SCRATCH_ROOT)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		var inner := DirAccess.open(SCRATCH_ROOT + sub)
		if inner != null:
			for file: String in inner.get_files():
				inner.remove(file)
		dir.remove(sub)
	for file: String in dir.get_files():
		dir.remove(file)
