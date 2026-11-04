# The Play API bridge ANSWERS a malformed command and keeps serving (#1602). One command with
# "args": null used to end its poll loop (a typed call, play_bridge.gd:91), and every later command
# timed out until somebody restarted the bridge -- which an unattended agent run cannot do. A null id
# ended it the same way, a null slot made it re-run the command every frame unanswered, and a null
# coordinate was read as the cell (0, 0).
# Drives the REAL bridge in a child process (tests/support/bridge_process.gd): the bug lived in the
# poll loop's own calls, which nothing in-process reaches.
extends GdUnitTestSuite

const BridgeProcess := preload("res://tests/support/bridge_process.gd")

var _bridge: BridgeProcess
var _id := 0


func before() -> void:
	_bridge = BridgeProcess.new("user://test_play_bridge_malformed")
	await _bridge.open()


func after() -> void:
	await _bridge.close()


func before_test() -> void:
	_expect_ok(await _ask('"cmd":"new"'), "new")


# One command, numbered here: `body` is the JSON object's members after the id.
func _ask(body: String) -> Dictionary:
	_id += 1
	return await _bridge.send(_id, '{"id":%d,%s}' % [_id, body])


func _expect_answered(r: Dictionary, what: String) -> void:
	assert_bool(r.answered).override_failure_message("%s was never answered: %s" % [what, r.text]).is_true()


func _expect_ok(r: Dictionary, what: String) -> void:
	_expect_answered(r, what)
	assert_bool(r.ok).override_failure_message("%s answered ok=0:\n%s" % [what, r.text]).is_true()


func _expect_refused(r: Dictionary, what: String, says: String) -> void:
	_expect_answered(r, what)
	assert_bool(r.ok).override_failure_message("%s answered ok=1:\n%s" % [what, r.text]).is_false()
	assert_str(r.text).override_failure_message("%s's refusal should say '%s':\n%s" % [what, says, r.text]) \
		.contains(says)


func test_args_that_are_not_an_object_are_answered_and_the_bridge_keeps_serving() -> void:
	for bad: String in ["null", "\"overview\"", "[1]"]:
		_expect_refused(await _ask('"cmd":"overview","args":%s' % bad), "args %s" % bad, "must be a JSON object")
		_expect_ok(await _ask('"cmd":"overview"'), "the overview after args %s" % bad)


func test_a_batch_entry_with_null_args_is_answered_and_stops_the_batch() -> void:
	var r := await _ask('"cmds":[{"cmd":"overview"},{"cmd":"overview","args":null},{"cmd":"overview"}]')
	_expect_refused(r, "the batch", "must be a JSON object")
	assert_str(r.text).override_failure_message("the batch should stop at the bad entry:\n%s" % r.text) \
		.contains("batch stopped at [1]")
	_expect_ok(await _ask('"cmd":"overview"'), "the overview after the batch")


# A slot read inline was an engine error in _dispatch: re-run every frame, never answered.
func test_a_null_slot_is_refused_by_name() -> void:
	_expect_refused(await _ask('"cmd":"give","args":{"from":"A","slot":null,"to":"stash"}'), "give with slot null",
			"\"slot\" must be a number")
	_expect_ok(await _ask('"cmd":"overview"'), "the overview after the refused give")


# A coordinate read in _xy came back as the cell (0, 0) -- both halves, the good x too -- so a unit
# standing anywhere but (0, 0) took a real order there.
func test_a_null_coordinate_is_refused_not_read_as_the_origin() -> void:
	_expect_refused(await _ask('"cmd":"move","args":{"unit":"A","x":2,"y":null}'), "move with y null",
			"\"y\" must be a number")
	_expect_ok(await _ask('"cmd":"overview"'), "the overview after the refused move")


# The table is only as good as its coverage: every int()/bool() read of an argument in the bridge
# must name a key the check knows, or a new arm brings the engine error back. Read from the source,
# as test_bridge_exposes_every_verb reads it.
func test_every_argument_read_as_a_number_or_flag_is_checked() -> void:
	var source := FileAccess.get_file_as_string(BridgeProcess.BRIDGE)
	var constants: Dictionary = (load(BridgeProcess.BRIDGE) as GDScript).get_script_constant_map()
	var checked := {"int": constants.get("NUMBER_ARGS", []), "bool": constants.get("FLAG_ARGS", [])}
	var rx := RegEx.create_from_string("\\b(int|bool)\\(args\\.get\\(\"([a-z_]+)\"")
	var reads := 0
	var unchecked: Array[String] = []
	for m: RegExMatch in rx.search_all(source):
		reads += 1
		if not (checked[m.get_string(1)] as Array).has(m.get_string(2)):
			unchecked.append("%s(args.get(\"%s\"))" % [m.get_string(1), m.get_string(2)])
	assert_int(reads).override_failure_message("the scan found no int()/bool() reads -- the regex has rotted") \
		.is_greater(0)
	assert_array(unchecked).override_failure_message(
		("the bridge reads these without the argument check knowing them, so a null there is an engine "
		+ "error again: %s -- add each key to NUMBER_ARGS or FLAG_ARGS") % ", ".join(unchecked)).is_empty()


# No id, nothing to answer: the bridge skips it and must still be there for the next one. The idle
# gives its ~30 Hz poll time to read the bad command before the good one replaces it.
func test_a_command_with_no_usable_id_is_skipped_and_the_bridge_keeps_serving() -> void:
	for bad: String in ["null", "[1]"]:
		_bridge.write('{"id":%s,"cmd":"overview"}' % bad)
		await _bridge.idle(1000)
		_expect_ok(await _ask('"cmd":"overview"'), "the overview after an id of %s" % bad)
