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

# The two file names live on TelemetryStore, which owns every path in the store.
const EVENTS_FILE := TelemetryStore.EVENTS_FILE
const BOARD_FILE := TelemetryStore.BOARD_FILE

var run_id := ""
var events: Array[Dictionary] = []
# The same lines as TEXT, exactly as they were written. The launch sweep (MissionLog.sweep_unsealed)
# rewrites a run it finishes, and re-encoding `events` would not give it back what it read: JSON has
# one number type, so every int in the file would come back a float. Kept beside the parse rather
# than read a second time, so the truncation rule below governs both halves at once.
var raw_lines := PackedStringArray()
var board: ScenarioData = null
# Why this run cannot be replayed, in the player's-eye order: the tool shows these instead of a
# Load button that does nothing.
var problems: Array[String] = []


# EVERY run this machine can replay, newest first -- BOTH folders since #53 slice 5, because
# whether a run has been sent has nothing to do with whether it can be replayed. The listing
# mechanism is TelemetryStore's (it owns the paths); the MERGE is this question's own answer.
static func list_runs() -> PackedStringArray:
	var ids := TelemetryStore.pending_runs()
	ids.append_array(TelemetryStore.sent_runs())
	ids.sort()
	ids.reverse()
	return ids


# THE EVENTS ALONE, with no board (#53 slice 5). The uploader asks "is this run sealed?" and then
# ships board.tres as BYTES -- so load_run's `load()` of it into a ScenarioData, and into the
# resource cache, is work it would only throw away. A seam SPLIT rather than a second parse loop:
# load_run is this plus the board, so the truncation rule below still governs both callers.
static func load_events(run_id: String) -> ReplayRun:
	var run := ReplayRun.new()
	run.run_id = run_id
	var events_path := TelemetryStore.run_dir(run_id) + EVENTS_FILE
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
				run.raw_lines.append(raw)
			else:
				# A run being APPENDED to when the process died can end mid-line. Report it and keep
				# the lines before it: a partial run still replays up to where it stops.
				run.problems.append("line %d is not valid JSON -- run truncated there" % line_no)
				break
		if file != null:
			file.close()
	return run


static func load_run(run_id: String) -> ReplayRun:
	var run := load_events(run_id)
	var board_path := TelemetryStore.run_dir(run_id) + BOARD_FILE
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
		# Read off WHERE THE FOLDER IS, never off a stored flag (#53 slice 5) -- the move is the
		# state, so this cannot go stale the way a marker could.
		"sent": TelemetryStore.is_sent(run_id),
	}
