# The release ledger (#1075) at its pure seams -- parsing CHANGELOG.md and choosing which releases an
# install has not been told about -- plus the seen store, and a LINT over the real file.
#
# THE LINT IS WHY THIS SUITE RUNS ON A CHANGELOG-ONLY PR (tests.yml lets that one .md through). The
# game prints a player line verbatim, so formatting is a visible bug, and archive-build.ps1's gate
# reads the headings with its own regex -- every `## ` heading must be one both readers agree on.
extends GdUnitTestSuite

const SCRATCH_CFG := "user://__release_notes_test.cfg"
const STRICT_HEADING := "^## v\\d+\\.\\d+\\.\\d+(\\s.*)?$"

# Captured when this script LOADS, so it is the value the process booted with.
static var _persistence_at_load := ReleaseNotes.persistence_enabled


func before_test() -> void:
	ReleaseNotes.reset_for_test()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CFG))


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CFG))
	ReleaseNotes.reset_for_test()


func _entry(version: String, lines: Array) -> Dictionary:
	var typed: Array[String] = []
	typed.assign(lines)
	return {"version": version, "lines": typed}


func _versions(entries: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in entries:
		out.append(str(entry["version"]))
	return out


func _lines_of(entry: Dictionary) -> Array:
	return entry["lines"]


# ==============================================================================
#  parse
# ==============================================================================

func test_parse_reads_each_release_and_its_player_lines() -> void:
	var entries := ReleaseNotes.parse("""# Title

## v0.2.0 (2026-01-02)

- Second release, first line.
- Second release, second line.

## v0.1.0 (2026-01-01)

- First release.
""")
	assert_array(_versions(entries)).is_equal(["0.2.0", "0.1.0"])
	assert_array(_lines_of(entries[0])).is_equal(["Second release, first line.", "Second release, second line."])
	assert_array(_lines_of(entries[1])).is_equal(["First release."])


# The line the card must never print: everything under `### Internal` is ours.
func test_player_lines_stop_at_the_internal_heading() -> void:
	var entries := ReleaseNotes.parse("""## v0.2.0

- For players.

### Internal

- For us (#123).
""")
	assert_int(entries.size()).is_equal(1)
	assert_array(_lines_of(entries[0])).is_equal(["For players."])


func test_the_preamble_and_non_release_headings_are_not_releases() -> void:
	var entries := ReleaseNotes.parse("""# Title

- A bullet in the preamble.

## Notes on the format

- A bullet under a heading that names no version.

## v0.1.0

- The only release.
""")
	assert_array(_versions(entries)).is_equal(["0.1.0"])
	assert_array(_lines_of(entries[0])).is_equal(["The only release."])


# git on Windows hands the file over with CRLF; a stray \r must not reach the card.
func test_windows_line_endings_parse_the_same() -> void:
	var entries := ReleaseNotes.parse("## v0.1.0\r\n\r\n- A line.\r\n")
	assert_array(_versions(entries)).is_equal(["0.1.0"])
	assert_array(_lines_of(entries[0])).is_equal(["A line."])


# ==============================================================================
#  since
# ==============================================================================

func _ledger() -> Array[Dictionary]:
	# Deliberately out of order, so the sort is what puts them newest first.
	var out: Array[Dictionary] = [
		_entry("0.190.2", ["c"]),
		_entry("0.192.0", ["a"]),
		_entry("0.188.8", ["e"]),
		_entry("0.191.0", ["b"]),
		_entry("0.188.7", ["f"]),
	]
	return out


func test_every_skipped_release_is_returned_newest_first() -> void:
	var due := ReleaseNotes.since("0.188.8", "0.192.0", _ledger())
	assert_array(_versions(due)).is_equal(["0.192.0", "0.191.0", "0.190.2"])


# The lower bound is EXCLUSIVE: the release last seen was already shown.
func test_the_release_already_seen_is_not_shown_again() -> void:
	assert_array(_versions(ReleaseNotes.since("0.191.0", "0.192.0", _ledger()))).is_equal(["0.192.0"])
	assert_array(ReleaseNotes.since("0.192.0", "0.192.0", _ledger())).is_empty()


# The upper bound is INCLUSIVE, and nothing past the running build is shown -- in the editor the
# ledger can hold the next release's entry before the build that carries it.
func test_nothing_past_the_running_build_is_shown() -> void:
	var ledger := _ledger()
	ledger.append(_entry("0.193.0", ["next"]))
	assert_array(_versions(ReleaseNotes.since("0.190.2", "0.192.0", ledger))).is_equal(["0.192.0", "0.191.0"])


# Numeric per segment, through VersionCheck.is_newer: a text compare puts .10 before .9.
func test_versions_compare_as_numbers() -> void:
	var ledger: Array[Dictionary] = [
		_entry("0.188.9", ["nine"]),
		_entry("0.188.10", ["ten"]),
	]
	assert_array(_versions(ReleaseNotes.since("0.188.8", "0.188.10", ledger))).is_equal(["0.188.10", "0.188.9"])


func test_a_release_with_nothing_for_players_is_left_out() -> void:
	var ledger: Array[Dictionary] = [
		_entry("0.2.0", []),
		_entry("0.3.0", ["shown"]),
	]
	assert_array(_versions(ReleaseNotes.since("0.1.0", "0.3.0", ledger))).is_equal(["0.3.0"])


# An unreadable version on either side answers nothing rather than everything.
func test_an_unreadable_version_answers_nothing() -> void:
	assert_array(ReleaseNotes.since("", "0.192.0", _ledger())).is_empty()
	assert_array(ReleaseNotes.since("dev", "0.192.0", _ledger())).is_empty()
	assert_array(ReleaseNotes.since("0.188.8", "dev", _ledger())).is_empty()


# ==============================================================================
#  the seen store
# ==============================================================================

func test_the_seen_store_round_trips() -> void:
	ReleaseNotes.persistence_enabled = true
	ReleaseNotes.config_path = SCRATCH_CFG
	assert_str(ReleaseNotes.last_seen()).is_empty()
	ReleaseNotes.mark_seen("0.192.0")
	assert_str(ReleaseNotes.last_seen()).is_equal("0.192.0")


func test_a_headless_process_boots_recording_nothing() -> void:
	if DisplayServer.get_name() != "headless":
		return
	assert_bool(_persistence_at_load).is_false()
	ReleaseNotes.config_path = SCRATCH_CFG
	ReleaseNotes.mark_seen("0.192.0")
	assert_str(ReleaseNotes.last_seen()).is_empty()


# ==============================================================================
#  the real ledger
# ==============================================================================

func _ledger_text() -> String:
	return FileAccess.get_file_as_string(ReleaseNotes.path)


# The vacuous-pass guard for every lint below: a ledger the reader cannot find or parse would
# otherwise satisfy all of them.
func test_the_shipped_ledger_has_releases() -> void:
	assert_bool(FileAccess.file_exists(ReleaseNotes.path)) \
		.override_failure_message("%s is missing" % ReleaseNotes.path).is_true()
	assert_int(ReleaseNotes.entries().size()) \
		.override_failure_message("%s parses to no releases" % ReleaseNotes.path).is_greater(0)


# archive-build.ps1 greps for `## v<version>`; anything at this level must be a release heading it
# and the card read the same way.
func test_every_level_two_heading_is_a_release() -> void:
	var strict := RegEx.create_from_string(STRICT_HEADING)
	var bad: Array[String] = []
	for raw: String in _ledger_text().split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("## ") and strict.search(line) == null:
			bad.append(line)
	assert_array(bad).override_failure_message(
		"Every `## ` heading in CHANGELOG.md must be `## v<major>.<minor>.<patch>`, optionally followed by a space and anything. Not:\n  %s"
		% "\n  ".join(bad)).is_empty()


func test_each_release_appears_once() -> void:
	var seen: Dictionary[String, bool] = {}
	var repeated: Array[String] = []
	for version: String in _versions(ReleaseNotes.entries()):
		if seen.has(version):
			repeated.append(version)
		seen[version] = true
	assert_array(repeated).override_failure_message(
		"CHANGELOG.md has more than one heading for: %s" % ", ".join(repeated)).is_empty()


# The card prints these verbatim, so markdown would show as asterisks and backticks on screen.
func test_player_lines_are_plain_bullets() -> void:
	var heading := RegEx.create_from_string(ReleaseNotes.HEADING)
	var markup := RegEx.create_from_string("\\*\\*|`|\\(#\\d|\\[|\\]\\(")
	var in_player_section := false
	var bad: Array[String] = []
	for raw: String in _ledger_text().split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			in_player_section = heading.search(line) != null
			continue
		if not in_player_section or line.is_empty():
			continue
		if not line.begins_with(ReleaseNotes.LINE_PREFIX) or markup.search(line) != null:
			bad.append(line)
	assert_array(bad).override_failure_message(
		"A release's player lines are one plain `- ` bullet each: no bold, no backticks, no links, no issue numbers (those go under ### Internal). Not:\n  %s"
		% "\n  ".join(bad)).is_empty()
