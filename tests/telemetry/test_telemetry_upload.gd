# SHIPPING A RUN (#53 slice 5). What this suite can hold is the PAYLOAD and the FOLDER MOVE; what
# it structurally cannot hold is the POST, because `is_configured()` refuses a headless run by
# design -- exactly #131's position, where no case has ever driven `submit()` end to end either.
#
# THE FIRST CASE IS A SAFETY PROPERTY, NOT A UNIT TEST. `ENDPOINT` is a live Worker in the
# committed source, so without the headless refusal every green suite run would POST a playtest run
# into the intake, and the first anyone would know is D1 filling with test fixtures.
#
# `requests` EXISTS FOR THIS SUITE and says so at its declaration: everything past that refusal is
# invisible here, so a mutant deleting the run_sealed connection would pass a suite that asserted
# on anything else. The counter is bumped ahead of the gate, which is what gives the wire teeth.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const SCRATCH_ROOT := "user://__telemetry_upload_test/"

var _main: Node
var game: Node2D
var mc: MissionController
var mission_log: MissionLog
var uploader: TelemetryUploader
var _fixture_hero: Unit   # the player unit _record_an_empty_mission spawned, for a case that adds one order


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
	uploader = game.telemetry_uploader
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
#  The safety property
# ==============================================================================

func test_a_headless_run_never_uploads() -> void:
	# Falsify by deleting the headless check in Uploader.is_configured(): this goes red, and in the
	# version that ships it would instead POST a run to the live intake for every case that seals
	# one. The premise assertion stops it going vacuous if ENDPOINT is ever blanked.
	assert_str(Uploader.ENDPOINT).is_not_equal("")
	assert_bool(uploader.is_configured()).is_false()

	var run_id := await _record_and_seal(MissionLog.Ending.VICTORY)
	assert_int(await uploader.send_pending()).is_equal(0)
	assert_bool(TelemetryStore.is_sent(run_id)).override_failure_message(
		"a headless run moved a folder, so it believed it had sent something").is_false()


# ==============================================================================
#  The payload
# ==============================================================================

func test_a_sealed_run_becomes_a_payload_carrying_summary_events_and_board() -> void:
	var run_id := await _record_and_seal(MissionLog.Ending.VICTORY)
	var payload := uploader.build_payload(run_id)
	assert_bool(payload.is_empty()).override_failure_message(
		"a sealed run built no payload").is_false()

	var fields: Dictionary = payload["fields"]
	assert_bool(fields.has("summary")).is_true()
	assert_array(_filenames(payload)).contains(
		[TelemetryStore.EVENTS_FILE, TelemetryStore.BOARD_FILE])


# BYTE-IDENTICAL, `MultipartForm`'s own binary case being the precedent. The events log is the
# AUTHORITY -- the summary is only a cache of what it says -- so anything that re-encodes it on the
# way out has quietly made the cache the authority.
func test_the_events_part_is_byte_identical_to_the_file() -> void:
	var run_id := await _record_and_seal(MissionLog.Ending.VICTORY)
	var payload := uploader.build_payload(run_id)
	var on_disk := FileAccess.get_file_as_bytes(TelemetryStore.events_path(run_id))
	assert_int(on_disk.size()).override_failure_message("fixture: nothing on disk").is_greater(0)

	var sent := PackedByteArray()
	for file: Dictionary in payload["files"]:
		if file["filename"] == TelemetryStore.EVENTS_FILE:
			sent = file["bytes"]
	assert_array(Array(sent)).override_failure_message(
		"the events part is not what the file holds").is_equal(Array(on_disk))


# The summary travels as the run's own LINE, raw. JSON has one number type, so JSON.stringify of
# the parsed line would turn every int in it back into a float (#53 slice 4b's rule) -- and this is
# the one part the intake parses, so a float `rounds` would land in every indexed column.
func test_the_summary_field_is_the_line_from_the_file_verbatim() -> void:
	var run_id := await _record_and_seal(MissionLog.Ending.VICTORY)
	var payload := uploader.build_payload(run_id)
	var sent := str((payload["fields"] as Dictionary)["summary"])

	var found := ""
	for raw: String in _read_lines(run_id):
		if raw.contains("\"event\":\"summary\"") or raw.contains("\"event\": \"summary\""):
			found = raw
	assert_str(found).override_failure_message("fixture: no summary line on disk").is_not_equal("")
	assert_str(sent).override_failure_message(
		"the summary was re-encoded on the way out").is_equal(found)


func test_the_summary_carries_the_run_install_and_session_ids() -> void:
	var run_id := await _record_and_seal(MissionLog.Ending.VICTORY)
	var summary := _summary_of(run_id)
	assert_str(str(summary.get("run_id", ""))).override_failure_message(
		"the intake keys on run_id -- a row without one cannot be stored").is_equal(run_id)
	assert_str(str(summary.get("install_id", ""))).is_not_equal("")
	assert_str(str(summary.get("session_id", ""))).is_not_equal("")


func test_an_unsealed_run_is_not_sent() -> void:
	var run_id := await _record_a_mission()
	_drop_the_handle()
	assert_bool(uploader.build_payload(run_id).is_empty()).override_failure_message(
		"a run with no summary was shipped -- the launch sweep has not finished it yet").is_true()


# A run recorded before this slice has no id in its summary, and SQLite would accept NULL in a TEXT
# PRIMARY KEY and treat every NULL as distinct -- so each old run would land as its own garbage row.
func test_a_run_whose_summary_predates_the_id_field_is_not_sent() -> void:
	var run_id := await _record_and_seal(MissionLog.Ending.VICTORY)
	var lines := _read_lines(run_id)
	var rewritten := PackedStringArray()
	for raw: String in lines:
		rewritten.append(raw.replace("\"run_id\":\"%s\"" % run_id, "\"run_id\":\"\""))
	assert_bool(TelemetryStore.rewrite_run_events(run_id, rewritten)).is_true()

	assert_bool(uploader.build_payload(run_id).is_empty()).override_failure_message(
		"a run with no id in its summary was shipped").is_true()


func test_a_run_over_the_payload_cap_is_not_sent() -> void:
	var run_id := await _record_and_seal(MissionLog.Ending.VICTORY)
	var lines := _read_lines(run_id)
	# One absurd line, so the run clears the cap without needing a real half-hour mission.
	lines.append('{"seq":9999,"t_ms":0,"round":1,"event":"pad","pad":"%s"}' % "x".repeat(
		TelemetryUploader.MAX_PAYLOAD_BYTES))
	assert_bool(TelemetryStore.rewrite_run_events(run_id, lines)).is_true()

	assert_bool(uploader.build_payload(run_id).is_empty()).override_failure_message(
		"a run over the D1 row limit was shipped -- the intake would refuse it forever").is_true()


# ==============================================================================
#  The empty run (#851)
# ==============================================================================
#
# THE REFUSAL IS TWO CONDITIONS AND EVERY CASE HERE PINS ONE HALF OF IT: nothing happened, AND
# somebody chose to end it. The CRASHED case is the one that matters most -- "zero passes" is also
# exactly what a crash on turn one looks like, and refusing on emptiness alone would silently eat
# the best data this intake will ever get.
#
# EVERY CASE ASSERTS ITS PRECONDITION FIRST, because build_payload answers {} for five different
# reasons (unsealed, no run_id, empty, no files, over cap) and a case that only reads the {} cannot
# tell which one it caught.

func test_an_empty_run_that_was_deliberately_abandoned_is_not_sent() -> void:
	var run_id := await _record_an_empty_mission()
	mission_log.seal(MissionLog.Ending.ABANDONED)
	_assert_recorded_but_empty(run_id)

	assert_bool(uploader.build_payload(run_id).is_empty()).override_failure_message(
		"a run in which nothing happened, abandoned on purpose, was shipped").is_true()


# INTERRUPTED is the MAIN door out, not an edge case: MissionController.reset() is the universal
# teardown behind F2, a board swap, Load Game and Mission Select. Driven through that door rather
# than by sealing by hand, because the point of the case is that the ordinary way of leaving a
# board is covered -- and it was measured: two of the three rows in the live intake when this was
# written were empty INTERRUPTED runs.
func test_an_empty_run_the_board_teardown_interrupted_is_not_sent() -> void:
	var run_id := await _record_an_empty_mission()
	mc.reset()
	_assert_recorded_but_empty(run_id)
	assert_str(str(_summary_of(run_id).get("outcome", ""))).override_failure_message(
		"fixture: reset() no longer seals INTERRUPTED, so this case is testing nothing").is_equal(
		"INTERRUPTED")

	assert_bool(uploader.build_payload(run_id).is_empty()).override_failure_message(
		"a board opened and backed out of was shipped").is_true()


# THE CASE THE WHOLE RULE IS SHAPED AROUND. A CRASHED run is swept -- nobody chose it -- so its
# emptiness IS the finding: the game died before the player could act. Refusing on "no passes"
# alone would drop exactly this.
func test_an_empty_run_that_crashed_is_still_sent() -> void:
	var run_id := await _record_an_empty_mission()
	mission_log.seal(MissionLog.Ending.CRASHED)
	_assert_recorded_but_empty(run_id)

	var payload := uploader.build_payload(run_id)
	assert_bool(payload.is_empty()).override_failure_message(
		"a crash before the player could act was refused -- that emptiness is the finding").is_false()
	assert_array(_filenames(payload)).contains([TelemetryStore.EVENTS_FILE])


# An order the player queued and took back is CONTENT: they expressed an intent, and a `pass` is
# not the only place a decision shows up. So orders_queued is checked beside passes, and this run
# has one order and no resolved pass.
func test_a_run_with_a_queued_order_and_no_pass_is_not_empty() -> void:
	var run_id := await _record_an_empty_mission()
	assert_bool(game.squad_manager.queue_action(_fixture_hero.squad, _build_move(_fixture_hero, Vector2i(2, 0)))
		).override_failure_message("fixture: the move never queued").is_true()
	mission_log.seal(MissionLog.Ending.QUIT)

	var summary := _summary_of(run_id)
	assert_int(int(summary.get("passes", -1))).override_failure_message(
		"fixture: a pass resolved, so this is not the queued-order-only case").is_equal(0)
	assert_int(int(summary.get("orders_queued", 0))).override_failure_message(
		"fixture: the order never reached the record").is_greater(0)

	assert_bool(uploader.build_payload(run_id).is_empty()).override_failure_message(
		"a run carrying a player's queued order was refused as empty").is_false()


# ==============================================================================
#  pending/ and sent/
# ==============================================================================

func test_marking_a_run_sent_moves_the_folder_and_the_replay_tab_still_finds_it() -> void:
	var run_id := await _record_and_seal(MissionLog.Ending.VICTORY)
	assert_array(Array(TelemetryStore.pending_runs())).contains([run_id])

	assert_bool(TelemetryStore.mark_sent(run_id)).is_true()

	assert_array(Array(TelemetryStore.pending_runs())).override_failure_message(
		"the run is still owed to the server after it landed").not_contains([run_id])
	assert_array(Array(TelemetryStore.sent_runs())).contains([run_id])
	# The whole point of keeping it: the dev Replay tab reads BOTH folders.
	assert_array(Array(ReplayRun.list_runs())).override_failure_message(
		"a sent run vanished from the replay list").contains([run_id])
	assert_bool(bool(ReplayRun.load_run(run_id).headline().get("sent", false))).is_true()


func test_run_dir_resolves_a_run_that_has_moved_to_sent() -> void:
	var run_id := await _record_and_seal(MissionLog.Ending.VICTORY)
	assert_bool(TelemetryStore.mark_sent(run_id)).is_true()

	assert_str(TelemetryStore.run_dir(run_id)).is_equal(TelemetryStore.sent_dir() + run_id + "/")
	var run := ReplayRun.load_run(run_id)
	assert_bool(run.can_replay()).override_failure_message(
		"a sent run cannot be replayed: %s" % str(run.problems)).is_true()


func test_a_brand_new_run_id_resolves_to_pending() -> void:
	assert_str(TelemetryStore.run_dir("never_seen")).is_equal(
		TelemetryStore.pending_dir() + "never_seen/")


# ==============================================================================
#  The wire
# ==============================================================================

# DRIVEN FROM A REAL SEAL, never by emitting the signal -- a signal with no listeners is legal
# GDScript (#103's thirteen-month gap). `requests` is the only thing about send_pending a headless
# suite can see, which is why it exists.
func test_sealing_a_run_asks_the_uploader_to_send() -> void:
	var before := uploader.requests
	var _run_id := await _record_and_seal(MissionLog.Ending.VICTORY)
	assert_int(uploader.requests).override_failure_message(
		"nothing asked the uploader to send -- the run_sealed wire is not connected"
		).is_equal(before + 1)


# The replay driver re-records through this same recorder with record_to_disk false. An ungated
# emit would make a dev replay session a network trigger, and there is no file to send anyway.
func test_a_run_with_no_file_asks_for_nothing() -> void:
	var _hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	mission_log.begin(false)
	var before := uploader.requests
	mission_log.seal(MissionLog.Ending.VICTORY)
	assert_int(uploader.requests).override_failure_message(
		"an in-memory replay asked for an upload").is_equal(before)


# game.gd's QUIT arm calls get_tree().quit() on the next line, so a request started here is at best
# wasted and at worst holds shutdown until its timeout. The next launch's sweep sends it.
func test_a_quit_seal_asks_for_nothing() -> void:
	var _run_id := await _record_a_mission()
	var before := uploader.requests
	mission_log.seal(MissionLog.Ending.QUIT)
	assert_int(uploader.requests).override_failure_message(
		"quitting started an upload the process will not live to finish").is_equal(before)


# MissionController seals BEFORE the end banner draws, and the banner claims the ModalLock, which
# DISABLES the Game subtree this node lives under. #131's "Sending... forever" trap, one tenant over.
func test_the_uploader_outlives_the_freeze_it_runs_behind() -> void:
	assert_int(uploader.process_mode).override_failure_message(
		"a subclass _ready that forgets super() leaves the upload frozen behind the end banner"
		).is_equal(Node.PROCESS_MODE_ALWAYS)


# ==============================================================================
#  Fixture
# ==============================================================================

# A RUN IN WHICH NOTHING HAPPENED -- the board is armed and the recorder is open, and then the
# fixture simply stops. Deliberately not _record_a_mission minus a line: what makes a run empty is
# that no pass ever resolved and no order was ever given, so the helper that produces one must not
# be able to drift into queueing something. `_fixture_hero` is kept so a case can add one order back.
func _record_an_empty_mission() -> String:
	_fixture_hero = _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	_fixture_hero.equipped_weapon = H.make_weapon(4)
	var foe := _spawn(Team.Faction.ENEMY, Vector2i(3, 0))
	foe.unit_instance.stats[Stats.Stat.MHP] = 200
	foe.set_current_hp(200)
	mc._begin_turn()
	await await_idle_frame()
	return mission_log.run_id()


# The precondition every #851 case shares, asserted rather than assumed: the run really is on disk,
# really carries an id, and really has nothing in it. Without this a case reads {} and cannot tell
# the refusal it is testing from the four other reasons build_payload answers {}.
func _assert_recorded_but_empty(run_id: String) -> void:
	assert_bool(FileAccess.file_exists(TelemetryStore.events_path(run_id))).override_failure_message(
		"fixture: nothing was written to disk").is_true()
	var summary := _summary_of(run_id)
	assert_str(str(summary.get("run_id", ""))).override_failure_message(
		"fixture: no run_id, so the payload would be refused for THAT reason instead").is_not_empty()
	assert_int(int(summary.get("passes", -1))).override_failure_message(
		"fixture: a pass resolved, so this run is not empty").is_equal(0)
	assert_int(int(summary.get("orders_queued", -1))).override_failure_message(
		"fixture: an order was queued, so this run is not empty").is_equal(0)


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
	await game.end_turn()
	return run_id


func _record_and_seal(ending: MissionLog.Ending) -> String:
	var run_id := await _record_a_mission()
	mission_log.seal(ending)
	assert_bool(FileAccess.file_exists(TelemetryStore.events_path(run_id))).override_failure_message(
		"fixture: nothing was written to disk").is_true()
	return run_id


# The process dies: no public door by construction, so the two fields a kill takes are dropped by
# hand (#53 slice 4b's fixture, same reason).
func _drop_the_handle() -> void:
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


func _filenames(payload: Dictionary) -> Array:
	var out: Array = []
	for file: Dictionary in payload["files"]:
		out.append(str(file["filename"]))
	return out


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


func _summary_of(run_id: String) -> Dictionary:
	return ReplayRun.load_events(run_id).first("summary").get("summary", {})


func _wipe() -> void:
	_wipe_dir(SCRATCH_ROOT)


# Recursive: a run is <root>/<pending|sent>/<id>/, and DirAccess.remove fails SILENTLY on a
# non-empty folder, so a shallow sweep hands every case the last one's runs (#846).
func _wipe_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_wipe_dir(path + sub + "/")
		dir.remove(sub)
	for file: String in dir.get_files():
		dir.remove(file)
