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
#   move   {"unit": "A", "x": 4, "y": 0}
#   attack {"unit": "A", "x": 5, "y": 0}
#   cancel {"unit": "A"}
#   rescue {"unit": "A", "target": "b"}   - A picks up adjacent downed ally b (a main action)
#   join   {"unit": "B", "leader": "A"}   - B joins A's squad (squad-up / join)
#   leave  {"unit": "B"}                  - B leaves its squad (back to solo)
#   disband{"unit": "A"}                  - A (squad leader) disbands its squad
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
			return {"ok": true, "text": await _cmd_load(str((args as Dictionary).get("path", "")))}
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
			return {"ok": true, "text": BoardView.render_legal_targets(_session, str(args.get("unit", "")))}
		"move":
			var r = _session.queue_move(str(args.get("unit", "")), _xy(args))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"attack":
			var r = _session.queue_attack(str(args.get("unit", "")), _xy(args))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"cancel":
			var r = _session.cancel(str(args.get("unit", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"rescue":
			var r = _session.rescue(str(args.get("unit", "")), str(args.get("target", "")))
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
		# The six verbs PlaySession has always implemented and _dispatch never exposed -- which is
		# why a driver asking for `burrow` got `unknown cmd` for a verb the docs list (#613).
		"guard":
			var r = _session.guard(str(args.get("unit", "")), str(args.get("target", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"overwatch":
			var r = _session.overwatch(str(args.get("unit", "")), _xy(args))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_preview(_session)}
		"rally":
			var r = _session.rally(str(args.get("unit", "")))
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
	return "New board (2 units)\n\n" + BoardView.render_overview(_session)

func _cmd_load(path: String) -> String:
	if path == "":
		return "load needs a path, e.g. {\"cmd\":\"load\",\"args\":{\"path\":\"res://Scenarios/Castle Assault.tres\"}}"
	_reset_board()
	_board = BoardBuilder.build(root, "PlayRoot_%d" % Time.get_ticks_msec())
	var loaded: Array = await BoardBuilder.load_scenario(_board, path)
	_session = PlaySession.new(_board)
	return "Loaded %s (%d units)\n\n%s" % [path, loaded.size(), BoardView.render_overview(_session)]

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

func _ack(r: Dictionary) -> String:
	return "> " + str(r.summary) if r.ok else "> ERROR: " + str(r.error)

func _mk(name: String, faction: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, faction)

