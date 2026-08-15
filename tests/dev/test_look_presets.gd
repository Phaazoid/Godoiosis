# The SHIPPED starter presets (#253 part 3) -- a content law, not a mechanism test. The mechanism
# is pinned next door in test_look_tool.gd; what these guard is that the twelve .tres files on disk
# are structurally complete and still round-trip through the real apply path.
#
# EVERY case here is a "for each preset" loop, so an empty scan would make all of them vacuously
# green -- the #264 blind shape, where the discriminating power lives in the fixture's data rather
# than in the assertion. `_names()` asserts non-empty before returning, which is what closes it.
#
# Deliberately NOT asserted: how many presets there are, or that any particular one exists. The dev
# was told to rename, retune and delete these freely; a case naming "Opus 3 Citrinitas" would turn
# his own tidying red. Non-empty is the real invariant.
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

# The precondition every case below leans on. A scan that returned nothing would otherwise make
# each loop pass by never running.
func _names() -> Array[String]:
	var names := LookTool.saved_presets()
	assert_array(names).override_failure_message(
		"no presets found under %s -- every case in this file would pass vacuously" % LookTool.PRESET_DIR
	).is_not_empty()
	return names


func _in_scope_keys() -> Array[String]:
	var keys: Array[String] = []
	for knob: Dictionary in LookTool.preset_knobs():
		keys.append(LookTool.preset_key(knob))
	return keys


# --- The laws ---------------------------------------------------------------------------

func test_every_shipped_preset_loads_and_owns_its_filename() -> void:
	for name: String in _names():
		var preset := load(LookTool.preset_path(name)) as LookPreset
		assert_object(preset).override_failure_message(
			"%s did not load as a LookPreset" % name).is_not_null()
		# The dropdown shows the FILENAME and Update writes back to it, so a preset_name that has
		# drifted from its file is a preset that reports itself as something it is not.
		assert_str(preset.preset_name).override_failure_message(
			"%s.tres calls itself '%s'" % [name, preset.preset_name]).is_equal(name)


# The back-add guard. When a knob is added to KNOBS, this is what says WHICH shipped presets are
# now stale -- rather than finding out by loading one in play and seeing a value snap to authored.
func test_every_shipped_preset_names_every_in_scope_knob() -> void:
	var expected := _in_scope_keys()
	for name: String in _names():
		var preset := load(LookTool.preset_path(name)) as LookPreset
		var missing: Array[String] = []
		for key: String in expected:
			if not preset.values.has(key):
				missing.append(key)
		assert_array(missing).override_failure_message(
			"preset '%s' predates %d knob(s): %s -- load it, set them, press Update"
				% [name, missing.size(), ", ".join(missing)]).is_empty()


# The other direction, and the one that would catch a game setting leaking into shipped content --
# which is exactly what #264's block_height_scale did before it was ruled out.
func test_no_shipped_preset_carries_an_out_of_scope_value() -> void:
	var expected := _in_scope_keys()
	for name: String in _names():
		var preset := load(LookTool.preset_path(name)) as LookPreset
		for key: String in preset.values:
			assert_bool(expected.has(key)).override_failure_message(
				"preset '%s' carries '%s', which a preset does not cover" % [name, key]).is_true()


# The wire-level version of the two above: not "does the dictionary look right" but "does the real
# apply path have nothing to complain about", against the real scene the dev actually loads onto.
func test_every_shipped_preset_applies_cleanly_to_the_real_scene() -> void:
	for name: String in _names():
		var preset := load(LookTool.preset_path(name)) as LookPreset
		var report := _look.apply_preset(preset)
		assert_array(report["missing"]).override_failure_message(
			"applying '%s' left knobs at the authored value: %s" % [name, report["missing"]]).is_empty()
		assert_array(report["unknown"]).override_failure_message(
			"applying '%s' skipped dead keys: %s" % [name, report["unknown"]]).is_empty()
	_look._load_authored()
	# apply_preset rebuilds every row; a detached-then-queue_free'd node reads as a gdUnit orphan
	# until a frame processes the queue (#215's lesson).
	await await_idle_frame()
