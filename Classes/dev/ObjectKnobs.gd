extends Object
class_name ObjectKnobs

# WHAT a terrain object's presentation fields are, and how a tuned one gets WRITTEN BACK to the
# place it is authored (#272). Static and pure -- LookKnobs' twin, one shelf along.
#
# It lives in Classes/dev/ rather than beside LookKnobs in presentation/ precisely because no
# shipping code reads it: a look is MISSION data (ScenarioData names a preset, battle3d applies it),
# and these are not. A block's height, a tuft's height and a cover bump's height are art conventions
# matched to the tile art ONCE and then constant for the whole game -- so there is nothing for a
# board to carry, and the only thing missing was a door to the authored value.
#
# That door is the difference from LookTool's Copy Values. A look knob's answer is "paste this line
# into Battle3D.tscn"; these three are authored as @export DEFAULTS in BoardMirror.gd -- measured,
# the scene overrides none of them -- so the honest write is the declaration line itself. One
# authority, edited in place, and a law in tests/dev/test_object_knobs.gd pins both halves of that
# claim (every prop is findable in its own script; the scene overrides none of them).
#
# res:// is writable only in an editor run, which is the whole population: DevTools.enabled() also
# admits a "devtools" export feature, but no export preset declares one, and the dev's ruling
# (2026-08-16) is that no build ever carries these tools. A failed write is REPORTED, never assumed.
#
# Slice 1 holds only the globals that already existed. Per-tile-TYPE fields (a lamp's own light) are
# the TileSet's custom-data layers and land next; per PLACED instance has no store at all and is a
# separate feature.

# Same row shape as LookKnobs.KNOBS -- node = path relative to the host, prop = property name -- so
# reading and writing a live value route through LookKnobs.read/write rather than a second copy of
# get_indexed. Only the TABLE forks; the property access does not.
const KNOBS: Array[Dictionary] = [
	{"group": "Globals", "node": "BoardMirror", "prop": "block_height_scale", "label": "Prop block height", "min": 0.2, "max": 2.5, "step": 0.01,
		"tip": "How tall a solid prop -- crate, chest, rock, pot -- stands relative to its own sprite. 1.0 is the height measured off the art; because the art is drawn in 3/4 it includes some of the object's own lid, so the honest measurement usually reads a little tall."},
	{"group": "Globals", "node": "BoardMirror", "prop": "tuft_scale", "label": "Grass tuft scale", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How tall the plants on a grass tile stand -- the flowers and weeds that pop up off a tile which is also still painted flat. 1.0 draws each one at the size the art draws it. Only the height changes: where they sit in the cell comes off the art."},
	{"group": "Globals", "node": "BoardMirror", "prop": "cover_scale", "label": "Cover bump scale", "min": 0.0, "max": 2.0, "step": 0.01,
		"tip": "How tall the mud bumps a dug-in Cover tile pops up stand, relative to the icon that draws them. 1.0 is the drawn size. Only the height changes: how many bumps there are and where they sit in the cell both come off the art."},
]

# The declaration this rewrites. Both spellings of an authored default are accepted (`:= value` and
# `: Type = value`) and any `: set = _x` suffix is CARRIED, not dropped -- two of the three knobs
# below own a setter, and losing it would silently un-live the knob rather than fail.
const EXPORT_LINE := "(?m)^(@export[ \\t]+var[ \\t]+%s[ \\t]*(?::[ \\t]*\\w+[ \\t]*=|:=)[ \\t]*)(.+?)([ \\t]*:[ \\t]*set[ \\t]*=[ \\t]*\\w+)?$"


# The whole write, as a pure string transform: source in, source out. Testable without a real file,
# which matters because the failure worth catching is the SILENT one -- so a property this cannot
# find returns "", never the source unchanged. A caller cannot then mistake a no-op for a save.
static func rewrite_export_default(source: String, prop: String, literal: String) -> String:
	if not prop.is_valid_identifier():
		push_error("ObjectKnobs: '%s' is not a plain property name -- a component path has no declaration line to write" % prop)
		return ""
	var re := RegEx.create_from_string(EXPORT_LINE % prop)
	if re == null:
		return ""
	var found := re.search(source)
	if found == null:
		return ""
	# Rebuilt from the match rather than through sub(), so a literal containing $ could never be
	# read as a backreference.
	var line := found.get_string(1) + literal + found.get_string(3)
	return source.substr(0, found.get_start(0)) + line + source.substr(found.get_end(0))


# Where a knob's value is authored: the script of the node it names. DERIVED rather than a column
# on the row -- the table already says which node owns the property, and a second spelling of
# "which file" would go stale the first time a node's script moved.
static func script_path_for(host: Node3D, knob: Dictionary) -> String:
	var target := LookKnobs.target_of(host, knob)
	if target == null:
		return ""
	var script := target.get_script() as Script
	if script == null:
		return ""
	return script.resource_path


# Write each named knob's LIVE value over its authored default. Takes KNOBS INDICES rather than the
# rows themselves so the answer can name exactly which ones landed -- the panel needs that to move
# its baseline, and identity-comparing Dictionaries to work it out afterwards would be a second,
# worse spelling of the same fact.
#
# Grouped by file so one script is read and written once however many knobs it holds. Returns
# {written, failed: display lines; saved: the indices now on disk}.
static func save_to_source(host: Node3D, indices: PackedInt32Array) -> Dictionary:
	var report := {"written": PackedStringArray(), "failed": PackedStringArray(),
		"saved": PackedInt32Array()}
	var by_path: Dictionary[String, PackedInt32Array] = {}
	for i: int in indices:
		var path := script_path_for(host, KNOBS[i])
		if path.is_empty():
			report["failed"].append("%s: no script to write" % KNOBS[i]["label"])
			continue
		if not by_path.has(path):
			by_path[path] = PackedInt32Array()
		by_path[path].append(i)
	for path: String in by_path:
		_save_one_file(host, path, by_path[path], report)
	return report


static func _save_one_file(host: Node3D, path: String, indices: PackedInt32Array,
		report: Dictionary) -> void:
	var source := _read_source(path)
	if source.is_empty():
		for i: int in indices:
			report["failed"].append("%s: could not read %s" % [KNOBS[i]["label"], path])
		return
	var lines: PackedStringArray = PackedStringArray()
	var landed: PackedInt32Array = PackedInt32Array()
	for i: int in indices:
		var prop: String = KNOBS[i]["prop"]
		var literal := DevWidgets.literal_for(LookKnobs.read(host, KNOBS[i]))
		var updated := rewrite_export_default(source, prop, literal)
		if updated.is_empty():
			report["failed"].append("%s: no '@export var %s' line in %s"
				% [KNOBS[i]["label"], prop, path.get_file()])
			continue
		source = updated
		lines.append("%s = %s" % [prop, literal])
		landed.append(i)
	if lines.is_empty():
		return
	if not _write_source(path, source):
		for line: String in lines:
			report["failed"].append("%s: could not write %s" % [line, path])
		return
	for line: String in lines:
		report["written"].append("%s  (%s)" % [line, path.get_file()])
	report["saved"].append_array(landed)


static func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ObjectKnobs: cannot read %s (%s)" % [path, FileAccess.get_open_error()])
		return ""
	return file.get_as_text()


static func _write_source(path: String, source: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ObjectKnobs: cannot write %s (%s)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(source)
	return true
