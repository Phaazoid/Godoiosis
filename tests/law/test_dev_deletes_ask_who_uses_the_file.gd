# Every dev Delete asks DevWidgets.refuse_delete_in_use BEFORE its confirm (#1366).
#
# A file something names by path cannot be deleted safely: the referrer becomes a dangling
# ext_resource, a hard PARSE error that takes the whole referring file down (#596). The Attack
# Editor and LibraryField asked; the Character and Item pages went straight to the confirm, and the
# Dialog page asked a narrower scan of its own. Every dev Delete rides confirm_delete (dev call
# 2026-08-11), so that call is what marks a door, and this scans every one.
#
# A door may be EXEMPT only by declaration, and the declaration is checked rather than trusted: the
# day a scanned file names one of its victims by path, the second case goes red and names the page.
#
# The stated limit, as test_ui_layers_one_axis_each's: a source scan sees the calls as spelled. A
# guard reached through a helper of the page's own slips past. This is a backstop for review.
extends GdUnitTestSuite

const SCANNED: Array[String] = ["res://Classes/", "res://Scenes/", "res://game.gd"]
const DOOR := "DevWidgets.confirm_delete("
const GUARD := "DevWidgets.refuse_delete_in_use("

# Pages whose victims nothing names by PATH, keyed to the folder they delete from: a board names
# its look and its roster by NAME (a missing one falls back, or BoardLint BLOCKS it), and nothing
# holds a scenario or a ground's ignition reaction at all. Asking users_of there would promise a
# guard that cannot see the reference that matters.
const NAMED_BY_NOTHING := {
	"MoodsTool.gd": LookKnobs.PRESET_DIR,
	"ObjectTool.gd": TerrainReactionCatalog.REACTION_DIR,
	"RosterTool.gd": RosterCatalog.ROSTER_DIR,
	"ScenarioHeader.gd": ScenarioManager.SCENARIO_DIR,
}
# confirm_delete over board state, not a file.
const DELETES_NO_FILE: Array[String] = ["TileBrushTool.gd"]


func test_every_dev_delete_asks_who_uses_the_file_first() -> void:
	var offences: Array[String] = []
	var guarded := 0
	var exempt_seen: Dictionary = {}
	for path: String in _scripts():
		var file := path.get_file()
		var exempt := NAMED_BY_NOTHING.has(file) or DELETES_NO_FILE.has(file)
		var function := ""
		var asked := false
		var line_no := 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			line_no += 1
			if line.begins_with("func ") or line.begins_with("static func "):
				function = line.get_slice("(", 0).get_slice("func ", 1)
				asked = false
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			if code.contains(GUARD):
				asked = true
			if not code.contains(DOOR):
				continue
			if exempt:
				exempt_seen[file] = true
			elif asked:
				guarded += 1
			else:
				offences.append("%s:%d  %s() confirms a delete it never refused" % [file, line_no, function])

	assert_array(offences).override_failure_message(
		"These Deletes reach the confirm without asking DevWidgets.refuse_delete_in_use first, so a "
		+ "file something names by path can be deleted out from under it (#1366). Ask it before the "
		+ "confirm, or declare the page in NAMED_BY_NOTHING with the folder it deletes from:\n  "
		+ "\n  ".join(offences)).is_empty()
	# A declaration naming a page with no door any more is a stale exemption, not a harmless one.
	for file: String in NAMED_BY_NOTHING.keys() + DELETES_NO_FILE:
		assert_bool(exempt_seen.has(file)).override_failure_message(
			"%s is declared exempt but has no confirm_delete -- drop the declaration" % file).is_true()
	# Non-vacuity: the Attack, Character, Item and Dialog pages plus LibraryField.
	assert_int(guarded).override_failure_message(
		"the scan found too few guarded Deletes -- DOOR or GUARD no longer matches the code").is_greater(4)


# The exemptions above are claims about content, so they are asked of the disk: every ext_resource
# in the files users_of reads, in ONE pass. Asking users_of once per victim answers the same thing
# and re-reads the whole corpus per file, which measured 7s here.
func test_nothing_names_an_exempt_pages_files_by_path() -> void:
	var reference := RegEx.create_from_string('\\[ext_resource [^\\]]*path="(?<path>[^"]+\\.tres)"')
	var files: Array[String] = []
	for root: String in ResourceCatalog.SCANNED_ROOTS:
		_collect_tres(root.trim_suffix("/"), files)
	var offences: Array[String] = []
	var references := 0
	for referrer: String in files:
		for hit: RegExMatch in reference.search_all(FileAccess.get_file_as_string(referrer)):
			references += 1
			var victim := hit.get_string("path")
			for page: String in NAMED_BY_NOTHING:
				if victim.begins_with(String(NAMED_BY_NOTHING[page])):
					offences.append("%s names %s, so %s's Delete must ask refuse_delete_in_use now"
						% [referrer.get_file(), victim, page])
	assert_array(offences).override_failure_message("\n  ".join(offences)).is_empty()
	# Non-vacuity: a pattern that stopped matching passes the check above while proving nothing.
	assert_int(references).override_failure_message(
		"the scan found no ext_resource naming a .tres -- the pattern no longer matches").is_greater(0)


func _collect_tres(dir_path: String, found: Array[String]) -> void:
	for sub: String in DirAccess.get_directories_at(dir_path):
		_collect_tres(dir_path.path_join(sub), found)
	for file: String in ResourceDir.files_with_extension(dir_path, ResourceCatalog.RESOURCE_EXT):
		found.append(dir_path.path_join(file))


func _scripts() -> Array[String]:
	var found: Array[String] = []
	for root: String in SCANNED:
		if root.ends_with(".gd"):
			found.append(root)
			continue
		_walk(root, found)
	return found


func _walk(dir_path: String, found: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk(full, found)
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
