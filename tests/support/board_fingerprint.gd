# A TOTAL snapshot of everything a test could dirty, so a shared-scene fixture can prove it did not
# (#622, leaf B). Two calls: take() before a case and take() after, then differences() names what
# moved. Nothing here resets anything -- that is clear_board's job, and keeping the two apart is the
# point: this is the independent witness, not the mechanism under test.
#
# WHY A DIFF AND NOT "RUN THE NEXT TEST AND SEE". A leak observed by a later case is a flake -- it
# depends on what that case happens to look at. A diff against the pristine state is DETERMINISTIC:
# it fails at the case that leaked, every run, naming the field. That is the whole argument for
# sharing a scene at all; without it, sharing trades a slow suite for an unreliable one.
#
# THREE THINGS IT COVERS, matching the three places state lives (#622's taxonomy):
#   1. the BOARD, via ScenarioManager.capture_scenario -- the same #87 door apply_scenario reverses.
#   2. TUNING, via the knob tables, which already enumerate every process-scoped value a panel or a
#      test can move. Derived, never listed: Law #4, so this and the panels cannot disagree.
#   3. the RESIDUE that belongs to neither -- staging, Dialogic, and the settings stores.
#
# The board half compares by REFLECTION rather than by serializing. Serializing looks obvious and is
# wrong: ResourceSaver mints `[sub_resource id="..."]` ids per save, so two saves of identical data
# differ and every case would report a leak. Reflection over PROPERTY_USAGE_STORAGE is derived from
# the @export declarations, so it needs no field list here and picks up new fields automatically --
# which is the same reason #258's embedded-content trap exists and the same defence against it.
class_name BoardFingerprint

# Floats and colours are compared with LookKnobs.same_value, which is APPROXIMATE on purpose: engine
# properties store single precision and a euler component round-trips through a basis, so an exact
# compare reports movement that never happened (the lesson #212 records for the Moods tab's own
# "has this moved?").
const MAX_DEPTH := 6


static func take(host: Node3D, scenario_manager) -> Dictionary:
	return {
		"board": _board_state(scenario_manager),
		"class_knobs": GameKnobs.capture_class_baseline(host),
		"node_knobs": node_knob_values(host),
		"staged_cells": _sorted_cells(BoardSpace.staged_cells()),
		"dialog_running": Dialogic.current_timeline != null,
		# The two settings stores. Both keep a static _state Dictionary that outlives any scene, so a
		# case that flips one hands it to every case after it -- which is exactly what happened the
		# first time a suite was shared: test_board_mirror turns PHOTOSENSITIVITY on to prove the
		# fire holds still and never turns it back off, harmless while a per-case reset_for_test()
		# wiped it and a real leak the moment that reset moved to once-per-suite. Nothing here could
		# see it, which is the argument for sampling them rather than trusting the recipe.
		"settings": _settings_state(),
		"experiments": _experiments_state(),
		# The camera is re-framed by apply_scenario (board_loaded -> fit_camera), so this is not
		# expected to move -- which is exactly why it is sampled. "The reset probably covers it"
		# is an argument; a diff is a guarantee, and camera suites are the ones most likely to
		# leave it somewhere.
		"camera": _resource_state(_camera_pose(host), 0),
		# A case that exits leaving ATTACK_TARGETING or a selection live hands the next case a
		# board mid-gesture. game_state is the one flag that says so.
		"game_state": _game_state(host),
		# The HOSTING VIEW, which is the same class of fact one layer out: not "what is on the
		# board" but "who is being shown it, and who owns the input". A case that swaps to FLAT_2D
		# stands the 3D picker down -- pointer_source is uninstalled, so HoverPresenter falls back
		# to the real mouse and every later case hovers wherever the headless cursor happens to sit.
		# Measured, not imagined: that is exactly what test_overlay_mirror's FLAT_2D case did to the
		# two crown cases after it, and the symptom was a hover that drew nothing at all.
		"view": null if host == null else host.get("view"),
		# ...and its sibling one level in: DEV MODE. Also not board state -- a session toggle -- but
		# it decides what _base_state() rests on, so a case that switches it on leaves every later
		# case's game_state at DEV_MODE however cleanly the board itself was restored. Sampled
		# separately from game_state because the two answer different questions and only this one
		# says WHY: "game_state: 0 -> 6" names the symptom, this names the cause.
		"dev_mode": _dev_mode(host),
	}


static func _camera_pose(host: Node3D) -> Resource:
	if host == null or not host.has_method("capture_camera_start"):
		return null
	return host.capture_camera_start()


static func _game_state(host: Node3D) -> Variant:
	if host == null:
		return null
	var game: Variant = host.get("game")
	return null if game == null else game.get("game_state")


# Derived from each store's own DEFS rather than listed, so a setting added later is covered with
# no edit here -- the same reason the tuning half reads the knob tables (Law #4).
static func _settings_state() -> Dictionary:
	var out := {}
	for setting: PlayerSettings.Setting in PlayerSettings.DEFS:
		out[PlayerSettings.Setting.keys()[setting]] = PlayerSettings.is_on(setting)
	return out


static func _experiments_state() -> Dictionary:
	var out := {}
	for flag: Experiments.Flag in Experiments.DEFS:
		out[Experiments.Flag.keys()[flag]] = Experiments.is_on(flag)
	return out


static func _dev_mode(host: Node3D) -> Variant:
	if host == null:
		return null
	var game: Variant = host.get("game")
	return null if game == null else game.get("dev_mode_enabled")


static func differences(before: Dictionary, after: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	_diff_value("board", before.get("board"), after.get("board"), out, 0)
	_diff_indexed("class knob", GameKnobs.CLASS_KNOBS, before.get("class_knobs", []),
			after.get("class_knobs", []), out)
	_diff_indexed("look knob", node_knob_table(), before.get("node_knobs", []),
			after.get("node_knobs", []), out)
	if str(before.get("staged_cells")) != str(after.get("staged_cells")):
		out.append("BoardSpace staging: %s -> %s" % [before.get("staged_cells"), after.get("staged_cells")])
	_diff_flags("setting", before.get("settings", {}), after.get("settings", {}), out)
	_diff_flags("experiment", before.get("experiments", {}), after.get("experiments", {}), out)
	if before.get("dialog_running") != after.get("dialog_running"):
		out.append("Dialogic timeline running: %s -> %s"
				% [before.get("dialog_running"), after.get("dialog_running")])
	_diff_value("camera", before.get("camera"), after.get("camera"), out, 0)
	if before.get("game_state") != after.get("game_state"):
		out.append("game_state: %s -> %s" % [before.get("game_state"), after.get("game_state")])
	if before.get("view") != after.get("view"):
		out.append("hosting view: %s -> %s" % [before.get("view"), after.get("view")])
	if before.get("dev_mode") != after.get("dev_mode"):
		out.append("dev mode: %s -> %s" % [before.get("dev_mode"), after.get("dev_mode")])
	return out


# --- the board half ------------------------------------------------------------------------------

# capture_scenario is the #87 door and it is total by construction: apply_scenario is its inverse,
# so anything apply_scenario would restore is something this sees. Its own deliberate omissions
# (the queued plan, the aiming cursor, projected knockback) are re-derived rather than stored, which
# is exactly why they are not leak candidates.
static func _board_state(scenario_manager) -> Dictionary:
	var scenario: ScenarioData = scenario_manager.capture_scenario("__fingerprint")
	var state: Dictionary = _resource_state(scenario, 0)
	# tile_data is a PackedByteArray whose ORDER follows insertion, so a board that is cleared and
	# rewritten with identical contents serializes to different bytes. Comparing it raw reports a
	# leak on every case that repaints -- the same trap as ResourceSaver's sub_resource ids, found
	# the same way (converting test_board_mirror, #622). Replaced with a canonical description read
	# from the grid: what the board IS, rather than the order it was written in.
	state.erase("tile_data")
	state["cells"] = _cells_of(scenario_manager)
	return state


static func _cells_of(scenario_manager) -> Array:
	var grid: Variant = scenario_manager.get("grid")
	if grid == null:
		return []
	var rows: Array = []
	for cell: Vector2i in grid.get_used_cells():
		rows.append("%d,%d=%d/%s/%d" % [cell.x, cell.y, grid.get_cell_source_id(cell),
				grid.get_cell_atlas_coords(cell), grid.get_cell_alternative_tile(cell)])
	rows.sort()
	return rows


static func _resource_state(res: Resource, depth: int) -> Variant:
	if res == null:
		return null
	if depth >= MAX_DEPTH:
		return "<depth>"
	var state := {}
	for prop: Dictionary in res.get_property_list():
		if not (int(prop.get("usage", 0)) & PROPERTY_USAGE_STORAGE):
			continue
		var name: String = prop.get("name", "")
		if name == "" or name == "resource_local_to_scene" or name == "resource_path" \
				or name == "resource_name" or name == "script":
			continue
		state[name] = _plain(res.get(name), depth + 1)
	return state


static func _plain(value: Variant, depth: int) -> Variant:
	if value is Resource:
		return _resource_state(value as Resource, depth)
	if value is Array:
		var items := []
		for item: Variant in value:
			items.append(_plain(item, depth))
		return items
	if value is Dictionary:
		# Sorted, because a Dictionary's iteration order is insertion order and a rebuilt board can
		# legitimately fill the same keys in a different sequence.
		var keys := (value as Dictionary).keys()
		keys.sort_custom(func(a, b): return str(a) < str(b))
		var out := {}
		for key: Variant in keys:
			out[str(key)] = _plain(value[key], depth)
		return out
	return value


# --- the tuning half -----------------------------------------------------------------------------

static func node_knob_table() -> Array[Dictionary]:
	var table: Array[Dictionary] = []
	table.append_array(LookKnobs.KNOBS)
	table.append_array(GameKnobs.KNOBS)
	return table


static func node_knob_values(host: Node3D) -> Array:
	var values := []
	for knob: Dictionary in node_knob_table():
		values.append(LookKnobs.read(host, knob))
	return values


# --- diffing -------------------------------------------------------------------------------------

static func _diff_indexed(label: String, table: Array, before: Array, after: Array,
		out: PackedStringArray) -> void:
	for i in mini(before.size(), after.size()):
		if LookKnobs.same_value(before[i], after[i]):
			continue
		var knob: Dictionary = table[i] if i < table.size() else {}
		var name: String = str(knob.get("static", knob.get("prop", "#%d" % i)))
		out.append("%s %s: %s -> %s" % [label, name, before[i], after[i]])


static func _diff_flags(label: String, before: Dictionary, after: Dictionary,
		out: PackedStringArray) -> void:
	for key: String in before:
		if before[key] != after.get(key, before[key]):
			out.append("%s %s: %s -> %s" % [label, key, before[key], after[key]])


static func _diff_value(path: String, before: Variant, after: Variant, out: PackedStringArray,
		depth: int) -> void:
	if depth >= MAX_DEPTH:
		return
	if before is Dictionary and after is Dictionary:
		var keys := {}
		for k: Variant in (before as Dictionary).keys():
			keys[k] = true
		for k: Variant in (after as Dictionary).keys():
			keys[k] = true
		for key: Variant in keys:
			_diff_value("%s.%s" % [path, key], (before as Dictionary).get(key),
					(after as Dictionary).get(key), out, depth + 1)
		return
	if before is Array and after is Array:
		if (before as Array).size() != (after as Array).size():
			out.append("%s: %d entries -> %d" % [path, (before as Array).size(), (after as Array).size()])
			return
		for i in (before as Array).size():
			_diff_value("%s[%d]" % [path, i], before[i], after[i], out, depth + 1)
		return
	if LookKnobs.same_value(before, after):
		return
	out.append("%s: %s -> %s" % [path, _short(before), _short(after)])


static func _short(value: Variant) -> String:
	var text := str(value)
	return text if text.length() <= 80 else text.substr(0, 77) + "..."


static func _sorted_cells(cells: Array[Vector2i]) -> Array:
	var out := []
	for cell: Vector2i in cells:
		out.append(str(cell))
	out.sort()
	return out
