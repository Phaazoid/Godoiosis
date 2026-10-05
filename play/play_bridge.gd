extends SceneTree
# Interactive file-bridge for the Play API (docs/play-api.md, #46 M3). A long-running
# headless host: it polls playrun/command.json (the driver writes it), runs the command
# through the M2 PlaySession, and writes the rendered text view back to playrun/state.txt
# with a monotonic `id` handshake. The driver writes a command, then reads state.txt until
# its `id` comes back. The SAME bridge can later be hosted by the live game (M4) so a human
# can watch. Every state write is also persisted to playrun/frames/run-<stamp>/ (numbered,
# one file per frame) so a playtest is auditable after the fact.
# Run:  <godot console exe> --headless --path . -s res://play/play_bridge.gd
#
# Protocol (command.json):  {"id": <int>, "cmd": "<name>", "args": { ... }}
#   new                          - build a small programmatic board
#   load   {"path": "res://..."} - load a saved scenario
#   overview | preview           - render the board / the active plan
#   focus  {"unit": "A"}         - render a unit's move/attack reach
#   ranges {"unit": "a"}         - where the enemy can strike or stand next turn, and who can hit each
#                                  of your units where its plan leaves it (the game's V key); "unit"
#                                  optional: omitted, every enemy
#   move   {"unit": "A", "x": 4, "y": 0}
#   group_move {"unit": "A", "x": 4, "y": 0} - A (a squad leader) moves and the squad follows in formation
#   attack {"unit": "A", "x": 5, "y": 0, "attack": "Splash"}   - "attack" optional (#615), as are
#                                 overwatch's and legal_targets'; omitted, the default fires
#   cancel {"unit": "A"}
#   rescue {"unit": "A", "target": "b", "x": 4, "y": 0}   - A picks up adjacent downed ally b (a main
#                                 action); x/y optional: the bank a body in deep water is hauled to (#116),
#                                 the first when omitted, with the reply naming the others
#   capture {"unit": "A"}                 - A claims the capture zone it will stand in (a main action)
#   join   {"unit": "B", "leader": "A"}   - B joins A's squad (squad-up / join)
#   leave  {"unit": "B"}                  - B leaves its squad (back to solo)
#   disband{"unit": "A"}                  - A (squad leader) disbands its squad
#   deploy {"unit": "F", "x": 4, "y": 0} | undeploy {"unit": "C"} | reposition {...} | begin
#                                - the pre-mission phase a roster mission opens on (#46)
#   give  {"from": "C", "slot": 0, "to": "stash"} - move gear; "stash" at either end
#   job   {"unit": "C", "job": "scout"}           - pick a job by id; "" for none
#   fit   {"unit": "C", "slot": 0, "mod": "Line Sniper", "space": 1} | unfit {unit, slot, mod}
#                                - "unit" may be "stash"; `slot` counts from 0, `space` from 1
#   kit   {"unit": "C"}          - a unit's slots, job and mods, or "stash"
#   equip | wear | use | toss {"unit": "C", "slot": 0} | unequip | remove_armor {"unit": "C"}
#                                - the inspect dock's verbs (#46), in either phase, for a unit on the board
#   restart                      - the loaded mission again, back in its pre-mission phase with the last
#                                  Begin's loadout; from inside the phase it is Reset Loadout (#46)
#   execute | endturn            - resolve+apply the plan / pass the turn
#   quit                         - shut the bridge down

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")
const FrameLog := preload("res://play/frame_log.gd")

const RUN_DIR := "res://playrun"
const CMD := "res://playrun/command.json"
const STATE := "res://playrun/state.txt"
const FRAMES_DIR := "res://playrun/frames"

var _session
var _board: Dictionary = {}
# The restart buffer (#46, #763): what the last Begin captured, kept across boards the way
# MissionController._staged survives reset(). Which loads replay it is PreMissionPhase's rule.
var _staged: PreMissionSnapshot = null
var _loaded_path := ""   # the mission `restart` reloads; "" on a `new` board
var _last_id := 0
var _quitting := false
var _frames   # FrameLog; every state write also lands as a numbered frame

func _initialize() -> void:
	Engine.max_fps = 30   # poll ~30x/s without pegging a core
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUN_DIR))
	if FileAccess.file_exists(CMD):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CMD))   # don't replay a stale command
	_frames = FrameLog.new(FRAMES_DIR)
	_write_state(0, true, "ready", "bridge ready - send {\"id\":1,\"cmd\":\"new\"} or {\"id\":1,\"cmd\":\"load\",\"args\":{\"path\":\"res://Scenarios/<name>.tres\"}}")
	print("[bridge] ready; polling ", CMD, "; frames -> ", _frames.run_dir)
	_poll_loop()

func _poll_loop() -> void:
	while not _quitting:
		await process_frame
		var c := _read_command()
		if not (c.has("id") and int(c.id) > _last_id):
			continue
		# BATCH: {"id": N, "cmds": [{"cmd": ..., "args": ...}, ...]} beside the single form.
		# One round trip instead of one per command, which for an agent driver costs more than the
		# bytes do -- each is a separate tool call (#613).
		if c.has("cmds") and c.cmds is Array:
			await _handle_batch(int(c.id), c.cmds as Array)
		else:
			await _handle(int(c.id), str(c.get("cmd", "")), c.get("args", {}))

# STOPS AT THE FIRST FAILURE, and that is the point rather than laziness: the logged runs show a
# refusal is almost always a wrong belief about the turn's state, so every command after it is
# built on the same wrong belief. Running them anyway turns one mistake into a compounding mess --
# which is exactly the pattern behind the 34 "no squad has queued orders" refusals.
func _handle_batch(id: int, cmds: Array) -> void:
	var parts: Array[String] = []
	var ok := true
	var last := "batch"
	for i in cmds.size():
		var entry = cmds[i]
		if not (entry is Dictionary):
			parts.append("[%d] > ERROR: not a command object" % i)
			ok = false
			break
		var one := entry as Dictionary
		last = str(one.get("cmd", ""))
		print("[bridge] id=%d [%d] cmd=%s" % [id, i, last])
		var res := await _run_one(last, one.get("args", {}))
		parts.append("[%d] %s\n%s" % [i, last, res.text])
		if not res.ok:
			ok = false
			if i < cmds.size() - 1:
				parts.append("> batch stopped at [%d]; %d command(s) not run" % [i, cmds.size() - 1 - i])
			break
	_write_state(id, ok, "batch:" + last, "\n\n".join(parts))
	_last_id = id


# The one place a command runs, so the single and batched forms cannot drift.
func _run_one(cmd: String, args) -> Dictionary:
	match cmd:
		"new":
			return {"ok": true, "text": await _cmd_new()}
		"load":
			return {"ok": true, "text": await _cmd_load(str((args as Dictionary).get("path", "")),
					bool((args as Dictionary).get("resume", false)))}
		"restart":
			return await _cmd_restart()
	if _session == null:
		return {"ok": false, "text": "no board - send {\"cmd\":\"new\"} or a load command first"}
	return _dispatch(cmd, args as Dictionary)


func _handle(id: int, cmd: String, args: Dictionary) -> void:
	print("[bridge] id=%d cmd=%s" % [id, cmd])
	var ok := true
	var text := ""
	match cmd:
		"quit":
			_write_state(id, true, cmd, "bridge shutting down")
			_last_id = id
			_quitting = true
			quit()
			return
		_:
			var res := await _run_one(cmd, args)
			ok = res.ok
			text = res.text
	_write_state(id, ok, cmd, text)
	_last_id = id

func _dispatch(cmd: String, args: Dictionary) -> Dictionary:
	match cmd:
		"overview":
			return {"ok": true, "text": BoardView.render_overview(_session)}
		"preview":
			return {"ok": true, "text": BoardView.render_preview(_session)}
		"focus":
			return {"ok": true, "text": BoardView.render_focus(_session, str(args.get("unit", "")))}
		# The two the doc promised and nothing implemented (#613). They cost a few hundred bytes
		# where the only previous way to ask was `focus`, which renders a 2 KB board to say it.
		"legal_moves":
			return {"ok": true, "text": BoardView.render_legal_moves(_session, str(args.get("unit", "")))}
		"legal_targets":
			return {"ok": true, "text": BoardView.render_legal_targets(_session, str(args.get("unit", "")), str(args.get("attack", "")))}
		"ranges":
			return {"ok": true, "text": BoardView.render_ranges(_session, str(args.get("unit", "")))}
		"move":
			var r = _session.queue_move(str(args.get("unit", "")), _xy(args))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"group_move":
			var r = _session.group_move(str(args.get("unit", "")), _xy(args))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"attack":
			var r = _session.queue_attack(str(args.get("unit", "")), _xy(args), str(args.get("attack", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"cancel":
			var r = _session.cancel(str(args.get("unit", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"rescue":
			var r = _session.rescue(str(args.get("unit", "")), str(args.get("target", "")), _optional_xy(args))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"capture":
			var r = _session.capture(str(args.get("unit", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		# The squad verbs used to redraw the whole board to report a one-line change. What they
		# actually changed -- which squads exist and which are spent -- is what the status line on
		# every frame now says, so the picture is a separate `overview` when it is wanted.
		"join":
			var r = _session.join(str(args.get("unit", "")), str(args.get("leader", "")))
			return {"ok": r.ok, "text": _ack(r)}
		"leave":
			var r = _session.leave(str(args.get("unit", "")))
			return {"ok": r.ok, "text": _ack(r)}
		"disband":
			var r = _session.disband(str(args.get("unit", "")))
			return {"ok": r.ok, "text": _ack(r)}
		# The pre-mission phase (#46): the loadout screen's placement decisions, then its Begin.
		"deploy":
			var r = _session.deploy(str(args.get("unit", "")), _xy(args))
			return {"ok": r.ok, "text": _ack(r)}
		"undeploy":
			var r = _session.undeploy(str(args.get("unit", "")))
			return {"ok": r.ok, "text": _ack(r)}
		"reposition":
			var r = _session.reposition(str(args.get("unit", "")), _xy(args))
			return {"ok": r.ok, "text": _ack(r)}
		"begin":
			var r = _session.begin()
			if r.ok:
				_staged = _session.staged   # the buffer outlives this board, as the game's does
			return {"ok": r.ok, "text": _ack(r)}
		# ...and its writes (#46 slice 2a): gear, jobs and mods, read back through `kit`.
		"give":
			var r = _session.give(str(args.get("from", "")), int(args.get("slot", -1)), str(args.get("to", "")))
			return {"ok": r.ok, "text": _ack(r)}
		"job":
			var r = _session.set_job(str(args.get("unit", "")), str(args.get("job", "")))
			return {"ok": r.ok, "text": _ack(r)}
		"fit":
			var r = _session.fit(str(args.get("unit", "")), int(args.get("slot", -1)),
					str(args.get("mod", "")), int(args.get("space", 0)))
			return {"ok": r.ok, "text": _ack(r)}
		"unfit":
			var r = _session.unfit(str(args.get("unit", "")), int(args.get("slot", -1)), str(args.get("mod", "")))
			return {"ok": r.ok, "text": _ack(r)}
		"kit":
			return {"ok": true, "text": BoardView.render_kit(_session, str(args.get("unit", "")))}
		# The inspect dock's six verbs (#46 slice 2b), named as a run records them, in either phase.
		# With a plan open, the reply carries its preview: a gear change re-resolves it.
		"equip", "unequip", "wear", "remove_armor", "use", "toss":
			var r = _session.gear(str(args.get("unit", "")), cmd, int(args.get("slot", -1)))
			var text: String = _ack(r)
			if r.ok and _session.squad_manager.active_squad != null:
				text += "\n\n" + BoardView.render_preview(_session)
			return {"ok": r.ok, "text": text}
		# The six verbs PlaySession has always implemented and _dispatch never exposed -- which is
		# why a driver asking for `burrow` got `unknown cmd` for a verb the docs list (#613).
		"guard":
			var r = _session.guard(str(args.get("unit", "")), str(args.get("target", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"overwatch":
			var r = _session.overwatch(str(args.get("unit", "")), _xy(args), str(args.get("attack", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"reload":
			var r = _session.reload(str(args.get("unit", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"rev":
			var r = _session.rev(str(args.get("unit", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"burrow":
			var r = _session.burrow(str(args.get("unit", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"execute":
			var r = _session.execute()
			if not r.ok:
				return {"ok": false, "text": "> ERROR: " + str(r.error)}
			# The event log IS the payload of a pass; the board picture that used to follow it was
			# 45% of all output and repeated terrain nothing had changed (#613).
			return {"ok": true, "text": BoardView.render_result(r.get("events", []))}
		"endturn":
			var r = _session.end_turn()
			if not r.ok:
				return {"ok": false, "text": "> " + str(r.error)}
			# WHAT THE OPPONENT DID (#664/#665). #613 stopped redrawing the board here, and the
			# measured consequence was drivers buying a 3 KB overview after every hand-off -- the
			# pre-registered guard caught it at 1.12 overviews per execute. The cause was not the
			# missing picture: it was that an AI turn mutated the board and said nothing, so there
			# was no way to learn what happened except to look at everything.
			#
			# The answer is the one `execute` already proved sufficient -- an EVENT LOG. Across
			# both treated runs, zero batches called `overview` after an execute, because the log
			# accounts for the pass. The same account, for the enemy's pass, costs a few hundred
			# bytes against a board redraw.
			var moves: Array = r.get("ai_events", [])
			if moves.is_empty():
				return {"ok": true, "text": "Turn -> %s\n  (nothing happened)" % str(r.faction)}
			return {"ok": true, "text": "Turn -> %s\n%s"
					% [str(r.faction), BoardView.render_result(moves)]}
		_:
			return {"ok": false, "text": "unknown cmd: " + cmd}

func _cmd_new() -> String:
	_reset_board()
	_board = BoardBuilder.build(root, "PlayRoot_%d" % Time.get_ticks_msec())
	BoardBuilder.paint_rect(_board.grid, Rect2i(-1, -1, 10, 8))
	var p := BoardBuilder.spawn(_board, _mk("Vanguard", Team.Faction.PLAYER), Vector2i(0, 0))
	var e := BoardBuilder.spawn(_board, _mk("Raider", Team.Faction.ENEMY), Vector2i(5, 0))
	await process_frame
	BoardBuilder.arm(p, 6)
	BoardBuilder.arm(e, 4)
	_session = PlaySession.new(_board)
	_loaded_path = ""   # nothing on disk to reload
	return "New board (2 units)\n\n" + BoardView.render_overview(_session)

# A load is a mission STARTING, the game's fresh-start door, so a board naming a roster opens the
# pre-mission phase (#46). `resume` is the other door: a mid-battle snapshot records `roster` too, and
# drawing it would stand a second force on top of the one the snapshot restored.
#
# Like begin_mission, it replays the last Begin's loadout when that was taken on THIS mission (#763
# ruling 1, PreMissionPhase.replay_for), and says so.
func _cmd_load(path: String, resume := false) -> String:
	if path == "":
		return "load needs a path, e.g. {\"cmd\":\"load\",\"args\":{\"path\":\"res://Scenarios/Castle Assault.tres\"}}"
	_reset_board()
	_board = BoardBuilder.build(root, "PlayRoot_%d" % Time.get_ticks_msec())
	var loaded: Array = await BoardBuilder.load_scenario(_board, path)
	_session = PlaySession.new(_board)
	_loaded_path = path
	var replay: PreMissionSnapshot = null if resume else PreMissionPhase.replay_for(_staged, path)
	var drawn: int = 0 if resume else _session.start_pre_mission(replay)
	await process_frame   # the drawn units' _ready, as load_scenario waits for its own spawns
	var head := "Loaded %s (%d units)" % [path, loaded.size()]
	if drawn > 0:
		head += "; pre-mission: %d of the roster stood up" % drawn
		var roster: Array[Unit] = _session.roster_units()
		if replay != null and replay.fits(roster):
			head += " -- your last loadout for this mission stands again"
	return "%s\n\n%s" % [head, BoardView.render_overview(_session)]

# The game's Restart (#763): the same mission again, back in its pre-mission phase. Taken from inside
# the phase it is Reset Loadout and drops the buffer; otherwise the last Begin's loadout replays.
# Asked BEFORE the reload, while the session still knows it was in the phase (PreMissionPhase.kept_by_restart).
func _cmd_restart() -> Dictionary:
	if _session == null or _loaded_path == "":
		return {"ok": false, "text": "restart reloads a loaded mission -- load one first"}
	var from_inside_phase: bool = _session.is_deploying()
	_staged = PreMissionPhase.kept_by_restart(_staged, from_inside_phase)
	var text := await _cmd_load(_loaded_path)
	var kind := "Reset Loadout -- the mission's own draw" if from_inside_phase else "Restarted"
	return {"ok": true, "text": "%s\n%s" % [kind, text]}

func _reset_board() -> void:
	if _board.has("root") and is_instance_valid(_board.root):
		_board.root.queue_free()
	_session = null

# ---- io ----

func _read_command() -> Dictionary:
	if not FileAccess.file_exists(CMD):
		return {}
	var f := FileAccess.open(CMD, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}

func _write_state(id: int, ok: bool, cmd: String, text: String) -> void:
	var f := FileAccess.open(STATE, FileAccess.WRITE)
	if f == null:
		push_error("[bridge] cannot open state file")
		return
	# The status line rides EVERY frame, failures included -- a refusal is precisely when the caller
	# needs to know whose turn it is, which squad holds the activation and what is already spent.
	# Written here rather than per dispatch arm so no arm can forget it (#613).
	# Composed ONCE and used for both sinks: the frame log is the record of what the caller was
	# shown, so a status line the log did not carry would make every byte measurement over
	# playrun/frames/ a measurement of something nobody read.
	var body := BoardView.render_status(_session) + "\n\n" + text
	f.store_string("@@ id=%d ok=%d cmd=%s @@\n\n%s\n" % [id, (1 if ok else 0), cmd, body])
	f.close()
	if _frames != null:
		_frames.record(id, ok, cmd, body)

# ---- helpers ----

func _xy(args: Dictionary) -> Vector2i:
	return Vector2i(int(args.get("x", 0)), int(args.get("y", 0)))

# The cell a command names, or null when it names none: _xy reads a missing x/y as (0,0), a real cell.
func _optional_xy(args: Dictionary) -> Variant:
	if not args.has("x"):
		return null
	return _xy(args)

func _ack(r: Dictionary) -> String:
	return "> " + str(r.summary) if r.ok else "> ERROR: " + str(r.error)

func _mk(name: String, faction: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, faction)

