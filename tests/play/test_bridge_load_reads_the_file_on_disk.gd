# A Play API `load` reads the scenario file as it is on disk NOW (#1661). It used to serve Godot's
# cached copy of a path it had loaded before, so a board rewritten by another process came back as the
# old one, answered as an ordinary successful load. This suite IS that other process: it rewrites a
# board under the bridge's run dir between two loads by the REAL bridge (tests/support/bridge_process.gd).
# Its boards are built here; no authored content is named.
extends GdUnitTestSuite

const BridgeProcess := preload("res://tests/support/bridge_process.gd")

var _bridge: BridgeProcess
var _id := 0


func before() -> void:
	_bridge = BridgeProcess.new("user://test_play_bridge_fresh_load")
	await _bridge.open()


func after() -> void:
	await _bridge.close()


func _file(name: String) -> String:
	return _bridge.run_dir.path_join(name)


# Two boards a reply tells apart: the round limit (the mission block) and a locked weather (the head).
func _board(limit: int, weather: Weather.Kind) -> ScenarioData:
	var s := ScenarioData.new()
	s.round_limit = limit
	s.weather = weather
	return s


func _load(path: String) -> Dictionary:
	_id += 1
	var r := await _bridge.send(_id, '{"id":%d,"cmd":"load","args":{"path":%s}}' % [_id, JSON.stringify(path)])
	assert_bool(r.ok).override_failure_message("the load of %s answered ok=0:\n%s" % [path, r.text]).is_true()
	return r


# The reply without its frame header (the id differs every time) and with the path it names blanked,
# so the same board loaded from two paths reads the same.
func _shown(r: Dictionary, path: String) -> String:
	var text: String = r.text
	return text.substr(text.find("\n") + 1).replace(path, "<path>")


func test_a_rewritten_board_loads_as_it_is_on_disk() -> void:
	var rewritten := _file("rewritten.tres")
	var other := _file("other.tres")
	ResourceSaver.save(_board(3, Weather.Kind.CLEAR), rewritten)
	ResourceSaver.save(_board(7, Weather.Kind.FOG), other)

	var expected := _shown(await _load(other), other)
	var first := _shown(await _load(rewritten), rewritten)
	assert_str(expected).override_failure_message(
		"non-vacuity: the two boards read the same, so a stale load could not be told apart:\n%s" % expected) \
		.is_not_equal(first)

	# The other process's write, while the board from this path still STANDS: the session holding it is
	# what keeps the cached copy alive. A load of another path in between would free it and hide the bug.
	ResourceSaver.save(_board(7, Weather.Kind.FOG), rewritten)
	assert_str(_shown(await _load(rewritten), rewritten)).override_failure_message(
		"the bridge served the board it loaded before, not the file now at the path") \
		.is_equal(expected)

	# `restart` reloads through the same door, so it reads the file as it is now too (#1661's ruling A).
	ResourceSaver.save(_board(3, Weather.Kind.CLEAR), rewritten)
	_id += 1
	var r := await _bridge.send(_id, '{"id":%d,"cmd":"restart"}' % _id)
	assert_bool(r.ok).override_failure_message("restart answered ok=0:\n%s" % r.text).is_true()
	assert_str(_shown(r, rewritten).replace("Restarted\n", "")).override_failure_message(
		"restart served the board it loaded before, not the file now at the path:\n%s" % _shown(r, rewritten)) \
		.is_equal(first)
