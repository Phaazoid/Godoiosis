extends VBoxContainer
class_name GameTool

# The dev-tools Game tab (#373): where the game's own presentation constants are tuned AND KEPT.
# LookTool's and ObjectTool's sibling, and deliberately the same shape -- rows over a table, a
# baseline that Reset returns to, one Save.
#
# What separates the three is the QUESTION each answers about a tuned value, which is also the
# question that decides where a new knob goes:
#   * one board may differ from another  -> LookKnobs, and a LookPreset a mission wears.
#   * one tile TYPE may differ           -> ObjectKnobs.FIELDS, a TileSet custom-data column.
#   * nobody may ever differ             -> HERE (or ObjectKnobs.KNOBS for world construction),
#                                           written back into the declaration that authors it.
# Everything on this tab is the third kind, which is why there is nothing to save it ONTO: the
# button rewrites the authored default in the owning script. That is one authority, edited in
# place, and the change shows up as an ordinary line in the diff.
#
# Two tables, one Save, for the reason GameKnobs states: a layer's colour is an entry of a const
# table and a reach colour is a static var, so neither is addressable as node:property. The panel
# does not care -- both draw the same row and both land in one edit list.
#
# The host is PUSHED in by DevOverlay.attach_3d_host, never looked up -- the same rule that keeps
# the game subtree free of an upward path to Battle3D, and the reason a flat Main.tscn launch
# reports "no 3D host" instead of failing.

const HEADING_COLOR := Color(1, 0.83, 0.4, 1)   # the Look and Scenario tabs' heading gold

var _host: Node3D
var _baseline: Array = []         # per KNOBS index: what is currently ON DISK, i.e. Reset's target
var _class_baseline: Array = []   # the same, per CLASS_KNOBS index
var _tabs: TabContainer
var _tab_rows: Dictionary[String, VBoxContainer] = {}   # tab title -> its row container
var _status: Label


func _ready() -> void:
	var buttons := HBoxContainer.new()
	buttons.add_child(_button("Save to source",
		"Write every value you have moved into the declaration that authors it, in the script that\ndeclares it. These are game-wide constants rather than mission mood, so this is the whole way\nto keep one -- the change shows up as an ordinary line in the diff. Editor runs only; res:// is\nread-only in a build.",
		_on_save_pressed))
	buttons.add_child(_button("Reset",
		"Put every knob back to what is currently saved on disk.", _on_reset_pressed))
	add_child(buttons)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	# Buttons and status sit ABOVE the sub-tabs and outside them, so they are reachable from every
	# tab -- Save and Reset are panel-wide, not per-group (the Look tab's dev ask, same answer).
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	for tab_title: String in tab_titles():
		var scroll := ScrollContainer.new()
		scroll.name = tab_title
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tabs.add_child(scroll)
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(rows)
		_tab_rows[tab_title] = rows
	# Before any host arrives, and not only on attach: a CLASS knob is readable with no host at all
	# (a static needs nothing but the class), so a panel that had not captured its baseline yet
	# reported all three statics as moved the moment it was built.
	_capture_baselines()
	_rebuild()


# Called by DevOverlay once battle3d hands it the 3D scene. The 2D game boots first (Godot readies
# children before parents), so this tab always builds its no-host state and then rebuilds here.
func attach_host(host: Node3D) -> void:
	_host = host
	_capture_baselines()
	_rebuild()


func has_host() -> bool:
	return _host != null


# Tab titles in GROUP_TABS declaration order, de-duplicated -- the order the sub-tabs appear in.
static func tab_titles() -> Array[String]:
	var titles: Array[String] = []
	for group: String in GameKnobs.GROUP_TABS:
		var title: String = GameKnobs.GROUP_TABS[group]
		if not titles.has(title):
			titles.append(title)
	return titles


# What is on disk, by definition: nothing has moved a knob yet at attach time, and after a save the
# written ones are re-read so the two agree again.
func _capture_baselines() -> void:
	_baseline = KnobSource.capture_baseline(_host, GameKnobs.KNOBS)
	_class_baseline = GameKnobs.capture_class_baseline(_host)


func baseline_of(index: int) -> Variant:
	if index < 0 or index >= _baseline.size():
		return null
	return _baseline[index]


func class_baseline_of(index: int) -> Variant:
	if index < 0 or index >= _class_baseline.size():
		return null
	return _class_baseline[index]


func changed_indices() -> PackedInt32Array:
	return KnobSource.changed_indices(_host, GameKnobs.KNOBS, _baseline)


func changed_class_indices() -> PackedInt32Array:
	return GameKnobs.changed_class_indices(_host, _class_baseline)


# --- Building the rows ---------------------------------------------------------------------------

# Where a group's rows go. A group missing from GROUP_TABS would otherwise draw nowhere at all, so
# it lands on the first tab and says so rather than vanishing.
func _rows_for_group(group: String) -> VBoxContainer:
	if not GameKnobs.GROUP_TABS.has(group):
		push_error("GameTool: group '%s' has no tab in GROUP_TABS" % group)
		return _tab_rows[tab_titles()[0]]
	return _tab_rows[GameKnobs.GROUP_TABS[group]]


func _rebuild() -> void:
	var showing := _tabs.current_tab   # a Reset must not bounce you off the tab you were tuning
	for rows: VBoxContainer in _tab_rows.values():
		for child in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
	if _host == null:
		DevWidgets.add_label(_tab_rows[tab_titles()[0]],
			"No 3D host attached - the flat 2D game has no markup stack to tune.")
		return
	var group := ""
	for knob: Dictionary in GameKnobs.KNOBS:
		var knob_group: String = knob["group"]
		var rows := _rows_for_group(knob_group)
		if knob_group != group:
			group = knob_group
			_add_heading(rows, knob_group)
		DevWidgets.add_knob_row(rows, knob, LookKnobs.read(_host, knob),
			func(value: Variant) -> void: LookKnobs.write(_host, knob, value),
			tip_for(knob))
	group = ""
	for knob: Dictionary in GameKnobs.CLASS_KNOBS:
		var knob_group: String = knob["group"]
		var rows := _rows_for_group(knob_group)
		if knob_group != group:
			group = knob_group
			_add_heading(rows, knob_group)
		_build_class_row(rows, knob)
	_tabs.current_tab = clampi(showing, 0, maxi(0, _tabs.get_tab_count() - 1))


# A class knob resolves through a store rather than a property path, so a failure to resolve cannot
# name a node:prop -- it says which knob and which store instead, then draws nothing.
func _build_class_row(rows: VBoxContainer, knob: Dictionary) -> void:
	var value: Variant = GameKnobs.read_class(_host, knob)
	if typeof(value) == TYPE_NIL:
		DevWidgets.add_label(rows, "%s - UNRESOLVED" % knob["label"])
		push_error("GameTool: class knob does not resolve: %s" % knob["label"])
		return
	DevWidgets.add_knob_row(rows, knob, value,
		func(picked: Variant) -> void: GameKnobs.write_class(_host, knob, picked),
		tip_for(knob))


# The where-does-this-live note is appended per table rather than typed into each tip, so it cannot
# drift out of step with what Save actually writes. GameKnobs owns the which-stack half.
func tip_for(knob: Dictionary) -> String:
	return GameKnobs.tip_for(knob) + "\n\n" + DevWidgets.wrap_tooltip(
		"GAME-WIDE -- one value for every board. Save to source writes it into the declaration that authors it; no mission can carry its own.")


func _add_heading(rows: VBoxContainer, text: String) -> void:
	if rows.get_child_count() > 0:
		rows.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = text
	heading.add_theme_color_override("font_color", HEADING_COLOR)
	rows.add_child(heading)


func _button(text: String, tooltip: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(on_pressed)
	return button


# --- The handoff ---------------------------------------------------------------------------------

func _on_save_pressed() -> void:
	if _host == null:
		_status.text = "No 3D host attached - nothing to save."
		return
	var moved := changed_indices()
	var moved_class := changed_class_indices()
	if moved.is_empty() and moved_class.is_empty():
		_status.text = "Nothing has moved off what is saved."
		return
	var report := GameKnobs.save_to_source(_host, moved, moved_class)
	# The baseline follows what LANDED, never what was asked for: a knob whose write failed is still
	# unsaved, and quietly adopting it would hide the failure behind an unchanged-looking panel.
	# Which baseline moves comes off the edit's own source tag -- the two tables share an index
	# space, so a bare number could move the wrong row's.
	for landed: Dictionary in report["saved"]:
		var i: int = landed["index"]
		if landed["source"] == GameKnobs.CLASS_SOURCE:
			_class_baseline[i] = GameKnobs.read_class(_host, GameKnobs.CLASS_KNOBS[i])
		else:
			_baseline[i] = LookKnobs.read(_host, GameKnobs.KNOBS[i])
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
	for i in GameKnobs.KNOBS.size():
		var saved: Variant = baseline_of(i)
		if typeof(saved) != TYPE_NIL:
			LookKnobs.write(_host, GameKnobs.KNOBS[i], saved)
	for i in GameKnobs.CLASS_KNOBS.size():
		var saved_class: Variant = class_baseline_of(i)
		if typeof(saved_class) != TYPE_NIL:
			GameKnobs.write_class(_host, GameKnobs.CLASS_KNOBS[i], saved_class)
	_rebuild()   # redraw every widget off the restored values -- one path, every widget kind
	_status.text = "Back to what is saved on disk."
