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
		"node_knobs": _node_knobs(host),
		"staged_cells": _sorted_cells(BoardSpace.staged_cells()),
		"dialog_running": Dialogic.current_timeline != null,
		# The camera is re-framed by apply_scenario (board_loaded -> fit_camera), so this is not
		# expected to move -- which is exactly why it is sampled. "The reset probably covers it"
		# is an argument; a diff is a guarantee, and camera suites are the ones most likely to
		# leave it somewhere.
		"camera": _resource_state(_camera_pose(host), 0),
		# A case that exits leaving ATTACK_TARGETING or a selection live hands the next case a
		# board mid-gesture. game_state is the one flag that says so.
		"game_state": _game_state(host),
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


static func differences(before: Dictionary, after: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	_diff_value("board", before.get("board"), after.get("board"), out, 0)
	_diff_indexed("class knob", GameKnobs.CLASS_KNOBS, before.get("class_knobs", []),
			after.get("class_knobs", []), out)
	_diff_indexed("look knob", _node_knob_table(), before.get("node_knobs", []),
			after.get("node_knobs", []), out)
	if str(before.get("staged_cells")) != str(after.get("staged_cells")):
		out.append("BoardSpace staging: %s -> %s" % [before.get("staged_cells"), after.get("staged_cells")])
	if before.get("dialog_running") != after.get("dialog_running"):
		out.append("Dialogic timeline running: %s -> %s"
				% [before.get("dialog_running"), after.get("dialog_running")])
	_diff_value("camera", before.get("camera"), after.get("camera"), out, 0)
	if before.get("game_state") != after.get("game_state"):
		out.append("game_state: %s -> %s" % [before.get("game_state"), after.get("game_state")])
	return out


# --- the board half ------------------------------------------------------------------------------

# capture_scenario is the #87 door and it is total by construction: apply_scenario is its inverse,
# so anything apply_scenario would restore is something this sees. Its own deliberate omissions
# (the queued plan, the aiming cursor, projected knockback) are re-derived rather than stored, which
# is exactly why they are not leak candidates.
static func _board_state(scenario_manager) -> Dictionary:
	var scenario: ScenarioData = scenario_manager.capture_scenario("__fingerprint")
	return _resource_state(scenario, 0)


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

static func _node_knob_table() -> Array[Dictionary]:
	var table: Array[Dictionary] = []
	table.append_array(LookKnobs.KNOBS)
	table.append_array(GameKnobs.KNOBS)
	return table


static func _node_knobs(host: Node3D) -> Array:
	var values := []
	for knob: Dictionary in _node_knob_table():
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
