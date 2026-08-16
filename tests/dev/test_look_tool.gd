# The Look tab (#212). Two of these are laws rather than examples.
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

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"

var _scene: Node3D
var _look: LookTool
# The reach colours are STATIC vars, i.e. process-global: a case that tunes one would leak into
# every later case AND every later suite in the run. Snapshot and restore around each case.
var _reach_snapshot: Array[Color] = []


func before_test() -> void:
	_reach_snapshot = [OverlayManager.ATTACK_MODULATE, OverlayManager.HEAL_ATTACK_MODULATE]
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false   # no board needed: every knob is a scene property
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var dev_overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	_look = dev_overlay.look_tool


func after_test() -> void:
	OverlayManager.ATTACK_MODULATE = _reach_snapshot[0]
	OverlayManager.HEAL_ATTACK_MODULATE = _reach_snapshot[1]
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
	assert_bool(_look.has_host()).is_true()


func test_every_knob_resolves_against_the_real_scene() -> void:
	var unresolved: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS:
		if typeof(_look.read(knob)) == TYPE_NIL:
			unresolved.append("%s:%s" % [knob["node"], knob["prop"]])
	assert_array(unresolved).override_failure_message(
		"Knobs pointing at nothing: %s" % ", ".join(unresolved)).is_empty()


func test_a_written_knob_survives_the_next_frame() -> void:
	var wanted: Array = []
	var inert: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS:
		var value: Variant = _look.read(knob)
		if typeof(value) == TYPE_NIL:
			continue
		_look.write(knob, _nudged(knob, value))
		# Compare against what the property ACCEPTED, never against what was asked for:
		# engine-backed floats are single-precision, so a double asked for and the float
		# stored differ in the last bits and every one of these would read as a revert.
		# A real per-frame overwrite still fails, which mutant 2 in the PR body proves.
		var stored: Variant = _look.read(knob)
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
		if _look.read(knob) != entry["want"]:
			reverted.append("%s:%s" % [knob["node"], knob["prop"]])
	assert_array(reverted).override_failure_message(
		"Knobs the game writes back (a slider here would lie): %s" % ", ".join(reverted)).is_empty()


# The panel's own WIRE. Every other case here calls write() directly, so without this the rows
# could be built completely disconnected and the whole suite would stay green -- two ends, no
# wire. A slider is what actually gets dragged.
func test_dragging_a_slider_moves_the_live_property() -> void:
	var knob := _knob("BoardOverlays", "fill_lift")
	var slider := _slider_for(knob["label"])
	assert_object(slider).is_not_null()
	var before: float = _look.read(knob)
	slider.value = before + 0.05
	assert_float(_look.read(knob)).is_equal_approx(before + 0.05, 0.0005)


func _slider_for(label_text: String) -> HSlider:
	return _row_for(label_text).get_child(1) as HSlider


# Walks the whole panel rather than one container: rows live under per-group SUB-TABS now, and a
# search that knows the layout would need updating every time the layout does.
func _row_for(label_text: String) -> HBoxContainer:
	return _find_row(_look, label_text)


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
	for knob: Dictionary in LookKnobs.KNOBS + LookTool.LAYER_KNOBS:
		if String(knob.get("tip", "")).strip_edges() == "":
			untipped.append(knob["label"])
	assert_array(untipped).override_failure_message(
		"Knobs with no tooltip: %s" % ", ".join(untipped)).is_empty()


# A tooltip is a plain Label with no autowrap, so an unwrapped one runs off the screen.
func test_no_tooltip_line_runs_too_long() -> void:
	var wide: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS + LookTool.LAYER_KNOBS:
		for line: String in _look.tip_for(knob).split("\n"):
			if line.length() > 90:   # the wrapper targets 74; this catches a wrap that never ran
				wide.append(knob["label"])
				break
	assert_array(wide).override_failure_message(
		"Tooltips with an unwrapped line: %s" % ", ".join(wide)).is_empty()


# The wire: the tip has to reach the control you actually hover, not just the row's label. A
# slider has mouse_filter STOP, so Godot asks IT for the tooltip and never walks up to the label.
func test_the_tooltip_reaches_the_slider_you_hover() -> void:
	var knob := _knob("BoardOverlays", "fill_lift")
	var slider := _slider_for(knob["label"])
	assert_object(slider).is_not_null()
	assert_str(slider.tooltip_text).is_equal(_look.tip_for(knob))
	assert_str(slider.tooltip_text).is_not_empty()


# Every group must land on a sub-tab. An unmapped group draws nowhere the dev would look, which is
# indistinguishable from the knob not existing.
func test_every_knob_group_has_a_sub_tab() -> void:
	var orphans: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS + LookTool.LAYER_KNOBS:
		var group: String = knob["group"]
		if not LookTool.GROUP_TABS.has(group) and not orphans.has(group):
			orphans.append(group)
	assert_array(orphans).override_failure_message(
		"Knob groups with no sub-tab (their rows would vanish): %s" % ", ".join(orphans)).is_empty()


# Every row is reachable: the panel builds one container per tab and fills it from the map, so a
# broken mapping shows up as a knob whose row exists nowhere.
func test_every_knob_has_a_row_somewhere_in_the_panel() -> void:
	var missing: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS:
		if knob.has("options") or typeof(_look.read(knob)) == TYPE_BOOL:
			continue   # dropdowns and checkboxes are not HBox-with-label rows
		if _row_for(knob["label"]) == null:
			missing.append(knob["label"])
	for knob: Dictionary in LookTool.LAYER_KNOBS:
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
	_walk_for_pickers(_look, offenders)
	assert_array(offenders).override_failure_message(
		"ColorPicker widgets in the Look tab (these freeze the dev window): %s"
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
	var before: Color = _look.read(knob)
	var red := row.get_child(3) as HSlider
	assert_object(red).is_not_null()
	red.value = 128.0                                        # 0-255, the scale a hex code is in
	var after: Color = _look.read(knob)
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
	assert_float(_look.read(knob).r).is_equal_approx(64.0 / 255.0, 0.005)
	assert_float(slider.value).is_equal_approx(64.0, 0.001)   # the two never disagree


# --- Board-markup colours (slice 2) --------------------------------------------------------

func _layer_knob(key: String, value: Variant) -> Dictionary:
	for knob: Dictionary in LookTool.LAYER_KNOBS:
		if knob.get(key) == value:
			return knob
	return {}


func test_every_layer_knob_resolves() -> void:
	var unresolved: Array[String] = []
	for knob: Dictionary in LookTool.LAYER_KNOBS:
		if typeof(_look.read_layer(knob)) != TYPE_COLOR:
			unresolved.append(knob["label"])
	assert_array(unresolved).override_failure_message(
		"Layer knobs pointing at nothing: %s" % ", ".join(unresolved)).is_empty()


# THE LAW, and the reason the layer list is measured rather than chosen. `set_layer_modulate`
# REPLACES a layer's albedo, so a layer something drives per frame would take a knob that
# silently reverts. Two frames, because process_frame resumes this coroutine before any node
# _process runs -- OverlayMirror._process is exactly what has to get a turn here.
func test_a_tuned_layer_colour_survives_the_mirror_poll() -> void:
	var wanted: Array = []
	var inert: Array[String] = []
	for knob: Dictionary in LookTool.LAYER_KNOBS:
		if knob.has("reach"):
			continue   # asserted separately below: the 2D owns it, so it round-trips differently
		var before: Color = _look.read_layer(knob)
		var target := Color(before.r, before.g, before.b, fposmod(before.a + 0.3, 1.0))
		_look.write_layer(knob, target)
		var stored: Variant = _look.read_layer(knob)
		# An inert write would record the UNCHANGED colour as "wanted" and then sail through the
		# survival check below, testing nothing. Same guard slice 1's property law carries.
		if LookKnobs.same_value(stored, before):
			inert.append(knob["label"])
			continue
		wanted.append({"knob": knob, "want": stored})
	assert_array(inert).override_failure_message(
		"Layer knobs that did not take a write at all: %s" % ", ".join(inert)).is_empty()
	await await_idle_frame()
	await await_idle_frame()
	var reverted: Array[String] = []
	for entry: Dictionary in wanted:
		var knob: Dictionary = entry["knob"]
		if not LookKnobs.same_value(_look.read_layer(knob), entry["want"]):
			reverted.append(knob["label"])
	assert_array(reverted).override_failure_message(
		"Layers the mirror writes back (a knob here would lie): %s" % ", ".join(reverted)).is_empty()


# ATTACK has no 3D-only value: the mirror pushes the 2D's modulate into the 3D every poll, so the
# knob's real target is the 2D static var and BOTH stacks move. Asserted end to end.
func test_the_attack_reach_knob_moves_both_stacks() -> void:
	var knob := _layer_knob("reach", "ATTACK_MODULATE")
	var tuned := Color(0.2, 0.4, 0.9, 0.6)
	_look.write_layer(knob, tuned)
	assert_that(OverlayManager.attack_reach_color(null)).is_equal(tuned)   # the authority
	var om: OverlayManager = _scene.game.overlay_manager
	assert_that(om.attack_overlay.modulate).is_equal(tuned)                # the 2D, refreshed
	await await_idle_frame()
	await await_idle_frame()
	var overlays := _scene.get_node("BoardOverlays") as BoardOverlays
	assert_that(overlays.layer_modulate(BoardOverlays.Layer.ATTACK)).is_equal(tuned)   # the 3D


func test_copy_values_emits_a_paste_ready_layers_row() -> void:
	var knob := _layer_knob("layer", BoardOverlays.Layer.MOVE)
	_look.write_layer(knob, Color(1, 1, 0, 0.35))
	var entries: Dictionary = _look.changed_values()["BoardOverlays.gd -> LAYERS"]
	assert_str(entries["MOVE"]).is_equal(
		'Layer.MOVE: {"color": Color(1.0, 1.0, 0.0, 0.35), "sort": 0, "kind": Kind.FILL},')


func test_copy_values_emits_a_static_var_line_for_a_reach_colour() -> void:
	var knob := _layer_knob("reach", "ATTACK_MODULATE")
	_look.write_layer(knob, Color(0.2, 0.4, 0.9, 0.6))
	var entries: Dictionary = _look.changed_values()["OverlayManager.gd"]
	assert_str(entries["ATTACK_MODULATE"]).is_equal(
		"static var ATTACK_MODULATE := Color(0.2, 0.4, 0.9, 0.6)")


func test_reset_restores_every_layer_colour() -> void:
	for knob: Dictionary in LookTool.LAYER_KNOBS:
		_look.write_layer(knob, Color(0.1, 0.2, 0.3, 0.4))
	assert_dict(_look.changed_values()).is_not_empty()
	_look._on_reset_pressed()
	assert_dict(_look.changed_values()).is_empty()
	await await_idle_frame()   # the rebuild's detached rows, or they read as orphans


# --- The handoff --------------------------------------------------------------------------

func test_nothing_is_reported_changed_until_something_moves() -> void:
	assert_dict(_look.changed_values()).is_empty()


func test_a_moved_knob_is_reported_under_its_paste_target() -> void:
	var knob := _knob("WorldEnvironment", "environment:glow_hdr_threshold")
	_look.write(knob, _nudged(knob, _look.read(knob)))
	var changed := _look.changed_values()
	# The header names the RESOURCE the value is authored in, not just the node -- that is
	# where the line gets pasted.
	assert_dict(changed).contains_keys(["Battle3D.tscn -> WorldEnvironment.environment"])
	var entries: Dictionary = changed["Battle3D.tscn -> WorldEnvironment.environment"]
	assert_dict(entries).contains_keys(["glow_hdr_threshold"])


# A vector component has no resource between it and the node, so the whole vector is emitted:
# "x = 0.6" would mean nothing pasted into a .tscn, and the x and y knobs share one line.
func test_a_vector_component_knob_emits_the_whole_vector() -> void:
	var knob := _knob("BoardMirror", "flame_size:x")
	_look.write(knob, _nudged(knob, _look.read(knob)))
	var entries: Dictionary = _look.changed_values()["Battle3D.tscn -> BoardMirror"]
	assert_dict(entries).contains_keys(["flame_size"])
	# The stored value is the finished paste LINE, not a bare literal (slice 2 unified both
	# knob kinds on that, since a layer colour has no "prop = value" shape to build from).
	assert_str(entries["flame_size"]).starts_with("flame_size = Vector2(")


func test_reset_puts_every_knob_back_to_its_authored_value() -> void:
	for knob: Dictionary in LookKnobs.KNOBS:
		var value: Variant = _look.read(knob)
		if typeof(value) != TYPE_NIL:
			_look.write(knob, _nudged(knob, value))
	assert_dict(_look.changed_values()).is_not_empty()
	_look._on_reset_pressed()
	assert_dict(_look.changed_values()).is_empty()
	# Reset redraws every row, and a detached-then-queue_free'd node reads as a gdUnit orphan
	# until a frame processes the queue (#215's lesson).
	await await_idle_frame()


# The flat 2D game is a real shipping target and never gets a host; the tab reports that
# instead of crashing on every read.
func test_a_tab_with_no_host_degrades_instead_of_crashing() -> void:
	var orphan := LookTool.new()
	add_child(orphan)
	await await_idle_frame()
	assert_bool(orphan.has_host()).is_false()
	assert_object(orphan.read(LookKnobs.KNOBS[0])).is_null()
	assert_dict(orphan.changed_values()).is_empty()
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

# The ruling restated in its OWN terms, deliberately not by re-reading PRESET_EXCLUDED -- a case
# that asks the same const it is checking is blind to the const changing, which is the one edit
# most likely to widen this quietly. Everything is scene mood by default; the three carve-outs
# below are the dev's, and changing one has to change this list too, i.e. has to be noticed.
const CAMERA_FRAMING := ["Board pitch", "FOV", "Opening shot (cells)", "Fit margin (cells)"]
# The Effects group is flame plus three things that are not mood at all. This list earned its keep
# immediately: #264 added "Prop block height" to Effects, it self-joined presets via the default-IN
# rule, and when the dev ruled it out (2026-08-15) THIS case went red -- because it states the
# ruling independently instead of re-reading PRESET_EXCLUDED, which would have agreed silently.
# #280's tuft scale reddened it a second time, the same day, and is out for the same reason: it is
# prop geometry, an art convention matched to the tile art once.
const EFFECTS_NOT_MOOD := ["Brush ghost alpha", "Prop block height", "Grass tuft scale"]

func test_a_preset_captures_scene_mood_and_no_game_setting() -> void:
	var captured: Array = _look.capture_preset("law").values.keys()
	for knob: Dictionary in LookKnobs.KNOBS:
		var group: String = knob["group"]
		var label: String = knob["label"]
		var belongs := true
		var because := "scene mood"
		if group == "Board markup":
			belongs = false                          # gameplay legibility, learned once
			because = "board markup is a game setting"
		elif group == "Camera":
			belongs = CAMERA_FRAMING.has(label)      # framing rides along, handling never does
			because = "camera handling is a game setting" if not belongs else "camera framing is look"
		elif group == "Effects":
			belongs = not EFFECTS_NOT_MOOD.has(label)   # dev chrome and prop geometry are not mood
			because = "'%s' is not scene mood" % label if not belongs else "flame lights the world"
		assert_bool(captured.has(LookKnobs.preset_key(knob))).override_failure_message(
			"'%s' should%s be captured -- %s" % [label, "" if belongs else " NOT", because]).is_equal(belongs)


# A preset only ever walks KNOBS -- board-markup COLOUR (the LAYER_KNOBS half) is out by
# construction rather than by exclusion, which is the same ruling reached a different way. Nothing
# may reach a preset that is not an in-scope KNOBS row, in either direction.
func test_a_preset_carries_exactly_the_in_scope_knobs_and_nothing_else() -> void:
	var captured: Array = _look.capture_preset("law").values.keys()
	var in_scope: Array[String] = []
	for knob: Dictionary in LookKnobs.preset_knobs():
		in_scope.append(LookKnobs.preset_key(knob))
	assert_int(captured.size()).is_equal(in_scope.size())
	for key: String in captured:
		assert_bool(in_scope.has(key)).override_failure_message(
			"'%s' reached a preset without being an in-scope knob" % key).is_true()


# A property rename would otherwise silently un-exclude its knob: the old key stops matching
# anything, the new one is in nobody's list, and a camera-handling value quietly joins presets.
func test_every_excluded_key_names_a_real_knob() -> void:
	var live_keys: Array[String] = []
	for knob: Dictionary in LookKnobs.KNOBS:
		live_keys.append(LookKnobs.preset_key(knob))
	for key: String in LookKnobs.PRESET_EXCLUDED:
		assert_bool(live_keys.has(key)).override_failure_message(
			"PRESET_EXCLUDED names '%s', which is not a knob -- it has silently stopped excluding anything" % key).is_true()


# Compared against what the property ACCEPTED, never against what was asked for: engine properties
# store single-precision. The "the write registered" assertion is the load-bearing one -- without
# it an apply_preset that did nothing at all would sit inside a passing case (the trap this panel
# has now walked into twice).
func test_a_captured_preset_round_trips_through_apply() -> void:
	var knob := _knob("Sun", "light_energy")
	var authored: Variant = _look.read(knob)
	_look.write(knob, _nudged(knob, authored))
	var accepted: Variant = _look.read(knob)
	assert_bool(LookKnobs.same_value(accepted, authored)).override_failure_message(
		"the tuning write never registered, so this case would pass against an inert apply").is_false()

	var preset := _look.capture_preset("roundtrip")
	_look._on_default_pressed()
	assert_bool(LookKnobs.same_value(_look.read(knob), authored)).is_true()

	_look.apply_preset(preset)
	assert_bool(LookKnobs.same_value(_look.read(knob), accepted)).is_true()
	await await_idle_frame()


# The dev's call: load a mood, tweak it, Reset returns to the MOOD. Getting back to Battle3D.tscn
# is the dropdown's own "(authored scene)" row instead.
func test_reset_returns_to_the_loaded_preset_not_the_authored_scene() -> void:
	var knob := _knob("WorldEnvironment", "environment:adjustment_saturation")
	var authored: Variant = _look.read(knob)
	_look.write(knob, _nudged(knob, authored))
	var preset := _look.capture_preset("mood")
	_look._on_default_pressed()
	_look.apply_preset(preset)
	var in_preset: Variant = _look.read(knob)
	assert_bool(LookKnobs.same_value(in_preset, authored)).is_false()

	_look.write(knob, _nudged(knob, in_preset))
	assert_bool(LookKnobs.same_value(_look.read(knob), in_preset)).is_false()
	_look._on_reset_pressed()
	assert_bool(LookKnobs.same_value(_look.read(knob), in_preset)).is_true()
	await await_idle_frame()


# Copy Values emits paste-ready lines FOR Battle3D.tscn, so it keeps measuring the scene even
# while a preset is loaded -- diffed against the preset those lines would not reproduce the look.
func test_copy_values_measures_the_authored_scene_even_with_a_preset_loaded() -> void:
	var knob := _knob("WorldEnvironment", "environment:tonemap_exposure")
	_look.write(knob, _nudged(knob, _look.read(knob)))
	var preset := _look.capture_preset("mood")
	_look._on_default_pressed()
	_look.apply_preset(preset)
	var entries: Dictionary = _look.changed_values()["Battle3D.tscn -> WorldEnvironment.environment"]
	assert_dict(entries).contains_keys(["tonemap_exposure"])
	await await_idle_frame()


# The dev accepted back-adding new knobs to old presets by hand -- so the panel has to SAY which
# ones, and the knob has to land on the authored value rather than on whatever was last on screen.
func test_a_preset_missing_a_knob_leaves_it_authored_and_says_so() -> void:
	var knob := _knob("Sun", "shadow_opacity")
	var authored: Variant = _look.read(knob)
	var preset := _look.capture_preset("partial")
	preset.values.erase(LookKnobs.preset_key(knob))
	_look.write(knob, _nudged(knob, authored))   # so "left at authored" is a real claim

	var report := _look.apply_preset(preset)
	assert_array(report["missing"]).contains([knob["label"]])
	assert_bool(LookKnobs.same_value(_look.read(knob), authored)).override_failure_message(
		"a knob the preset predates must land on the authored value, not on the last look").is_true()
	await await_idle_frame()


func test_a_preset_naming_a_dead_knob_is_skipped_and_reported() -> void:
	var preset := _look.capture_preset("stale")
	preset.values["Sun|a_property_that_no_longer_exists"] = 1.0
	var report := _look.apply_preset(preset)
	assert_array(report["unknown"]).contains(["Sun|a_property_that_no_longer_exists"])
	await await_idle_frame()


# Update writes the LOADED preset back over its own file and nothing else -- the 2026-08-11
# scenario rule, which exists because a mis-aimed Update destroyed missions/Prolog.
func test_update_refuses_a_preset_that_is_not_the_loaded_one() -> void:
	_look._preset_dropdown.add_item("Some Other Preset")
	_look._preset_dropdown.select(_look._preset_dropdown.item_count - 1)
	assert_str(_look.loaded_preset()).is_empty()
	assert_str(_look.update_block_reason()).is_not_empty()


# EVERY dropdown row is a file now that #253 part 2 gave the way back its own Default button, so
# nothing may fall back to index 0 -- that row is a write target Update and Delete would aim at.
# Part 1 shipped exactly that fallback and it was safe only because row 0 was the authored scene.
func test_the_dropdown_selects_nothing_when_no_preset_is_loaded() -> void:
	_look.refresh_preset_dropdown()
	assert_int(_look._preset_dropdown.selected).override_failure_message(
		"the dropdown fell back to a real preset file, which Update and Delete would then aim at"
	).is_equal(-1)
	assert_bool(_look._update_button.disabled).is_true()
	assert_bool(_look._delete_button.disabled).is_true()


# Default is the ONE way back (dev, 2026-08-15), replacing the "(authored scene)" row.
func test_default_loads_the_fallback_look_and_becomes_the_baseline() -> void:
	var knob := _knob("Sun", "light_energy")
	var default_look := LookKnobs.default_preset()
	assert_object(default_look).is_not_null()
	_look.write(knob, _nudged(knob, _look.read(knob)))
	_look._on_default_pressed()
	var expected: Variant = default_look.values[LookKnobs.preset_key(knob)]
	assert_bool(LookKnobs.same_value(_look.read(knob), expected)).is_true()
	# ...and Reset now holds there rather than snapping somewhere else.
	_look.write(knob, _nudged(knob, _look.read(knob)))
	_look._on_reset_pressed()
	assert_bool(LookKnobs.same_value(_look.read(knob), expected)).is_true()
	await await_idle_frame()
