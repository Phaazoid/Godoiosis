# Every move production builds walks RulesService.route_to's path (#920). The arrow, the click, the
# group move, the Play API and the replay all used to reconstruct the cheapest tree themselves; one of
# them doing so again would be a move that walks into a watch the arrow beside it detours around.
extends GdUnitTestSuite

const SCANNED: Array[String] = ["res://Classes/", "res://Scenes/", "res://play/", "res://game.gd"]

# The one file that may walk the tree: route_to falls back to it when no watch is in play.
const DOOR := "res://Classes/board/RulesService.gd"


func test_no_production_move_reconstructs_the_cheapest_tree_itself() -> void:
	var scanned := 0
	var offences: Array[String] = []
	for path: String in _scripts():
		scanned += 1
		if path == DOOR:
			continue
		var line_no := 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			line_no += 1
			var code := line.strip_edges()
			if not code.begins_with("#") and code.contains("reconstruct_path("):
				offences.append("%s:%d  %s" % [path.get_file(), line_no, code])

	assert_array(offences).override_failure_message(
		"These build a move's path past route_to, so they walk the cheapest route through a watch "
		+ "the arrow detours around. Ask RulesService.route_to:\n  " + "\n  ".join(offences)
	).is_empty()
	assert_int(scanned).override_failure_message(
		"the scan found no production scripts -- SCANNED is wrong, not the repo").is_greater(20)


# Non-vacuity: the door still holds the call this law scans for, so the pattern matches something real.
func test_the_door_itself_still_walks_the_tree() -> void:
	assert_bool(FileAccess.get_file_as_string(DOOR).contains("reconstruct_path(")).is_true()


func _scripts() -> Array[String]:
	var found: Array[String] = []
	for root: String in SCANNED:
		if root.ends_with(".gd"):
			found.append(root)
		else:
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
