# A resolve pass reads no LIVE body (#1480 stage 4). Inside SquadManager._resolve_actions every body
# read goes through PlanResolver's doors (state_of / _hypo_for), so a unit the pass has hit, maimed or
# stripped is read as the pass has left it, and a unit it has not touched is read live through the one
# declared door. Unit.state is sealed for the length of a pass: a read past the doors counts a break on
# Unit.seal_breaks and logs once, and this law walks every kind of real pass on every saved board and
# refuses a break.
#
# Driven through the real game scene, so the passes are the ones the game runs: an AI turn, a player's
# aim through the queue gate and its plan, and a hover's preview, from the weapon in hand and from
# another carried source.
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


func test_no_pass_reads_a_live_body() -> void:
	var breaks: Array[String] = []
	var ran: Dictionary = await Walk.walk(game, func(board: String, kind: String, run: Callable) -> void:
		var before := Unit.seal_breaks
		run.call()
		if Unit.seal_breaks != before:
			breaks.append("%s, %s: %d live read(s)" % [board, kind, Unit.seal_breaks - before]))

	for kind: String in Walk.KINDS:
		assert_int(ran[kind]).override_failure_message(
				"no %s ran on any saved board, so this law checked none" % kind).is_greater(0)
	assert_array(breaks).override_failure_message(
			"a pass read a live body past PlanResolver's doors (the log names each reader):\n  %s"
			% "\n  ".join(breaks)).is_empty()
