# The headless twin of tests/flow/test_battle_begins_wet.gd (#1653): a Play API `load` that starts the
# battle soaks whoever stands in open water, and a `load` with `resume` does not -- a resume replays the
# state it saved. Drives the REAL bridge in a child process (tests/support/bridge_process.gd), on a
# board this suite authors into the run dir: no authored content is named.
extends GdUnitTestSuite

const BridgeProcess := preload("res://tests/support/bridge_process.gd")
const BoardBuilder := preload("res://play/board_builder.gd")

const SHALLOW_WATER := Vector2i(6, 6)   # TestTiles' wadeable water (#116)
const WET_CELL := Vector2i(1, 0)

var _bridge: BridgeProcess
var _id := 0


func before() -> void:
	_bridge = BridgeProcess.new("user://test_play_bridge_battle_begins_wet")
	await _bridge.open()
	# Written after open(), which clears the run dir; close() takes it with it.
	assert_int(ResourceSaver.save(_scenario(), _path())).is_equal(OK)


func after() -> void:
	await _bridge.close()


func _path() -> String:
	return _bridge.run_dir.path_join("wade_board.tres")


# A grass field with one shallow cell, a player standing in it, a player on grass, a foe far off.
func _scenario() -> ScenarioData:
	var src: Dictionary = BoardBuilder.build(self, "WadeSrc")
	auto_free(src.root)
	BoardBuilder.paint_rect(src.grid, Rect2i(-2, -2, 14, 8))
	BoardBuilder.paint_cell(src.grid, WET_CELL, SHALLOW_WATER)
	var scenario := ScenarioData.new()
	scenario.tile_data = src.grid.tile_map_data
	_place(scenario, "Wader", Team.Faction.PLAYER, WET_CELL)
	_place(scenario, "Dry", Team.Faction.PLAYER, Vector2i(3, 0))
	_place(scenario, "Foe", Team.Faction.ENEMY, Vector2i(10, 0))
	return scenario


func _place(scenario: ScenarioData, name: String, fac: Team.Faction, cell: Vector2i) -> void:
	var entry := ScenarioUnitEntry.new()
	entry.unit_data = UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, fac)
	entry.cell = cell
	scenario.unit_entries.append(entry)


func _ask(body: String) -> Dictionary:
	_id += 1
	return await _bridge.send(_id, '{"id":%d,%s}' % [_id, body])


func _load(resume: bool) -> Dictionary:
	var r := await _ask('"cmd":"load","args":{"path":%s,"resume":%s}' % [JSON.stringify(_path()),
			"true" if resume else "false"])
	assert_bool(r.ok).override_failure_message("the load failed:\n%s" % r.text).is_true()
	return r


func _overview() -> String:
	var r := await _ask('"cmd":"overview"')
	assert_bool(r.ok).override_failure_message("overview failed:\n%s" % r.text).is_true()
	return r.text


func test_a_fresh_load_soaks_the_stander_and_only_the_stander() -> void:
	var r := await _load(false)
	assert_str(r.text).override_failure_message(
			"a fresh load did not report the water's soak:\n%s" % r.text).contains("standing in water, Wet: ")
	var clause: String = r.text.get_slice("standing in water, Wet: ", 1).get_slice("\n", 0)
	assert_int(clause.split(", ").size()).override_failure_message(
			"one unit stands in the water, but the soak named: %s" % clause).is_equal(1)
	assert_str(await _overview()).override_failure_message("the soak was reported and not landed") \
			.contains(Elemental.state_display_name(Elemental.State.WET))


func test_a_resume_soaks_nobody() -> void:
	var r := await _load(true)
	assert_str(r.text).override_failure_message(
			"a resume started the battle again and soaked the stander:\n%s" % r.text) \
			.not_contains("standing in water")
	assert_str(await _overview()).override_failure_message("a resume left somebody Wet") \
			.not_contains(Elemental.state_display_name(Elemental.State.WET))
