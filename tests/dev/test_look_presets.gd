# The SHIPPED starter presets (#253 part 3) -- a content law, not a mechanism test. The mechanism
# is pinned next door in test_moods_tool.gd; what these guard is that the twelve .tres files on disk
# are structurally complete and still round-trip through the real apply path.
#
# EVERY case here is a "for each preset" loop, so an empty scan makes all of them vacuously green
# -- the #264 blind shape, where the discriminating power lives in the fixture's data rather than
# in the assertion. `_names()` used to close that by ASSERTING non-empty; since 2026-08-27 it
# warns instead, because deleting presets is authoring and an absence of authored content is not a
# failure (tests/README.md rule 9). The vacuity is real, and now audible rather than fatal.
#
# Deliberately NOT asserted: how many presets there are, or that any particular one exists. The dev
# was told to rename, retune and delete these freely; a case naming "Opus 3 Citrinitas" would turn
# his own tidying red -- and so, it turned out, would demanding that any preset exist at all.
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

# Every case below loops over this. An empty scan makes them all vacuous, which is said out loud
# rather than failed -- an absence of authored content is not a defect (tests/README.md rule 9).
func _names() -> Array[String]:
	var names := LookKnobs.saved_presets()
	if names.is_empty():   # content-absent: warn, never fail (tests/README.md rule 9)
		push_warning("no presets found under %s -- every case in this file is vacuous" % LookKnobs.PRESET_DIR)
	return names


func _in_scope_keys() -> Array[String]:
	var keys: Array[String] = []
	for knob: Dictionary in LookKnobs.preset_knobs():
		keys.append(LookKnobs.preset_key(knob))
	return keys


# --- The laws ---------------------------------------------------------------------------

func test_every_shipped_preset_loads_and_owns_its_filename() -> void:
	for name: String in _names():
		var preset := load(LookKnobs.preset_path(name)) as LookPreset
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
		var preset := load(LookKnobs.preset_path(name)) as LookPreset
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
		var preset := load(LookKnobs.preset_path(name)) as LookPreset
		for key: String in preset.values:
			assert_bool(expected.has(key)).override_failure_message(
				"preset '%s' carries '%s', which a preset does not cover" % [name, key]).is_true()


# The wire-level version of the two above: not "does the dictionary look right" but "does the real
# apply path have nothing to complain about", against the real scene the dev actually loads onto.
func test_every_shipped_preset_applies_cleanly_to_the_real_scene() -> void:
	for name: String in _names():
		var preset := load(LookKnobs.preset_path(name)) as LookPreset
		var report := _moods.apply_preset(preset)
		assert_array(report["missing"]).override_failure_message(
			"applying '%s' left knobs at the authored value: %s" % [name, report["missing"]]).is_empty()
		assert_array(report["unknown"]).override_failure_message(
			"applying '%s' skipped dead keys: %s" % [name, report["unknown"]]).is_empty()
	_moods._on_default_pressed()
	# apply_preset rebuilds every row; a detached-then-queue_free'd node reads as a gdUnit orphan
	# until a frame processes the queue (#215's lesson).
	await await_idle_frame()
