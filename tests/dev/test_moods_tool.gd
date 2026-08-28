# The Moods tab (#212). Two of these are laws rather than examples.
#
# "Every knob resolves" catches a table entry left pointing at a renamed or moved property --
# the drift a pointer-shaped table is exposed to.
#
# "A written knob survives the next frame" is the one that matters: a knob may only name a
# property that is authored and READ, never one the game writes back per frame. Pointed at
# runtime-written state (the rig's yaw, dof_blur_*_distance, max_distance, orbit_button) a
# slider moves and silently reverts, which is the failure that makes a tuning panel worthless.
# Writing and asserting immediately cannot see it -- the write always lands -- so these wait
# TWO frames: process_frame resumes a coroutine BEFORE node _process runs (#215's lesson), so
# one await proves nothing about what _process does with the value.
#
# The host arriving at all is a WIRE, not two ends: the suite instantiates the real Battle3D
# scene and lets battle3d._ready push, rather than calling attach_host itself.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")

var _scene: Node3D
var _moods: MoodsTool


func before_test() -> void:
	var packed := SCENE
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false   # no board needed: every knob is a scene property
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var dev_overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	_moods = dev_overlay.moods_tool


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


# --- Helpers ---------------------------------------------------------------------------

func _knob(node: String, prop: String) -> Dictionary:
	for knob: Dictionary in LookKnobs.KNOBS:
		if knob["node"] == node and knob["prop"] == prop:
			return knob
	return {}


# A different, legal value for whatever kind this knob holds.
func _nudged(knob: Dictionary, value: Variant) -> Variant:
	if knob.has("options"):
		var options: Array = knob["options"]
		return (int(value) + 1) % options.size()
	match typeof(value):
		TYPE_BOOL:
			return not value
		TYPE_COLOR:
			var color: Color = value
			return Color(color.r, color.g, color.b, fposmod(color.a + 0.3, 1.0))
		_:
			var low: float = knob["min"]
			var high: float = knob["max"]
			var current: float = value
			var step: float = (high - low) * 0.1
			return current - step if current + step > high else current + step


# --- The laws ---------------------------------------------------------------------------

func test_battle3d_hands_the_look_tab_its_host() -> void:
	assert_bool(_moods.has_host()).is_true()


func test_every_knob_resolves_against_the_real_scene() -> void:
	var unresolved: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS:
		if typeof(_moods.read(knob)) == TYPE_NIL:
			unresolved.append("%s:%s" % [knob["node"], knob["prop"]])
	assert_array(unresolved).override_failure_message(
		"Knobs pointing at nothing: %s" % ", ".join(unresolved)).is_empty()


func test_a_written_knob_survives_the_next_frame() -> void:
	var wanted: Array = []
	var inert: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS:
		var value: Variant = _moods.read(knob)
		if typeof(value) == TYPE_NIL:
			continue
		_moods.write(knob, _nudged(knob, value))
		# Compare against what the property ACCEPTED, never against what was asked for:
		# engine-backed floats are single-precision, so a double asked for and the float
		# stored differ in the last bits and every one of these would read as a revert.
		# A real per-frame overwrite still fails, which mutant 2 in the PR body proves.
		var stored: Variant = _moods.read(knob)
		if stored == value:
			inert.append("%s:%s" % [knob["node"], knob["prop"]])
			continue
		wanted.append({"knob": knob, "want": stored})
	# A knob whose nudge never registered would sail through the survival check below without
	# testing anything -- a set_indexed that silently does nothing looks identical to a value
	# that held. Fail on it separately rather than letting it hide.
	assert_array(inert).override_failure_message(
		"Knobs that did not take a write at all: %s" % ", ".join(inert)).is_empty()
	# Two frames: the first resumes this coroutine before any node _process has run.
	await await_idle_frame()
	await await_idle_frame()
	var reverted: Array[String] = []
	for entry: Dictionary in wanted:
		var knob: Dictionary = entry["knob"]
		if _moods.read(knob) != entry["want"]:
			reverted.append("%s:%s" % [knob["node"], knob["prop"]])
	assert_array(reverted).override_failure_message(
		"Knobs the game writes back (a slider here would lie): %s" % ", ".join(reverted)).is_empty()


# The panel's own WIRE. Every other case here calls write() directly, so without this the rows
# could be built completely disconnected and the whole suite would stay green -- two ends, no
# wire. A slider is what actually gets dragged.
func test_dragging_a_slider_moves_the_live_property() -> void:
	var knob := _knob("Sun", "light_energy")
	var slider := _slider_for(knob["label"])
	assert_object(slider).is_not_null()
	var before: float = _moods.read(knob)
	slider.value = before + 0.05
	assert_float(_moods.read(knob)).is_equal_approx(before + 0.05, 0.0005)


func _slider_for(label_text: String) -> HSlider:
	return _row_for(label_text).get_child(1) as HSlider


# Walks the whole panel rather than one container: rows live under per-group SUB-TABS now, and a
# search that knows the layout would need updating every time the layout does.
func _row_for(label_text: String) -> HBoxContainer:
	return _find_row(_moods, label_text)


func _find_row(node: Node, label_text: String) -> HBoxContainer:
	for child in node.get_children():
		var box := child as HBoxContainer
		if box != null and box.get_child_count() > 0:
			var label := box.get_child(0) as Label
			if label != null and label.text == label_text:
				return box
		var found := _find_row(child, label_text)
		if found != null:
			return found
	return null


# The dev asked for a tooltip on every knob (2026-08-14), so a knob shipping without one is a
# regression rather than an oversight to notice later.
func test_every_knob_has_a_tooltip() -> void:
	var untipped: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS:
		if String(knob.get("tip", "")).strip_edges() == "":
			untipped.append(knob["label"])
	assert_array(untipped).override_failure_message(
		"Knobs with no tooltip: %s" % ", ".join(untipped)).is_empty()


# A tooltip is a plain Label with no autowrap, so an unwrapped one runs off the screen.
func test_no_tooltip_line_runs_too_long() -> void:
	var wide: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS:
		for line: String in _moods.tip_for(knob).split("\n"):
			if line.length() > 90:   # the wrapper targets 74; this catches a wrap that never ran
				wide.append(knob["label"])
				break
	assert_array(wide).override_failure_message(
		"Tooltips with an unwrapped line: %s" % ", ".join(wide)).is_empty()


# The wire: the tip has to reach the control you actually hover, not just the row's label. A
# slider has mouse_filter STOP, so Godot asks IT for the tooltip and never walks up to the label.
func test_the_tooltip_reaches_the_slider_you_hover() -> void:
	var knob := _knob("Sun", "light_energy")
	var slider := _slider_for(knob["label"])
	assert_object(slider).is_not_null()
	assert_str(slider.tooltip_text).is_equal(_moods.tip_for(knob))
	assert_str(slider.tooltip_text).is_not_empty()


# Every group must land on a sub-tab. An unmapped group draws nowhere the dev would look, which is
# indistinguishable from the knob not existing.
func test_every_knob_group_has_a_sub_tab() -> void:
	var orphans: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS:
		var group: String = knob["group"]
		if not MoodsTool.GROUP_TABS.has(group) and not orphans.has(group):
			orphans.append(group)
	assert_array(orphans).override_failure_message(
		"Knob groups with no sub-tab (their rows would vanish): %s" % ", ".join(orphans)).is_empty()


# Every row is reachable: the panel builds one container per tab and fills it from the map, so a
# broken mapping shows up as a knob whose row exists nowhere.
func test_every_knob_has_a_row_somewhere_in_the_panel() -> void:
	var missing: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS:
		if knob.has("options") or typeof(_moods.read(knob)) == TYPE_BOOL:
			continue   # dropdowns and checkboxes are not HBox-with-label rows
		if _row_for(knob["label"]) == null:
			missing.append(knob["label"])
	assert_array(missing).override_failure_message(
		"Knobs with no row drawn anywhere: %s" % ", ".join(missing)).is_empty()


# A colour knob is FOUR sliders and a swatch, not a picker. ColorPickerButton froze the dev window
# solid the first time one was opened (dev, 2026-08-14), so the ban is a law with a test rather
# than a comment that the next colour knob quietly re-breaks. It bans the ColorPicker FAMILY, not
# popups -- the tonemap OptionButton on this same panel is fine, as it is on every other dev tab.
func test_the_panel_builds_no_colorpicker_widgets() -> void:
	var offenders: Array[String] = []
	_walk_for_pickers(_moods, offenders)
	assert_array(offenders).override_failure_message(
		"ColorPicker widgets in the Moods tab (these freeze the dev window): %s"
		% ", ".join(offenders)).is_empty()


func _walk_for_pickers(node: Node, offenders: Array[String]) -> void:
	for child in node.get_children(true):   # include internal children
		if child is ColorPicker or child is ColorPickerButton:
			offenders.append("%s (%s)" % [child.name, child.get_class()])
		_walk_for_pickers(child, offenders)


# Child order is label, swatch, then (tag, slider, field) per channel: 3 = R slider, 4 = R field.
func test_dragging_a_colour_channel_moves_the_live_property() -> void:
	var knob := _knob("Sun", "light_color")
	var row := _row_for(knob["label"])
	assert_object(row).is_not_null()
	var before: Color = _moods.read(knob)
	var red := row.get_child(3) as HSlider
	assert_object(red).is_not_null()
	red.value = 128.0                                        # 0-255, the scale a hex code is in
	var after: Color = _moods.read(knob)
	assert_float(after.r).is_equal_approx(128.0 / 255.0, 0.005)
	# Editing R must not re-quantise the others through 8-bit -- G is authored 0.985, and a
	# round trip would land it on 0.9843 and report the colour as changed when it was not.
	assert_float(after.g).is_equal_approx(before.g, 0.0001)


# Typing a number is its own wire: the field could be built, display correctly, and drive nothing.
func test_typing_a_colour_channel_moves_the_live_property_and_the_slider() -> void:
	var knob := _knob("Sun", "light_color")
	var row := _row_for(knob["label"])
	var slider := row.get_child(3) as HSlider
	var field := row.get_child(4) as SpinBox
	assert_object(field).is_not_null()
	field.value = 64.0
	assert_float(_moods.read(knob).r).is_equal_approx(64.0 / 255.0, 0.005)
	assert_float(slider.value).is_equal_approx(64.0, 0.001)   # the two never disagree


# --- Reset --------------------------------------------------------------------------------

# Asserted knob-by-knob rather than through a summary: this used to lean on Copy Values'
# changed_values() as a probe, and that feature is gone (#386).
func test_reset_puts_every_knob_back_to_its_authored_value() -> void:
	var before: Array = []
	for knob: Dictionary in LookKnobs.KNOBS:
		before.append(_moods.read(knob))
	var moved := 0
	for i in LookKnobs.KNOBS.size():
		var knob: Dictionary = LookKnobs.KNOBS[i]
		if typeof(before[i]) == TYPE_NIL:
			continue
		_moods.write(knob, _nudged(knob, before[i]))
		if not LookKnobs.same_value(_moods.read(knob), before[i]):
			moved += 1
	# Without this the case would pass against a panel whose writes never landed at all.
	assert_int(moved).override_failure_message(
		"nothing moved, so Reset had nothing to undo and this case asserts nothing").is_greater(0)

	_moods._on_reset_pressed()

	for i in LookKnobs.KNOBS.size():
		var knob: Dictionary = LookKnobs.KNOBS[i]
		assert_bool(LookKnobs.same_value(_moods.read(knob), before[i])).override_failure_message(
			"'%s' did not come back to its authored value" % knob["label"]).is_true()
	# Reset redraws every row, and a detached-then-queue_free'd node reads as a gdUnit orphan
	# until a frame processes the queue (#215's lesson).
	await await_idle_frame()


# The flat 2D game is a real shipping target and never gets a host; the tab reports that
# instead of crashing on every read. Update default is included because it is the newest way
# in and it WRITES -- a host-less press must reach neither the dialog nor the file.
func test_a_tab_with_no_host_degrades_instead_of_crashing() -> void:
	var orphan := MoodsTool.new()
	add_child(orphan)
	await await_idle_frame()
	assert_bool(orphan.has_host()).is_false()
	assert_object(orphan.read(LookKnobs.KNOBS[0])).is_null()
	var before := FileAccess.get_file_as_string(LookKnobs.DEFAULT_PATH)
	orphan._on_reset_pressed()
	orphan._on_update_default_pressed()
	assert_object(_dialog_under(orphan)).override_failure_message(
		"a host-less panel offered to overwrite the default").is_null()
	assert_str(FileAccess.get_file_as_string(LookKnobs.DEFAULT_PATH)).is_equal(before)
	orphan.queue_free()
	await await_idle_frame()


# --- Presets (#253 part 1) -----------------------------------------------------------------
#
# NO CASE HERE WRITES TO DISK, matching test_dev_tool_overwrite_guards.gd's discipline: presets
# are captured and applied in memory, and the Save/Update/Delete guards are asserted at REASON
# level. A real save would drop a .tres into Resources/LookPresets/ that the dropdown then lists
# forever.
#
# Two of these are laws. What a preset covers is a DESIGN ruling (scene mood in, game settings
# out -- dev, 2026-08-15), and the only thing standing between that ruling and a silent widening
# is the pair below.

# THE RULING, restated in its own terms rather than by re-reading whatever list the code keeps --
# a case that asks the same const it is checking is blind to that const changing, which is the one
# edit most likely to widen this quietly. It used to enumerate carve-outs from PRESET_EXCLUDED;
# #373 emptied that list by MOVING its population to GameKnobs, so the ruling is now structural and
# what this states is the other side of it: these nodes hold game settings, and a row on one of them
# reappearing in the look table is the widening to catch.
#
# History worth keeping, because this list has earned its keep four times: #264's prop block height,
# #280's tuft scale and #326's cover bumps each self-joined presets under the default-IN rule and
# were each caught here, not by the exclusion list, which would have agreed silently. #272 moved all
# three out of KNOBS entirely, and #373 did the same for markup, the readout and camera handling.
const GAME_SETTING_NODES := ["BoardOverlays", "UnitMirror", "BoardMirror"]
# CameraRig is the one node that holds BOTH, so it cannot be excluded wholesale: framing is mood and
# handling is not, and only the property name separates them.
const CAMERA_HANDLING := ["zoom_step", "smoothing", "glide_smoothing", "pan_speed",
	"orbit_sensitivity", "pan_margin_cells", "zoom_out_slack"]   # min_distance went with the floor


func test_the_look_table_holds_no_game_setting() -> void:
	var strays: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS:
		var node: String = knob["node"]
		var prop: String = knob["prop"]
		if GAME_SETTING_NODES.has(node) or (node == "CameraRig" and CAMERA_HANDLING.has(prop)):
			strays.append("%s (%s:%s)" % [knob["label"], node, prop])
	assert_array(strays).override_failure_message(
		"Game settings in the look table -- a mission would carry these (they belong in GameKnobs): %s"
		% ", ".join(strays)).is_empty()


# The guard on the list above, and the lesson #272 paid for: a list that exists to notice a widening
# is silently disarmed when its names stop matching anything. CAMERA_HANDLING names rows that must
# still be REAL somewhere, so a rename or a deletion reds this instead of quietly emptying the law.
func test_every_camera_handling_name_is_a_real_game_knob() -> void:
	var live: Array[String] = []
	for knob: Dictionary in GameKnobs.KNOBS:
		if knob["node"] == "CameraRig":
			live.append(knob["prop"])
	for prop: String in CAMERA_HANDLING:
		assert_bool(live.has(prop)).override_failure_message(
			"CAMERA_HANDLING names '%s', which is no longer a camera knob -- this law has stopped catching anything" % prop).is_true()


# A preset walks the whole table now, so "in scope" and "the table" are the same set. Asserted in
# both directions anyway: the filter surviving as a named function is what a future non-mood knob
# would reach for, and this is what notices if it starts dropping rows.
func test_a_preset_carries_exactly_the_in_scope_knobs_and_nothing_else() -> void:
	var captured: Array = _moods.capture_preset("law").values.keys()
	var in_scope: Array[String] = []
	for knob: Dictionary in LookKnobs.preset_knobs():
		in_scope.append(LookKnobs.preset_key(knob))
	assert_int(in_scope.size()).is_equal(LookKnobs.KNOBS.size())
	assert_int(captured.size()).is_equal(in_scope.size())
	for key: String in captured:
		assert_bool(in_scope.has(key)).override_failure_message(
			"'%s' reached a preset without being an in-scope knob" % key).is_true()


# Compared against what the property ACCEPTED, never against what was asked for: engine properties
# store single-precision. The "the write registered" assertion is the load-bearing one -- without
# it an apply_preset that did nothing at all would sit inside a passing case (the trap this panel
# has now walked into twice).
func test_a_captured_preset_round_trips_through_apply() -> void:
	var knob := _knob("Sun", "light_energy")
	var authored: Variant = _moods.read(knob)
	_moods.write(knob, _nudged(knob, authored))
	var accepted: Variant = _moods.read(knob)
	assert_bool(LookKnobs.same_value(accepted, authored)).override_failure_message(
		"the tuning write never registered, so this case would pass against an inert apply").is_false()

	var preset := _moods.capture_preset("roundtrip")
	# Written back by hand rather than by pressing Default: since #386 the default is a file the
	# dev can REWRITE, so "Default puts this knob back to the scene's value" is no longer true by
	# construction, and leaning on it here would red the first time he legitimately used the button.
	# The Default button keeps its own coverage below, where the expectation is read from the file.
	_moods.write(knob, authored)
	assert_bool(LookKnobs.same_value(_moods.read(knob), authored)).is_true()

	_moods.apply_preset(preset)
	assert_bool(LookKnobs.same_value(_moods.read(knob), accepted)).is_true()
	await await_idle_frame()


# The dev's call: load a mood, tweak it, Reset returns to the MOOD. Getting back to Battle3D.tscn
# is the dropdown's own "(authored scene)" row instead.
func test_reset_returns_to_the_loaded_preset_not_the_authored_scene() -> void:
	var knob := _knob("WorldEnvironment", "environment:adjustment_saturation")
	var authored: Variant = _moods.read(knob)
	_moods.write(knob, _nudged(knob, authored))
	var preset := _moods.capture_preset("mood")
	_moods._on_default_pressed()
	_moods.apply_preset(preset)
	var in_preset: Variant = _moods.read(knob)
	assert_bool(LookKnobs.same_value(in_preset, authored)).is_false()

	_moods.write(knob, _nudged(knob, in_preset))
	assert_bool(LookKnobs.same_value(_moods.read(knob), in_preset)).is_false()
	_moods._on_reset_pressed()
	assert_bool(LookKnobs.same_value(_moods.read(knob), in_preset)).is_true()
	await await_idle_frame()


# The dev accepted back-adding new knobs to old moods by hand -- so the panel has to SAY which
# ones, and the knob has to land on the DEFAULT's value rather than on whatever was last on screen.
#
# The expectation is read out of the default FILE, not off the scene. It used to assert the scene's
# authored value, which only ever passed because the two agreed; since #386 the default is a file
# the dev rewrites, and LookKnobs.apply has always sourced this fallback from it.
func test_a_preset_missing_a_knob_falls_back_to_the_default_and_says_so() -> void:
	var knob := _knob("Sun", "shadow_opacity")
	var fallback: Variant = LookKnobs.default_preset().values[LookKnobs.preset_key(knob)]
	var preset := _moods.capture_preset("partial")
	preset.values.erase(LookKnobs.preset_key(knob))
	_moods.write(knob, _nudged(knob, _moods.read(knob)))   # so "it moved back" is a real claim
	assert_bool(LookKnobs.same_value(_moods.read(knob), fallback)).override_failure_message(
		"the nudge landed on the default's own value, so this case would assert nothing").is_false()

	var report := _moods.apply_preset(preset)
	assert_array(report["missing"]).contains([knob["label"]])
	assert_bool(LookKnobs.same_value(_moods.read(knob), fallback)).override_failure_message(
		"a knob the mood predates must land on the DEFAULT's value, not on the last look").is_true()
	await await_idle_frame()


func test_a_preset_naming_a_dead_knob_is_skipped_and_reported() -> void:
	var preset := _moods.capture_preset("stale")
	preset.values["Sun|a_property_that_no_longer_exists"] = 1.0
	var report := _moods.apply_preset(preset)
	assert_array(report["unknown"]).contains(["Sun|a_property_that_no_longer_exists"])
	await await_idle_frame()


# Update writes the LOADED preset back over its own file and nothing else -- the 2026-08-11
# scenario rule, which exists because a mis-aimed Update destroyed missions/Prolog.
func test_update_refuses_a_preset_that_is_not_the_loaded_one() -> void:
	_moods._preset_dropdown.add_item("Some Other Preset")
	_moods._preset_dropdown.select(_moods._preset_dropdown.item_count - 1)
	assert_str(_moods.loaded_preset()).is_empty()
	assert_str(_moods.update_block_reason()).is_not_empty()


# EVERY dropdown row is a file now that #253 part 2 gave the way back its own Default button, so
# nothing may fall back to index 0 -- that row is a write target Update and Delete would aim at.
# Part 1 shipped exactly that fallback and it was safe only because row 0 was the authored scene.
func test_the_dropdown_selects_nothing_when_no_preset_is_loaded() -> void:
	_moods.refresh_preset_dropdown()
	assert_int(_moods._preset_dropdown.selected).override_failure_message(
		"the dropdown fell back to a real preset file, which Update and Delete would then aim at"
	).is_equal(-1)
	assert_bool(_moods._update_button.disabled).is_true()
	assert_bool(_moods._delete_button.disabled).is_true()


# Update default (#386) is the only button here that writes a file OUTSIDE Resources/LookPresets/,
# and the file it writes is what every board with no named mood wears -- so the ask-first
# convention (#380) is the whole guard, and these cases assert it without letting a byte move.
func test_update_default_asks_before_it_overwrites() -> void:
	var before := FileAccess.get_file_as_string(LookKnobs.DEFAULT_PATH)
	_moods.write(_knob("Sun", "light_energy"), 9.0)   # something worth not saving by accident

	_moods._on_update_default_pressed()

	assert_object(_dialog_under(_moods)).override_failure_message(
		"Update default wrote without asking").is_not_null()
	assert_str(FileAccess.get_file_as_string(LookKnobs.DEFAULT_PATH)).override_failure_message(
		"the default was rewritten while its confirmation was still on screen").is_equal(before)
	await await_idle_frame()


# A capture under any other name would RENAME the default rather than overwrite it, and the file
# is found by path, so nothing else would notice.
func test_the_default_keeps_its_name_when_it_is_rewritten() -> void:
	assert_str(LookKnobs.default_preset().preset_name).is_equal(LookKnobs.DEFAULT_NAME)
	assert_str(_moods.capture_preset(LookKnobs.DEFAULT_NAME).preset_name).is_equal(LookKnobs.DEFAULT_NAME)


func _dialog_under(host: Node) -> ConfirmationDialog:
	for child in host.get_children():
		if child is ConfirmationDialog:
			return child as ConfirmationDialog
	return null


# Default is the ONE way back (dev, 2026-08-15), replacing the "(authored scene)" row.
func test_default_loads_the_fallback_look_and_becomes_the_baseline() -> void:
	var knob := _knob("Sun", "light_energy")
	var default_look := LookKnobs.default_preset()
	assert_object(default_look).is_not_null()
	_moods.write(knob, _nudged(knob, _moods.read(knob)))
	_moods._on_default_pressed()
	var expected: Variant = default_look.values[LookKnobs.preset_key(knob)]
	assert_bool(LookKnobs.same_value(_moods.read(knob), expected)).is_true()
	# ...and Reset now holds there rather than snapping somewhere else.
	_moods.write(knob, _nudged(knob, _moods.read(knob)))
	_moods._on_reset_pressed()
	assert_bool(LookKnobs.same_value(_moods.read(knob), expected)).is_true()
	await await_idle_frame()
