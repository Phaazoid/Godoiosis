extends VBoxContainer
class_name MoodsTool

# The dev-tools Moods tab (#212): the live SURFACE onto the HD-2D stack's aesthetic values.
#
# What the look IS -- the knob table, reading and writing it, capturing and applying a preset --
# moved to Classes/presentation/LookKnobs.gd in #253 part 2, because a MISSION carries a look now
# and the shipping path cannot route through a dev tab. This file owns the PANEL: the rows, the
# sub-tabs, the mood buttons, and the baseline that Reset returns to.
#
# The host is PUSHED in by battle3d._ready (attach_host), never looked up: no part of the game
# subtree gains an upward path to the 3D scene, and launching Main.tscn flat -- a real shipping
# target -- simply never attaches one, which this reports instead of crashing.
#
# Loading a mood makes it the BASELINE, so Reset returns there; Default returns to the fallback
# look every board wears when its mission names none -- and Update default WRITES that file, so
# the panel is the door to it (#386). It replaced Copy Values, which spelled a tuned look as
# paste-ready GDScript to hand-type into Battle3D.tscn: a second way to say "make this the
# baseline", and the worse one.
#
# The panel says MOOD; the files it writes are LookPresets under Resources/LookPresets/. Renaming
# the resource would drop the look from every saved mission (ScenarioData.look_preset is an
# @export), so the vocabulary split is deliberate.
#
# Board-markup colours were a second table here (LAYER_KNOBS) until #373 moved them, with the rest
# of the markup, to the Game tab: none of it was scene mood, and none of it had a Save. What is
# left on this panel is mood entire, which is what let LookKnobs' exclusion list go away.

const HEADING_COLOR := Color(1, 0.83, 0.4, 1)   # the Scenario tab's heading gold

# Which SUB-TAB each group lands on (dev, 2026-08-14: ~60 rows in one scroll is too much for a
# 900x360 window, so split to about a windowful each). A map rather than a key on every knob, so
# adding a knob stays one line and adding a GROUP is one line here -- and a group with no tab is a
# group that silently vanishes from the panel, which is why a law test pins the mapping complete.
# Declaration order below is the tab order.
const GROUP_TABS: Dictionary[String, String] = {
	"Lighting": "Lighting",
	"Sky": "Lighting",
	"Post": "Post",
	"Fog": "Fog & DoF",
	"Depth of field": "Fog & DoF",
	# The Effects and Markup sub-tabs are both gone, and for one reason twice: their populations
	# were not scene mood. Effects left for the Objects tab (#272, world construction and the fire
	# block), Markup for the Game tab (#373, board markup and its colours, the unit readout, camera
	# handling, the brush ghost). What remains is the look, and every group of it joins a preset.
	"Camera framing": "Camera",
}

var _host: Node3D                # the Battle3D scene; pushed in, never looked up
var _baseline: Array = []        # what Reset returns to: the scene, or whatever was last applied
var _loaded_preset := ""         # dropdown-relative name; "" = nothing loaded (default or scene)
var _tabs: TabContainer
var _tab_rows: Dictionary[String, VBoxContainer] = {}   # tab title -> its row container
var _status: Label
var _preset_name_input: LineEdit
var _preset_dropdown: OptionButton
var _update_button: Button
var _delete_button: Button


func _ready() -> void:
	_build_preset_row()
	var buttons := HBoxContainer.new()
	buttons.add_child(_button("Reset",
		"Put every knob back to whatever was last applied -- the loaded mood, the default, or the\nscene's own values if neither", _on_reset_pressed))
	buttons.add_child(_button("Default",
		"Load the default mood -- what every board wears when its mission names none. This is the\nway back; Reset returns to whatever you last loaded.",
		_on_default_pressed))
	buttons.add_child(_button("Update default",
		"Overwrite the default mood with what is on screen, so every board naming no mood wears\nthis. Asks first. Named moods are untouched -- this writes the one file Default loads.",
		_on_update_default_pressed))
	buttons.add_child(_button("Re-fit camera",
		"Pitch and FOV feed the framing maths, which only runs on a board load -- press this after moving either",
		_on_refit_pressed))
	add_child(buttons)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	# Buttons and status sit ABOVE the sub-tabs and outside them, so they are reachable from every
	# tab (dev ask) -- Reset and Re-fit are panel-wide, not per-group.
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	for tab_title: String in _tab_titles():
		var scroll := ScrollContainer.new()
		scroll.name = tab_title
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tabs.add_child(scroll)
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(rows)
		_tab_rows[tab_title] = rows
	refresh_preset_dropdown()   # after _status exists: a refusal has somewhere to print
	_rebuild()


# Called by battle3d._ready. The 2D game boots first (Godot readies children before parents), so
# the tab always builds its no-host state and then rebuilds here.
func attach_host(host: Node3D) -> void:
	_host = host
	_baseline = _live_values()   # no mood loaded yet, so Reset means "back to the scene"
	_rebuild()


func has_host() -> bool:
	return _host != null


# --- Reading and writing a knob ---------------------------------------------------------

# Thin binds over LookKnobs' statics, closing over this tab's own _host. NOT a second answer --
# the table and the property access both live there; these only save every call site passing it.

func read(knob: Dictionary) -> Variant:
	return LookKnobs.read(_host, knob)


func write(knob: Dictionary, value: Variant) -> void:
	LookKnobs.write(_host, knob, value)


# What Reset returns to -- the loaded mood if there is one, else the authored scene.
func baseline_of(index: int) -> Variant:
	if index < 0 or index >= _baseline.size():
		return null
	return _baseline[index]


# --- Building the rows ------------------------------------------------------------------

# Tab titles in GROUP_TABS declaration order, de-duplicated -- the order the sub-tabs appear in.
func _tab_titles() -> Array[String]:
	var titles: Array[String] = []
	for group: String in GROUP_TABS:
		var title: String = GROUP_TABS[group]
		if not titles.has(title):
			titles.append(title)
	return titles


# Where a group's rows go. A group missing from GROUP_TABS would otherwise draw nowhere at all,
# so it lands on the first tab and says so; the law test is what stops that shipping.
func _rows_for_group(group: String) -> VBoxContainer:
	if not GROUP_TABS.has(group):
		push_error("MoodsTool: group '%s' has no tab in GROUP_TABS" % group)
		return _tab_rows[_tab_titles()[0]]
	return _tab_rows[GROUP_TABS[group]]


func _rebuild() -> void:
	var showing := _tabs.current_tab   # a Reset must not bounce you off the tab you were tuning
	for rows: VBoxContainer in _tab_rows.values():
		for child in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
	if _host == null:
		DevWidgets.add_label(_tab_rows[_tab_titles()[0]],
			"No 3D host attached - the flat 2D game has no look stack to tune.")
		return
	var group := ""
	for knob: Dictionary in LookKnobs.KNOBS:
		var knob_group: String = knob["group"]
		var rows := _rows_for_group(knob_group)
		if knob_group != group:
			group = knob_group
			_add_heading(rows, group)
		_build_row(rows, knob)
	_tabs.current_tab = clampi(showing, 0, maxi(0, _tabs.get_tab_count() - 1))


# The where-does-this-live note is appended per TABLE rather than typed into each tip, so it cannot
# drift out of step with what Save actually writes -- the Game and Objects tabs say their own.
func tip_for(knob: Dictionary) -> String:
	return DevWidgets.wrap_tooltip(String(knob.get("tip", ""))
		+ "\n\nMISSION MOOD -- a preset captures this, and a board wearing that preset wears this value. Save As / Update is how it is kept; a value that must be the same on every board is a Game tab knob instead.")


# The row itself is DevWidgets.add_knob_row since #272 -- the Object tab draws the same kind of row
# and "how is a knob a control" is one question. What stays here is what is this panel's: which host
# the write lands on, and the which-stack note the tip carries.
func _build_row(rows: VBoxContainer, knob: Dictionary) -> void:
	DevWidgets.add_knob_row(rows, knob, read(knob),
		func(value: Variant) -> void: write(knob, value), tip_for(knob))


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


# --- Presets ----------------------------------------------------------------------------

# Identity, capture and apply all live on LookKnobs now (#253 part 2) -- a mission carries a look,
# so the shipping path can no longer route through a dev tab. What is left here is the SURFACE.

func loaded_preset() -> String:
	return _loaded_preset


func capture_preset(preset_name: String) -> LookPreset:
	return LookKnobs.capture(_host, preset_name)


# The PANEL's half of applying. LookKnobs does the writing and the reporting (including falling a
# knob the preset predates back to the default, and re-fitting the camera); this keeps the baseline
# in step so Reset returns to whatever was just loaded, and redraws every row off it.
func apply_preset(preset: LookPreset) -> Dictionary:
	var report := LookKnobs.apply(_host, preset)
	if _host != null and preset != null:
		_baseline = _live_values()   # what the properties ACCEPTED, never what was asked for
		_rebuild()
	return report


func _build_preset_row() -> void:
	var top := HBoxContainer.new()
	var label := Label.new()
	label.text = "Preset"
	top.add_child(label)
	_preset_dropdown = OptionButton.new()
	_preset_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_dropdown.item_selected.connect(func(_index: int) -> void: _refresh_preset_buttons())
	top.add_child(_preset_dropdown)
	top.add_child(_button("Load", "Apply the picked preset to the live scene", _on_load_pressed))
	_update_button = _button("Update", "", _on_update_pressed)
	top.add_child(_update_button)
	_delete_button = _button("Delete", "", _on_delete_pressed)
	top.add_child(_delete_button)
	add_child(top)

	var bottom := HBoxContainer.new()
	_preset_name_input = LineEdit.new()
	_preset_name_input.placeholder_text = "New preset name"
	_preset_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_preset_name_input)
	bottom.add_child(_button("Save As",
		"Save every scene-mood knob under a new name. Camera handling, board markup and the brush\nghost are deliberately not captured -- those are game settings, not a mission's mood.",
		_on_save_as_pressed))
	add_child(bottom)


# select_name is a display name. Empty re-selects whatever was showing, so a rebuild never silently
# moves Update's target.
func refresh_preset_dropdown(select_name := "") -> void:
	if select_name == "":
		select_name = DevWidgets.selected_name(_preset_dropdown)
	_preset_dropdown.clear()
	for preset_name: String in LookKnobs.saved_presets():
		_preset_dropdown.add_item(preset_name)
	# add_item auto-selects index 0 -- force the match rather than inheriting it, or a deleted
	# preset leaves the selection silently pointing at whatever sorts first. Every row is a FILE
	# now that the authored row is gone (#253 part 2 gave the way back its own button), so nothing
	# may fall back to index 0: row 0 is a write target Update and Delete would aim at.
	_preset_dropdown.select(-1)
	for i in _preset_dropdown.item_count:
		if _preset_dropdown.get_item_text(i) == select_name:
			_preset_dropdown.select(i)
			break
	_refresh_preset_buttons()


func _refresh_preset_buttons() -> void:
	var target := DevWidgets.selected_name(_preset_dropdown)
	DevWidgets.refresh_update_button(_update_button, target, "mood", update_block_reason())
	DevWidgets.refresh_delete_button(_delete_button, target, "mood")


# "" = allowed. Update only ever writes the LOADED preset back over its own file -- the 2026-08-11
# scenario rule, for the same reason: aiming Update at a preset you have not loaded overwrites it
# with a look you were never looking at.
func update_block_reason() -> String:
	var target := DevWidgets.selected_name(_preset_dropdown)
	if target == "":
		return ""
	if target != _loaded_preset:
		return "Load '%s' before updating it -- Update saves the live look back over its own file" % target
	return ""


func _on_load_pressed() -> void:
	if _host == null:
		return
	var target := DevWidgets.selected_name(_preset_dropdown)
	if target == "":
		return
	var preset := LookKnobs.resolve(target)
	if preset == null:
		_status.text = "Could not load mood '%s', and the default is missing too" % target
		return
	var report := apply_preset(preset)
	_loaded_preset = target
	_refresh_preset_buttons()
	_status.text = _load_report(target, report)


# The way back, and the ONE way back (dev, 2026-08-15): Reset returns to the loaded preset, so
# without this the fallback look would be unreachable from the panel. It replaced an "(authored
# scene)" dropdown row that did the same thing -- once a mission carries a look, Battle3D.tscn's
# inline values stop being the truth, so two affordances would have been two names for one idea.
func _on_default_pressed() -> void:
	if _host == null:
		return
	var preset := LookKnobs.default_preset()
	if preset == null:
		_status.text = "The default mood is missing from %s." % LookKnobs.DEFAULT_PATH
		return
	apply_preset(preset)
	_loaded_preset = ""
	_preset_dropdown.select(-1)
	_refresh_preset_buttons()
	_status.text = "Loaded the default mood. Reset now returns here."


# Default's twin (#386): the file it loads is what every board with no named mood wears, and until
# now the panel could only READ it -- the same doorless-value shape as #272 and #373. Confirmed
# rather than load-gated: there is one default and it is always the target, so the mis-click this
# guards is not "the wrong file" but "not yet".
func _on_update_default_pressed() -> void:
	if _host == null:
		return
	DevWidgets.confirm_overwrite(self, "the default mood", "what is on screen",
		_update_default_confirmed)


func _update_default_confirmed() -> void:
	if not DevWidgets.save_over(capture_preset(LookKnobs.DEFAULT_NAME), LookKnobs.DEFAULT_PATH, _status):
		return
	# The file now holds what is on screen, so leave the panel exactly where pressing Default would:
	# the live look IS the default, and no named mood is loaded any more.
	_baseline = _live_values()
	_loaded_preset = ""
	_preset_dropdown.select(-1)
	_refresh_preset_buttons()
	_status.text = "The default mood is now what you see (%d knobs). Reset returns here." \
		% LookKnobs.preset_knobs().size()


func _load_report(target: String, report: Dictionary) -> String:
	var text := "Loaded mood '%s'. Reset now returns here." % target
	var missing: Array = report["missing"]
	if not missing.is_empty():
		text += ("\n%d knob(s) added since this mood was saved, left at the scene's value: %s."
			+ " Set them and press Update to back-add.") % [missing.size(), ", ".join(missing)]
	var unknown: Array = report["unknown"]
	if not unknown.is_empty():
		text += "\n%d saved value(s) no longer apply (knob removed or now excluded): %s." \
			% [unknown.size(), ", ".join(unknown)]
	return text


func _on_save_as_pressed() -> void:
	if _host == null:
		_status.text = "No 3D host attached - there is no mood to save."
		return
	var entered := _preset_name_input.text.strip_edges()
	if entered == "":
		var msg := "Mood needs a name"
		push_warning(msg)
		_status.text = msg
		return
	# Flat folder, so no allow_slash: a '/' would land the file where the scan never looks (#168).
	if DevWidgets.refuse_illegal_name(entered, "mood", _status):
		return
	if DevWidgets.refuse_existing_file(LookKnobs.preset_path(entered), "mood", _status):
		return
	if not DevWidgets.save_over(capture_preset(entered), LookKnobs.preset_path(entered), _status):
		return
	# Saving is also loading: the look on screen IS this mood now, so Reset should return to it.
	_baseline = _live_values()
	_loaded_preset = entered
	_preset_name_input.text = ""
	refresh_preset_dropdown(entered)
	_status.text = "Saved mood '%s' (%d knobs). Reset now returns here." % [entered, LookKnobs.preset_knobs().size()]


func _on_update_pressed() -> void:
	var target := DevWidgets.selected_name(_preset_dropdown)
	if target == "":
		return
	# The handler is the real gate; the greyed button is only its surface (#166 shape).
	var reason := update_block_reason()
	if reason != "":
		_status.text = reason
		return
	# Confirmed as well as load-gated (the 2026-08-12 scenario call): the gate cannot catch a
	# mis-click at the file you DID load, which is exactly how a tuned look would be lost.
	DevWidgets.confirm_overwrite(self, "mood '%s'" % target, "the current look",
		func() -> void: _update_confirmed(target))


func _update_confirmed(target: String) -> void:
	if not DevWidgets.save_over(capture_preset(target), LookKnobs.preset_path(target), _status):
		return
	_baseline = _live_values()   # the file now says what is on screen, so Reset must too
	_status.text = "Updated mood '%s' (%d knobs)." % [target, LookKnobs.preset_knobs().size()]


func _on_delete_pressed() -> void:
	var target := DevWidgets.selected_name(_preset_dropdown)
	if target == "":
		return
	DevWidgets.confirm_delete(self, "mood '%s'" % target, func() -> void: _delete_confirmed(target))


func _delete_confirmed(target: String) -> void:
	if not DevWidgets.delete_saved_file(LookKnobs.preset_path(target), "mood", _status):
		return
	if _loaded_preset == target:
		# The look on screen is untouched -- only its file is gone. Reset holds it rather than
		# snapping anywhere, so deleting a file never also changes what you are looking at.
		_baseline = _live_values()
		_loaded_preset = ""
		_status.text = "Deleted mood '%s'. The look on screen is unchanged; press Default to leave it." % target
	refresh_preset_dropdown()


# The live value of every knob, per LookKnobs.KNOBS index -- the baseline a just-saved mood
# establishes. It used to skip the excluded rows, which is now every row of a table that is mood
# entire (#373).
func _live_values() -> Array:
	var values: Array = []
	values.resize(LookKnobs.KNOBS.size())
	for i in LookKnobs.KNOBS.size():
		values[i] = read(LookKnobs.KNOBS[i])
	return values


func _on_reset_pressed() -> void:
	if _host == null:
		return
	for i in LookKnobs.KNOBS.size():
		var authored: Variant = baseline_of(i)
		if typeof(authored) != TYPE_NIL:
			write(LookKnobs.KNOBS[i], authored)
	_rebuild()   # redraw every widget off the restored values -- one path, every widget kind
	if _loaded_preset == "":
		_status.text = "Every knob is back at its authored value."
	else:
		_status.text = "Every knob is back at mood '%s'." % _loaded_preset


func _on_refit_pressed() -> void:
	if _host == null:
		return
	_host.fit_camera()
	_status.text = "Camera re-framed on the current board."

