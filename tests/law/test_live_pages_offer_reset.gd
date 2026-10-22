# Every dev page that edits LIVE offers Reset-to-saved, greyed while there is nothing to put back
# (#1376; dev: "a reset button in any page where I'm editing visuals").
#
# A page wearing the unsaved marker (DevWidgets.mark_unsaved) is a page with something to lose, so it
# must also call DevWidgets.offer_reset -- the one door that greys its Reset off the same flag. The
# behaviour behind it (greyed, lit by an edit, the FILE back on Reset) is asserted per page in
# test_unsaved_markers, test_weather_tool, test_weights_tool and test_ground_rules.
#
# A page may be EXEMPT only by declaration, and the declaration is checked rather than trusted: one
# that no longer wears a marker is a stale exemption and goes red.
#
# The stated limit: a page that edits live but wears NO marker is invisible here. The Attack Editor's
# Weapon Families mode and its effect looks are that page today -- a follow-up, not a pass.
extends GdUnitTestSuite

const SCANNED := "res://Classes/dev/"
const MARKER := "DevWidgets.mark_unsaved("
const RESET := "DevWidgets.offer_reset("

# Pages whose marker sits on a COPY of the file: the form is a duplicate, nothing on the board moved,
# and Load re-reads the file. Load is their way back (dev, 2026-10-21).
const EDITS_A_COPY: Array[String] = ["RosterTool.gd", "DialogTool.gd"]


func test_every_page_with_an_unsaved_marker_offers_reset() -> void:
	var offences: Array[String] = []
	var offering := 0
	var marked: Dictionary = {}
	for file: String in ResourceDir.files_with_extension(SCANNED, ".gd"):
		var code := _code_of(SCANNED + file)
		if not code.contains(MARKER):
			continue
		marked[file] = true
		if EDITS_A_COPY.has(file):
			continue
		if code.contains(RESET):
			offering += 1
		else:
			offences.append(file)

	assert_array(offences).override_failure_message(
		"These pages wear the unsaved marker but offer no Reset-to-saved (#1376). Add a Reset that "
		+ "re-reads the file (DevWidgets.revert_to_saved) and grey it with DevWidgets.offer_reset beside "
		+ "every mark_unsaved, or declare the page in EDITS_A_COPY if it edits a copy:\n  "
		+ "\n  ".join(offences)).is_empty()
	for file: String in EDITS_A_COPY:
		assert_bool(marked.has(file)).override_failure_message(
			"%s is declared as editing a copy but wears no unsaved marker -- drop the declaration" % file).is_true()
	# Non-vacuity: Moods, Game, Tiles, Weather and Weights.
	assert_int(offering).override_failure_message(
		"the scan found too few pages offering Reset -- MARKER or RESET no longer matches the code").is_greater_equal(5)


# Comment lines dropped, so a door named only in prose counts for nothing.
func _code_of(path: String) -> String:
	var kept: PackedStringArray = PackedStringArray()
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	return "\n".join(kept)
