extends VBoxContainer
class_name GameTool

# The dev-tools Game tab (#373): where the game's own presentation constants are tuned AND KEPT.
# MoodsTool's and ObjectTool's sibling, and deliberately the same shape -- rows over a table, a
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
var _save_button: Button
# Touched since the last save/reset (#389). A FLAG for the marker; the exact answer is re-derived
# where it is cheap -- once per save, from changed_indices()/changed_class_indices().
var _dirty := false

# --- The Playback page's two filters (#520 2b slice 2, dev 2026-08-27) ------------------------
#
# Thirty flat rows was unreadable, and half of them were inert depending on a setting the panel
# never mentioned. So the page shows ONE pacing profile at a time and ONE action at a time, and the
# thing that picks the profile is the real Battle zoom setting -- meaning you always tune the mode
# you are watching, and a row that would move nothing is simply not in front of you.
#
# EVERY ROW IS STILL BUILT; the filter only sets `visible`. That is load-bearing rather than lazy:
# tests/dev/test_game_knobs.gd's panel laws walk the whole tree for a row per knob and never ask
# about visibility, so building on demand would fail them for every row not currently showing.
# TileBrushTool._set_paint_mode is the same idiom one panel over.
var _action_picker: OptionButton
var _shown_action: BaseAction.ActionType = BaseAction.ActionType.ATTACK
# Every control each row put on the page, by its row's tags. Kept because a row is not one node --
# a colour row is several -- so hiding one means hiding the span DevWidgets.add_knob_row returned.
var _filtered: Array = []   # of {"controls": Array[Node], "profile": String, "action": int}


func _ready() -> void:
	var buttons := HBoxContainer.new()
	_save_button = _button("Save to source",
		"Write every value you have moved into the declaration that authors it, in the script that\ndeclares it. These are game-wide constants rather than mission mood, so this is the whole way\nto keep one -- the change shows up as an ordinary line in the diff. Editor runs only; res:// is\nread-only in a build.",
		_on_save_pressed)
	buttons.add_child(_save_button)
	buttons.add_child(_button("Reset",
		"Put every knob back to what is currently saved on disk.", _on_reset_pressed))
	add_child(buttons)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	# Buttons and status sit ABOVE the sub-tabs and outside them, so they are reachable from every
	# tab -- Save and Reset are panel-wide, not per-group (the Moods tab's dev ask, same answer).
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	for tab_title: String in tab_titles():
		_tab_rows[tab_title] = DevWidgets.add_knob_scroll(_tabs, tab_title)
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
	_refresh_dirty()


# --- The unsaved marker (#389) --------------------------------------------------------------

func has_unsaved_changes() -> bool:
	return _dirty


func _touch() -> void:
	_dirty = true
	_refresh_save_mark()


# Re-DERIVED rather than cleared: a partial save (some writes failed) leaves real edits behind, and
# quietly adopting them would hide the failure behind a clean-looking panel. Affordable here --
# once per save, never per drag tick.
func _refresh_dirty() -> void:
	_dirty = _host != null and not (changed_indices().is_empty() and changed_class_indices().is_empty())
	_refresh_save_mark()


func _refresh_save_mark() -> void:
	if is_instance_valid(_save_button):
		DevWidgets.mark_unsaved(_save_button, "Save to source", _dirty)


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
	_filtered.clear()
	_action_picker = null
	_build_playback_header()
	var group := ""
	for knob: Dictionary in GameKnobs.KNOBS:
		var knob_group: String = knob["group"]
		var rows := _rows_for_group(knob_group)
		if knob_group != group:
			group = knob_group
			_add_heading(rows, knob_group)
			_build_group_header(rows, knob_group)
		_remember_filter(knob, DevWidgets.add_knob_row(rows, knob, LookKnobs.read(_host, knob),
			func(value: Variant) -> void:
				LookKnobs.write(_host, knob, value)
				_touch(),
			tip_for(knob)))
	group = ""
	for knob: Dictionary in GameKnobs.CLASS_KNOBS:
		var knob_group: String = knob["group"]
		var rows := _rows_for_group(knob_group)
		if knob_group != group:
			group = knob_group
			_add_heading(rows, knob_group)
			_build_group_header(rows, knob_group)
		_build_class_row(rows, knob)
	_apply_playback_filter()
	_tabs.current_tab = clampi(showing, 0, maxi(0, _tabs.get_tab_count() - 1))


# A class knob resolves through a store rather than a property path, so a failure to resolve cannot
# name a node:prop -- it says which knob and which store instead, then draws nothing.
func _build_class_row(rows: VBoxContainer, knob: Dictionary) -> void:
	var value: Variant = GameKnobs.read_class(_host, knob)
	if typeof(value) == TYPE_NIL:
		DevWidgets.add_label(rows, "%s - UNRESOLVED" % knob["label"])
		push_error("GameTool: class knob does not resolve: %s" % knob["label"])
		return
	_remember_filter(knob, DevWidgets.add_knob_row(rows, knob, value,
		func(picked: Variant) -> void:
			GameKnobs.write_class(_host, knob, picked)
			_touch(),
		tip_for(knob)))


# The where-does-this-live note is appended per table rather than typed into each tip, so it cannot
# drift out of step with what Save actually writes. GameKnobs owns the which-stack half.
func tip_for(knob: Dictionary) -> String:
	return GameKnobs.tip_for(knob) + "\n\n" + DevWidgets.wrap_tooltip(
		"GAME-WIDE -- one value for every board. Save to source writes it into the declaration that authors it; no mission can carry its own.")


# --- The Playback page's filters (#520 2b slice 2) --------------------------------------------

# The BATTLE ZOOM toggle, at the top of the Playback tab and above every heading in it.
#
# It is not a knob row and cannot be one: a PlayerSettings value has none of KnobSource's three save
# shapes (it is neither an @export default, nor a static var, nor a table entry) and needs no Save
# at all -- the store is its own persistence. This is the first dev tool to write one.
#
# It writes the REAL setting, the same one Pacing.active_profile reads and the same one the pause
# menu's Settings page shows, so the panel cannot drift from what the player gets -- and flipping it
# here really does change your preference. That is the point: the fastest A/B for a pacing value is
# the one that moves the game and the page together.
func _build_playback_header() -> void:
	var rows: VBoxContainer = _tab_rows.get(GameKnobs.PROFILE_TAB)
	if rows == null:
		return
	DevWidgets.add_checkbox(rows, "Battle zoom",
		PlayerSettings.is_on(PlayerSettings.Setting.BATTLE_ZOOM),
		func(on: bool) -> void:
			PlayerSettings.set_on(PlayerSettings.Setting.BATTLE_ZOOM, on)
			_apply_playback_filter(),
		"THE REAL PLAYER SETTING, not a preview -- the same one the Settings page shows and the one Pacing reads to pick a profile. It also chooses which column of this page you are looking at, so you always tune the mode you are watching.")


# A section's own control, drawn under its heading. Only Actions has one: the picker that decides
# which verb's rows are on the page (ObjectTool's per-type dropdown, one panel over).
func _build_group_header(rows: VBoxContainer, group: String) -> void:
	if group != GameKnobs.ACTION_GROUP:
		return
	var labels: Array = []
	for type: BaseAction.ActionType in GameKnobs.tunable_actions():
		labels.append(GameKnobs.action_label(type))
	var picker := DevWidgets.add_option(rows, "Action", labels,
		GameKnobs.action_label(_shown_action),
		func(picked: String) -> void:
			_shown_action = GameKnobs.action_for_label(picked)
			_apply_playback_filter())
	_action_picker = picker.get_child(1) as OptionButton


# What this row is tagged with, kept so the filter can find it again. Untagged rows are not stored
# at all -- there is nothing to decide about them, and they must never be hidden.
func _remember_filter(knob: Dictionary, controls: Array[Node]) -> void:
	if controls.is_empty():
		return
	var profile: String = knob.get("profile", "")
	var action: int = knob.get("action", -1)
	if profile.is_empty() and action < 0:
		return
	_filtered.append({"controls": controls, "profile": profile, "action": action})


# Show the column the live setting names, and the verb the picker names. Sets `visible` and nothing
# else: every row stays in the tree (see the note on _filtered).
func _apply_playback_filter() -> void:
	var cinematic := Pacing.active_profile() == Pacing.Profile.CINEMATIC
	for entry: Dictionary in _filtered:
		var profile: String = entry["profile"]
		var action: int = entry["action"]
		var shown := true
		if not profile.is_empty():
			shown = shown and (profile == "cinematic") == cinematic
		if action >= 0:
			shown = shown and action == _shown_action
		for control: Node in entry["controls"]:
			var drawn := control as CanvasItem
			if drawn != null:
				drawn.visible = shown


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

# Asks first (#380's convention: anything that can overwrite settings does). The gates run BEFORE
# the dialog, so a no-op save never reaches one.
func _on_save_pressed() -> void:
	if _host == null:
		_status.text = "No 3D host attached - nothing to save."
		return
	var moved := changed_indices()
	var moved_class := changed_class_indices()
	if moved.is_empty() and moved_class.is_empty():
		_status.text = "Nothing has moved off what is saved."
		return
	DevWidgets.confirm(self,
		"Write %d changed value(s) into the scripts that declare them? The old defaults are replaced."
			% (moved.size() + moved_class.size()),
		func() -> void: _save_confirmed(moved, moved_class))


func _save_confirmed(moved: PackedInt32Array, moved_class: PackedInt32Array) -> void:
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
	_refresh_dirty()   # the truth after a partial save, not a blind clear
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
	_refresh_dirty()
	_status.text = "Back to what is saved on disk."
