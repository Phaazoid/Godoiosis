# An input binding's `device` is not decoration -- it GATES matching. A binding at device 5 fires
# only for events arriving from device 5; -1 (DEVICE_ID_EMULATION) is the wildcard that matches
# every device. So a wrong device id is a dead key, not a cosmetic difference.
#
# Godot 4.6 and earlier had no dedicated ids for the keyboard and the mouse: `InputEventKey.new()`
# defaulted to device 0, and that 0 is what the editor wrote. 4.7 introduced DEVICE_ID_KEYBOARD
# (16) and DEVICE_ID_MOUSE (32) -- they sit just above the joypad range, which is 0..15 -- and
# ships a COMPAT MIGRATION that rewrites a legacy 0 on load: key 0 -> 16, mouse 0 -> 32, while a
# joypad's 0 stays 0, that being a real device. This project carried six 4.6-era zeroes across the
# 4.7.1 upgrade (F1, F2, and the four arrow-key camera alternates).
#
# Nothing was observably broken -- the migration runs on the exported `project.binary` path as well
# as the text one, so the game played correctly -- but the committed bytes were not what the writer
# emits, so every `ProjectSettings.save()` re-dirtied the file with ~12 lines of churn unrelated to
# whatever was actually being changed. That is the acceptance half of the dirty-tree rule, and it
# also left the bindings depending on a compat shim a later engine is free to drop.
#
# THE COMMITTED FILE, via ConfigFile -- deliberately NOT InputMap or ProjectSettings. Measured, not
# assumed: the migration is DOWNSTREAM of parsing, so a live read is circular. Against the
# unfixed file, `ProjectSettings.get_setting("input/toggle_dev_overlay")` reported device 16 while
# the bytes on disk said 0. ConfigFile is the only reader that answers the question this suite
# asks, since a stale device id is a thing that gets COMMITTED rather than anything the runtime
# ever sees.
#
# A failure here is fixed by ROUND-TRIPPING the file through its own writer -- a headless
# `ProjectSettings.save()` over the project -- never by hand-editing a device number, and never by
# editing this suite.
extends GdUnitTestSuite

const PROJECT_FILE := "res://project.godot"

# The legacy id, and what 4.7's loader migrates it to per event class. An event class absent from
# this table has no dedicated id and its device 0 is a genuine device (joypad 0), not a leftover.
const LEGACY_DEVICE := 0
const MIGRATED_TO := {
	"InputEventKey": InputEvent.DEVICE_ID_KEYBOARD,
	"InputEventMouseButton": InputEvent.DEVICE_ID_MOUSE,
}


# action -> the Array of InputEvent objects as the COMMITTED FILE spells them.
func _committed_actions() -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(PROJECT_FILE)
	assert_int(err) \
		.override_failure_message("could not read %s -- this suite cannot check anything" % PROJECT_FILE) \
		.is_equal(OK)
	var out := {}
	if not config.has_section("input"):
		return out
	for action: String in config.get_section_keys("input"):
		var stored: Variant = config.get_value("input", action, {})
		if stored is Dictionary and (stored as Dictionary).has("events"):
			out[action] = (stored as Dictionary)["events"]
	return out


func test_no_committed_binding_carries_a_legacy_device_id() -> void:
	var checked := 0
	for action: String in _committed_actions():
		for event: Variant in _committed_actions()[action]:
			var class_key: String = (event as Object).get_class()
			if not MIGRATED_TO.has(class_key):
				continue   # a joypad's device 0 is joypad 0, not a leftover
			checked += 1
			assert_int((event as InputEvent).device) \
				.override_failure_message(
					"input/%s: a committed %s carries device %d -- that is the pre-4.7 default, which the engine silently migrates to %d at every load. Re-round-trip project.godot through a headless ProjectSettings.save() rather than editing the number by hand."
					% [action, class_key, LEGACY_DEVICE, MIGRATED_TO[class_key]]) \
				.is_not_equal(LEGACY_DEVICE)
	assert_int(checked) \
		.override_failure_message("no keyboard or mouse binding was read out of %s at all -- this case would pass vacuously" % PROJECT_FILE) \
		.is_greater(0)


# The general property the case above is one instance of, and the one that survives the NEXT
# engine upgrade: whatever the file says must be what the engine actually runs. Any future
# migration reds here and names itself, instead of waiting to be noticed as save churn.
func test_every_committed_device_is_what_the_engine_actually_loads() -> void:
	var checked := 0
	for action: String in _committed_actions():
		var committed: Array = _committed_actions()[action]
		var live: Variant = ProjectSettings.get_setting("input/" + action)
		assert_bool(live is Dictionary) \
			.override_failure_message("input/%s is in project.godot but ProjectSettings has no such action" % action) \
			.is_true()
		var loaded: Array = (live as Dictionary)["events"]
		assert_int(loaded.size()) \
			.override_failure_message("input/%s: the file spells %d events, the engine loaded %d" % [action, committed.size(), loaded.size()]) \
			.is_equal(committed.size())
		for i: int in committed.size():
			checked += 1
			assert_int((loaded[i] as InputEvent).device) \
				.override_failure_message(
					"input/%s event %d: the file says device %d, the engine runs it as %d. The committed bytes are not what the writer emits -- re-round-trip project.godot through a headless ProjectSettings.save()."
					% [action, i, (committed[i] as InputEvent).device, (loaded[i] as InputEvent).device]) \
				.is_equal((committed[i] as InputEvent).device)
	assert_int(checked) \
		.override_failure_message("no committed event was compared against the engine at all -- this case would pass vacuously")\
		.is_greater(0)
