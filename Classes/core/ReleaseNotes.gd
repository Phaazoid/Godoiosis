extends Object
class_name ReleaseNotes

# THE RELEASE LEDGER, AS THE GAME READS IT (#1075). CHANGELOG.md at the repo root is the one record of
# what each build that went out changed; this file parses it and answers the one question the title
# screen's WhatsNewCard asks: which releases has THIS install not been told about yet?
#
# THE FILE SHIPS IN THE PACK. export_presets.cfg names it in include_filter, the first non-resource
# file the game carries -- which is also why `*.md` left the exclude list, since exclude wins over
# include. Scenes/Smoke/smoke.gd proves it arrived, inside the exported pack, on every CI run.
#
# ITS OWN cfg, on TelemetryStore's reasoning: PlayerSettings.save_state() rewrites settings.cfg whole,
# and what an install has been shown is not a preference anyway -- every PlayerSettings entry becomes
# a row on the settings page.
#
# THE HEADING FORMAT HAS A SECOND READER, declared: archive-build.ps1's release gate greps for
# `## v<version>` without running any of this. test_release_notes lints the real file so that every
# `## ` heading in it is one both readers agree on.

const CONFIG_SECTION := "release_notes"
const LAST_SEEN_KEY := "last_seen"

# A release heading. The version is captured without its `v`, since VersionCheck.is_newer refuses a
# version with anything but integer segments.
const HEADING := "^## v(\\d+(?:\\.\\d+)*)(?:\\s|$)"
const LINE_PREFIX := "- "

# Both redirectable, so a suite can point the ledger and the store at scratch files.
static var path := "res://CHANGELOG.md"
static var config_path := "user://release_notes.cfg"
static var persistence_enabled := true

static var _entries: Array[Dictionary] = []
static var _loaded := false


# A headless process has no player to have told anything, as PlayerSettings and TelemetryStore rule.
static func _static_init() -> void:
	if DisplayServer.get_name() == "headless":
		persistence_enabled = false


# Every release in the ledger, as parse() shapes them. Read once per process: the file cannot change
# under a running build.
static func entries() -> Array[Dictionary]:
	if not _loaded:
		_loaded = true
		_entries = []
		if FileAccess.file_exists(path):
			_entries = parse(FileAccess.get_file_as_string(path))
	return _entries


# {"version": "0.192.0", "lines": Array[String]} per release heading, in file order. A release's
# player lines are the `- ` bullets under its heading, up to the next heading of ANY level -- which is
# what keeps `### Internal` out. Anything before the first release heading is preamble.
static func parse(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var heading := RegEx.create_from_string(HEADING)
	# Array[String] rather than PackedStringArray: a packed array is a VALUE, so appending through the
	# dictionary would append to a copy.
	var lines: Array[String] = []
	var collecting := false
	for raw: String in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			var found := heading.search(line)
			collecting = found != null
			if collecting:
				lines = []
				out.append({"version": found.get_string(1), "lines": lines})
			continue
		if collecting and line.begins_with(LINE_PREFIX):
			lines.append(line.substr(LINE_PREFIX.length()).strip_edges())
	return out


# The releases after last_seen, up to and including the running build, newest first. A release with
# no player lines is left out -- an internal-only build has nothing to say on the card.
#
# Both bounds go through VersionCheck.is_newer, the project's one version comparison, so an
# unreadable version on either side answers nothing rather than everything.
static func since(last_seen: String, running: String, from: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in from:
		var version := str(entry["version"])
		if not VersionCheck.is_newer(version, last_seen):
			continue
		if version != running and not VersionCheck.is_newer(running, version):
			continue
		var lines: Array = entry["lines"]
		if lines.is_empty():
			continue
		out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return VersionCheck.is_newer(str(a["version"]), str(b["version"])))
	return out


# The last build this install was shown notes for. "" is no record: a fresh install, or one that has
# only ever run builds from before the card existed.
static func last_seen() -> String:
	if not persistence_enabled:
		return ""
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return ""
	return str(cfg.get_value(CONFIG_SECTION, LAST_SEEN_KEY, ""))


static func mark_seen(version: String) -> void:
	if not persistence_enabled:
		return
	var cfg := ConfigFile.new()
	cfg.load(config_path)   # a missing file is the first-run case, not an error
	cfg.set_value(CONFIG_SECTION, LAST_SEEN_KEY, version)
	cfg.save(config_path)


# --- test seam ---

## Wipe runtime state and skip disk I/O so suites stay hermetic. Call in before_test().
static func reset_for_test() -> void:
	persistence_enabled = false
	config_path = "user://release_notes_test.cfg"
	path = "res://CHANGELOG.md"
	_entries = []
	_loaded = false
