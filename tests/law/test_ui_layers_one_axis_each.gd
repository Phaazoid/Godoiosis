# A UiLayers value is read on the axis it was declared for (#1034).
#
# The table holds two kinds of number: CanvasLayer.layer values (LAYER_*), which order whole layers,
# and z_index values, which order siblings inside one layer and never cross into another -- for the
# eye or for the mouse. It once held both as one unprefixed list, the radial read its entry as a
# CanvasLayer while every card read theirs as a z_index, and the pause menu's 200 lost to the radial's
# 20. Nothing about a number says which axis it is on, so a wrong read compiles, runs, and is found in
# play. This scans every production write.
#
# The stated limit, as test_board_writes_announce's: a source scan sees an ASSIGNMENT spelled with
# the property name. A value passed through a variable first slips past. This is a backstop for
# review, not a proof.
extends GdUnitTestSuite

const SCANNED: Array[String] = ["res://Classes/", "res://Scenes/", "res://play/", "res://game.gd"]

# `.layer = UiLayers.X` -- the word boundary keeps `card_layer`/`ui_layer` receivers from matching on
# their own names; only the property after the dot does.
const LAYER_WRITE := "\\blayer\\s*=\\s*UiLayers\\.(\\w+)"
# `z_index = UiLayers.X`, `card_z_index = ...`, and a typed declaration (`var x_z_index: int = ...`).
# `[^=\n]*=` cannot cross an `==`, so a comparison is never read as a write.
const Z_WRITE := "z_index\\b[^=\\n]*=\\s*UiLayers\\.(\\w+)"


func test_every_ui_layers_write_reads_the_axis_it_was_declared_for() -> void:
	var layer_re := RegEx.create_from_string(LAYER_WRITE)
	var z_re := RegEx.create_from_string(Z_WRITE)
	var layer_writes := 0
	var z_writes := 0
	var offences: Array[String] = []
	for path: String in _scripts():
		var line_no := 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			line_no += 1
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			var hit := layer_re.search(code)
			if hit != null:
				layer_writes += 1
				if not hit.get_string(1).begins_with("LAYER_"):
					offences.append("%s:%d  a CanvasLayer given a z value: %s" % [path.get_file(), line_no, code])
			hit = z_re.search(code)
			if hit != null:
				z_writes += 1
				if hit.get_string(1).begins_with("LAYER_"):
					offences.append("%s:%d  a z_index given a layer value: %s" % [path.get_file(), line_no, code])

	assert_array(offences).override_failure_message(
		"These read a UiLayers value on the other axis. A z_index never crosses a CanvasLayer, so a "
		+ "number that looks larger can still lose -- see UiLayers' header:\n  " + "\n  ".join(offences)
	).is_empty()
	# Non-vacuity: a mis-rooted scan, or a pattern that stopped matching, passes the check above while
	# proving nothing. The counts are floors, not a census.
	assert_int(layer_writes).override_failure_message(
		"the scan found no CanvasLayer write -- LAYER_WRITE no longer matches the code").is_greater(0)
	assert_int(z_writes).override_failure_message(
		"the scan found no z_index write -- Z_WRITE no longer matches the code").is_greater(3)


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
