# A resolve pass writes no LIVE tile (#1498, resolution-pipeline R2), the tile twin of
# test_a_pass_writes_no_live_body.gd: a pass lands its changes on its own PlannedTiles, and execution
# (ResolvedPlan.play_landing) is the only writer of a live store. This law walks every kind of real pass
# on every saved board and fingerprints the whole board around each.
#
# The fingerprint is ScenarioManager.capture_board(), the one answer to "what is the board" (grid, tile
# states with their clocks and authored starts, heights, gas, zones), diffed field by field so a store
# BoardSnapshot grows is watched here too; and each store's write count, so a write that lands back on
# the same value is still a write. This one watches the grid and heights, which the read seal cannot.
#
# The walk is tests/support/every_pass.gd's, shared with the other three pass laws.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const Walk := preload("res://tests/support/every_pass.gd")

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")


func after_test() -> void:
	game.scenario_manager.clear_board()
	get_tree().root.remove_child(_main)
	_main.free()


func _fingerprint() -> Dictionary:
	var out := {}
	var snapshot: BoardSnapshot = game.scenario_manager.capture_board()
	for property in snapshot.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[property.name] = snapshot.get(property.name)
	out["grid writes"] = game.grid.dirty.version
	out["height writes"] = game.board_heights.dirty.version
	out["tile state writes"] = game.terrain_states.dirty.version
	out["gas writes"] = game.gas_field.dirty.version
	out["zone edits"] = game._zone_edits
	return out


func test_no_pass_writes_a_live_tile() -> void:
	var writes: Array[String] = []
	var ran: Dictionary = await Walk.walk(game, func(board: String, kind: String, run: Callable) -> void:
		var before := _fingerprint()
		run.call()
		var after := _fingerprint()
		var changed: Array[String] = []
		for field: String in before:
			if before[field] != after.get(field):
				changed.append(field)
		if not changed.is_empty():
			writes.append("%s, %s: %s" % [board, kind, ", ".join(changed)]))

	for kind: String in Walk.KINDS:
		assert_int(ran[kind]).override_failure_message(
				"no %s ran on any saved board, so this law checked none" % kind).is_greater(0)
	assert_array(writes).override_failure_message(
			"a pass wrote the live board:\n  %s" % "\n  ".join(writes)).is_empty()
