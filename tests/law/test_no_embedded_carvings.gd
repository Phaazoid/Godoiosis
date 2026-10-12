# No committed file outside the carving library embeds its own copy of a carving (#1313).
#
# A rune holds library carvings BY REFERENCE. Before that, the Item Editor's Inscribe copied the
# library carving and every scenario snapshot copied the rune again, so nothing referenced
# Resources/TransmutationData/ at all: a library edit reached no rune and no board, and 18 of 37
# shipped copies had drifted (Fireball, Freeze and Zap Cannon hitting as BLUNT, a Rock Throw at an
# old power) -- the Fireball-lob class of bug (#258) arriving a second time.
#
# This law is the fork made explicit: shipped content references library carvings. A carving made
# for one rune alone would be a deliberate decision to relax it, never something that happens
# quietly. It reads the files as text, the way test_no_embedded_image_resources.gd does, over the
# same roots.
extends GdUnitTestSuite

const SCANNED_ROOTS: Array[String] = ["res://Scenes/", "res://Resources/", "res://Scenarios/"]
const LIBRARY_DIR := "res://Resources/TransmutationData/"
const CARVING_SCRIPT := "res://Classes/alchemy/TransmutationData.gd"
const PROBE_PATH := "user://__test_embedded_carving_probe.tres"


func after_test() -> void:
	if FileAccess.file_exists(PROBE_PATH):
		DirAccess.remove_absolute(PROBE_PATH)


func test_no_committed_file_embeds_a_carving_copy() -> void:
	var scanned := 0
	var offenders: Array[String] = []
	for file: String in _scan():
		if file.begins_with(LIBRARY_DIR):
			continue
		scanned += 1
		var count := embedded_carvings(FileAccess.get_file_as_string(file))
		if count > 0:
			offenders.append("%s (%d)" % [file, count])

	assert_int(offenders.size()).override_failure_message(
		"These files embed their own copy of a carving, so a library edit can never reach them: %s. "
		% ", ".join(offenders)
		+ "Inscribe the library carving itself (Item Editor) so the file names it as an ext_resource."
	).is_equal(0)
	assert_int(scanned).override_failure_message(
		"the scan found no resource files at all -- SCANNED_ROOTS is wrong, not the repo"
	).is_greater(0)


# The detector has teeth: a rune holding a carving with no file of its own, written by the real
# saver, is exactly the shape every shipped copy had, and it must be counted.
func test_the_detector_counts_an_inline_carving_the_saver_writes() -> void:
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	var copy := TransmutationData.new()
	copy.recipe = "Push(A2)"
	rune.inscriptions.append(copy)
	assert_int(ResourceSaver.save(rune, PROBE_PATH)).is_equal(OK)

	assert_int(embedded_carvings(FileAccess.get_file_as_string(PROBE_PATH))).is_equal(1)


# How many [sub_resource] blocks in `text` are carvings: blocks whose script is the ext_resource
# naming the carving script. Naming the script is not enough: a rune's typed inscriptions array
# names it in its TYPE even when every element is a reference, and a file can name it unused.
static func embedded_carvings(text: String) -> int:
	var script_ids: Array[String] = []
	for line: String in text.split("\n"):
		if line.begins_with("[ext_resource") and line.contains('path="%s"' % CARVING_SCRIPT):
			script_ids.append(line.get_slice(' id="', 1).get_slice('"', 0))
	if script_ids.is_empty():
		return 0
	var count := 0
	var in_sub := false
	for line: String in text.split("\n"):
		if line.begins_with("["):
			in_sub = line.begins_with("[sub_resource")
			continue
		if in_sub and line.begins_with("script = ExtResource("):
			if script_ids.has(line.get_slice('ExtResource("', 1).get_slice('"', 0)):
				count += 1
	return count


func _scan() -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = SCANNED_ROOTS.duplicate()
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub: String in dir.get_directories():
			pending.append(dir_path.path_join(sub) + "/")
		for file: String in dir.get_files():
			if file.ends_with(".tscn") or file.ends_with(".tres"):
				found.append(dir_path.path_join(file))
	return found
