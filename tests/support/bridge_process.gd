# The REAL Play API bridge (play/play_bridge.gd), booted in a child process on a scratch run dir and
# driven as a driver drives it: write command.json, then read state.txt until the id comes back
# (#1602). The bridge owns its process and polls a file, so this is the only seam a suite has to its
# poll loop. `--run-dir` keeps it off any playtest's playrun/ in the same checkout.
extends RefCounted

const BRIDGE := "res://play/play_bridge.gd"
const ROOT_PREFIX := "user://test_play_bridge"   # the only dirs this may delete
const BOOT_MS := 60000
const REPLY_MS := 20000
const POLL_MS := 30

var run_dir: String
var pid := -1
# Once one reply never comes, every later send fails at once, so a red run costs one timeout, not one
# per remaining command.
var stopped := ""


func _init(dir: String) -> void:
	assert(dir.begins_with(ROOT_PREFIX), "a bridge run dir must live under %s" % ROOT_PREFIX)
	run_dir = dir


# True once the bridge has written its ready frame (id 0).
func open() -> bool:
	_remove_tree(run_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_dir))
	var args := PackedStringArray(["--headless", "--audio-driver", "Dummy",
			"--path", ProjectSettings.globalize_path("res://"), "-s", BRIDGE, "--", "--run-dir=" + run_dir])
	pid = OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		stopped = "the bridge process did not start"
		return false
	var ready := await _await_reply(0, BOOT_MS)
	if ready == "":
		stopped = "the bridge never wrote its ready frame"
	return ready != ""


# Writes one raw command line and waits for the frame answering `id`:
# {"answered": bool, "ok": bool, "text": String}.
func send(id: int, raw: String) -> Dictionary:
	if stopped != "":
		return {"answered": false, "ok": false, "text": stopped}
	write(raw)
	var frame := await _await_reply(id, REPLY_MS)
	if frame == "":
		stopped = "the bridge stopped answering at id=%d (%s); its last frame:\n%s" % [id, raw, state()]
		return {"answered": false, "ok": false, "text": stopped}
	return {"answered": true, "ok": frame.contains("@@ id=%d ok=1 " % id), "text": frame}


# Writes a command without waiting for anything.
func write(raw: String) -> void:
	var f := FileAccess.open(run_dir.path_join("command.json"), FileAccess.WRITE)
	f.store_string(raw)
	f.close()


func state() -> String:
	var path := run_dir.path_join("state.txt")
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


# Real time passing with frames still turning: gdUnit's await_millis hangs a paused tree.
func idle(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await (Engine.get_main_loop() as SceneTree).process_frame


func close() -> void:
	if pid > 0 and OS.is_process_running(pid):
		write('{"id":%d,"cmd":"quit"}' % 2147483647)
		var until := Time.get_ticks_msec() + 5000
		while OS.is_process_running(pid) and Time.get_ticks_msec() < until:
			await (Engine.get_main_loop() as SceneTree).process_frame
		if OS.is_process_running(pid):
			OS.kill(pid)
	pid = -1
	_remove_tree(run_dir)


# The frame answering `id`, once two reads a poll apart agree (a read can land mid-write), or "".
func _await_reply(id: int, budget_ms: int) -> String:
	var header := "@@ id=%d " % id
	var until := Time.get_ticks_msec() + budget_ms
	var last := ""
	while Time.get_ticks_msec() < until:
		await idle(POLL_MS)
		var now := state()
		if now.begins_with(header) and now == last:
			return now
		last = now
	return ""


static func _remove_tree(path: String) -> void:
	if not path.begins_with(ROOT_PREFIX):
		return
	var abs := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for sub in DirAccess.get_directories_at(abs):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file))
	DirAccess.remove_absolute(abs)
