# A Play API `load` the bridge refuses leaves the board it was asked over standing (#1603). It used to
# tear the board down first and read second, so a mistyped path wiped the game and still answered
# ok=1 "Loaded ... (0 units)". Drives the REAL bridge in a child process (tests/support/
# bridge_process.gd), and builds its own boards in the run dir: no authored content is named.
extends GdUnitTestSuite

const BridgeProcess := preload("res://tests/support/bridge_process.gd")

var _bridge: BridgeProcess
var _id := 0


func before() -> void:
	_bridge = BridgeProcess.new("user://test_play_bridge_load")
	await _bridge.open()
	# Written after open(), which clears the run dir; close() takes them with it.
	ResourceSaver.save(Resource.new(), _file("not_a_board.tres"))
	ResourceSaver.save(ScenarioData.new(), _file("blank_board.tres"))


func after() -> void:
	await _bridge.close()


func before_test() -> void:
	var made := await _ask('"cmd":"new"')
	assert_bool(made.ok).override_failure_message("new failed:\n%s" % made.text).is_true()


func _file(name: String) -> String:
	return _bridge.run_dir.path_join(name)


func _ask(body: String) -> Dictionary:
	_id += 1
	return await _bridge.send(_id, '{"id":%d,%s}' % [_id, body])


func _load(path: String) -> Dictionary:
	return await _ask('"cmd":"load","args":{"path":%s}' % JSON.stringify(path))


# The board as `overview` draws it, without the frame's own header (its id differs every time).
func _board() -> String:
	var r := await _ask('"cmd":"overview"')
	assert_bool(r.ok).override_failure_message("overview failed:\n%s" % r.text).is_true()
	var text: String = r.text
	return text.substr(text.find("\n") + 1)


func _expect_refused_and_standing(path: String, says: String) -> void:
	var before_load := await _board()
	var r := await _load(path)
	assert_bool(r.answered).override_failure_message("the load was never answered: %s" % r.text).is_true()
	assert_bool(r.ok).override_failure_message("a load of %s answered ok=1:\n%s" % [path, r.text]).is_false()
	assert_str(r.text).override_failure_message("the refusal should say '%s':\n%s" % [says, r.text]).contains(says)
	assert_str(await _board()).override_failure_message(
		"the refused load of '%s' changed the board -- it was torn down before the file was read" % path) \
		.is_equal(before_load)


func test_a_missing_path_is_refused_and_the_board_stands() -> void:
	await _expect_refused_and_standing(_file("__no_such_board__.tres"), "no file at")


func test_a_file_that_is_not_a_scenario_is_refused_and_the_board_stands() -> void:
	await _expect_refused_and_standing(_file("not_a_board.tres"), "is a Resource, not a scenario")


func test_an_empty_path_is_refused_and_the_board_stands() -> void:
	await _expect_refused_and_standing("", "load needs a path")


# Non-vacuity for the three above: the same door still loads, and a load that does replaces the board.
func test_a_good_load_still_replaces_the_board() -> void:
	var before_load := await _board()
	var r := await _load(_file("blank_board.tres"))
	assert_bool(r.ok).override_failure_message("a good load answered ok=0:\n%s" % r.text).is_true()
	assert_str(r.text).contains("Loaded %s" % _file("blank_board.tres"))
	assert_str(await _board()).override_failure_message("the good load left the old board standing") \
		.is_not_equal(before_load)
