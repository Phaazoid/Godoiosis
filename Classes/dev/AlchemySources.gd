extends VBoxContainer
class_name AlchemySources

# THE ALCHEMY PAGE'S SOURCES TAB (#1532, AlchemyTool hosts it): SubstanceMap's four tables -- what each
# ground kind, tile state, gas and unit state is MADE of, which is what a carving cast beside one can
# draw on (CellSubstances).
#
# IT EDITS THE LIVE MAP, never a copy: for the shipped path that is SubstanceMap.authored(), the one
# object every reader reads, so a row reaches the next cast with no save. A row is parsed on every
# keystroke and written only when it parses -- every term a real substance file, none twice -- so the
# table never holds a name nothing answers to (tests/law/test_substance_map.gd). A row's readout is
# CellSubstances.present_from, the walk a cast runs, so the page cannot disagree with play.
#
# A write moves whether a carving fizzles, so it re-resolves the open plan (a queued cast may turn red)
# and drops the enemy-range cache, as every page that moves what an enemy reaches does (#1360).
#
# The rows feed PRESENCE only (dev ruling 2026-10-30): Materia's +1 is a declared second reading. A vein
# (#696) is per tile or per cell, so it gets no row here.

const NOTE_COLOR := Color(0.62, 0.82, 1.0, 1)   # WeightsTool's note blue
const BAD_COLOR := Color(1.0, 0.45, 0.4, 1)
const EMPTY_COLOR := Color(0.75, 0.75, 0.75, 1)
const NAME_WIDTH := 130
const FIELD_WIDTH := 240
const READOUT_WIDTH := 320
const NOTHING := "Nothing. A carving here draws on the air alone."

# The file the page edits and saves. A test aims it at a user:// copy.
var path := SubstanceMap.PATH

var _game = null
var _held: SubstanceMap = null
var _save_button: Button
var _reset_button: Button
var _status: Label
var _rows: VBoxContainer
# Written since the last save or reset. A pure FLAG, ObjectTool's shape: a write goes straight into the
# live map, so the honest question is whether it has diverged from disk, which any write answers yes to.
var _dirty := false
# Each row's field -> {table, key}: which SubstanceMap row it edits, so a test can find a row by it.
var _fields: Dictionary[LineEdit, Dictionary] = {}
var _readouts: Dictionary[LineEdit, Label] = {}


func _ready() -> void:
	var buttons := HBoxContainer.new()
	add_child(buttons)
	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.tooltip_text = "Write every row on this page into its file. Asks first."
	_save_button.pressed.connect(_on_save_pressed)
	buttons.add_child(_save_button)
	_reset_button = Button.new()
	_reset_button.text = "Reset"
	_reset_button.tooltip_text = "Put every row back to what is saved on disk. Greyed while nothing has moved."
	_reset_button.pressed.connect(_on_reset_pressed)
	buttons.add_child(_reset_button)
	_status = Label.new()   # beside the buttons: an empty status takes no line of its own
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_status)
	var note := Label.new()
	note.text = ("What each thing on the board is MADE of: what a carving cast within %d %s of it can draw "
		+ "on. A change reaches the next cast. Save writes %s. It never changes what EMPOWERS a carving "
		+ "(the +1 from water, rock or fire).") % [Materia.REACH, "tile" if Materia.REACH == 1 else "tiles",
		path.trim_prefix("res://")]
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", NOTE_COLOR)
	add_child(note)
	_rows = DevWidgets.add_knob_scroll(self)
	_rebuild()
	_refresh_dirty()


func init(game) -> void:
	_game = game


func refresh_on_show() -> void:
	_rebuild()


func is_dirty() -> bool:
	return _dirty


# The tables, each with the members test_substance_map holds to a row and the name a player reads.
static func groups() -> Array[Dictionary]:
	var retired: Array = [Terrain.TileState.NONE]
	retired.append_array(Terrain.RETIRED_STATES)
	return [
		{"title": "Grounds", "table": &"grounds", "members": _members(Terrain.Kind.values(),
			[Terrain.Kind.NONE], func(k: int) -> String: return Terrain.kind_display_name(k as Terrain.Kind))},
		{"title": "Tile states", "table": &"tile_states", "members": _members(Terrain.TileState.values(),
			retired, func(k: int) -> String: return Terrain.tile_state_display_name(k as Terrain.TileState))},
		{"title": "Gases", "table": &"gases", "members": _members(Gas.Kind.values(),
			[], func(k: int) -> String: return Gas.display_name(k as Gas.Kind))},
		{"title": "Unit states", "table": &"unit_states", "members": _members(Elemental.State.values(),
			[Elemental.State.NONE], func(k: int) -> String: return Elemental.state_display_name(k as Elemental.State))},
	]


static func _members(values: Array, skip: Array, name_of: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: int in values:
		if not skip.has(key):
			out.append({"key": key, "name": name_of.call(key)})
	return out


# The ids a row's text names, or why it cannot be written. Terms are joined by `+`, and an empty one
# is skipped, so a half-typed `dirt + ` still reads as dirt.
static func parse_row(text: String, catalog: Dictionary) -> Dictionary:
	var ids: Array[String] = []
	for raw: String in text.split("+", false):
		var id := raw.strip_edges()
		if id == "":
			continue
		if not catalog.has(id):
			return {"ids": ids, "error": "No substance \"%s\". Not written: casts still read the row as it was." % id}
		if ids.has(id):
			return {"ids": ids, "error": "%s is named twice. Not written: casts still read the row as it was." % id}
		ids.append(id)
	return {"ids": ids, "error": ""}


# What a row makes present, as names: the row's own substances, then the parts they lend.
static func present_names(ids: Array[String]) -> Dictionary:
	var catalog := SubstanceCatalog.get_all()
	var own := PackedStringArray()
	var parts := PackedStringArray()
	for id: String in CellSubstances.present_from(ids):
		if ids.has(id):
			own.append(_name(id, catalog))
		else:
			parts.append(_name(id, catalog))
	return {"own": own, "parts": parts}


# The Tiles page's line for a ground, from the same reading as this page's readout.
static func made_of_line(ids: Array[String]) -> String:
	if ids.is_empty():
		return "Made of: nothing   (edit on Project > Alchemy)"
	var named := present_names(ids)
	var line := "Made of: " + " + ".join(named["own"])
	if not (named["parts"] as PackedStringArray).is_empty():
		line += ", and %s parts %s" % [_its(ids), ", ".join(named["parts"])]
	return line + "   (edit on Project > Alchemy)"


static func _its(ids: Array[String]) -> String:
	return "its" if ids.size() == 1 else "their"


static func _name(id: String, catalog: Dictionary) -> String:
	var substance := catalog.get(id) as Substance
	if substance != null and substance.display_name != "":
		return substance.display_name
	return id


# HELD, so the object written between saves is the one Save writes and Reset reverts: nothing else
# holds a map loaded from another path, and the cache drops an unheld resource.
func _map() -> SubstanceMap:
	if _held == null or _held.resource_path != path:
		_held = SubstanceMap.authored() if path == SubstanceMap.PATH else load(path) as SubstanceMap
	return _held


func _row(map: SubstanceMap, table: StringName, key: int) -> Array[String]:
	var out: Array[String] = []
	out.assign(Array((map.get(table) as Dictionary).get(key, PackedStringArray())))
	return out


func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_fields.clear()
	_readouts.clear()
	var map := _map()
	for group: Dictionary in groups():
		var heading := Label.new()
		heading.text = group["title"]
		heading.add_theme_color_override("font_color", DevWidgets.HEADING_COLOR)
		heading.set_meta(DevWidgets.HEADING_META, true)
		_rows.add_child(heading)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		_rows.add_child(grid)
		for member: Dictionary in group["members"]:
			_add_row(grid, map, group["table"], member)


func _add_row(grid: GridContainer, map: SubstanceMap, table: StringName, member: Dictionary) -> void:
	var tip := DevWidgets.wrap_tooltip(("What %s is made of: substance file names (Resources/Substances/) "
		+ "joined by +. A carving cast within %d tile of it can draw on each one, and on the parts a "
		+ "compound lends. Empty means nothing.") % [member["name"], Materia.REACH])
	var label := Label.new()
	label.text = "    " + String(member["name"])
	label.custom_minimum_size = Vector2(NAME_WIDTH, 0)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(label)
	var field := LineEdit.new()
	field.text = " + ".join(_row(map, table, member["key"]))
	field.placeholder_text = "nothing"
	field.custom_minimum_size = Vector2(FIELD_WIDTH, 0)
	grid.add_child(field)
	var readout := Label.new()
	readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readout.custom_minimum_size = Vector2(READOUT_WIDTH, 0)
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readout.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(readout)
	for node: Control in [label, field, readout]:
		DevWidgets.apply_tooltip(node, tip)
	_fields[field] = {"table": table, "key": member["key"]}
	_readouts[field] = readout
	_show_readout(field, _row(map, table, member["key"]))
	field.text_changed.connect(func(text: String) -> void: _on_row_typed(field, text))


func _on_row_typed(field: LineEdit, text: String) -> void:
	var parsed := parse_row(text, SubstanceCatalog.get_all())
	if parsed["error"] != "":
		var readout := _readouts[field]
		readout.text = parsed["error"]
		readout.add_theme_color_override("font_color", BAD_COLOR)
		return
	var row: Dictionary = _fields[field]
	var ids: Array[String] = parsed["ids"]
	(_map().get(row["table"]) as Dictionary)[row["key"]] = PackedStringArray(ids)
	_show_readout(field, ids)
	_dirty = true
	_refresh_dirty()
	_redraw_plan()


func _show_readout(field: LineEdit, ids: Array[String]) -> void:
	var readout := _readouts[field]
	readout.remove_theme_color_override("font_color")
	if ids.is_empty():
		readout.text = NOTHING
		readout.add_theme_color_override("font_color", EMPTY_COLOR)
		return
	var named := present_names(ids)
	var text := ", ".join(named["own"])
	if not (named["parts"] as PackedStringArray).is_empty():
		text += "   and %s parts: %s" % [_its(ids), ", ".join(named["parts"])]
	var row: Dictionary = _fields[field]
	if row["table"] == &"grounds" and row["key"] == Terrain.Kind.WATER:
		text += "   (open water only: ice offers %s's row)" % Terrain.tile_state_display_name(Terrain.TileState.FROZEN)
	elif row["table"] == &"tile_states" and row["key"] == Terrain.TileState.BURNING:
		text += "   (and every lit prop)"
	readout.text = text


# A queued cast may have just started or stopped fizzling, and an enemy's reach with it.
func _redraw_plan() -> void:
	AlchemyTool.redraw_plan(_game)


func _refresh_dirty() -> void:
	DevWidgets.mark_unsaved(_save_button, "Save", _dirty)
	DevWidgets.offer_reset(_reset_button, _dirty)


func _on_save_pressed() -> void:
	if not _dirty:
		_status.text = "Nothing has moved off what is saved."
		return
	DevWidgets.confirm(self, "Write what each thing is made of to %s? Its saved rows are replaced."
		% path.trim_prefix("res://"), save_now)


func save_now() -> void:
	if DevWidgets.save_over(_map(), path, _status):
		_dirty = false
		_status.text = "Saved %s." % path.trim_prefix("res://")
	_refresh_dirty()


func _on_reset_pressed() -> void:
	if DevWidgets.revert_to_saved(_map(), path, _status):
		_dirty = false
		_status.text = "Back to what is saved on disk."
	_rebuild()
	_refresh_dirty()
	_redraw_plan()
