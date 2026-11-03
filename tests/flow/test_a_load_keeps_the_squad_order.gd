# A mid-battle load keeps the SQUAD ORDER (#1566). SquadManager.squads is creation order, and that is
# the order the AI acts in (AIController.actable_squads). A load creates the squads in leader SPAWN
# order, so a board whose squads had been re-formed in play (a join, a Leave) came back acting in a
# different order, and the battle played out differently after a save.
#
# The order is built through the real doors here: three spawns, a join, and the Leave verb, which
# makes the live order differ from the spawn order. The round trip is the game's own
# capture_scenario/apply_scenario, and the order is read off the AI's own acting list on the game host
# AND on the headless BoardBuilder load of the same data.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")

const ENEMY := Team.Faction.ENEMY
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const WIDTH := 6
const HEIGHT := 5

# Spawned in this order: a1, b1, a2.
const A1 := Vector2i(1, 1)
const B1 := Vector2i(1, 3)
const A2 := Vector2i(2, 1)

var _main: Node
var game: Node2D
var sm: ScenarioManager


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	sm = game.scenario_manager
	game.mission_controller._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()
	for x in range(WIDTH):
		for y in range(HEIGHT):
			game.grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# The order the enemy's squads act in, named by each leader's cell.
static func _acting_order(manager: SquadManager) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for squad: Squad in AIController.actable_squads(ENEMY, manager):
		cells.append(squad.get_leader().movement.cell)
	return cells


# The same captured board onto a fresh headless board, through the Play API's loader.
func _headless_load(scenario: ScenarioData) -> SquadManager:
	var board := BoardBuilder.build(self, "SquadOrderHeadless")
	auto_free(board.root)
	await BoardBuilder.apply_scenario(board, scenario)
	return board.squad_manager


# ==============================================================================

func test_the_squads_act_in_the_same_order_after_a_load() -> void:
	var a1: Unit = game.spawn_unit(H.make_unit_data({}, ENEMY), A1)
	var b1: Unit = game.spawn_unit(H.make_unit_data({}, ENEMY), B1)
	var a2: Unit = game.spawn_unit(H.make_unit_data({}, ENEMY), A2)
	game.squad_manager.join_squad(a2, a1.squad)
	game.squad_manager.leave_squad(a1)   # a2 now leads the first squad; a1 is a new squad, last
	var live := _acting_order(game.squad_manager)
	var expected: Array[Vector2i] = [A2, B1, A1]
	assert_array(live).override_failure_message(
		"precondition: the join and Leave did not make the order differ from spawn order").is_equal(expected)
	assert_object(b1.squad).is_not_same(a2.squad)

	var snapshot: ScenarioData = sm.capture_scenario("squad_order_full")
	sm.apply_scenario(snapshot)
	await await_idle_frame()

	assert_array(_acting_order(game.squad_manager)).override_failure_message(
		"the game's load rebuilt the squads in spawn order, so they act in a different order").is_equal(expected)

	var headless_manager := await _headless_load(snapshot)
	assert_array(_acting_order(headless_manager)).override_failure_message(
		"the headless load rebuilt the squads in spawn order, so they act in a different order").is_equal(expected)
