# The playtest recorder (#53), driven through the REAL scene -- MissionController's doors,
# OrderExecutor's pass, the manager and unit signals -- never by hand-emitting into it.
#
# Two cases exist because the plan's review caught what a naive recorder misses, and each is
# pinned against its own mutant:
#   * the FIRST turn_start is written by begin(): TurnManager.turn_started never fires for turn 1
#   * a pass records the QUEUE as well as the plan: rescue, rally, reload are not on a ResolvedPlan
#
# Persistence is ON here, aimed at a scratch folder, so the file half is exercised in every case
# rather than trusted: the seal is read back off disk, and the flush case reads the file of a run
# that is still OPEN. Every case builds its own board cell by cell (tests/README.md #4/#9) and the
# mission path is a plain string -- begin() only reads it, and "" is the sandbox rule under test.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const MISSION := "res://tests/telemetry/not_a_real_file.tres"   # a name, never loaded
const SCRATCH_ROOT := "user://__telemetry_test/"
const SCRATCH_MISSION := "user://__telemetry_53.tres"   # the one case that RELOADS needs a real file

var _main: Node
var game: Node2D
var mc: MissionController
var mission_log: MissionLog


func before_test() -> void:
	TelemetryStore.reset_for_test()
	TelemetryStore.root = SCRATCH_ROOT
	TelemetryStore.persistence_enabled = true
	_wipe(SCRATCH_ROOT)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	mc = game.mission_controller
	mission_log = game.mission_log
	mc._close_mission_select()
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(3):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	game.scenario_manager.last_loaded_path = MISSION
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	_wipe(SCRATCH_ROOT)
	if FileAccess.file_exists(SCRATCH_MISSION):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_MISSION))
	TelemetryStore.reset_for_test()


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir + sub + "/")
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + file)
	DirAccess.remove_absolute(dir)


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


func _of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in mission_log.events():
		if e.get("event") == kind:
			out.append(e)
	return out


func _lines_of(run_id: String) -> Array[Dictionary]:
	var path := TelemetryStore.run_dir(run_id) + "events.jsonl"
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return out
	var text := FileAccess.get_file_as_string(path)
	for line in text.split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed)
	return out


func _last_line_of(run_id: String) -> Dictionary:
	var lines := _lines_of(run_id)
	return lines.back() if not lines.is_empty() else {}


func _queue_attack(attacker: Unit, target: Unit) -> AttackAction:
	var action := AttackAction.declare(attacker, attacker.movement.cell, target.movement.cell)
	assert_bool(game.squad_manager.queue_action(attacker.squad, action)).override_failure_message(
		"fixture: the attack never queued").is_true()
	return action


# ==============================================================================
#  begin()
# ==============================================================================

func test_begin_writes_mission_start_and_the_first_turn_start() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var foe := _spawn(Team.Faction.ENEMY, Vector2i(5, 0))
	mc._begin_turn()

	assert_bool(mission_log.is_open()).is_true()
	var events := mission_log.events()
	assert_int(events.size()).override_failure_message("begin() writes exactly two lines").is_equal(2)
	assert_str(str(events[0].get("event"))).is_equal("mission_start")
	assert_str(str(events[0].get("scenario"))).is_equal(MISSION)
	var names: Array[String] = []
	for row: Dictionary in events[0].get("roster", []):
		names.append(str(row.get("name")))
	assert_array(names).contains_exactly_in_any_order([hero.get_unit_name(), foe.get_unit_name()])
	# THE REVIEW'S CASE: the signal never fires for turn 1, so the baseline is begin()'s to write.
	assert_str(str(events[1].get("event"))).override_failure_message(
		"the first turn_start must be written by begin() -- turn_started fires only from end_turn"
		).is_equal("turn_start")
	assert_str(str(events[1].get("faction"))).is_equal("PLAYER")
	var units: Array = events[1].get("units", [])
	assert_int(units.size()).is_equal(2)
	assert_int(int(events[1].get("round", 0))).is_equal(1)


# FLAGGED, not dropped (dev, 2026-09-08). A sandbox run is still data; what it must never do is
# look like a mission, so the flag is its own field rather than an empty `scenario` read as one.
func test_the_sandbox_records_itself_as_a_sandbox() -> void:
	game.scenario_manager.last_loaded_path = ""
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mc._begin_turn()

	assert_bool(mission_log.is_open()).override_failure_message(
		"a sandbox run is flagged, never ignored -- ignoring it is what this replaced").is_true()
	var start := _of("mission_start")[0]
	assert_bool(bool(start.get("sandbox"))).is_true()
	assert_str(str(start.get("scenario"))).is_equal("")


func test_a_real_mission_is_not_flagged_as_a_sandbox() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mc._begin_turn()   # before_test aimed last_loaded_path at a mission
	assert_bool(bool(_of("mission_start")[0].get("sandbox"))).override_failure_message(
		"a flag that is always true separates nothing").is_false()


func test_the_summary_carries_the_separation_flags() -> void:
	game.scenario_manager.last_loaded_path = ""
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mc._begin_turn()
	var run := mission_log.run_id()
	mission_log.seal(MissionLog.Ending.ABANDONED)

	var lines := _lines_of(run)
	var summary: Dictionary = (lines.back() as Dictionary).get("summary", {})
	assert_bool(bool(summary.get("sandbox"))).override_failure_message(
		"the summary is the INDEXED row -- the flag has to reach where the querying happens"
		).is_true()
	assert_bool(summary.has("dev_mode")).is_true()


func test_a_resume_is_flagged_with_its_starting_round() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mc.restore_progress([], false, 3)   # a save taken three rounds in
	mc._begin_turn()
	var start := _of("mission_start")[0]
	assert_bool(bool(start.get("resumed", false))).is_true()
	assert_int(int(start.get("round", 0))).is_equal(4)


func test_the_roster_names_what_each_unit_brought() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	hero.equipped_weapon = H.make_weapon(4)
	mc._begin_turn()
	var start := _of("mission_start")[0]
	var row: Dictionary = start.get("roster", [])[0]
	assert_bool(bool(row.get("deployed", false))).is_true()
	assert_that(row.get("cell")).is_equal([0, 0])
	var weapon: Variant = row.get("weapon")
	assert_bool(weapon is Dictionary).override_failure_message("the equipped weapon is written").is_true()
	assert_bool((weapon as Dictionary).has("family")).is_true()
	assert_bool((row.get("stats") as Dictionary).has("STR")).is_true()
	assert_int(int(row.get("hp_max", 0))).is_equal(hero.get_max_hp())


func test_every_line_carries_seq_time_and_round() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mc._begin_turn()
	mc.capture("nowhere")   # refused (no such zone) -- the events below are begin()'s two
	var seq := -1
	for e: Dictionary in mission_log.events():
		assert_bool(e.has("t_ms") and e.has("round") and e.has("event")).is_true()
		assert_int(int(e.get("seq"))).is_greater(seq)
		seq = int(e.get("seq"))


# ==============================================================================
#  The signal side
# ==============================================================================

func test_a_queued_order_and_its_cancel_are_recorded_with_faction_and_pass_state() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var foe := _spawn(Team.Faction.ENEMY, Vector2i(1, 0))
	mc._begin_turn()
	var action := _queue_attack(hero, foe)

	var queued := _of("order_queued")
	assert_int(queued.size()).is_equal(1)
	assert_str(str(queued[0].get("faction"))).is_equal("PLAYER")
	assert_bool(bool(queued[0].get("during_pass", true))).is_false()
	var order: Dictionary = queued[0].get("order", {})
	assert_str(str(order.get("type"))).is_equal("ATTACK")
	# The AIM is the order's identity -- a declared attack carries no target (see _order).
	assert_that(order.get("at")).is_equal([foe.movement.cell.x, foe.movement.cell.y])
	assert_bool(order.has("target")).override_failure_message(
		"a queued attack has no victim yet -- recording one would write id 0 forever").is_false()

	# The hold filler game.gd queues alongside it is NOT in this stream -- see _on_order_queued.
	# Read off the RAW queue: has_action_type_queued answers false for a hold on purpose.
	var holds := 0
	for queued_action: BaseAction in hero.squad.action_queue:
		if queued_action is MoveAction and (queued_action as MoveAction).is_hold_position:
			holds += 1
	assert_int(holds).override_failure_message(
		"fixture: no hold filler was queued, so this case is not exercising the exclusion").is_greater(0)

	game.squad_manager.remove_action(hero.squad, action)
	var cancelled := _of("order_cancelled")
	assert_int(cancelled.size()).is_equal(1)
	assert_str(str(cancelled[0].get("type"))).is_equal("ATTACK")
	assert_str(str(cancelled[0].get("faction"))).is_equal("PLAYER")


func test_turn_starts_after_the_first_ride_the_signal() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	_spawn(Team.Faction.ENEMY, Vector2i(7, 2))
	mc._begin_turn()
	await game.end_turn()   # -> ENEMY, round 1
	await game.end_turn()   # -> PLAYER, round 2
	var starts := _of("turn_start")
	assert_int(starts.size()).is_equal(3)
	assert_str(str(starts[1].get("faction"))).is_equal("ENEMY")
	assert_int(int(starts[1].get("round", 0))).is_equal(1)
	assert_str(str(starts[2].get("faction"))).is_equal("PLAYER")
	assert_int(int(starts[2].get("round", 0))).is_equal(2)


func test_a_down_and_a_death_are_recorded() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var foe := _spawn(Team.Faction.ENEMY, Vector2i(5, 0))
	var other := _spawn(Team.Faction.ENEMY, Vector2i(6, 0))
	mc._begin_turn()
	foe.force_down()
	other.die()
	var downed := _of("unit_downed")
	assert_int(downed.size()).is_equal(1)
	assert_int(int(downed[0].get("id", 0))).is_equal(foe.get_instance_id())
	assert_str(str(downed[0].get("state"))).is_equal("DOWNED")
	var died := _of("unit_died")
	assert_int(died.size()).is_equal(1)
	assert_str(str(died[0].get("faction"))).is_equal("ENEMY")


# ==============================================================================
#  The explicit hooks
# ==============================================================================

func test_a_pass_records_the_hit_it_landed() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var foe := _spawn(Team.Faction.ENEMY, Vector2i(1, 0))
	hero.equipped_weapon = H.make_weapon(4)
	foe.unit_instance.stats[Stats.Stat.MHP] = 200
	foe.set_current_hp(200)
	mc._begin_turn()
	_queue_attack(hero, foe)
	await game.order_executor.execute_orders(hero)

	var passes := _of("pass")
	assert_int(passes.size()).is_equal(1)
	assert_str(str(passes[0].get("faction"))).is_equal("PLAYER")
	var hits: Array = passes[0].get("hits", [])
	assert_int(hits.size()).override_failure_message("the plan's one attack is one hit").is_equal(1)
	var hit: Dictionary = hits[0]
	assert_str(str(hit.get("kind"))).is_equal("attack")
	assert_int(int((hit.get("target") as Dictionary).get("id", 0))).is_equal(foe.get_instance_id())
	assert_int(int(hit.get("damage", 0))).is_greater(0)
	assert_int(int(hit.get("hp_after", -1))).is_equal(foe.get_current_hp())
	assert_str(str(hit.get("lethality"))).is_equal("NONE")


func test_a_pass_records_the_side_channel_order_the_plan_does_not_hold() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	hero.unit_instance.set_current_will(0)
	assert_bool(hero.can_rally()).override_failure_message("fixture: rally must be offered").is_true()
	mc._begin_turn()
	game.queue_simple_action(hero, BaseAction.ActionType.RALLY)
	await game.order_executor.execute_orders(hero)

	var passes := _of("pass")
	assert_int(passes.size()).is_equal(1)
	var types: Array[String] = []
	for order: Dictionary in passes[0].get("orders", []):
		types.append(str(order.get("type")))
	# THE REVIEW'S CASE: a ResolvedPlan carries attacks; rally, rescue, reload live on the queue.
	assert_array(types).override_failure_message(
		"a side-channel verb is on the squad's queue and NOT on the plan -- both must be read"
		).contains(["RALLY"])
	assert_int((passes[0].get("hits", []) as Array).size()).is_equal(0)


func test_burning_ground_is_recorded_as_turn_effects() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	_spawn(Team.Faction.ENEMY, Vector2i(7, 2))
	mc._begin_turn()
	var effect := ResolvedCellEffect.new()
	effect.cell = hero.movement.cell
	effect.states_added = [Terrain.TileState.BURNING]
	game.terrain_states.apply(effect)
	var before := hero.get_current_hp()
	await game.end_turn()

	var effects := _of("turn_effects")
	assert_int(effects.size()).override_failure_message(
		"end-of-turn burn is in no pass and on no signal -- the executor must write it").is_equal(1)
	assert_str(str(effects[0].get("faction"))).is_equal("PLAYER")
	var hits: Array = effects[0].get("hits", [])
	assert_int(hits.size()).is_equal(1)
	assert_str(str((hits[0] as Dictionary).get("state"))).is_equal("BURNING")
	assert_int(int((hits[0] as Dictionary).get("damage", 0))).is_equal(before - hero.get_current_hp())


func test_a_capture_is_recorded() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	game.zone_manager.paint_cell("Point", ZoneManager.Kind.CAPTURE, Vector2i(2, 2))
	mc._begin_turn()
	mc.capture("Point")
	var captures := _of("zone_captured")
	assert_int(captures.size()).is_equal(1)
	assert_str(str(captures[0].get("zone"))).is_equal("Point")


# ==============================================================================
#  Sealing
# ==============================================================================

func test_the_mission_ending_seals_the_run_before_the_banner() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var foe := _spawn(Team.Faction.ENEMY, Vector2i(5, 0))
	var typed: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(typed)
	mc._begin_turn()
	mc.check()   # latches contested
	var run := mission_log.run_id()
	foe.die()
	mc.check()   # VICTORY -> _end_mission, which seals and then awaits the banner
	assert_bool(mc.is_over()).override_failure_message("fixture: the rout did not end the mission").is_true()

	assert_bool(mission_log.is_open()).is_false()
	var lines := _lines_of(run)
	var end: Dictionary = lines[lines.size() - 2]
	assert_str(str(end.get("event"))).is_equal("mission_end")
	assert_str(str(end.get("outcome"))).is_equal("VICTORY")
	assert_str(str(end.get("failed_by"))).is_equal("NONE")
	var summary: Dictionary = lines.back()
	assert_str(str(summary.get("event"))).is_equal("summary")
	assert_str(str((summary.get("summary") as Dictionary).get("outcome"))).is_equal("VICTORY")


func test_events_after_the_seal_are_dropped() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var foe := _spawn(Team.Faction.ENEMY, Vector2i(1, 0))
	mc._begin_turn()
	mission_log.seal(MissionLog.Ending.DEFEAT, MissionRules.LoseCondition.SQUAD_LOST)
	var run := mission_log.run_id()
	var sealed := _lines_of(run).size()
	_queue_attack(hero, foe)   # STAY at the banner: the board is unlocked, the run is over
	assert_int(_lines_of(run).size()).is_equal(sealed)
	assert_int(_of("order_queued").size()).is_equal(0)


func test_beginning_again_seals_the_open_run_as_interrupted() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mc._begin_turn()
	var first := mission_log.run_id()
	mc._begin_turn()
	assert_str(mission_log.run_id()).is_not_equal(first)
	var end: Dictionary = _lines_of(first)[_lines_of(first).size() - 2]
	assert_str(str(end.get("event"))).is_equal("mission_end")
	assert_str(str(end.get("outcome"))).is_equal("INTERRUPTED")


# THE F2 CASE. reload_current has two callers and only restart_mission seals, so a board torn down
# any OTHER way used to leave the run open, appending events about a board that no longer exists.
# Driven through clear_board -- the universal teardown F2, a board swap, Load Game and Mission
# Select all reach -- rather than through the dev key, so it covers all four doors at once.
func test_tearing_the_board_down_seals_the_open_run() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mc._begin_turn()
	var run := mission_log.run_id()
	assert_bool(mission_log.is_open()).is_true()
	var during := _lines_of(run).size()

	game.scenario_manager.clear_board()

	assert_bool(mission_log.is_open()).override_failure_message(
		"a torn-down board must seal its run -- an open one goes on recording a dead board").is_false()
	var lines := _lines_of(run)
	var end: Dictionary = lines[lines.size() - 2]
	assert_str(str(end.get("event"))).is_equal("mission_end")
	assert_str(str(end.get("outcome"))).is_equal("INTERRUPTED")
	# Sealed BEFORE the board was emptied, so the record still names who was standing.
	assert_int((end.get("units", []) as Array).size()).override_failure_message(
		"the seal must run before clear_board frees the units, or it records an empty board"
		).is_equal(1)
	assert_int(lines.size()).is_greater(during)
	assert_object(hero).is_not_null()   # the fixture's own unit, not yet freed at seal time


func test_abandon_seals_as_abandoned() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mc._begin_turn()
	var run := mission_log.run_id()
	mc.abandon_mission()
	var lines := _lines_of(run)
	assert_str(str(lines[lines.size() - 2].get("outcome"))).is_equal("ABANDONED")


func test_restart_seals_as_restarted_and_opens_a_new_run() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var scenario: ScenarioData = game.scenario_manager.capture_scenario("telemetry_53", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH_MISSION)).is_equal(OK)
	game.scenario_manager.last_loaded_path = SCRATCH_MISSION
	mc._begin_turn()
	var run := mission_log.run_id()
	mc.restart_mission()
	var lines := _lines_of(run)
	assert_str(str(lines[lines.size() - 2].get("outcome"))).is_equal("RESTARTED")
	assert_bool(mission_log.is_open()).override_failure_message("the reload opens a fresh run").is_true()
	assert_str(mission_log.run_id()).is_not_equal(run)


# ==============================================================================
#  The file
# ==============================================================================

func test_the_file_holds_one_line_per_event_while_the_run_is_still_open() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var foe := _spawn(Team.Faction.ENEMY, Vector2i(1, 0))
	mc._begin_turn()
	_queue_attack(hero, foe)
	assert_bool(mission_log.is_open()).is_true()
	# Read WITHOUT sealing: a crash leaves exactly this file, and it must already be complete.
	assert_int(_lines_of(mission_log.run_id()).size()).override_failure_message(
		"every line is flushed as it is written, or a crash loses the tail").is_equal(
		mission_log.events().size())


# ==============================================================================
#  Replay-grade capture (slice 2)
# ==============================================================================

# THE REPLAY SEED. The JSON roster is names and effective stats and cannot rebuild a unit; this is
# the machine-exact state, through the same #87 snapshot a save slot round-trips.
func test_the_run_folder_holds_a_board_snapshot_that_reloads() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	_spawn(Team.Faction.ENEMY, Vector2i(5, 0))
	mc._begin_turn()

	var path := TelemetryStore.run_dir(mission_log.run_id()) + "board.tres"
	assert_bool(FileAccess.file_exists(path)).override_failure_message(
		"a run with no board snapshot can never be replayed, and that cannot be backfilled").is_true()
	# Read back through a FRESH load, never the object just saved -- a plain load() would hand back
	# the very resource take_over_path just claimed and assert nothing.
	var back: ScenarioData = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_object(back).is_not_null()
	assert_int(back.unit_entries.size()).override_failure_message(
		"the snapshot must carry the board's units, or it is not a starting state").is_equal(2)
	assert_object(hero).is_not_null()


func test_a_rescue_records_the_bank_the_player_picked() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var body := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	mc._begin_turn()
	body.force_down()
	var rescue := RescueAction.new()
	rescue.init(hero, body, Vector2i(0, 1))
	assert_bool(game.squad_manager.queue_action(hero.squad, rescue)).override_failure_message(
		"fixture: the rescue never queued").is_true()

	# Read at QUEUE time, not after a pass: `_order` is what both records go through, and the haul
	# is a fact of the ORDER rather than of its execution. (A rescue plan here does not survive
	# execute_orders' validity guard, which is a fixture matter and not what this case is about.)
	var queued := _of("order_queued")
	assert_int(queued.size()).override_failure_message("fixture: the rescue was not recorded").is_equal(1)
	var order: Dictionary = queued[0].get("order", {})
	assert_str(str(order.get("type"))).is_equal("RESCUE")
	assert_that(order.get("haul_to")).override_failure_message(
		"the haul cell is the PLAYER's pick -- without it a replay drops the body elsewhere"
		).is_equal([0, 1])


# Squad Up and Join both commit through join_squad; leave and disband are their own verbs. All four
# must name their OWN cause -- the bug this case exists for is logging a leave as a squad-up.
func test_the_squad_verbs_each_record_their_own_cause() -> void:
	var leader := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var other := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	mc._begin_turn()

	game.squad_manager.join_squad(other, leader.squad)
	game.mission_log.record_squad_verb("leave", other)
	game.squad_manager.leave_squad(other)

	var verbs: Array[String] = []
	for e: Dictionary in _of("squad_verb"):
		verbs.append(str(e.get("verb")))
	assert_array(verbs).override_failure_message(
		"a join and a leave must be distinguishable -- squad_created cannot tell them apart"
		).contains_exactly(["join", "leave"])


# The ejection sweeps call leave_squad too, and those are consequences a replay re-derives.
func test_an_automatic_ejection_is_not_recorded_as_a_player_verb() -> void:
	var leader := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var other := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	mc._begin_turn()
	game.squad_manager.join_squad(other, leader.squad)
	var before := _of("squad_verb").size()

	game.squad_manager.leave_squad(other)   # the sweep's own door, no menu involved

	assert_int(_of("squad_verb").size()).override_failure_message(
		"an automatic ejection is a CONSEQUENCE, not a decision -- recording it would be a phantom"
		).is_equal(before)


func test_a_gear_change_records_the_act_and_not_the_state() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mc._begin_turn()
	game.unit_info_panel.loadout_acted.emit(hero, "equip", 2)

	var gear := _of("gear")
	assert_int(gear.size()).override_failure_message(
		"the gear seam is a WIRE -- inventory_panel emits, the panel forwards, the log listens"
		).is_equal(1)
	assert_str(str(gear[0].get("verb"))).is_equal("equip")
	assert_int(int(gear[0].get("index"))).override_failure_message(
		"the INDEX is what makes it replayable through the real door").is_equal(2)


func test_a_dev_intervention_marks_the_run_untrustworthy() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mc._begin_turn()
	var run := mission_log.run_id()
	game.mission_log.note_dev_intervention()
	mission_log.seal(MissionLog.Ending.ABANDONED)

	var lines := _lines_of(run)
	var end: Dictionary = lines[lines.size() - 2]
	assert_bool(bool(end.get("dev_touched"))).override_failure_message(
		"a dev-touched board must say so, or a replay diverges silently").is_true()


func test_an_untouched_run_is_not_flagged() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mc._begin_turn()
	var run := mission_log.run_id()
	mission_log.seal(MissionLog.Ending.ABANDONED)
	var lines := _lines_of(run)
	assert_bool(bool(lines[lines.size() - 2].get("dev_touched"))).override_failure_message(
		"a flag that is always true says nothing").is_false()


func test_with_persistence_off_nothing_is_written() -> void:
	TelemetryStore.persistence_enabled = false
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mc._begin_turn()
	assert_bool(mission_log.is_open()).is_true()
	assert_int(mission_log.events().size()).is_equal(2)
	assert_bool(DirAccess.dir_exists_absolute(TelemetryStore.pending_dir())).is_false()
