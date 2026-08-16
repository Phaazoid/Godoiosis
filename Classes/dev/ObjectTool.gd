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


func _ready() -> void:
	var buttons := HBoxContainer.new()
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
# written ones are re-read so the two agree again.
func _capture_baseline() -> void:
	_baseline.clear()
	for knob: Dictionary in ObjectKnobs.KNOBS:
		_baseline.append(LookKnobs.read(_host, knob))


func baseline_of(index: int) -> Variant:
	if index < 0 or index >= _baseline.size():
		return null
	return _baseline[index]


# Which rows have been moved off what is saved. The APPROXIMATE compare, for LookKnobs' reason:
# engine properties store single-precision, so a value written and read straight back is not
# bit-identical and an exact compare reports every knob as changed the moment it is touched.
func changed_indices() -> PackedInt32Array:
	var moved: PackedInt32Array = PackedInt32Array()
	for i in ObjectKnobs.KNOBS.size():
		var live: Variant = LookKnobs.read(_host, ObjectKnobs.KNOBS[i])
		if typeof(live) == TYPE_NIL:
			continue
		if not LookKnobs.same_value(live, baseline_of(i)):
			moved.append(i)
	return moved


func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if _host == null:
		DevWidgets.add_label(_rows, "No 3D host attached - the flat 2D game has no objects to tune.")
		return
	var group := ""
	for knob: Dictionary in ObjectKnobs.KNOBS:
		var knob_group: String = knob["group"]
		if knob_group != group:
			group = knob_group
			_add_heading(group)
		DevWidgets.add_knob_row(_rows, knob, LookKnobs.read(_host, knob),
			func(value: Variant) -> void: LookKnobs.write(_host, knob, value),
			DevWidgets.wrap_tooltip(tip_for(knob)))


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
	for i: int in report["saved"]:
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
