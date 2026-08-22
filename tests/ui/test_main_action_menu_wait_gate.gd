# Wait must only be offered to a squad that hasn't acted yet (#190). Wait and End Turn used to
# share one gate (active_squad == null), so an already-spent squad's menu still offered Wait --
# pressing it re-ran set_has_acted(true), a harmless no-op that told the player the squad could
# still do something. End Turn stays unconditional: it's about the faction's turn, not this
# squad's state.
#
# Real game scene (the #114 fixture -- root MUST be named "Main").
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn_player() -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 1))
	assert_object(unit).is_not_null()
	game.turn_manager.set_active_faction(Team.Faction.PLAYER)
	return unit


func test_wait_is_offered_before_the_squad_acts() -> void:
	var unit := _spawn_player()
	var options: Array = game.main_action_menu.populate(unit)
	assert_array(options).contains([MainActionMenu.WAIT])


func test_wait_is_withdrawn_once_the_squad_has_acted() -> void:
	var unit := _spawn_player()
	game.squad_manager.set_has_acted(unit.squad, true)

	var options: Array = game.main_action_menu.populate(unit)

	assert_bool(options.has(MainActionMenu.WAIT)) \
		.override_failure_message("Wait was still offered to a squad that already acted") \
		.is_false()
	# End Turn used to be asserted here as the unaffected neighbour. It left the ring entirely in
	# #467 -- ending the faction's turn is the corner button's job now, and never hiding is
	# tests/ui/test_end_turn_button.gd's rule. Inspect is the neighbour that stayed.
	assert_array(options).contains([MainActionMenu.INSPECT])
