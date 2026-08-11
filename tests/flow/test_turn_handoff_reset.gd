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
