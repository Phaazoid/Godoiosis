extends Object
class_name KnobSource

# HOW a tuned game constant gets written back to the place it is authored (#272, widened by #373).
# Static and pure -- no table of its own, and that is the point: it is the one answer to "keep this
# value". Since #380 the Game tab is its one caller (the Objects tab saves per-type fields into the
# TILESET instead), but the split stands on its own: the transform is testable without a table, and
# the next table that wants a Save gets this one rather than a copy that agrees right up until one
# of them is taught something the other is not.
#
# A tuned value has three destinations (#272): mission mood -> a LookPreset, per object type -> a
# TileSet custom-data column, GAME CONSTANT -> here, the declaration line itself. One authority,
# edited in place, so the change shows up as an ordinary line in the diff.
#
# res:// is writable only in an editor run, which is the whole population: no export preset declares
# the `devtools` feature (dev, 2026-08-16 -- builds never carry these tools). A failed write is
# REPORTED, never assumed.

# WHAT can be rewritten. Two shapes, because a game constant is authored two ways: as a var's
# default, or as a field of a const table that has no var to name.
enum Kind {
	DECLARATION,   # `@export var x := v` / `static var x := v` -- the var's own default
	LAYER_COLOR,   # `Layer.X: {"color": v, ...}` -- one entry of BoardOverlays.LAYERS
}

# Both spellings of an authored default are accepted (`:= value` and `: Type = value`) and any
# `: set = _x` suffix is CARRIED, not dropped -- several knobs own a setter, and losing it would
# silently un-live the knob rather than fail. A trailing # comment is carried the same way (#378:
# the first real Save deleted billboard_lift's), and the value group excluding # is what makes
# that sound -- the value can never cross into a comment, so a comment whose TEXT contains
# ": set = foo" cannot be half-eaten as a setter. No knob value contains # (DevWidgets.literal_for
# emits numeric Color forms, never hex strings), and the save laws run this against every real
# declaration, so one arriving later fails there. `@export` and `static` are one pattern rather
# than two: which prefix a declaration wears is a fact about the SOURCE, not about the caller's
# intent, and a name is unique in its script either way. The `^` anchor is what keeps an indented
# local `var` of the same name out.
const DECLARATION_LINE := "(?m)^((?:@export|static)[ \\t]+var[ \\t]+%s[ \\t]*(?::[ \\t]*\\w+[ \\t]*=|:=)[ \\t]*)([^#\\n]+?)([ \\t]*:[ \\t]*set[ \\t]*=[ \\t]*\\w+)?([ \\t]*#[^\\n]*)?$"

# One entry of a const Layer -> spec dictionary, keyed by the layer's NAME as written. The value is
# a Color(...) call or a constant reference, and it cannot be matched as "up to the next comma" --
# Color(1, 1, 0, 0.5) is full of commas. Reformatting LAYERS to multi-line entries breaks this,
# which is why a miss is a reported failure rather than a silent one, and why a law pins that every
# layer knob is still findable.
const LAYER_COLOR_LINE := "(?m)^([ \\t]*Layer\\.%s:[ \\t]*\\{[ \\t]*\"color\":[ \\t]*)(Color\\([^)]*\\)|[A-Za-z_][\\w.]*)"


# --- The transforms ----------------------------------------------------------------------------
#
# Source in, source out, testable without a real file -- which matters because the failure worth
# catching is the SILENT one. Neither returns the source unchanged on a miss; both return "", so a
# caller cannot mistake a no-op for a save.

static func rewrite_declaration_default(source: String, prop: String, literal: String) -> String:
	if not prop.is_valid_identifier():
		push_error("KnobSource: '%s' is not a plain property name -- a component path has no declaration line to write" % prop)
		return ""
	return _rewrite(source, DECLARATION_LINE % prop, literal, true)


static func rewrite_layer_color(source: String, layer_name: String, literal: String) -> String:
	if not layer_name.is_valid_identifier():
		push_error("KnobSource: '%s' is not a plain Layer name" % layer_name)
		return ""
	return _rewrite(source, LAYER_COLOR_LINE % layer_name, literal, false)


# Rebuilt from the match rather than through sub(), so a literal containing $ could never be read
# as a backreference. `keep_suffix` carries groups 3 and 4 (a declaration's `: set = _x` and its
# trailing comment, in that order -- #378); the layer form has neither group and keeps whatever
# follows the value untouched by ending the match there.
static func _rewrite(source: String, pattern: String, literal: String, keep_suffix: bool) -> String:
	var re := RegEx.create_from_string(pattern)
	if re == null:
		return ""
	var found := re.search(source)
	if found == null:
		return ""
	var line := found.get_string(1) + literal
	if keep_suffix:
		line += found.get_string(3) + found.get_string(4)
	return source.substr(0, found.get_start(0)) + line + source.substr(found.get_end(0))


# --- Which declaration, and where ---------------------------------------------------------------

# WHICH declaration a knob's value is written into. A component knob (flame_size:x) tunes one axis
# of a property that is declared whole, so the line to write is the VECTOR's -- "x = 0.4" is not
# something a script can say. Its consequence: the width and height knobs collapse to one line.
static func declaration_prop(knob: Dictionary) -> String:
	return String(knob["prop"]).split(":")[0]


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


# --- Baselines ----------------------------------------------------------------------------------
#
# What is on disk, by definition: nothing has moved a knob at attach time, and after a save the
# written ones are re-read so the two agree again.

static func capture_baseline(host: Node3D, table: Array[Dictionary]) -> Array:
	var baseline: Array = []
	for knob: Dictionary in table:
		baseline.append(LookKnobs.read(host, knob))
	return baseline


# Which rows have been moved off what is saved. The APPROXIMATE compare, for LookKnobs' reason:
# engine properties store single-precision, so a value written and read straight back is not
# bit-identical and an exact compare reports every knob as changed the moment it is touched.
static func changed_indices(host: Node3D, table: Array[Dictionary], baseline: Array) -> PackedInt32Array:
	var moved: PackedInt32Array = PackedInt32Array()
	for i in table.size():
		var live: Variant = LookKnobs.read(host, table[i])
		if typeof(live) == TYPE_NIL:
			continue
		if i >= baseline.size() or not LookKnobs.same_value(live, baseline[i]):
			moved.append(i)
	return moved


# --- Writing ------------------------------------------------------------------------------------

# One edit = one value going into one file. The panels build these; this file applies them. Keeping
# the two apart is what lets a Save mix kinds -- the Game tab writes a marker's lift and a layer's
# colour, both authored in BoardOverlays.gd, in a single read-modify-write.
#
# `source` is the caller's own name for WHICH table the row came from, carried so the report can say
# it back. A panel with two tables cannot read a bare index: they share an index space, so row 3 of
# each would be one number and the wrong baseline would move on a partial save.
static func edit(path: String, kind: Kind, name: String, literal: String, label: String,
		index: int, source := "") -> Dictionary:
	return {"path": path, "kind": kind, "name": name, "literal": literal, "label": label,
		"index": index, "source": source}


# The declaration edits for a table's moved rows. Takes INDICES rather than the rows themselves so
# the answer can name exactly which ones landed -- a panel needs that to move its baseline, and
# identity-comparing Dictionaries afterwards would be a second, worse spelling of the same fact.
static func declaration_edits(host: Node3D, table: Array[Dictionary], indices: PackedInt32Array,
		source := "") -> Array[Dictionary]:
	var edits: Array[Dictionary] = []
	for i: int in indices:
		var knob: Dictionary = table[i]
		var prop := declaration_prop(knob)
		# The whole property, never the component: what gets written is the declaration's value.
		var target := LookKnobs.target_of(host, knob)
		var literal := DevWidgets.literal_for(null if target == null else target.get(prop))
		edits.append(edit(script_path_for(host, knob), Kind.DECLARATION, prop, literal,
			knob["label"], i, source))
	return edits


# Grouped by file so one script is read and written once however many edits it holds. Returns
# {written, failed: display lines; saved: the EDITS now on disk, so a caller reads back both which
# row landed and which table it came from}.
static func apply_edits(edits: Array[Dictionary]) -> Dictionary:
	var report := {"written": PackedStringArray(), "failed": PackedStringArray(),
		"saved": [] as Array[Dictionary]}
	var by_path: Dictionary[String, Array] = {}
	for an_edit: Dictionary in edits:
		var path: String = an_edit["path"]
		if path.is_empty():
			report["failed"].append("%s: no script to write" % an_edit["label"])
			continue
		if not by_path.has(path):
			by_path[path] = []
		by_path[path].append(an_edit)
	for path: String in by_path:
		_save_one_file(path, by_path[path], report)
	return report


static func _save_one_file(path: String, edits: Array, report: Dictionary) -> void:
	var source := _read_source(path)
	if source.is_empty():
		for an_edit: Dictionary in edits:
			report["failed"].append("%s: could not read %s" % [an_edit["label"], path])
		return
	var lines: PackedStringArray = PackedStringArray()
	var landed: Array[Dictionary] = []
	var done: PackedStringArray = PackedStringArray()   # declarations already rewritten this pass
	for an_edit: Dictionary in edits:
		var kind: Kind = an_edit["kind"]
		var name: String = an_edit["name"]
		var key := "%d|%s" % [kind, name]
		# Two component knobs share one declaration, so the second is already saved by the first --
		# recorded as landed (its baseline must move) but not rewritten or reported twice.
		if done.has(key):
			landed.append(an_edit)
			continue
		var literal: String = an_edit["literal"]
		var updated := ""
		match kind:
			Kind.DECLARATION:
				updated = rewrite_declaration_default(source, name, literal)
			Kind.LAYER_COLOR:
				updated = rewrite_layer_color(source, name, literal)
		if updated.is_empty():
			report["failed"].append("%s: nothing to rewrite for %s in %s"
				% [an_edit["label"], name, path.get_file()])
			continue
		source = updated
		lines.append(_written_line(kind, name, literal))
		landed.append(an_edit)
		done.append(key)
	if lines.is_empty():
		return
	if not _write_source(path, source):
		for line: String in lines:
			report["failed"].append("%s: could not write %s" % [line, path])
		return
	for line: String in lines:
		report["written"].append("%s  (%s)" % [line, path.get_file()])
	report["saved"].append_array(landed)


static func _written_line(kind: Kind, name: String, literal: String) -> String:
	match kind:
		Kind.LAYER_COLOR:
			return "Layer.%s color = %s" % [name, literal]
	return "%s = %s" % [name, literal]


static func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("KnobSource: cannot read %s (%s)" % [path, FileAccess.get_open_error()])
		return ""
	return file.get_as_text()


static func _write_source(path: String, source: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("KnobSource: cannot write %s (%s)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(source)
	return true
