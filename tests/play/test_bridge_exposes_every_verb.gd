# Every command PlaySession implements has a bridge arm that reaches it (#613).
#
# WHY THIS IS A LAW. PlaySession grew guard/overwatch/rally/reload/rev/burrow and _dispatch was
# never widened, so the bridge exposed 12 of 18 verbs -- silently, because nothing fails when a
# verb is merely unreachable. It surfaced when a driver playing Level_1 asked for `burrow`, a verb
# docs/play-api.md lists, and got `unknown cmd`. That is the whole failure mode: the session is
# correct, the doc is correct, and the one line joining them is missing.
#
# It is a SPELLING check over the bridge's source, for the same reason the preload law is: the
# bridge is a SceneTree script that owns the process and polls a file, so there is no seam to call
# _dispatch through from a suite. Reading the text is what is available, and it is enough -- what
# can rot is an arm going missing, and that is visible in the text.
extends GdUnitTestSuite

const BRIDGE := "res://play/play_bridge.gd"
const SESSION := "res://play/play_session.gd"

# Session methods that are NOT player commands, each with the reason it is not one. A method added
# here without a reason is the loophole this list would otherwise become.
const NOT_COMMANDS := {
	"preview": "dispatched, but named differently in the session (preview() is the query)",
	"execute": "dispatched",
	"end_turn": "dispatched as `endturn`",
	"legal_moves": "dispatched",
	"legal_targets": "dispatched",
	"status": "rides every frame rather than being asked for",
	"cancel": "dispatched",
	"join": "dispatched",
	"leave": "dispatched",
	"disband": "dispatched",
	"rescue": "dispatched",
	"queue_move": "dispatched as `move`",
	"queue_attack": "dispatched as `attack`",
	"objectives": "read by the view, not ordered",
	"zones": "read by the view, not ordered",
	"round_limit": "read by the view, not ordered",
	"lose_conditions": "read by the view, not ordered",
	"mission_outcome": "read by the view, not ordered",
	"mission_tag": "read by the view, not ordered",
	"terrain_at": "read by the view, not ordered",
	"live_units": "read by the view, not ordered",
	"handle_for": "read by the view, not ordered",
	"unit_by_handle": "read by the view, not ordered",
	"active_faction": "read by the view, not ordered",
}


func _source(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	assert_str(text).override_failure_message("could not read %s" % path).is_not_empty()
	return text


# The verbs a player can order: public session methods returning a result Dictionary, minus the
# declared non-commands above.
func _session_verbs() -> PackedStringArray:
	var out: PackedStringArray = []
	var rx := RegEx.create_from_string("(?m)^func ([a-z][a-z_]*)\\(")
	for m: RegExMatch in rx.search_all(_source(SESSION)):
		var name := m.get_string(1)
		if name.begins_with("_") or NOT_COMMANDS.has(name):
			continue
		out.append(name)
	return out


func test_every_session_verb_has_a_bridge_arm() -> void:
	var bridge := _source(BRIDGE)
	var missing: Array[String] = []
	for verb: String in _session_verbs():
		if not bridge.contains('"%s"' % verb):
			missing.append(verb)
	assert_array(missing).override_failure_message(
		("PlaySession implements these and the bridge cannot reach them, so a caller asking for "
		+ "one gets `unknown cmd` for a verb the docs list: %s\n"
		+ "Add a _dispatch arm, or -- if it genuinely is not a player command -- add it to "
		+ "NOT_COMMANDS with the reason.") % ", ".join(missing)).is_empty()


func test_the_six_that_were_missing_are_reachable() -> void:
	# Named explicitly rather than left to the law above, because these are the ones a real run hit
	# and a regression here should say so by name.
	var bridge := _source(BRIDGE)
	var gone: Array[String] = []
	for verb: String in ["guard", "overwatch", "rally", "reload", "rev", "burrow"]:
		if not bridge.contains('"%s"' % verb):
			gone.append(verb)
	assert_array(gone).override_failure_message(
		"verbs that #613 wired are unreachable again: %s" % ", ".join(gone)).is_empty()


func test_the_scan_actually_found_verbs() -> void:
	# Non-vacuity: let the regex rot, or NOT_COMMANDS swallow everything, and the law above passes
	# over an empty list.
	assert_int(_session_verbs().size()).override_failure_message(
		"the verb scan matched nothing -- the regex or NOT_COMMANDS has rotted").is_greater(5)
	# ...and NOT_COMMANDS must describe methods that EXIST; a stale entry is an exemption guarding
	# nothing, and worse, one that could hide a verb added later under the same name.
	var session := _source(SESSION)
	var stale: Array[String] = []
	for name: String in NOT_COMMANDS:
		if not session.contains("func %s(" % name):
			stale.append(name)
	assert_array(stale).override_failure_message(
		"declared in NOT_COMMANDS but no longer a session method: %s" % ", ".join(stale)).is_empty()
