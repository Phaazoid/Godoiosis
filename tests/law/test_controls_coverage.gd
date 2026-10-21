# Controls registry completeness (#690, widened by #691): the store and the real Input Map agree, in BOTH
# directions. A miss here is fixed by AUTHORING the entry or deleting the dead action, never by
# editing this suite -- the whole point is that a doc could not be checked against the bindings
# and this can.
#
# The reverse direction is the one that earns its keep. It is what found `dev_spawn_unit`: an
# action declared in project.godot and consumed by nothing, Space-spawn being a hardcoded
# KEY_SPACE check in game.gd. A markdown table cannot notice that; this reds.
#
# #691 filled the player contexts, which let that direction go from "every `dev`-named action" to
# "every action the project authored". The scope now lives in BUILTIN_PREFIX and nowhere else.
#
# Presence only, never wording: what an entry SAYS is edited freely.
extends GdUnitTestSuite

# Godot's own built-ins, which the project never authored and a controls page has no business
# listing. Everything else in the Input Map is the project's, and must be documented -- see
# test_every_project_action_is_documented for why that widened at #691.
const BUILTIN_PREFIX := "ui_"


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


# #1368: V was the enemy ranges (BOARD, "") AND the selector depth (DEV, "3D view"), so in the view
# the game boots into every press did both. The case above compares whole triples, which is why it
# never saw it -- the duplicate hid behind a different context and a different `when`.
#
# An AMBIENT `when` holds through ordinary play and claims nothing: "" everywhere, a view throughout
# that view. Two of them on one press both fire, unless they are two DIFFERENT views. Any other
# `when` is a MODE ("Spawn tool armed", "Aiming"), and a mode's handler taking the press from the
# ambient binding is code this registry cannot see -- a blind spot, declared rather than guessed at.
const AMBIENT_WHENS: Array[String] = ["", "3D view", "flat 2D view"]


func test_no_press_means_two_things_at_once() -> void:
	var by_press: Dictionary[String, Array] = {}
	for entry: Dictionary in Controls.ENTRIES:
		if not AMBIENT_WHENS.has(entry["when"]):
			continue
		var key: String = entry["key"]
		for press: String in key.split(" / "):
			var spelled := press.strip_edges().to_lower()
			if not by_press.has(spelled):
				by_press[spelled] = []
			by_press[spelled].append(entry)
	for press: String in by_press:
		var entries: Array = by_press[press]
		for i in entries.size():
			for j in range(i + 1, entries.size()):
				var a: Dictionary = entries[i]
				var b: Dictionary = entries[j]
				var together: bool = a["when"] == "" or b["when"] == "" or a["when"] == b["when"]
				assert_bool(together).override_failure_message(
					"'%s' is bound twice at once: '%s' (%s, when '%s') and '%s' (%s, when '%s') -- move one"
						% [press, a["does"], Controls.context_name(a["context"]), a["when"],
							b["does"], Controls.context_name(b["context"]), b["when"]]) \
					.is_false()


# --- The two directions against the live Input Map -------------------------------------------

func test_every_documented_action_exists() -> void:
	for action: String in Controls.documented_actions():
		assert_bool(InputMap.has_action(action)) \
			.override_failure_message("Controls documents Input Map action '%s', which does not exist -- it was renamed or deleted"
				% action) \
			.is_true()


# WIDENED AT #691, and the widening is the point. While only the dev context existed this could
# ask about `dev`-named actions alone, because `cam_*` and Dialogic's action were documented
# nowhere and the strong form would have failed. With the player contexts landed, every action the
# project authored has an entry -- so the law becomes "anything in the Input Map that is not a
# Godot built-in is documented". A new action now cannot ship undocumented at all, rather than
# only being caught if somebody happened to name it `dev_`.
#
# `ui_*` is SKIPPED rather than listed: those are Godot's, there are dozens, and a controls page
# naming `ui_graphics_toggle` is noise. An entry MAY still name one -- Escape names `ui_cancel` --
# and the forward case above checks it exists.
func test_every_project_action_is_documented() -> void:
	var documented: Array[String] = Controls.documented_actions()
	for action_name: StringName in InputMap.get_actions():
		var action: String = String(action_name)
		if action.begins_with(BUILTIN_PREFIX):
			continue
		assert_bool(documented.has(action)) \
			.override_failure_message("Input Map action '%s' is documented nowhere -- either give it a Controls entry or delete the action"
				% action) \
			.is_true()


# The player's page is filtered by PLAYER_CONTEXTS, so an authoring binding reaching it is a FILTER
# fault rather than a wording one. This is what makes that list worth declaring instead of writing
# "everything except DEV" at the page: a second dev-only context must not publish itself.
func test_no_dev_binding_is_reachable_from_the_player_contexts() -> void:
	var player_rows := 0
	for context: Controls.Context in Controls.PLAYER_CONTEXTS:
		assert_bool(context == Controls.Context.DEV) \
			.override_failure_message("Controls.PLAYER_CONTEXTS includes the DEV context -- the Settings page would list authoring keys") \
			.is_false()
		player_rows += Controls.in_context(context).size()
	assert_int(player_rows).override_failure_message(
		"No player-facing bindings at all -- the Settings Controls tab would render empty").is_greater(0)
