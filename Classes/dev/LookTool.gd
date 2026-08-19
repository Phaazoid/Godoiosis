extends VBoxContainer
class_name LookTool

# The dev-tools Look tab (#212): the live SURFACE onto the HD-2D stack's aesthetic values.
#
# What the look IS -- the knob table, reading and writing it, capturing and applying a preset --
# moved to Classes/presentation/LookKnobs.gd in #253 part 2, because a MISSION carries a look now
# and the shipping path cannot route through a dev tab. This file owns the PANEL: the rows, the
# sub-tabs, the preset buttons, the baseline that Reset returns to, and Copy Values.
#
# The host is PUSHED in by battle3d._ready (attach_host), never looked up: no part of the game
# subtree gains an upward path to the 3D scene, and launching Main.tscn flat -- a real shipping
# target -- simply never attaches one, which this reports instead of crashing.
#
# Loading a preset makes it the BASELINE, so Reset returns there; Default returns to the fallback
# look every board falls back to. Copy Values still diffs the AUTHORED scene rather than either,
# because its output is paste-ready lines FOR Battle3D.tscn -- diffed against a loaded preset they
# would not reproduce what you are looking at.

# Board-markup colours (#212 slice 2). A DECLARED second table rather than a widening of KNOBS,
# and it stays HERE rather than moving with the rest: these address a LAYER through an accessor
# pair rather than a property path, presets never touch them, and only this panel tunes them.
#
# Which layers appear here is measured, not chosen. `set_layer_modulate` REPLACES a layer's albedo,
# so any layer something already drives per frame would take a knob that silently reverts -- the
# lying-slider class. Excluded for that reason: ATTACK's 3D side and AIM (OverlayMirror rewrites
# both from the 2D every poll) and HOVER (battle3d._sync_bracket_tint). ZONE_PATROL/ZONE_HIGHLIGHT
# are excluded as authoring-only -- invisible during real play, and they READ OverlayManager's
# constants, so a knob would fork a value that is deliberately one (dev call).
#
# `reach` entries are the exception that proves it: ATTACK has no 3D-only colour to tune, because
# the 3D mirrors the 2D's modulate rather than holding an answer. Tuning it moves BOTH stacks.
const LAYER_KNOBS: Array[Dictionary] = [
	{"group": "Board markup colours", "label": "Move fill", "layer": BoardOverlays.Layer.MOVE,
		"tip": "The tiles a unit can reach while you are ordering a move. Alpha is the dial that matters most -- markup has to read as gameplay information without burying the terrain under it."},
	{"group": "Board markup colours", "label": "Invalid-move fill", "layer": BoardOverlays.Layer.INVALID_MOVE,
		"tip": "Tiles inside a unit's movement range that it still may not stop on -- out of its leader's cohesion range, or already occupied. Clicking one does nothing, so this colour is the only warning."},
	{"group": "Board markup colours", "label": "Squad fill", "layer": BoardOverlays.Layer.SQUAD,
		"tip": "The candidate bubble while FORMING a squad (Squad Up / Join Squad) -- the cells a recruit may be picked from. Membership itself is the ring/square markers, not this fill."},
	{"group": "Board markup colours", "label": "Squad-range fill", "layer": BoardOverlays.Layer.SQUAD_RANGE,
		"tip": "The leader's cohesion range -- how far squadmates may stray before the plan is refused. Shares its colour with Squad fill by default, since they are two halves of the same idea."},
	{"group": "Board markup colours", "label": "Capture zone", "layer": BoardOverlays.Layer.ZONE_CAPTURE,
		"tip": "A painted objective zone that can be captured. Stays visible for the whole battle -- this is live objective information, not authoring scaffolding."},
	{"group": "Board markup colours", "label": "Extraction zone", "layer": BoardOverlays.Layer.ZONE_EXTRACTION,
		"tip": "A painted zone your units must reach to extract. Also visible all battle."},
	{"group": "Board markup colours", "label": "Attack reach (2D+3D)", "reach": "ATTACK_MODULATE",
		"tip": "The reach fill while aiming a damaging attack. Red reads as hostile, which is the whole reason a healing pick paints green instead."},
	{"group": "Board markup colours", "label": "Heal reach (2D+3D)", "reach": "HEAL_ATTACK_MODULATE",
		"tip": "The same reach fill when the pick HEALS. Forked off the attack's own heals flag, so an attack cannot paint the wrong colour for what it does."},
]

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
	"Camera": "Camera",
	"Board markup": "Markup",
	"Board markup colours": "Markup",
	# The Effects sub-tab is gone (#272): its whole population moved to the Objects tab, and the one
	# knob left is dev chrome, which shares Markup for the reason the Unit HUD does — neither is
	# scene mood, and a tab holding a single row is a tab that has stopped meaning anything.
	"Dev chrome": "Markup",
	# #229's health readout. Shares the Markup tab rather than taking its own: it is HUD hung on a
	# unit, i.e. the same "gameplay legibility, not scene mood" family as the board overlays, and
	# both are excluded from presets for that one reason.
	"Unit HUD": "Markup",
}

var _host: Node3D                # the Battle3D scene; pushed in, never looked up
var _authored: Array = []        # the SCENE's own value per KNOBS index, read once on attach.
								 # Only Copy Values reads it now -- its lines paste into the scene.
var _baseline: Array = []        # what Reset returns to: the scene, or whatever was last applied
var _layer_baseline: Array = []  # the same, per LAYER_KNOBS index (presets never touch these)
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
	buttons.add_child(_button("Copy changed values",
		"Copy every value moved off the SCENE's authored setting to the clipboard, as paste-ready\nGDScript. Always measured against Battle3D.tscn, never against a loaded preset -- these lines\nare what you paste INTO the scene, so a preset-relative diff would not reproduce what you see.",
		_on_copy_pressed))
	buttons.add_child(_button("Reset",
		"Put every knob back to whatever was last applied -- the loaded preset, the default, or the\nscene's own values if neither", _on_reset_pressed))
	buttons.add_child(_button("Default",
		"Load the default look -- what every board falls back to, and what a mission gets when it\nnames no preset. This is the way back; Reset returns to whatever you last loaded.",
		_on_default_pressed))
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
	_authored.clear()
	for knob: Dictionary in LookKnobs.KNOBS:
		_authored.append(read(knob))   # authored by definition: nothing has moved one yet
	_baseline = _authored.duplicate()  # no preset loaded yet, so Reset means "back to the scene"
	_layer_baseline.clear()
	for knob: Dictionary in LAYER_KNOBS:
		_layer_baseline.append(read_layer(knob))
	_rebuild()


# --- Board-markup colours ---------------------------------------------------------------

func _overlays() -> BoardOverlays:
	if _host == null:
		return null
	return _host.get_node_or_null(^"BoardOverlays") as BoardOverlays


# A reach colour is a STATIC var, and Object.get/set are instance methods -- there is no reflecting
# on the class, so the two names are matched explicitly. An unknown one is a loud failure rather
# than a silently dead knob.
func read_layer(knob: Dictionary) -> Variant:
	if knob.has("reach"):
		match knob["reach"]:
			"ATTACK_MODULATE": return OverlayManager.ATTACK_MODULATE
			"HEAL_ATTACK_MODULATE": return OverlayManager.HEAL_ATTACK_MODULATE
		push_error("LookTool: unknown reach colour %s" % knob["reach"])
		return null
	var overlays := _overlays()
	if overlays == null:
		return null
	return overlays.layer_modulate(knob["layer"])


func write_layer(knob: Dictionary, color: Color) -> void:
	if knob.has("reach"):
		# The static var IS the authority; the live 2D fill is re-derived from it so the tuned
		# colour shows now rather than at the next aim (the 3D mirrors that fill, not the var).
		match knob["reach"]:
			"ATTACK_MODULATE": OverlayManager.ATTACK_MODULATE = color
			"HEAL_ATTACK_MODULATE": OverlayManager.HEAL_ATTACK_MODULATE = color
			_:
				push_error("LookTool: unknown reach colour %s" % knob["reach"])
				return
		var om: OverlayManager = _overlay_manager()
		if om != null:
			om.refresh_attack_reach_color()
		return
	var overlays := _overlays()
	if overlays != null:
		overlays.set_layer_modulate(knob["layer"], color)


func _overlay_manager() -> OverlayManager:
	if _host == null:
		return null
	var game: Node2D = _host.game
	if game == null:
		return null
	return game.overlay_manager as OverlayManager


func layer_baseline_of(index: int) -> Variant:
	if index < 0 or index >= _layer_baseline.size():
		return null
	return _layer_baseline[index]


func has_host() -> bool:
	return _host != null


# --- Reading and writing a knob ---------------------------------------------------------

# Thin binds over LookKnobs' statics, closing over this tab's own _host. NOT a second answer --
# the table and the property access both live there; these only save every call site passing it.

func target_of(knob: Dictionary) -> Node:
	return LookKnobs.target_of(_host, knob)


func read(knob: Dictionary) -> Variant:
	return LookKnobs.read(_host, knob)


func write(knob: Dictionary, value: Variant) -> void:
	LookKnobs.write(_host, knob, value)


# What Reset returns to -- the loaded preset if there is one, else the authored scene.
func baseline_of(index: int) -> Variant:
	if index < 0 or index >= _baseline.size():
		return null
	return _baseline[index]


# What the SCENE was authored with, whatever is loaded. Copy Values' reference point, because its
# output is lines you paste into Battle3D.tscn.
func authored_of(index: int) -> Variant:
	if index < 0 or index >= _authored.size():
		return null
	return _authored[index]


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
		push_error("LookTool: group '%s' has no tab in GROUP_TABS" % group)
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
	var layer_group: String = LAYER_KNOBS[0]["group"]
	var layer_rows := _rows_for_group(layer_group)
	_add_heading(layer_rows, layer_group)
	for knob: Dictionary in LAYER_KNOBS:
		var value: Variant = read_layer(knob)
		if typeof(value) != TYPE_COLOR:
			DevWidgets.add_label(layer_rows, "%s - UNRESOLVED" % knob["label"])
			push_error("LookTool layer knob does not resolve: %s" % knob["label"])
			continue
		var first := layer_rows.get_child_count()
		DevWidgets.add_color(layer_rows, knob["label"], value,
			func(picked: Color) -> void: write_layer(knob, picked))
		_apply_tip(layer_rows, first, tip_for(knob))
	_build_squad_marker_rows(layer_rows)
	_tabs.current_tab = clampi(showing, 0, maxi(0, _tabs.get_tab_count() - 1))


# --- #325 experiment: squares vs rings ---------------------------------------------------

# Bespoke rows rather than table entries: the style flag is a bool STATIC on OverlayManager
# (both stacks read it), which neither KNOBS (property paths on scene nodes) nor LAYER_KNOBS
# (Color-only) can address. They die with the experiment, whichever style wins.
func _build_squad_marker_rows(rows: VBoxContainer) -> void:
	_add_heading(rows, "Squad markers (#325 experiment)")
	var first := rows.get_child_count()
	DevWidgets.add_checkbox(rows, "Rings underfoot", OverlayManager.SQUAD_MARKER_RINGS,
		_on_ring_toggle)
	_apply_tip(rows, first, DevWidgets.wrap_tooltip(
		"ON: squad membership reads as a per-squad coloured ring under each member, with the crown decal inside the leader's. OFF: the legacy green squares over heads. MOVES BOTH STACKS -- and takes effect on markers already up. The losing style gets deleted when the experiment resolves."))
	first = rows.get_child_count()
	DevWidgets.add_slider(rows, "Ring opacity", OverlayManager.SQUAD_RING_ALPHA, 0.1, 1.0, 0.01,
		_on_ring_alpha)
	_apply_tip(rows, first, DevWidgets.wrap_tooltip(
		"Alpha of the membership rings (the crown decal stays opaque). MOVES BOTH STACKS."))


func _on_ring_toggle(on: bool) -> void:
	OverlayManager.SQUAD_MARKER_RINGS = on
	_restyle_squad_markers()


func _on_ring_alpha(moved: float) -> void:
	OverlayManager.SQUAD_RING_ALPHA = moved
	_restyle_squad_markers()


func _restyle_squad_markers() -> void:
	var om: OverlayManager = _overlay_manager()
	if om != null:
		om.restyle_squad_markers()


# The which-stack note is appended per KIND rather than typed into each tip, so it cannot drift
# out of step with the table it describes.
func tip_for(knob: Dictionary) -> String:
	var tip: String = knob.get("tip", "")
	if knob.has("layer"):
		tip += "\n\n3D ONLY -- the flat 2D board keeps its own colour. A declared divergence, and provisional: tune it, look at it, then decide whether 2D should follow."
	elif knob.has("reach"):
		tip += "\n\nMOVES BOTH STACKS -- the 3D mirrors the 2D's fill rather than holding a colour of its own, so this tunes OverlayManager and the flat 2D game changes with it."
	return DevWidgets.wrap_tooltip(tip)


# Every control the row added, so hovering the slider handle answers as well as the label.
func _apply_tip(rows: VBoxContainer, first_index: int, tip: String) -> void:
	for i in range(first_index, rows.get_child_count()):
		DevWidgets.apply_tooltip(rows.get_child(i), tip)


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
		"Save every scene-mood knob under a new name. Camera handling, board markup and the brush\nghost are deliberately not captured -- those are game settings, not a mission's look.",
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
	DevWidgets.refresh_update_button(_update_button, target, "preset", update_block_reason())
	DevWidgets.refresh_delete_button(_delete_button, target, "preset")


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
		_status.text = "Could not load preset '%s', and the default is missing too" % target
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
		_status.text = "The default look is missing from %s." % LookKnobs.DEFAULT_PATH
		return
	apply_preset(preset)
	_loaded_preset = ""
	_preset_dropdown.select(-1)
	_refresh_preset_buttons()
	_status.text = "Loaded the default look. Reset now returns here."


func _load_report(target: String, report: Dictionary) -> String:
	var text := "Loaded preset '%s'. Reset now returns here." % target
	var missing: Array = report["missing"]
	if not missing.is_empty():
		text += ("\n%d knob(s) added since this preset was saved, left at the scene's value: %s."
			+ " Set them and press Update to back-add.") % [missing.size(), ", ".join(missing)]
	var unknown: Array = report["unknown"]
	if not unknown.is_empty():
		text += "\n%d saved value(s) no longer apply (knob removed or now excluded): %s." \
			% [unknown.size(), ", ".join(unknown)]
	return text


func _on_save_as_pressed() -> void:
	if _host == null:
		_status.text = "No 3D host attached - there is no look to save."
		return
	var entered := _preset_name_input.text.strip_edges()
	if entered == "":
		var msg := "Preset needs a name"
		push_warning(msg)
		_status.text = msg
		return
	# Flat folder, so no allow_slash: a '/' would land the file where the scan never looks (#168).
	if DevWidgets.refuse_illegal_name(entered, "preset", _status):
		return
	if DevWidgets.refuse_existing_file(LookKnobs.preset_path(entered), "preset", _status):
		return
	if not DevWidgets.save_over(capture_preset(entered), LookKnobs.preset_path(entered), _status):
		return
	# Saving is also loading: the look on screen IS this preset now, so Reset should return to it.
	_baseline = _live_values()
	_loaded_preset = entered
	_preset_name_input.text = ""
	refresh_preset_dropdown(entered)
	_status.text = "Saved preset '%s' (%d knobs). Reset now returns here." % [entered, LookKnobs.preset_knobs().size()]


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
	DevWidgets.confirm(self, "Overwrite preset '%s' with the current look? The saved version is lost." % target,
		func() -> void: _update_confirmed(target))


func _update_confirmed(target: String) -> void:
	if not DevWidgets.save_over(capture_preset(target), LookKnobs.preset_path(target), _status):
		return
	_baseline = _live_values()   # the file now says what is on screen, so Reset must too
	_status.text = "Updated preset '%s' (%d knobs)." % [target, LookKnobs.preset_knobs().size()]


func _on_delete_pressed() -> void:
	var target := DevWidgets.selected_name(_preset_dropdown)
	if target == "":
		return
	DevWidgets.confirm_delete(self, "preset '%s'" % target, func() -> void: _delete_confirmed(target))


func _delete_confirmed(target: String) -> void:
	if not DevWidgets.delete_saved_file(LookKnobs.preset_path(target), "preset", _status):
		return
	if _loaded_preset == target:
		# The look on screen is untouched -- only its file is gone. Reset holds it rather than
		# snapping anywhere, so deleting a file never also changes what you are looking at.
		_baseline = _live_values()
		_loaded_preset = ""
		_status.text = "Deleted preset '%s'. The look on screen is unchanged; press Default to leave it." % target
	refresh_preset_dropdown()


# The live value of every knob, per LookKnobs.KNOBS index -- the baseline a just-saved preset establishes.
func _live_values() -> Array:
	var values: Array = _authored.duplicate()
	for i in LookKnobs.KNOBS.size():
		if not LookKnobs.PRESET_EXCLUDED.has(LookKnobs.preset_key(LookKnobs.KNOBS[i])):
			values[i] = read(LookKnobs.KNOBS[i])
	return values


# --- The handoff ------------------------------------------------------------------------

func _on_copy_pressed() -> void:
	var moved := changed_values()
	if moved.is_empty():
		_status.text = "Nothing has moved off the scene's authored values yet."
		return
	DisplayServer.clipboard_set(_format(moved))
	var count := _value_count(moved)
	if _loaded_preset == "":
		_status.text = "Copied %d changed value(s) to the clipboard." % count
	else:
		# Say which, or the count reads as "what I tuned" when it is "preset + what I tuned".
		_status.text = ("Copied %d value(s) differing from Battle3D.tscn -- that is preset '%s' PLUS "
			+ "anything you moved since. Save As / Update is the handoff for a preset.") % [count, _loaded_preset]


func _on_reset_pressed() -> void:
	if _host == null:
		return
	for i in LookKnobs.KNOBS.size():
		var authored: Variant = baseline_of(i)
		if typeof(authored) != TYPE_NIL:
			write(LookKnobs.KNOBS[i], authored)
	for i in LAYER_KNOBS.size():
		var authored_color: Variant = layer_baseline_of(i)
		if typeof(authored_color) == TYPE_COLOR:
			write_layer(LAYER_KNOBS[i], authored_color)
	_rebuild()   # redraw every widget off the restored values -- one path, every widget kind
	if _loaded_preset == "":
		_status.text = "Every knob is back at its authored value."
	else:
		_status.text = "Every knob is back at preset '%s'." % _loaded_preset


func _on_refit_pressed() -> void:
	if _host == null:
		return
	_host.fit_camera()
	_status.text = "Camera re-framed on the current board."


# Only what MOVED, keyed by where it gets pasted: header -> {property: literal}. A property path
# that passes through a sub-resource is authored INSIDE that resource, so the header names the
# resource and the line is what goes in it. A vector component (flame_size:x) has no resource
# between it and the node, so the whole vector is emitted -- "x = 0.6" would mean nothing in a
# .tscn, and it also collapses the x and y knobs into the single line they share.
func changed_values() -> Dictionary:
	var groups := {}
	for i in LookKnobs.KNOBS.size():
		var knob: Dictionary = LookKnobs.KNOBS[i]
		var live: Variant = read(knob)
		var authored: Variant = authored_of(i)
		if typeof(live) == TYPE_NIL or typeof(authored) == TYPE_NIL or LookKnobs.same_value(live, authored):
			continue
		_record(groups, _paste_split(knob))
	for i in LAYER_KNOBS.size():
		var knob: Dictionary = LAYER_KNOBS[i]
		var live: Variant = read_layer(knob)
		var authored: Variant = layer_baseline_of(i)
		if typeof(live) != TYPE_COLOR or typeof(authored) != TYPE_COLOR or LookKnobs.same_value(live, authored):
			continue
		_record(groups, _layer_paste_split(knob, live))
	return groups


# split = [paste header, dedup key, the finished line]. The key exists only so two knobs that
# emit the SAME line (flame_size:x and :y) collapse to one entry.
func _record(groups: Dictionary, split: Array) -> void:
	var header: String = split[0]
	if not groups.has(header):
		groups[header] = {}
	var entries: Dictionary = groups[header]
	entries[split[1]] = split[2]


# A layer colour is not authored at a property path, so it gets its own paste shape: the whole
# LAYERS row (sort and kind read off the live table, so the line is paste-ready as-is), or the
# static var declaration for a reach colour.
func _layer_paste_split(knob: Dictionary, live: Color) -> Array:
	if knob.has("reach"):
		var name: String = knob["reach"]
		return ["OverlayManager.gd", name,
			"static var %s := %s" % [name, DevWidgets.literal_for(live)]]
	var layer: BoardOverlays.Layer = knob["layer"]
	var spec: Dictionary = BoardOverlays.LAYERS[layer]
	var layer_name: String = BoardOverlays.Layer.keys()[layer]
	var kind_name: String = BoardOverlays.Kind.keys()[spec["kind"]]
	return ["BoardOverlays.gd -> LAYERS", layer_name,
		'Layer.%s: {"color": %s, "sort": %d, "kind": Kind.%s},'
			% [layer_name, DevWidgets.literal_for(live), spec["sort"], kind_name]]


func _paste_split(knob: Dictionary) -> Array:
	var segments: PackedStringArray = String(knob["prop"]).split(":")
	var current: Object = target_of(knob)
	var owner_bits: PackedStringArray = PackedStringArray()
	var i := 0
	# Walk to the DEEPEST object in the chain: that is the thing the value is authored on.
	while i < segments.size() - 1:
		var next: Variant = current.get(segments[i])
		if not (next is Object):
			break
		owner_bits.append(segments[i])
		current = next as Object
		i += 1
	var node_path: String = knob["node"]
	var header := "Battle3D.tscn -> %s" % ("Battle3D" if node_path == "." else node_path)
	if owner_bits.size() > 0:
		header += ".%s" % ".".join(owner_bits)
	var prop: String = segments[i]
	return [header, prop, "%s = %s" % [prop, DevWidgets.literal_for(current.get(prop))]]


func _format(groups: Dictionary) -> String:
	var out: PackedStringArray = PackedStringArray()
	for header: String in groups:
		out.append("# %s" % header)
		var entries: Dictionary = groups[header]
		for key: String in entries:
			out.append(entries[key])   # the split already built the finished line
		out.append("")
	return "\n".join(out).strip_edges()


func _value_count(groups: Dictionary) -> int:
	var total := 0
	for header: String in groups:
		var entries: Dictionary = groups[header]
		total += entries.size()
	return total


# literal_for moved to DevWidgets in #272 -- the Object tab writes the same literals into a script
# rather than onto the clipboard, so "what is the GDScript spelling of this value" gained a second
# reader and stopped being this panel's private business.
