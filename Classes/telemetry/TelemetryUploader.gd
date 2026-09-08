extends Uploader
class_name TelemetryUploader

# SENDS A SEALED RUN (#53 slice 5) -- the last slice of the arc, and the first time anything
# recorded leaves the machine. A game collaborator on the DevController pattern, built in
# game._build_collaborators with a back-ref.
#
# ONE MECHANISM, TWO TRIGGERS, which is slice 4b's shape again: send_pending() ships everything in
# `pending/`, and it is called at launch and again whenever a run seals. The launch call is
# therefore also the retry -- an offline session, a 500, a closed laptop all resolve themselves the
# next time the game starts, with no retry ledger to get wrong.
#
# `pending/` vs `sent/` IS the state (dev, 2026-09-08: keep a sent run so the Replay tab can still
# open it). A folder move rather than a marker file, so there is nothing that can disagree with
# where the run actually is.
#
# The intake reads ONLY the summary line and stores the events verbatim, which is what keeps a
# Worker on the free plan inside its CPU budget -- see tools/intake-worker/.

const ROUTE := "/telemetry"

# Insertion order is send order, ReportUploader's idiom exactly. A missing board.tres is SKIPPED
# rather than fatal: a run whose snapshot failed to write is still worth every metric in it.
const ATTACHMENTS := {
	TelemetryStore.EVENTS_FILE: "application/x-ndjson",
	TelemetryStore.BOARD_FILE: "text/plain",
}

# D1 caps a ROW at 2,000,000 bytes, and summary + events + board share one row -- so the budget is
# the whole payload's, not each part's. Under the cap rather than at it, since the multipart
# envelope and the row's own columns are not free either.
const MAX_PAYLOAD_BYTES := 1_800_000

var game   # the Game coordinator; set by game._build_collaborators()

## How many times send_pending has been ASKED to run, bumped before any refusal. It exists because
## everything past the headless gate is invisible to the suite: without it, a mutant deleting the
## run_sealed connection passes every case. See tests/telemetry/test_telemetry_upload.gd.
var requests := 0

var _sending := false
var _again := false


func _ready() -> void:
	super()   # PROCESS_MODE_ALWAYS -- the seal happens BEFORE the end banner, which freezes Game
	game.mission_log.run_sealed.connect(_on_run_sealed)


func _on_run_sealed(_run_id: String) -> void:
	# Deliberately not awaited: sealing must not wait on a network round trip, and a run this call
	# misses is picked up by the next launch.
	send_pending()


# Ships every sealed run in `pending/`. Returns how many landed.
func send_pending() -> int:
	requests += 1
	if _sending:
		# A seal during a send: remember it rather than interleaving two walks over one folder.
		_again = true
		return 0
	# NEITHER OF THESE IS THE SAFETY PROPERTY, and a mutant proved it: deleting the is_configured
	# call changes nothing observable, because Uploader.submit refuses a headless run itself and no
	# POST is attempted either way. What they buy is not doing the WORK -- walking pending/ and
	# reading every run off disk to build payloads nothing will send. The gate that matters lives
	# one class up, and `test_a_headless_run_never_uploads` asserts on THAT.
	if not is_configured() or not TelemetryStore.persistence_enabled:
		return 0

	_sending = true
	var sent := 0
	while true:
		_again = false
		sent += await _send_round()
		if not _again:
			break
	_sending = false
	return sent


func _send_round() -> int:
	var sent := 0
	for run_id: String in TelemetryStore.pending_runs():
		var payload := build_payload(run_id)
		if payload.is_empty():
			continue
		if await submit(ROUTE, payload["fields"], payload["files"]):
			TelemetryStore.mark_sent(run_id)
			sent += 1
	return sent


# What one run puts on the wire, or {} for a run that must not be sent. Split out because the POST
# itself cannot be driven headlessly (is_configured refuses), so this is the half a test can hold.
func build_payload(run_id: String) -> Dictionary:
	var run := ReplayRun.load_events(run_id)
	var summary_line := _summary_line(run)
	if summary_line == "":
		return {}   # unsealed -- MissionLog.sweep_unsealed finishes these at the next launch

	# A run sealed before this slice carries no run_id, and the intake keys on it. Skipped with a
	# word rather than retried forever: nothing will ever make an old run grow the field.
	var summary: Dictionary = run.first("summary").get("summary", {})
	if str(summary.get("run_id", "")) == "":
		push_warning("Telemetry: run %s predates the id field and will not be sent" % run_id)
		return {}

	var files: Array[Dictionary] = []
	var total := summary_line.length()
	for file_name: String in ATTACHMENTS:
		var bytes := FileAccess.get_file_as_bytes(TelemetryStore.run_dir(run_id) + file_name)
		if bytes.is_empty():
			continue
		total += bytes.size()
		files.append({
			"field": file_name,
			"filename": file_name,
			"mime": ATTACHMENTS[file_name],
			"bytes": bytes,
		})
	if files.is_empty():
		return {}

	if total > MAX_PAYLOAD_BYTES:
		# Left in pending/ and retried, which is honest: it will never fit, and a folder that stops
		# emptying is the visible symptom. Engineering a give-up ledger for a case measured at 3% of
		# the cap would be building for a number nobody has seen.
		push_warning("Telemetry: run %s is %d bytes, over the %d cap -- not sent" % [
			run_id, total, MAX_PAYLOAD_BYTES])
		return {}

	# RAW TEXT off raw_lines, never JSON.stringify of the parsed line: JSON has one number type, so
	# a re-encode turns every int in the summary back into a float (#53 slice 4b's rule). The intake
	# unwraps `.summary` from it.
	return {"fields": {"summary": summary_line}, "files": files}


# The LAST summary line, by the same walk the sweep uses. Parallel arrays: load_events appends to
# events and raw_lines together, so an index into one indexes the other.
static func _summary_line(run: ReplayRun) -> String:
	for i in range(run.events.size() - 1, -1, -1):
		if run.events[i].get("event") == "summary":
			return run.raw_lines[i]
	return ""
