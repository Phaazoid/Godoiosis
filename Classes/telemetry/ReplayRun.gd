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
#
# TWO LISTS, TWO QUESTIONS (#871). `problems` is why a run CANNOT be replayed. `degraded` is why
# replaying it proves less than it looks like: a board naming content this build has moved is a hard
# parse error for the whole file, so the board comes through ContentRepair like every other board in
# the project -- and what the repair COST is reported rather than swallowed, because a harness that
# certifies a run it seeded from the wrong board is worse than one that refuses to open it.

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
# THE BOARD LOADED, BUT IT IS NOT THE BOARD THAT WAS RECORDED (#871) -- the references this build
# could not resolve, which ContentRepair took out to get the file to parse at all. A SECOND
# QUESTION, not a second kind of problem: a degraded board replays, so this is never a reason to
# refuse it, it is the reason every difference the replay reports afterwards is suspect.
var degraded: Array[String] = []


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
# ships board.tres as BYTES -- so load_run's parse of it into a ScenarioData, and into the resource
# cache, is work it would only throw away. Since #871 that parse also text-scans and can write a
# repaired copy, which the launch sweep pays for once per recorded run on the machine if it comes
# through the wrong door. A seam SPLIT rather than a second parse loop: load_run is this plus the
# board, so the truncation rule below still governs both callers.
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


# THE EVENTS PLUS THE BOARD, TOLERANTLY (#871). A board naming content that has since moved is a
# hard PARSE error for the whole file, and a run recorded on somebody else's build is exactly where
# that happens -- so this goes through ContentRepair like every other board load in the project.
static func load_run(run_id: String) -> ReplayRun:
	var run := load_events(run_id)
	var board_path := TelemetryStore.run_dir(run_id) + BOARD_FILE
	if not FileAccess.file_exists(board_path):
		run.problems.append("no %s -- nothing to seed the board from" % BOARD_FILE)
		return run

	# ASKED OF THE FILE'S TEXT, NEVER OF ContentRepair'S REGISTRY. load_tolerant erases its own repair
	# record the moment a later load comes back clean -- and the SECOND look at one run is a clean
	# load, because the repaired board took over that path in the resource cache. Reading the text
	# answers the same both times, and answers for a REFUSED load too, which the registry never holds.
	var cannot_load := ContentRepair.missing_references(board_path)
	run.board = ContentRepair.load_tolerant(board_path) as ScenarioData
	# A run's board is a frozen snapshot of a mission somebody else played, so it is not content
	# anyone can go and fix. Left in the registry it would sit in every later BoardLint report telling
	# the dev to restore a file for a board that is not authored content.
	ContentRepair.forget(board_path)

	if run.board == null:
		if cannot_load.is_empty():
			# Broken for some reason we have NOT diagnosed. Nothing to name, and the flat line is still
			# more than silence.
			run.problems.append("%s did not load as a ScenarioData" % BOARD_FILE)
		else:
			run.problems.append("%s could not be loaded -- it references %s, which this build cannot load"
				% [BOARD_FILE, ", ".join(cannot_load)])
	elif not cannot_load.is_empty():
		# WORDED FOR BOTH WAYS THIS HAPPENS. Usually ContentRepair stripped the reference and the
		# property with it -- but an ext_resource NOTHING USES does not fail the file at all, so the
		# board can come back whole with the reference still named in it. "References X and cannot
		# load it" is true in both; "loaded without X" would be a guess in the second.
		run.degraded.append("%s references %s, which this build cannot load -- so a difference the"
			% [BOARD_FILE, ", ".join(cannot_load)]
			+ " replay reports may be the board rather than the build")
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
