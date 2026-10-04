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
const GONE_POSE := "res://Scenarios/__test_no_such_pose.tres"

var _main: Node
var game: Node2D
var mc: MissionController
var mission_log: MissionLog
var driver: ReplayDriver


func before_test() -> void:
	TelemetryStore.reset_for_test()
	TelemetryStore.root = SCRATCH_ROOT
	TelemetryStore.persistence_enabled = true
	_wipe(SCRATCH_ROOT)
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
	_wipe(SCRATCH_ROOT)
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


# A RECORDED WATCH IS RE-ARMED FROM THE WATCH VIEW (#615). The log records a watch by NAME, and since
# #590 a watch-only attack is never in the fire view -- so a lookup there missed every recorded
# overwatch and replayed it with the MAIN. The outcome diff cannot see that (a watch nobody walks
# into lands no hit), so this asks the board what the replayed watch fires.
func test_a_recorded_watch_replays_with_its_own_attack() -> void:
	var run_id := await _record_a_watch()
	var run := ReplayRun.load_run(run_id)
	assert_bool(driver.seed(run)).is_true()
	await driver.play()

	assert_array(driver.notes.filter(func(n: String) -> bool: return n.contains("no longer has"))
		).override_failure_message("the replay could not find the recorded watch: %s" % str(driver.notes)
		).is_empty()
	var watcher: Unit = null
	for live: Unit in game.units_root.get_children():
		if live.get_faction() == Team.Faction.PLAYER:
			watcher = live
	assert_object(watcher).is_not_null()
	assert_object(watcher.watch).override_failure_message("the replay armed no watch at all").is_not_null()
	var armed: AttackData = watcher.watch.attack
	assert_str(armed.display_name if armed != null else "(none)").is_equal("Watch")


# A gear act recorded off the dock's own handler replays through GearVerbs (#46), the rule the dock
# asks -- and one the replayed board refuses is a disagreement with the run, never a silent no-op.
func test_a_recorded_wear_replays_through_the_shared_door() -> void:
	var run := ReplayRun.load_run(await _record_a_wear())
	assert_bool(driver.seed(run)).is_true()
	await driver.play()
	var wearer := _player_unit()
	assert_object(wearer).is_not_null()
	assert_object(wearer.worn_armor).override_failure_message("the replay never wore the recorded plate").is_not_null()
	assert_str(wearer.worn_armor.display_name).is_equal(REPLAY_PLATE)
	assert_int(driver.divergences.size()).override_failure_message(
		"the replay diverged from the run: %s" % str(driver.divergences)).is_equal(0)


func test_a_refused_gear_act_is_reported_as_a_divergence() -> void:
	var run := ReplayRun.load_run(await _record_a_wear())
	var doctored := false
	for e: Dictionary in run.events:
		if str(e.get("event", "")) == "gear":
			e["index"] = Unit.MAX_INVENTORY_SIZE - 1   # an empty slot on the replayed board
			doctored = true
	assert_bool(doctored).override_failure_message("fixture: the run recorded no gear act").is_true()
	assert_bool(driver.seed(run)).is_true()
	await driver.play()
	assert_array(driver.divergences.filter(func(d: String) -> bool: return d.contains("was refused"))
		).override_failure_message("a refused gear act went unreported: %s" % str(driver.divergences)
		).is_not_empty()


# THE STAND-DOWN IS AFTER THE SEED, and that ordering is the whole of it: apply_scenario REPLACES
# the AI set from the board it loads (#150), so a stand-down written first is overwritten by the
# very next line. Every faction's orders are in the log, so the driver plays them; letting the AI
# plan fresh ones would be asking a different question entirely.
#
# The board is armed by hand rather than by recording a real AI turn: what is under test is what
# seed() does with a board that enables AI, and an actual enemy turn would only add frames.
func test_the_ai_stands_down_even_though_the_seeded_board_enables_it() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	var enemy_ai: Array[Team.Faction] = [Team.Faction.ENEMY]
	run.board.ai_factions = enemy_ai
	# Non-vacuity: without this the case passes on a board that never enabled anything.
	assert_bool(run.board.ai_factions.has(Team.Faction.ENEMY)).is_true()

	assert_bool(driver.seed(run)).is_true()
	assert_bool(game.ai_controller.is_ai_faction(Team.Faction.ENEMY)).override_failure_message(
		"the AI is still enabled after seeding -- it would plan its own orders over the recorded ones"
		).is_false()


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


# A UNIT THAT DIES DURING THE REPLAY -- and the diff still has to come back CLEAN, because the
# casualty is the same casualty the run recorded.
#
# Every other case here hands the foe 200 HP, so the board being diffed was the board that was
# bound, and `_mapped_id` was only ever asked about a unit still standing. Ask it about one that has
# been freed and the typed read it used to do (`var unit: Unit = _by_recorded_id[recorded]`) dies on
# the ASSIGNMENT -- resolving the ObjectID to type-check it -- before its own is_instance_valid
# guard one line below can answer (CLAUDE.md #149). A real replay crashed exactly there.
#
# Merely making that read SAFE would not be enough, which is why this asserts clean rather than
# merely alive: falling through to `return recorded` compares a recorded id against a live one, so
# every row naming the casualty reports a FALSE divergence -- the tool's one job broken quietly.
func test_a_replay_with_a_casualty_still_diffs_clean() -> void:
	var run_id := await _record_a_mission(true)
	var run := ReplayRun.load_run(run_id)
	assert_bool(_records_a_death(run.events)).override_failure_message(
		"fixture: nobody died, so this case cannot reach the freed-id read at all").is_true()

	assert_bool(driver.seed(run)).is_true()
	await driver.play()

	assert_array(driver.unbindable).is_empty()
	assert_bool(_records_a_death(mission_log.events())).override_failure_message(
		"the replay killed nobody, so the diff never read an id off a freed unit").is_true()
	assert_int(driver.divergences.size()).override_failure_message(
		"a replay whose casualty is the run's own casualty must report nothing: %s"
		% str(driver.divergences)).is_equal(0)


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


# THE WIRE, ON THE PATH THAT SUCCEEDS (#871). A degraded board SEEDS, so the warning cannot ride the
# refusal branch above it -- and a report reading "Clean -- the replay matched the run." over a board
# that lost a reference is the silence this ticket removed, arriving one click later.
func test_a_degraded_board_still_seeds_and_the_report_carries_the_warning() -> void:
	var run_id := await _record_a_mission()
	_break_a_reference_in_the_board(run_id)
	var run := ReplayRun.load_run(run_id)
	assert_array(run.degraded).override_failure_message(
		"fixture: the board came back undegraded, so this case cannot see the wire").is_not_empty()
	assert_bool(driver.seed(run)).override_failure_message(
		"a degraded board must still seed: %s" % str(driver.notes)).is_true()
	var r := driver.report()
	assert_bool(bool(r.get("seeded", false))).is_true()
	assert_array(r.get("degraded", [])).override_failure_message(
		"the report said nothing about the degraded board, so every line in it now reads as the build's"
		).is_not_empty()

func test_a_run_folder_is_listed_and_headlined() -> void:
	var run_id := await _record_a_mission()
	assert_array(Array(ReplayRun.list_runs())).contains([run_id])
	var head := ReplayRun.load_run(run_id).headline()
	assert_str(str(head.get("run_id"))).is_equal(run_id)
	assert_int(int(head.get("rounds", 0))).is_greater(0)


# ==============================================================================
#  The transport (#853)
# ==============================================================================

# A PAUSE LANDS BETWEEN EVENTS. Requested from the first progressed signal, it must stop play before
# another step starts -- the cursor moves BEFORE an event is applied, so a step begun and abandoned
# would leave it one past the last event that landed. Then play picks up from there and finishes clean.
func test_pause_lands_on_an_event_boundary_and_play_picks_up_from_it() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	assert_bool(driver.seed(run)).is_true()
	var landed: Array[int] = []
	var on_step := func(_finished: bool) -> void:
		landed.append(int(driver.report()["at"]))
		if landed.size() == 1:
			driver.pause()
	driver.progressed.connect(on_step)

	await driver.play()
	assert_int(landed.size()).override_failure_message(
		"play went on stepping after the pause: landed at %s" % [str(landed)]).is_equal(1)
	assert_int(int(driver.report()["at"])).override_failure_message(
		"the pause left a step begun past the last event that landed").is_equal(landed[0])
	assert_bool(driver.is_finished()).override_failure_message(
		"the pause stopped nothing: the replay ran to the end").is_false()
	assert_bool(driver.is_playing()).is_false()

	await driver.play()
	assert_bool(driver.is_finished()).override_failure_message(
		"play did not pick up where the pause left it").is_true()
	assert_int(driver.divergences.size()).override_failure_message(
		"a paused and resumed replay diverged: %s" % [str(driver.divergences)]).is_equal(0)


func test_the_next_readout_names_the_event_the_next_step_applies() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	assert_bool((driver.report()["next"] as Dictionary).is_empty()).override_failure_message(
		"an unseeded driver names a next event").is_true()
	assert_bool(driver.seed(run)).is_true()

	var checked := 0
	while not driver.is_finished():
		var r := driver.report()
		var at := int(r["at"])
		var next: Dictionary = r["next"]
		var expected: Dictionary = run.events[at]
		assert_str(str(next.get("event", ""))).override_failure_message(
			"at event %d the readout names the wrong event" % [at]).is_equal(str(expected.get("event")))
		assert_int(int(next.get("round", -1))).override_failure_message(
			"at event %d the readout names the wrong round" % [at]).is_equal(int(expected.get("round")))
		checked += 1
		await driver.step()
	assert_int(checked).override_failure_message("fixture: the walk skipped events").is_equal(run.events.size())
	assert_bool((driver.report()["next"] as Dictionary).is_empty()).override_failure_message(
		"a finished replay still names a next event").is_true()


# THE PER-STEP VERDICT, against the end-only diff it replaced. The doctored hit must show up on the
# step that replays its pass and not before; and once the run ends, the list must be exactly what one
# end-of-run comparison over the same two logs produces -- nothing skipped, nothing counted twice.
func test_a_divergence_shows_at_the_step_that_made_it_and_the_list_matches_an_end_only_diff() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	var doctored := _doctor_first_hit(run)
	assert_int(doctored).override_failure_message("fixture: the run recorded no hit to doctor").is_greater_equal(0)
	assert_bool(driver.seed(run)).is_true()

	while int(driver.report()["at"]) < doctored:
		await driver.step()
	assert_array(driver.divergences).override_failure_message(
		"a divergence arrived before the doctored pass was replayed: %s" % [str(driver.divergences)]).is_empty()
	await driver.step()
	assert_bool(driver.is_finished()).override_failure_message(
		"fixture: the doctored pass is the last event, so this is not a mid-run verdict").is_false()
	assert_str(" | ".join(driver.divergences)).override_failure_message(
		"the step that replayed the doctored pass reported nothing about its damage: %s"
		% [str(driver.divergences)]).contains("damage")

	await driver.play()
	var end_only := _end_only(run)
	assert_int(end_only.size()).override_failure_message("fixture: the doctored run compares clean").is_greater(0)
	assert_bool(driver.divergences == end_only).override_failure_message(
		"per-step: %s\nend-only: %s" % [str(driver.divergences), str(end_only)]).is_true()


func test_run_to_next_divergence_stops_just_past_the_divergent_record() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	var doctored := _doctor_first_hit(run)
	assert_int(doctored).override_failure_message("fixture: the run recorded no hit to doctor").is_greater_equal(0)
	assert_int(doctored + 1).override_failure_message(
		"fixture: the doctored pass is the last event, so stopping there reads the same as running out"
		).is_less(run.events.size())
	assert_bool(driver.seed(run)).is_true()

	await driver.run_to_next_divergence()
	assert_int(int(driver.report()["at"])).override_failure_message(
		"it stopped somewhere other than just past the doctored pass (%d)" % [doctored]).is_equal(doctored + 1)
	assert_int(driver.divergences.size()).is_greater(0)
	assert_bool(driver.is_playing()).is_false()

	# With nothing further to find it runs out rather than stopping early or hanging.
	await driver.run_to_next_divergence()
	assert_bool(driver.is_finished()).is_true()


# THE LIST STOPS AT LIST_CAP AND THE STOP MUST NOT, or a heavily diverged run -- the one the button is
# reached for -- turns it into Play. The list is filled by hand: this mission cannot diverge forty
# times before its doctored pass.
func test_run_to_next_divergence_still_stops_once_the_list_is_full() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	var doctored := _doctor_first_hit(run)
	assert_int(doctored).override_failure_message("fixture: the run recorded no hit to doctor").is_greater_equal(0)
	assert_int(doctored + 1).override_failure_message(
		"fixture: the doctored pass is the last event, so stopping there reads the same as running out"
		).is_less(run.events.size())
	assert_bool(driver.seed(run)).is_true()
	for i in ReplayDriver.LIST_CAP:
		driver.divergences.append("filler %d" % [i])

	await driver.run_to_next_divergence()
	assert_int(driver.divergences.size()).override_failure_message(
		"fixture: the doctored line was listed, so the list was never full").is_equal(ReplayDriver.LIST_CAP)
	assert_int(int(driver.report()["at"])).override_failure_message(
		"a full list hid the divergence: it did not stop just past the doctored pass (%d)" % [doctored]
		).is_equal(doctored + 1)


# THE PAGE'S STEP: one event under the play guard, and the guard let go once it lands.
func test_step_once_lands_one_event_and_lets_go_of_the_play_guard() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	assert_int(run.events.size()).override_failure_message("fixture: a one-event run cannot tell one step from all").is_greater(1)
	assert_bool(driver.seed(run)).is_true()

	await driver.step_once()
	assert_int(int(driver.report()["at"])).is_equal(1)
	assert_bool(driver.is_playing()).is_false()


# THE COUNT IS KNOWN ONLY AT THE END, so it is the one check the per-step diff cannot make on the way.
# One extra recorded outcome past the last one the replay produces: every record that exists on both
# sides matches, and only the count can say anything.
func test_a_replay_one_record_short_of_the_run_says_so_at_the_end() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	var last: Dictionary = run.events[run.events.size() - 1]
	run.events.append(MissionLog.line(int(last.get("seq", 0)) + 1, int(last.get("t_ms", 0)),
		int(last.get("round", 1)), "zone_captured", {"zone": "nowhere"}))
	assert_bool(ReplayDriver.COMPARED.has("zone_captured")).override_failure_message(
		"fixture: the appended record is not an outcome the diff compares").is_true()
	assert_bool(driver.seed(run)).is_true()

	await driver.play()
	assert_int(driver.divergences.size()).override_failure_message(
		"expected the count line and nothing else: %s" % [str(driver.divergences)]).is_equal(1)


# THE FINISH IS ALWAYS DIFFED, even when its seal writes nothing -- here, a recorded ending this build
# does not know. The skip gate would otherwise pass it over and the page would read Clean.
func test_a_finish_whose_seal_writes_nothing_is_still_compared() -> void:
	var run_id := await _record_a_mission()
	var run := ReplayRun.load_run(run_id)
	var end := run.first("mission_end")
	assert_bool(end.is_empty()).override_failure_message("fixture: the run was never sealed").is_false()
	end["outcome"] = "NO_SUCH_ENDING"
	assert_bool(driver.seed(run)).is_true()

	await driver.play()
	assert_str(" | ".join(driver.notes)).override_failure_message(
		"fixture: the seal did not refuse the ending, so it wrote a record: %s" % [str(driver.notes)]
		).contains("NO_SUCH_ENDING")
	assert_int(driver.divergences.size()).override_failure_message(
		"the recorded mission_end was never compared -- the finish was skipped").is_greater(0)


# ==============================================================================
#  Fixture
# ==============================================================================

# A real mission, played: two units, a move, an attack, a resolved pass, a turn hand-over, sealed.
# Driven through the same doors a player uses, because a run assembled by hand would be a run this
# driver has never had to reproduce.
#
# `lethal` is the same mission with one number moved: a foe on 1 HP and a swing far past the
# overkill ceiling, so the enemy is FREED rather than downed. Every other case leaves it on 200,
# which is why the diff had never once been asked about a unit that is gone.
func _record_a_mission(lethal := false) -> String:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var foe := _spawn(Team.Faction.ENEMY, Vector2i(3, 0))
	hero.equipped_weapon = H.make_weapon(60 if lethal else 4)
	foe.unit_instance.stats[Stats.Stat.MHP] = 200
	foe.set_current_hp(1 if lethal else 200)
	if lethal:
		# A SECOND enemy, far away and never touched, because killing the ONLY one routs the board:
		# the mission ends, MissionEndBanner claims the ModalLock, and a Game node frozen behind it can
		# never finish the replay's first walk. A casualty is what this fixture is for; ending the
		# mission is not.
		var survivor := _spawn(Team.Faction.ENEMY, Vector2i(7, 3))
		survivor.unit_instance.stats[Stats.Stat.MHP] = 200
		survivor.set_current_hp(200)
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


# A mission whose one order is a WATCH, taken through the menu's own steps: pick the Overwatch row's
# attack, queue, execute. The weapon has the shipped Carbine's shape -- a fire main and a watch that
# is an extra -- which is the shape the fire-view lookup could not replay.
func _record_a_watch() -> String:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	_spawn(Team.Faction.ENEMY, Vector2i(5, 0))
	hero.add_item(_carbine_shaped_weapon())
	mc._begin_turn()
	var run_id: String = mission_log.run_id()

	hero.active_attack = hero.overwatch_attacks()[0]
	game.queue_overwatch(hero, Vector2i(1, 0))
	hero.active_attack = null
	var queued := false
	for action: BaseAction in hero.squad.action_queue:
		queued = queued or action.action_type == BaseAction.ActionType.OVERWATCH
	assert_bool(queued).override_failure_message("fixture: the watch never queued").is_true()
	await game.order_executor.execute_orders(hero)

	await game.end_turn()
	mission_log.seal(MissionLog.Ending.ABANDONED)
	return run_id


const REPLAY_PLATE := "Replay Test Plate"


# A mission whose one act is WEARING a plate, taken through the dock's own handler so MissionLog
# records it off the real signal.
func _record_a_wear() -> String:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	_spawn(Team.Faction.ENEMY, Vector2i(5, 0))
	var plate := ArmorData.new()
	plate.display_name = REPLAY_PLATE
	hero.add_item(plate)
	mc._begin_turn()
	var run_id: String = mission_log.run_id()

	game.unit_info_panel.set_unit(hero, true)
	game.unit_info_panel.inventory_panel._do_wear(hero.inventory.find(plate))
	assert_object(hero.worn_armor).override_failure_message("fixture: the dock never wore the plate").is_same(plate)

	await game.end_turn()
	mission_log.seal(MissionLog.Ending.ABANDONED)
	return run_id


func _player_unit() -> Unit:
	for live: Unit in game.units_root.get_children():
		if live.get_faction() == Team.Faction.PLAYER:
			return live
	return null


static func _carbine_shaped_weapon() -> WeaponInstance:
	var shot := WeaponAttackData.new()
	shot.display_name = "Shot"
	shot.power = 4
	var watch := WeaponAttackData.new()
	watch.display_name = "Watch"
	watch.power = 4
	watch.max_range = 2
	watch.can_overwatch = true
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = shot
	template.extra_attacks.assign([watch])
	return WeaponInstance.make(template)


# One recorded number moved: the first recorded hit's damage. Returns the index of the pass it sits
# in, or -1 when the run recorded no hit.
static func _doctor_first_hit(run: ReplayRun) -> int:
	for i in run.events.size():
		var e: Dictionary = run.events[i]
		if str(e.get("event", "")) != "pass":
			continue
		var hits: Array = e.get("hits", [])
		if hits.is_empty():
			continue
		var hit: Dictionary = hits[0]
		hit["damage"] = int(hit.get("damage", 0)) + 999
		return i
	return -1


# THE END-ONLY DIFF THE PER-STEP ONE REPLACED, as it stood, run once over the two finished logs on a
# scratch driver holding the same binding. The reference the per-step verdict has to reproduce.
func _end_only(run: ReplayRun) -> Array[String]:
	var ref := ReplayDriver.new()
	ref._live_id_of = driver._live_id_of
	var a := ref._outcomes(run.events, true)
	var b := ref._outcomes(mission_log.events(), false)
	if a.size() != b.size():
		ref.divergences.append("the replay produced %d outcome records where the run had %d" % [b.size(), a.size()])
	for i in mini(a.size(), b.size()):
		ref._diff_record(a[i], b[i], i)
	var out: Array[String] = ref.divergences.duplicate()
	ref.free()
	return out


static func _records_a_death(events: Array[Dictionary]) -> bool:
	for e: Dictionary in events:
		if str(e.get("event", "")) == "unit_died":
			return true
	return false


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


# THE RECORDED BOARD with one reference pointed at a file that is not there -- a moved .tres, which
# is what a run from another build looks like.
#
# EDITED IN PLACE, not in a copy: TelemetryStore writes the board with ResourceSaver.save and no
# FLAG_CHANGE_PATH, so the captured resource never claimed this path and is not in the resource cache
# under it. The next load therefore reads these bytes off disk.
func _break_a_reference_in_the_board(run_id: String) -> void:
	var path := TelemetryStore.run_dir(run_id) + ReplayRun.BOARD_FILE
	var kept: Array[String] = []
	var added := false
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("camera_start = "):
			continue   # whatever the recorded board held there, this fixture is taking it over
		kept.append(line)
		if line.begins_with("[ext_resource") and not added:
			kept.append('[ext_resource type="Resource" path="%s" id="99_gone"]' % GONE_POSE)
			added = true
	assert_bool(added).override_failure_message(
		"the recorded board has no ext_resource line to hang the dangling one beside").is_true()
	# [resource] is the LAST section in a .tres, so a property appended at EOF lands inside it.
	kept.append('camera_start = ExtResource("99_gone")')
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(kept) + "\n")
	f.close()

# RECURSIVE, and that is not tidiness: a run is a folder inside `pending/` inside the root, so a
# one-level sweep leaves `pending/` non-empty, its remove() fails SILENTLY, and every case inherits
# the last one's runs. Same shape as test_telemetry_store.gd and test_mission_log.gd.
static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir + sub + "/")
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + file)
	DirAccess.remove_absolute(dir)
