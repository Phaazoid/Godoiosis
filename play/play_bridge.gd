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
		if c.has("id") and int(c.id) > _last_id:
			await _handle(int(c.id), str(c.get("cmd", "")), c.get("args", {}))

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
		"new":
			text = await _cmd_new()
		"load":
			text = await _cmd_load(str(args.get("path", "")))
		_:
			if _session == null:
				ok = false
				text = "no board - send {\"cmd\":\"new\"} or a load command first"
			else:
				var res := _dispatch(cmd, args)
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
		"join":
			var r = _session.join(str(args.get("unit", "")), str(args.get("leader", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_overview(_session)}
		"leave":
			var r = _session.leave(str(args.get("unit", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_overview(_session)}
		"disband":
			var r = _session.disband(str(args.get("unit", "")))
			return {"ok": r.ok, "text": _ack(r) + "\n\n" + BoardView.render_overview(_session)}
		"execute":
			var r = _session.execute()
			if not r.ok:
				return {"ok": false, "text": "> ERROR: " + str(r.error)}
			return {"ok": true, "text": BoardView.render_result(r.get("events", [])) + "\n\n" + BoardView.render_overview(_session)}
		"endturn":
			var r = _session.end_turn()
			return {"ok": true, "text": "Turn -> %s\n\n%s" % [str(r.faction), BoardView.render_overview(_session)]}
		_:
			return {"ok": false, "text": "unknown cmd: " + cmd}

func _cmd_new() -> String:
	_reset_board()
	_board = BoardBuilder.build(root, "PlayRoot_%d" % Time.get_ticks_msec())
	BoardBuilder.paint_rect(_board.grid, Rect2i(-1, -1, 10, 8))
	var p := BoardBuilder.spawn(_board, _mk("Vanguard", Team.Faction.PLAYER), Vector2i(0, 0))
	var e := BoardBuilder.spawn(_board, _mk("Raider", Team.Faction.ENEMY), Vector2i(5, 0))
	await process_frame
	_arm(p, 6)
	_arm(e, 4)
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
	f.store_string("@@ id=%d ok=%d cmd=%s @@\n\n%s\n" % [id, (1 if ok else 0), cmd, text])
	f.close()
	if _frames != null:
		_frames.record(id, ok, cmd, text)

# ---- helpers ----

func _xy(args: Dictionary) -> Vector2i:
	return Vector2i(int(args.get("x", 0)), int(args.get("y", 0)))

func _ack(r: Dictionary) -> String:
	return "> " + str(r.summary) if r.ok else "> ERROR: " + str(r.error)

func _mk(name: String, faction: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, faction)

func _arm(unit: Unit, power: int) -> void:
	var template := WeaponData.new()
	template.power = power   # scaling_blend defaults to pure STR — nothing else to set
	unit.add_item(WeaponInstance.make(template))
