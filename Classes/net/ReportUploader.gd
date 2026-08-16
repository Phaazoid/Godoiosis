extends Node
class_name ReportUploader

# Ships a finished report folder to the intake endpoint (#131).
#
# It owns the TRANSPORT and nothing else: handed a directory and a one-line summary, it never looks
# inside a report. What a report CONTAINS stays BugReporter's single answer, so adding a file to a
# report is one line in ATTACHMENTS here and no other change anywhere.
#
# ENDPOINT is a Cloudflare Worker relaying to a Discord webhook (tools/report-worker/). The game
# never holds the Discord token, so it can be rotated without re-exporting a build.

# The intake Worker (tools/report-worker/). NOT a secret -- it is an address, and the Discord token
# it relays to lives in a Worker secret. Empty disables upload and leaves reports local-only.
const ENDPOINT := "https://iosis-reports.phlogiston-games.workers.dev"

const TIMEOUT_SECONDS := 20.0

# Insertion order is send order. A missing file is SKIPPED, not an error: a report sent from the
# mission select screen has no board.tres because there is no board.
const ATTACHMENTS := {
	"report.md": "text/markdown",
	"board.tres": "text/plain",
	"board.png": "image/png",
	"devtools.png": "image/png",   # #328: only written while the dev-tools window is open
}

func _ready() -> void:
	# An upload is in flight while the report card is up, i.e. while ModalLock has the Game subtree
	# DISABLED and this node is under it. HTTPRequest polls its own internal process to emit
	# request_completed, so a freezable uploader never finishes: submit() awaits forever and the
	# card sticks on "Sending..." with no button to press. The HTTPRequest built in submit() is a
	# child, so it inherits this.
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_configured() -> bool:
	# A headless run is a test run or CI, never a player. Without this the 975-case suite would
	# POST a report into the intake channel on every green run -- and the first anyone would know
	# is the channel filling up. It also keeps the card's disclosure honest: a build that will not
	# send says so instead of promising delivery.
	if DisplayServer.get_name() == "headless":
		return false
	return ENDPOINT != ""

func submit(dir: String, summary: String) -> bool:
	if not is_configured():
		return false

	var files: Array[Dictionary] = []
	for file_name: String in ATTACHMENTS:
		var bytes := FileAccess.get_file_as_bytes(dir + file_name)
		if bytes.is_empty():
			continue
		files.append({
			"field": "files[%d]" % files.size(),
			"filename": file_name,
			"mime": ATTACHMENTS[file_name],
			"bytes": bytes,
		})

	# parse:[] disarms mentions: a playtester typing @everyone into the note must not ping a server.
	var fields := {"payload_json": JSON.stringify({
		"content": summary,
		"allowed_mentions": {"parse": []},
	})}

	var boundary := "iosis%d" % Time.get_ticks_usec()
	var body := MultipartForm.build(boundary, fields, files)

	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = TIMEOUT_SECONDS
	add_child(http)

	var headers := PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary])
	var err := http.request_raw(ENDPOINT, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_warning("Report upload: could not start request (error %s)" % err)
		http.queue_free()
		return false

	var outcome: Array = await http.request_completed
	http.queue_free()

	var result: int = outcome[0]
	var code: int = outcome[1]
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		push_warning("Report upload failed: result %s, HTTP %s" % [result, code])
		return false
	return true
