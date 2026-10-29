# A resolve pass reads no LIVE tile (#1498 stage 4), the tile twin of test_a_pass_reads_no_live_body.gd.
# Inside SquadManager._resolve_actions the board wears the plan's own tiles (ResolvedPlan.lend_tiles), so
# every tile-state and gas read goes through PlannedTiles, which reads the stores past their seal. A store
# read that skips it counts on PlannedTiles.seal_breaks, as does a judge's board (candidate_board) built
# inside a pass or handed to one. This law walks every kind of real pass on every saved board and refuses
# a break.
#
# The grid and heights are not sealed (a pass changes neither); the write law watches them.
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


func test_no_pass_reads_a_live_tile() -> void:
	var breaks: Array[String] = []
	var ran: Dictionary = await Walk.walk(game, func(board: String, kind: String, run: Callable) -> void:
		var before := PlannedTiles.seal_breaks
		run.call()
		if PlannedTiles.seal_breaks != before:
			breaks.append("%s, %s: %d live read(s)" % [board, kind, PlannedTiles.seal_breaks - before]))

	for kind: String in Walk.KINDS:
		assert_int(ran[kind]).override_failure_message(
				"no %s ran on any saved board, so this law checked none" % kind).is_greater(0)
	assert_array(breaks).override_failure_message(
			"a pass read the live tiles past its planned tiles (the log names each reader):\n  %s"
			% "\n  ".join(breaks)).is_empty()
