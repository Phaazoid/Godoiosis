# A board wears the look it names (#253 part 2).
#
# The case that matters here is the WIRE. ScenarioData carrying a name and LookKnobs applying a
# preset can both be perfect while nothing connects them -- that is #103's thirteen-month gap, a
# signal with no listener -- so the load cases drive the REAL path (apply_scenario -> board_loaded
# -> battle3d._apply_board_look) and assert on the live scene property, never on a return value.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const A_PRESET := "Night"        # any shipped preset; only that it DIFFERS from the default matters

var _scene: Node3D
var _game: Node2D


func before_test() -> void:
	var packed := SCENE
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_game = _scene.game


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


# --- Helpers ---------------------------------------------------------------------------

func _sun_energy_knob() -> Dictionary:
	for knob: Dictionary in LookKnobs.KNOBS:
		if knob["node"] == "Sun" and knob["prop"] == "light_energy":
			return knob
	return {}


# Load a board that names `preset_name`, through the real path.
func _load_board_naming(preset_name: String) -> void:
	var manager: ScenarioManager = _game.scenario_manager
	var scenario := manager.capture_scenario("look-test")
	scenario.look_preset = preset_name
	manager.apply_scenario(scenario)
	await await_idle_frame()


func _live_sun_energy() -> Variant:
	return LookKnobs.read(_scene, _sun_energy_knob())


func _expected_from(preset: LookPreset) -> Variant:
	return preset.values[LookKnobs.preset_key(_sun_energy_knob())]


# --- The board carries it ---------------------------------------------------------------

func test_a_boards_look_round_trips_through_capture_and_apply() -> void:
	var manager: ScenarioManager = _game.scenario_manager
	manager.current_look_preset = A_PRESET
	var scenario := manager.capture_scenario("look-test")
	assert_str(scenario.look_preset).is_equal(A_PRESET)

	manager.current_look_preset = "something else"
	manager.apply_scenario(scenario)
	assert_str(manager.current_look_preset).override_failure_message(
		"apply_scenario did not adopt the board's own look").is_equal(A_PRESET)
	await await_idle_frame()


# THE WIRE. Not "does apply() work" -- that is pinned next door -- but "does loading a board that
# names a preset actually change the world", asserted on the scene property itself.
func test_loading_a_board_that_names_a_preset_changes_the_live_scene() -> void:
	var preset := LookKnobs.resolve(A_PRESET)
	assert_object(preset).is_not_null()
	var expected: Variant = _expected_from(preset)
	# The preset has to DIFFER from where the scene starts, or this case cannot fail.
	assert_bool(LookKnobs.same_value(_live_sun_energy(), expected)).override_failure_message(
		"'%s' matches the scene already -- this case would pass without the wire" % A_PRESET).is_false()

	await _load_board_naming(A_PRESET)
	assert_bool(LookKnobs.same_value(_live_sun_energy(), expected)).override_failure_message(
		"the board loaded but its look never reached the scene").is_true()


func test_a_board_naming_nothing_wears_the_default() -> void:
	await _load_board_naming(A_PRESET)   # somewhere OTHER than the default first
	var default_look := LookKnobs.default_preset()
	assert_object(default_look).is_not_null()

	await _load_board_naming("")
	assert_bool(LookKnobs.same_value(_live_sun_energy(), _expected_from(default_look))).is_true()


# The dev's ruling: a mission pointing at a preset that has been deleted falls back to the default
# rather than rendering with whatever the scene happens to hold.
func test_a_board_naming_a_deleted_preset_falls_back_to_the_default() -> void:
	await _load_board_naming(A_PRESET)
	var default_look := LookKnobs.default_preset()

	await _load_board_naming("A Preset That Was Deleted")
	assert_bool(LookKnobs.same_value(_live_sun_energy(), _expected_from(default_look))
		).override_failure_message("a dead preset name left the board wearing the previous look").is_true()


# --- The fallback itself ----------------------------------------------------------------

# It is what EVERY board falls back to, so a partial default is a partial fallback -- the knobs it
# omits would silently keep whatever the last board left behind.
func test_the_default_look_exists_and_names_every_in_scope_knob() -> void:
	var default_look := LookKnobs.default_preset()
	assert_object(default_look).override_failure_message(
		"no default look at %s -- every board falls back to it" % LookKnobs.DEFAULT_PATH).is_not_null()
	var missing: Array[String] = []
	for knob: Dictionary in LookKnobs.preset_knobs():
		if not default_look.values.has(LookKnobs.preset_key(knob)):
			missing.append(knob["label"])
	assert_array(missing).override_failure_message(
		"the default look predates %d knob(s): %s" % [missing.size(), ", ".join(missing)]).is_empty()


# The other direction, and the one nothing was watching: test_look_presets.gd's out-of-scope law
# scans PRESET_DIR, which the default deliberately sits outside, so it carried eleven dead
# BoardMirror|flame_* keys from before #380 moved fire to the Game tab -- reported as "unknown" by
# every single apply and silently discarded. A dead key is also a SECOND authority for a value the
# declaration it was copied from still owns.
func test_the_default_look_carries_no_dead_key() -> void:
	var default_look := LookKnobs.default_preset()
	assert_object(default_look).is_not_null()
	var live: Array[String] = []
	for knob: Dictionary in LookKnobs.preset_knobs():
		live.append(LookKnobs.preset_key(knob))
	var dead: Array[String] = []
	for key: String in default_look.values:
		if not live.has(key):
			dead.append(key)
	assert_array(dead).override_failure_message(
		"the default look carries %d key(s) no knob claims: %s" % [dead.size(), ", ".join(dead)]).is_empty()


# It lives OUTSIDE Resources/LookPresets/ on purpose (dev, 2026-08-15): outside, it cannot appear
# in the load dropdown, Delete can never target it and Save As cannot shadow it -- all structural
# rather than a filename check anyone could get wrong later.
func test_the_default_is_not_a_listed_preset() -> void:
	assert_bool(LookKnobs.DEFAULT_PATH.begins_with(LookKnobs.PRESET_DIR)).override_failure_message(
		"the default sits inside the scanned folder, so it can be listed, deleted or shadowed").is_false()
