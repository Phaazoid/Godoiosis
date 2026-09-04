# Ownership of the faction action reset (#144): a turn HANDOFF resets has_acted, a menu
# arrival trusts the file. The reset lived inside start_faction_turn until #144, where the
# menu paths (MissionController._begin_turn) ran it too — so resuming a mid-battle save
# handed already-acted squads their actions back, destroying the has_acted #87 had just
# restored. Nobody saw it because the dev-overlay Load skips _begin_turn entirely.
#
# Real game scene (the #114 fixture — root MUST be named "Main"); boards built cell by cell.
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


func _spawn_acted_player_squad() -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 1))
	assert_object(unit).is_not_null()
	var manager: SquadManager = game.squad_manager
	manager.set_has_acted(unit.squad, true)
	var tm: TurnManager = game.turn_manager
	tm.set_active_faction(Team.Faction.PLAYER)
	return unit


func test_a_menu_arrival_preserves_has_acted() -> void:
	# The resume path: MissionController._begin_turn starts the restored faction's turn
	# WITHOUT resetting its actions — the file said the squad already acted.
	var unit := _spawn_acted_player_squad()

	var mc: MissionController = game.mission_controller
	mc._begin_turn()
	await await_idle_frame()

	assert_bool(unit.squad.has_acted) \
		.override_failure_message("_begin_turn reset has_acted — a resumed save just handed an acted squad its turn back") \
		.is_true()


func test_a_turn_handoff_still_resets_actions() -> void:
	# The companion pin: cycling back to a faction through the real handoff
	# (TurnManager.end_turn -> turn_started -> game._on_turn_started) must still reset.
	var unit := _spawn_acted_player_squad()

	var board: BoardContext = game._board()
	var tm: TurnManager = game.turn_manager
	tm.end_turn(board.present_factions())   # only PLAYER is present, so the cycle returns to it
	await await_idle_frame()

	assert_bool(unit.squad.has_acted) \
		.override_failure_message("the turn handoff no longer resets has_acted — squads would stay spent forever") \
		.is_false()


const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)


# THE HAND-OFF SHEDS WHAT NOBODY EXECUTED (#709, dev ruling 2026-09-03). An order the player queued
# and did not run used to survive the whole enemy turn -- and it could never happen, because the
# reset at the player's OWN next turn discarded it unexecuted. While it stood, the two layers that
# ask where a unit is disagreed: PlanResolver seeds every unit from get_projected_destination() and
# so placed it at the queued destination, while queue_action's whiff gate positions a foreign unit
# at the cell it stands on. Two answers, during the one turn when something else is aiming at it.
#
# Asserted through the REAL hand-off (TurnManager.end_turn -> turn_started -> _on_turn_started ->
# reset_faction_actions), which is the one step both this walk and play_session's share.
func test_a_handoff_sheds_orders_the_outgoing_faction_never_executed() -> void:
	for x in range(6):
		for y in range(3):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 1))
	assert_object(unit).is_not_null()
	assert_object(game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(5, 1))).is_not_null()
	game.turn_manager.set_active_faction(Team.Faction.PLAYER)
	await await_idle_frame()

	var move := MoveAction.new()
	var path: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1)]
	move.init(unit, path, null)
	assert_bool(game.squad_manager.queue_action(unit.squad, move)) \
		.override_failure_message("fixture failed to queue the move").is_true()
	assert_vector(unit.get_projected_destination()) \
		.override_failure_message("fixture never got the projection it exists to measure") \
		.is_equal(Vector2i(2, 1))

	game.turn_manager.end_turn(game._board().present_factions())
	await await_idle_frame()

	assert_int(unit.squad.action_queue.size()) \
		.override_failure_message("the player's un-executed order survived the hand-off into the enemy turn") \
		.is_equal(0)
	assert_vector(unit.get_projected_destination()) \
		.override_failure_message("the enemy turn still reads the player on a cell no order can now reach") \
		.is_equal(Vector2i(1, 1))
