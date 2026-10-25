# A resolve pass writes no LIVE body (#1480, resolution-pipeline R2): it writes its own copy
# (PlanResolver._hypo_for(unit, hypo).state), and execution is the only writer of a live one. This law
# walks every kind of real pass on every saved board and fingerprints every live body around each,
# by the same tables the copy law classifies a body with (tests/support/unit_state_fields.gd), so a
# field added to a body is watched here as soon as it is classified there.
#
# The walk is tests/support/every_pass.gd's, shared with the no-live-read law.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const Walk := preload("res://tests/support/every_pass.gd")
const Fields := preload("res://tests/support/unit_state_fields.gd")

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


func _fingerprints() -> Dictionary:
	var out := {}
	for child in game.units_root.get_children():
		var unit := child as Unit
		if unit != null and is_instance_valid(unit):
			out[unit] = Fields.fingerprint(unit.state)
	return out


func test_no_pass_writes_a_live_body() -> void:
	var writes: Array[String] = []
	var ran: Dictionary = await Walk.walk(game, func(board: String, kind: String, run: Callable) -> void:
		var before := _fingerprints()
		run.call()
		var after := _fingerprints()
		for unit: Unit in before:
			var changed := Fields.diff(before[unit], after.get(unit, {}))
			if not changed.is_empty():
				writes.append("%s, %s: %s's %s" % [board, kind, unit.get_unit_name(), ", ".join(changed)]))

	for kind: String in Walk.KINDS:
		assert_int(ran[kind]).override_failure_message(
				"no %s ran on any saved board, so this law checked none" % kind).is_greater(0)
	assert_array(writes).override_failure_message(
			"a pass wrote a live body:\n  %s" % "\n  ".join(writes)).is_empty()
