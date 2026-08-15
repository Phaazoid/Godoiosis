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


func before_test() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false   # no board needed: every knob is a scene property
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var dev_overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	_look = dev_overlay.look_tool


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


# --- Helpers ---------------------------------------------------------------------------

func _knob(node: String, prop: String) -> Dictionary:
	for knob: Dictionary in LookTool.KNOBS:
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
	for knob: Dictionary in LookTool.KNOBS:
		if typeof(_look.read(knob)) == TYPE_NIL:
			unresolved.append("%s:%s" % [knob["node"], knob["prop"]])
	assert_array(unresolved).override_failure_message(
		"Knobs pointing at nothing: %s" % ", ".join(unresolved)).is_empty()


func test_a_written_knob_survives_the_next_frame() -> void:
	var wanted: Array = []
	var inert: Array[String] = []
	for knob: Dictionary in LookTool.KNOBS:
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


func _row_for(label_text: String) -> HBoxContainer:
	for row in _look._rows.get_children():
		var box := row as HBoxContainer
		if box == null:
			continue
		var label := box.get_child(0) as Label
		if label != null and label.text == label_text:
			return box
	return null


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
	assert_str(entries["flame_size"]).starts_with("Vector2(")


func test_reset_puts_every_knob_back_to_its_authored_value() -> void:
	for knob: Dictionary in LookTool.KNOBS:
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
	assert_object(orphan.read(LookTool.KNOBS[0])).is_null()
	assert_dict(orphan.changed_values()).is_empty()
	orphan.queue_free()
	await await_idle_frame()
