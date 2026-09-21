extends Node
class_name VersionCheck

# IS THERE A NEWER BUILD? Asked once per launch (#1060), against our own Worker.
#
# NOT api.itch.io, which answers exactly this for free (dev, 2026-09-20): itch is where the game is
# hosted NOW and may not be later, so nothing a player is running may hold an itch address. The
# DOWNLOAD URL comes back in the payload for the same reason -- a const in the game would be frozen
# into every build already in someone's hands, which is the hazard wrangler.toml names about the
# Worker's own name. Moving host is then one UPDATE and no re-export.
#
# IT READS Uploader.ENDPOINT BUT IS NOT AN Uploader. That class owns what the project SENDS, and
# its subclasses are ATTACHMENT tables; this sends nothing and asks one question. What is shared is
# the ADDRESS -- one answer to "where is our server" -- not the transport.
#
# Everything here fails to {} rather than to an error: a nag that cannot be delivered is worth
# nothing, and the player is mid-launch.

# The one question, and what a "no" looks like.
signal finished

const ROUTE := "/version"

# Short where Uploader's is 20s: this sits between the player and the title screen, and must never
# feel like the game is waiting on something.
const TIMEOUT_SECONDS := 5.0

# The server's answer, shaped for the banner: {} or {"version": String, "url": String}.
static var _latest: Dictionary = {}
static var _asked := false
static var _pending: VersionCheck = null

# Cleared headless by _static_init, exactly as TelemetryNotice clears its own and for the same
# reason: 89 suites boot Main.tscn and reach the title screen, and none of them may make a real
# network call. A suite that wants the real thing sets this back itself.
static var enabled := true


static func _static_init() -> void:
	if DisplayServer.get_name() == "headless":
		enabled = false


# The one door. Awaits the answer the first time and hands back the cached one after -- so the
# title screen reopening after every mission costs nothing.
static func latest(parent: Node) -> Dictionary:
	if not enabled or Uploader.ENDPOINT == "":
		return {}
	if _asked:
		# A second caller arriving while the first is still in flight waits for it rather than
		# reading a cache that is not filled yet.
		if is_instance_valid(_pending):
			await _pending.finished
		return _latest
	_asked = true
	var node := VersionCheck.new()
	_pending = node
	parent.add_child(node)
	_latest = await node._fetch()
	_pending = null
	node.finished.emit()
	node.queue_free()
	return _latest


# NUMERIC PER SEGMENT, never a string compare: "0.188.10" sorts BEFORE "0.188.9" as text, so the
# one release that most needs the nag is the one a string compare would stay quiet for.
#
# Anything that is not all-integer segments -- Build.version()'s "dev" fallback, a blank, a tag --
# answers false. An unreadable version is not a reason to tell somebody they are out of date.
static func is_newer(remote: String, local: String) -> bool:
	var there := _segments(remote)
	var here := _segments(local)
	if there.is_empty() or here.is_empty():
		return false
	for i in maxi(there.size(), here.size()):
		# Zero-filled, so 0.189 and 0.189.0 are the same build rather than an upgrade.
		var a: int = there[i] if i < there.size() else 0
		var b: int = here[i] if i < here.size() else 0
		if a != b:
			return a > b
	return false


static func _segments(version: String) -> Array[int]:
	var out: Array[int] = []
	for part in version.split("."):
		if not part.is_valid_int():
			return []
		out.append(part.to_int())
	return out


# THE PURE HALF, so a test can drive every answer without a network. Static and total: it takes
# what the wire produced and returns what the banner needs.
#
# THE URL IS CHECKED BEFORE IT IS EVER HANDED TO OS.shell_open. It arrives over the wire, and
# shell_open on Windows will happily open something that is not a web page; requiring https:// is
# the cheap half of not trusting a payload with a shell call.
static func read_payload(response_code: int, body: PackedByteArray, local: String) -> Dictionary:
	if response_code != 200:
		return {}
	# JSON.new().parse rather than JSON.parse_string: the static one PRINTS the engine error on a
	# malformed body, so the suite's own bad-payload cases would each put a red ERROR line into a
	# green run. Refusing quietly is also the right behaviour in a player build.
	var reader := JSON.new()
	if reader.parse(body.get_string_from_utf8()) != OK:
		return {}
	if typeof(reader.data) != TYPE_DICTIONARY:
		return {}
	var payload: Dictionary = reader.data
	var version := str(payload.get("version", ""))
	var url := str(payload.get("url", ""))
	if version == "" or not url.begins_with("https://"):
		return {}
	if not is_newer(version, local):
		return {}
	return {"version": version, "url": url}


func _ready() -> void:
	# HTTPRequest polls its own _process to emit request_completed, so a freezable node never
	# finishes and the await above hangs forever. Uploader carries this same line for this reason.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _fetch() -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	if http.request(Uploader.ENDPOINT + ROUTE) != OK:
		return {}
	var answer: Array = await http.request_completed
	# request_completed(result, response_code, headers, body) -- result is the TRANSPORT verdict,
	# and a timeout arrives here rather than as a code.
	if int(answer[0]) != HTTPRequest.RESULT_SUCCESS:
		return {}
	return read_payload(int(answer[1]), answer[3], Build.version())
