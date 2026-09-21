extends Node
class_name Uploader

# THE ONE OUTBOUND PIPE (#131, generalised by #53 slice 5). Everything this project sends anywhere
# goes through here: a bug report, and now a recorded playtest run.
#
# It owns the TRANSPORT and nothing else -- a route, some fields, some files, and whether the far
# end said yes. WHAT is sent stays its caller's single answer, which is why the ATTACHMENTS tables
# live on the subclasses rather than here: adding a file to a report is one line in ReportUploader
# and no change anywhere else.
#
# VersionCheck (#1060) IS DELIBERATELY NOT A SUBCLASS. It asks the same server one question and
# sends nothing at all, so what it shares is the ADDRESS below -- one answer to "where is our
# server" -- and none of this transport. Bending submit() around a GET with no payload would blur
# what this class is for.
#
# ENDPOINT is a Cloudflare Worker (tools/intake-worker/) which routes on PATH -- "" is the report
# relay to Discord, "/telemetry" is the run intake. The game holds neither the Discord token nor a
# database credential, so both rotate without re-exporting a build.

# NOT a secret -- it is an address, and everything it fronts lives in a Worker secret or binding.
# Empty disables upload entirely and leaves everything local-only.
const ENDPOINT := "https://iosis-reports.phlogiston-games.workers.dev"

const TIMEOUT_SECONDS := 20.0


func _ready() -> void:
	# An upload is in flight while a modal has the Game subtree DISABLED -- the report card is up,
	# or (slice 5) the mission-end banner is, since MissionController seals BEFORE it draws.
	# HTTPRequest polls its own internal process to emit request_completed, so a freezable uploader
	# never finishes: submit() awaits forever. The HTTPRequest built in submit() is a child, so it
	# inherits this. A SUBCLASS THAT OVERRIDES _ready MUST CALL super().
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_configured() -> bool:
	# A headless run is a test run or CI, never a player. Without this the suite would POST on every
	# green run -- and the first anyone would know is the intake filling up. It also keeps the report
	# card's disclosure honest: a build that will not send says so instead of promising delivery.
	if DisplayServer.get_name() == "headless":
		return false
	return ENDPOINT != ""


# `route` is appended to ENDPOINT, "" being the Worker's own root. Returns whether the far end
# answered 2xx; nothing richer, because no caller has anything to do with a status code.
func submit(route: String, fields: Dictionary, files: Array[Dictionary]) -> bool:
	if not is_configured():
		return false

	var boundary := "iosis%d" % Time.get_ticks_usec()
	var body := MultipartForm.build(boundary, fields, files)

	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = TIMEOUT_SECONDS
	add_child(http)

	var headers := PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary])
	var err := http.request_raw(ENDPOINT + route, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_warning("Upload: could not start request to %s (error %s)" % [route, err])
		http.queue_free()
		return false

	var outcome: Array = await http.request_completed
	http.queue_free()

	var result: int = outcome[0]
	var code: int = outcome[1]
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		push_warning("Upload to %s failed: result %s, HTTP %s" % [route, result, code])
		return false
	return true
