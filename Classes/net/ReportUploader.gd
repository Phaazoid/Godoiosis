extends Uploader
class_name ReportUploader

# Ships a finished report folder to the intake endpoint (#131).
#
# Handed a directory and a one-line summary, it never looks inside a report. What a report CONTAINS
# stays BugReporter's single answer, so adding a file to a report is one line in ATTACHMENTS here
# and no other change anywhere.
#
# The HTTP half moved to Uploader in #53 slice 5, when telemetry became a second sender. What is
# left here is the report-shaped half: which files go, and the Discord-shaped field beside them.

# Insertion order is send order. A missing file is SKIPPED, not an error: a report sent from the
# mission select screen has no board.tres because there is no board.
const ATTACHMENTS := {
	"report.md": "text/markdown",
	"board.tres": "text/plain",
	"board.png": "image/png",
	"devtools.png": "image/png",   # #328: only written while the dev-tools window is open
}


func send_report(dir: String, summary: String) -> bool:
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

	# The Worker's ROOT is the report relay -- the URL this game has always posted to.
	return await submit("", fields, files)
