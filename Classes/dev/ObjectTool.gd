extends VBoxContainer
class_name ObjectTool

# The dev-tools Objects tab (#272 slice 1): where a terrain object's presentation fields are tuned
# AND KEPT. LookTool's twin, and deliberately the same shape -- rows over a table, a baseline that
# Reset returns to, one action button.
#
# The difference is what the button does. A look is mission mood, so the Look tab's answer to "keep
# this" is a LookPreset a board can wear. These values are the same in every mission forever, so
# there is nothing to save them ONTO: the button writes the authored default in the owning script,
# which is where they already live. See ObjectKnobs for why that is one authority rather than two.
#
# The host is PUSHED in by DevOverlay.attach_3d_host, never looked up -- the same rule that keeps
# the game subtree free of an upward path to Battle3D, and the reason a flat Main.tscn launch
# reports "no 3D host" instead of failing.
#
# Slice 1 draws the Globals section alone. Per-tile-TYPE object fields land above it, from the
# TileSet's custom data, and the heading is here so the two stores stay visibly separate when they do.

const HEADING_COLOR := Color(1, 0.83, 0.4, 1)   # the Look and Scenario tabs' heading gold

var _host: Node3D
var _baseline: Array = []   # per KNOBS index: what is currently ON DISK, i.e. what Reset returns to
var _rows: VBoxContainer
var _status: Label
var _object_picker: OptionButton
var _objects: Array[Dictionary] = []   # ObjectKnobs.object_tiles, in picker order
var _picked := 0                       # survives the rebuild every field write triggers


func _ready() -> void:
	var buttons := HBoxContainer.new()
	buttons.add_child(_button("Save object fields",
		"Write every per-object field into the board's TILESET, where the tile itself carries it.\nThe board already shows them; this is what makes them permanent.",
		_on_save_fields_pressed))
	buttons.add_child(_button("Save to source",
		"Write every value you have moved into its authored default, in the script that declares it.\nThese are game-wide constants rather than mission mood, so this is the whole way to keep one --\nthe change shows up as an ordinary line in the diff. Editor runs only; res:// is read-only in a build.",
		_on_save_pressed))
	buttons.add_child(_button("Reset",
		"Put every field back to what is currently saved on disk.", _on_reset_pressed))
	add_child(buttons)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_rebuild()


# Called by DevOverlay once battle3d hands it the 3D scene. The 2D game boots first (Godot readies
# children before parents), so this tab always builds its no-host state and then rebuilds here.
func attach_host(host: Node3D) -> void:
	_host = host
	_capture_baseline()
	_rebuild()


func has_host() -> bool:
	return _host != null


# What is on disk, by definition: nothing has moved a knob yet at attach time, and after a save the
# written ones are re-read so the two agree again. Both this tab and the Game tab ask it, so the
# walk itself is KnobSource's.
func _capture_baseline() -> void:
	_baseline = KnobSource.capture_baseline(_host, ObjectKnobs.KNOBS)


func baseline_of(index: int) -> Variant:
	if index < 0 or index >= _baseline.size():
		return null
	return _baseline[index]


func changed_indices() -> PackedInt32Array:
	return KnobSource.changed_indices(_host, ObjectKnobs.KNOBS, _baseline)


func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if _host == null:
		DevWidgets.add_label(_rows, "No 3D host attached - the flat 2D game has no objects to tune.")
		return
	_build_object_section()
	var group := ""
	for knob: Dictionary in ObjectKnobs.KNOBS:
		var knob_group: String = knob["group"]
		if knob_group != group:
			group = knob_group
			_add_heading(group)
		DevWidgets.add_knob_row(_rows, knob, LookKnobs.read(_host, knob),
			func(value: Variant) -> void: LookKnobs.write(_host, knob, value),
			DevWidgets.wrap_tooltip(tip_for(knob)))


# --- Per-object fields -------------------------------------------------------------------------

# One object at a time, picked from a dropdown rather than fifteen expanded sections: the fields are
# per TYPE, so you tune one thing and look at it, and a wall of collapsed headers would cost more
# scrolling than it saves. Icon + authored name, the same identity the tile brush's palette shows.
func _build_object_section() -> void:
	_add_heading("Objects")
	var tiles := _tile_set()
	_objects = ObjectKnobs.object_tiles(tiles)
	if _objects.is_empty():
		DevWidgets.add_label(_rows, "The board's tileset declares no objects (no non-flat prop_shape).")
		return
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Object"
	row.add_child(label)
	_object_picker = OptionButton.new()
	for entry: Dictionary in _objects:
		_object_picker.add_icon_item(GridUtils.tile_sprite(entry["source"], entry["coords"]),
			_object_label(entry))
	_object_picker.selected = clampi(_picked, 0, _objects.size() - 1)
	_object_picker.item_selected.connect(_on_object_picked)
	row.add_child(_object_picker)
	_rows.add_child(row)
	_build_field_rows(_objects[_object_picker.selected])


# The authored name, falling back to the shape and sheet position — an unnamed prop is still a
# legitimate object, and it must not become unpickable just for being unnamed.
func _object_label(entry: Dictionary) -> String:
	var authored := GridUtils.authored_tile_display_name(entry["data"])
	if authored != "":
		return authored
	var shape_name: String = GridUtils.PropShape.keys()[entry["shape"]]
	var coords: Vector2i = entry["coords"]
	return "%s (%d:%d)" % [shape_name, coords.x, coords.y]


func _build_field_rows(entry: Dictionary) -> void:
	var data: TileData = entry["data"]
	var lit := GridUtils.prop_lit_of(data)
	for field: Dictionary in ObjectKnobs.fields_for(entry["shape"], lit):
		if field["type"] == TYPE_BOOL:
			_build_bool_field(data, field)
		else:
			_build_override_field(data, field)


# The one field with no global behind it, so no Inherit row: off IS the answer for most tiles.
func _build_bool_field(data: TileData, field: Dictionary) -> void:
	var first := _rows.get_child_count()
	DevWidgets.add_checkbox(_rows, field["label"], data.get_custom_data(field["layer"]),
		func(on: bool) -> void: _write_field(data, field["layer"], on))
	_tip_rows(first, field["tip"])


# An override row is TWO controls and that is the design: the checkbox says whether this object has
# an opinion, the control says what it is. Inheriting SHOWS the value it inherits rather than an
# empty slot -- a row that cannot say what it falls back to sends you looking for the global.
func _build_override_field(data: TileData, field: Dictionary) -> void:
	var layer: String = field["layer"]
	var is_color: bool = field["type"] == TYPE_COLOR
	var authored: Variant = GridUtils.prop_color_override_of(data, layer) if is_color \
		else GridUtils.prop_override_of(data, layer)
	var inherited: bool = GridUtils.is_inherited_color(authored) if is_color \
		else GridUtils.is_inherited(authored)
	var resolved: Variant = _resolved_value(data, field)
	var first := _rows.get_child_count()
	DevWidgets.add_checkbox(_rows, "%s - inherit" % field["label"], inherited,
		func(on: bool) -> void:
			# Ticking gives the value back to the global; unticking adopts whatever it currently
			# RESOLVES to, so turning an override on never moves the board by itself.
			_write_field(data, layer,
				(GridUtils.INHERIT_COLOR if is_color else GridUtils.INHERIT) if on else resolved))
	if inherited:
		DevWidgets.add_label(_rows, "    inherits %s" % _shown(resolved))
	elif is_color:
		DevWidgets.add_color(_rows, field["label"], authored,
			func(picked: Color) -> void: _write_field(data, layer, picked))
	else:
		DevWidgets.add_slider(_rows, field["label"], authored,
			field["min"], field["max"], field["step"],
			func(moved: float) -> void: _write_field(data, layer, moved))
	_tip_rows(first, field["tip"])


# What this field actually comes out as for this tile — asked of BoardMirror, which owns the
# global-then-override layering. The panel deliberately does not re-derive it.
func _resolved_value(data: TileData, field: Dictionary) -> Variant:
	var mirror := _mirror()
	if mirror == null:
		return 0.0
	match field["layer"]:
		"prop_light_energy": return mirror.light_energy_for(data)
		"prop_light_range": return mirror.light_range_for(data)
		"prop_light_height": return mirror.light_height_for(data)
		"prop_light_color": return mirror.light_color_for(data)
		"prop_height_scale": return mirror.block_height_for(data)
		"prop_tuft_scale": return mirror.tuft_scale_for(data)
	push_error("ObjectTool: field '%s' has no resolver" % field["layer"])
	return 0.0


func _shown(value: Variant) -> String:
	if value is Color:
		return DevWidgets.literal_for(value)
	return String.num(value, 3)


# Written LIVE, then the board re-stands its props so you can see it. Saving is a separate act --
# the same split every dev tab makes between editing and committing.
func _write_field(data: TileData, layer: String, value: Variant) -> void:
	data.set_custom_data(layer, value)
	var host := _host
	if host != null:
		host.rebuild_props()
	_rebuild()


func _on_object_picked(index: int) -> void:
	_picked = index
	_rebuild()


func _tip_rows(first: int, tip: String) -> void:
	var wrapped := DevWidgets.wrap_tooltip(tip)
	for i in range(first, _rows.get_child_count()):
		DevWidgets.apply_tooltip(_rows.get_child(i), wrapped)


func _tile_set() -> TileSet:
	if _host == null or _host.game == null or _host.game.grid == null:
		return null
	return _host.game.grid.tile_set


func _mirror() -> BoardMirror:
	if _host == null:
		return null
	return _host.get_node_or_null(^"BoardMirror") as BoardMirror


func _on_save_fields_pressed() -> void:
	var tiles := _tile_set()
	if tiles == null:
		_status.text = "No board tileset attached - nothing to save."
		return
	if ObjectKnobs.save_fields(tiles, _status):
		_status.text = "Object fields saved to %s" % tiles.resource_path


# The where-does-this-live note is appended per table rather than typed into each tip, so it cannot
# drift out of step with what Save actually writes.
func tip_for(knob: Dictionary) -> String:
	var tip: String = knob.get("tip", "")
	return tip + "\n\nGAME-WIDE -- one value for every board. Save to source writes it into the script that declares it; no mission can carry its own."


func _add_heading(text: String) -> void:
	if _rows.get_child_count() > 0:
		_rows.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = text
	heading.add_theme_color_override("font_color", HEADING_COLOR)
	_rows.add_child(heading)


func _on_save_pressed() -> void:
	if _host == null:
		_status.text = "No 3D host attached - nothing to save."
		return
	var moved := changed_indices()
	if moved.is_empty():
		_status.text = "Nothing has moved off what is saved."
		return
	var report := ObjectKnobs.save_to_source(_host, moved)
	# The baseline follows what LANDED, never what was asked for: a knob whose write failed is still
	# unsaved, and quietly adopting it would hide the failure behind an unchanged-looking panel.
	for landed: Dictionary in report["saved"]:
		var i: int = landed["index"]
		_baseline[i] = LookKnobs.read(_host, ObjectKnobs.KNOBS[i])
	var parts: PackedStringArray = PackedStringArray()
	var written: PackedStringArray = report["written"]
	var failed: PackedStringArray = report["failed"]
	if not written.is_empty():
		parts.append("Saved: %s" % ", ".join(written))
	if not failed.is_empty():
		parts.append("FAILED: %s" % ", ".join(failed))
	_status.text = " | ".join(parts)


func _on_reset_pressed() -> void:
	if _host == null:
		return
	for i in ObjectKnobs.KNOBS.size():
		var saved: Variant = baseline_of(i)
		if typeof(saved) != TYPE_NIL:
			LookKnobs.write(_host, ObjectKnobs.KNOBS[i], saved)
	_rebuild()
	_status.text = "Back to what is saved on disk."


func _button(text: String, tooltip: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(on_pressed)
	return button
