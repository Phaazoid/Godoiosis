extends RefCounted
class_name ReplayRun

# ONE RECORDED RUN, READ BACK (#53 slice 4). The write half is MissionLog + TelemetryStore; this is
# the only thing in the project that reads a run folder, and it is deliberately DUMB DATA -- it
# parses and hands over, and knows nothing about replaying. ReplayDriver owns that.
#
# A run is a FOLDER: `events.jsonl` (one JSON object per line, flushed as the battle went) beside
# `board.tres` (the ScenarioData the battle started from). Either may be absent -- an unsealed run
# from a process that was killed still has its events, and a run recorded with persistence off has
# no folder at all -- so `problems` carries what is missing instead of refusing to load.

const EVENTS_FILE := "events.jsonl"
const BOARD_FILE := "board.tres"

var run_id := ""
var events: Array[Dictionary] = []
var board: ScenarioData = null
# Why this run cannot be replayed, in the player's-eye order: the tool shows these instead of a
# Load button that does nothing.
var problems: Array[String] = []


# Newest first -- a dev opening this wants the run they just played, and the id starts with a
# sortable stamp. Directories, not files: ResourceDir answers a different question (files by
# extension, res:// packing) and would be the wrong tool wearing a familiar name.
static func list_runs() -> PackedStringArray:
	var dir := TelemetryStore.pending_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return PackedStringArray()
	var ids := DirAccess.get_directories_at(dir)
	ids.sort()
	ids.reverse()
	return ids


static func load_run(run_id: String) -> ReplayRun:
	var run := ReplayRun.new()
	run.run_id = run_id
	var dir := TelemetryStore.run_dir(run_id)

	var events_path := dir + EVENTS_FILE
	if not FileAccess.file_exists(events_path):
		run.problems.append("no %s in this folder" % EVENTS_FILE)
	else:
		var file := FileAccess.open(events_path, FileAccess.READ)
		var line_no := 0
		while file != null and not file.eof_reached():
			var raw := file.get_line()
			line_no += 1
			if raw.strip_edges() == "":
				continue   # a trailing newline is not a broken line
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary:
				run.events.append(parsed)
			else:
				# A run being APPENDED to when the process died can end mid-line. Report it and keep
				# the lines before it: a partial run still replays up to where it stops.
				run.problems.append("line %d is not valid JSON -- run truncated there" % line_no)
				break
		if file != null:
			file.close()

	var board_path := dir + BOARD_FILE
	if not FileAccess.file_exists(board_path):
		run.problems.append("no %s -- nothing to seed the board from" % BOARD_FILE)
	else:
		run.board = load(board_path) as ScenarioData
		if run.board == null:
			run.problems.append("%s did not load as a ScenarioData" % BOARD_FILE)

	return run


func can_replay() -> bool:
	return board != null and not events.is_empty()


func first(kind: String) -> Dictionary:
	for e: Dictionary in events:
		if e.get("event") == kind:
			return e
	return {}


func all(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events:
		if e.get("event") == kind:
			out.append(e)
	return out


# What the run list shows per row. Read off the events rather than the folder name, so a run that
# never sealed says so instead of reading as a finished mission.
func headline() -> Dictionary:
	var start := first("mission_start")
	var end := first("mission_end")
	var rounds := 0
	for e: Dictionary in events:
		rounds = maxi(rounds, int(e.get("round", 0)))
	return {
		"run_id": run_id,
		"scenario": str(start.get("scenario_name", start.get("scenario", "(unknown)"))),
		"outcome": str(end.get("outcome", "UNSEALED")),
		"rounds": rounds,
		"sandbox": bool(start.get("sandbox", false)),
		"dev_mode": bool(start.get("dev_mode", false)),
		"dev_touched": bool(end.get("dev_touched", false)),
	}
