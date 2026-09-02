# Controls registry completeness (#690): the store and the real Input Map agree, in BOTH
# directions. A miss here is fixed by AUTHORING the entry or deleting the dead action, never by
# editing this suite -- the whole point is that a doc could not be checked against the bindings
# and this can.
#
# The reverse direction is the one that earns its keep. It is what found `dev_spawn_unit`: an
# action declared in project.godot and consumed by nothing, Space-spawn being a hardcoded
# KEY_SPACE check in game.gd. A markdown table cannot notice that; this reds.
#
# Presence only, never wording: what an entry SAYS is edited freely.
extends GdUnitTestSuite

# The naming convention the dev bindings follow -- `dev_*` plus `toggle_dev_overlay`. Matching on
# the substring rather than a listed set on purpose: a list here would be a second copy of the
# Input Map, which is the seam this registry exists to close. `cam_*`, `ui_*` and Dialogic's
# action are player-facing and belong to #691's contexts, so they are out of scope until it lands.
const DEV_ACTION_MARKER := "dev"


func test_every_entry_is_complete() -> void:
	for entry: Dictionary in Controls.ENTRIES:
		var key: String = entry["key"]
		assert_str(key).override_failure_message("A Controls entry has no key").is_not_empty()
		assert_str(entry["does"]) \
			.override_failure_message("Controls entry '%s' has no description" % key).is_not_empty()
		assert_bool(Controls.CONTEXT_NAMES.has(entry["context"])) \
			.override_failure_message("Controls entry '%s' names a context with no display name" % key) \
			.is_true()


func test_no_context_is_empty() -> void:
	for value: int in Controls.Context.values():
		var context: Controls.Context = value
		assert_int(Controls.in_context(context).size()) \
			.override_failure_message("Controls context %s has no entries -- its section would render blank"
				% Controls.Context.keys()[context]) \
			.is_greater(0)


func test_no_two_entries_claim_the_same_binding() -> void:
	var seen: Array[String] = []
	for entry: Dictionary in Controls.ENTRIES:
		var id: String = "%s|%s|%s" % [entry["context"], entry["key"], entry["when"]]
		assert_bool(seen.has(id)) \
			.override_failure_message("Two Controls entries claim '%s' under the same condition -- the store has two answers for one press"
				% entry["key"]) \
			.is_false()
		seen.append(id)


# --- The two directions against the live Input Map -------------------------------------------

func test_every_documented_action_exists() -> void:
	for action: String in Controls.documented_actions():
		assert_bool(InputMap.has_action(action)) \
			.override_failure_message("Controls documents Input Map action '%s', which does not exist -- it was renamed or deleted"
				% action) \
			.is_true()


func test_every_dev_action_is_documented() -> void:
	var documented: Array[String] = Controls.documented_actions()
	for action_name: StringName in InputMap.get_actions():
		var action: String = String(action_name)
		if not action.contains(DEV_ACTION_MARKER):
			continue
		assert_bool(documented.has(action)) \
			.override_failure_message("Input Map action '%s' is documented nowhere -- either give it a Controls entry or delete the action"
				% action) \
			.is_true()
