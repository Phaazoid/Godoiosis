extends RefCounted
# Frame persistence for the Play API bridge (#46): every rendered view is also written to
# playrun/frames/run-<stamp>/NNNN-<cmd>.txt, so a playtest is a replayable frame sequence.

var run_dir: String = ""
var _frame: int = 0

func _init(base_dir: String, stamp: String = "") -> void:
	if stamp == "":
		stamp = Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	run_dir = base_dir.path_join("run-" + stamp)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_dir))

# Mirrors the state.txt handshake header, plus the frame counter. Returns the frame path.
func record(id: int, ok: bool, cmd: String, text: String) -> String:
	_frame += 1
	var path := run_dir.path_join("%04d-%s.txt" % [_frame, _safe_name(cmd)])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[framelog] cannot open " + path)
		return ""
	f.store_string("@@ frame=%d id=%d ok=%d cmd=%s @@\n\n%s\n" % [_frame, id, (1 if ok else 0), cmd, text])
	f.close()
	return path

static func _safe_name(cmd: String) -> String:
	var out := ""
	for i in cmd.length():
		var c := cmd[i]
		var keep := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
		out += c if keep else "_"
	return out if out != "" else "cmd"
