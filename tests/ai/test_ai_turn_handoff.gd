# #1220 ruling 7: an AI faction's first squad plans INSIDE the turn hand-off beat, so the costliest
# decision of the turn hides behind the banner -- and the faction claims the board BEFORE that beat,
# because orders queued on an unlocked board would be the player's to click.
#
# What a headless run can and cannot see: every beat lasts no time here (Pacing), so WHEN the plan
# lands relative to the banner is the dev's to see by playing. What it can see is the wire -- which
# squad the hand-off planned, that nobody is planned twice -- and that every order the turn queues
# finds the board already locked. Fixture is tests/ai/test_ai_turn_terminates.gd's game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true, move_cost=1 in TestTiles.tres

var _main: Node
var game: Node2D


func before_test() -> void:
	AIProfiles.use_fixtures({"": AIProfile.new()})   # #1230: this suite owns its AI profile
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	AIProfiles.clear_fixtures()
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 40}, faction), cell)
	assert_object(unit).is_not_null()
	unit.equipped_weapon = H.make_weapon()
	return unit


# Two enemy squads a corridor's length from the player, the enemy AI-controlled and its turn begun
# through the real door.
func _enemy_turn() -> Array[Squad]:
	for x in range(14):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var first := _spawn(Team.Faction.ENEMY, Vector2i(11, 0))
	var second := _spawn(Team.Faction.ENEMY, Vector2i(13, 0))
	game.ai_controller.set_ai_factions([Team.Faction.ENEMY] as Array[Team.Faction])
	game.turn_manager.set_active_faction(Team.Faction.ENEMY)
	var squads: Array[Squad] = [first.squad, second.squad]
	return squads


func test_the_first_squad_plans_in_the_handoff_and_nobody_plans_twice() -> void:
	var squads := _enemy_turn()
	var first: Squad = AIController.actable_squads(Team.Faction.ENEMY, game.squad_manager)[0]
	assert_bool(squads.has(first)).override_failure_message("fixture: the first actable squad is an enemy one").is_true()
	await await_idle_frame()

	await game.start_faction_turn(Team.Faction.ENEMY)

	assert_object(game.ai_controller.handoff_squad).override_failure_message(
			"the turn did not plan its first squad inside the hand-off").is_same(first)
	assert_int(game.ai_controller.planned_squad_count).override_failure_message(
			"two squads should plan once each").is_equal(2)


func test_every_order_of_an_ai_turn_is_queued_on_a_locked_board() -> void:
	_enemy_turn()
	await await_idle_frame()
	var unlocked: Array[String] = []
	var queued: Array[int] = [0]
	game.squad_manager.squad_action_queued.connect(func(_squad: Squad, action: BaseAction) -> void:
		if action.actor.get_faction() != Team.Faction.ENEMY:
			return
		queued[0] += 1
		if not game.playback_owns_board():
			unlocked.append("%s at %s" % [BaseAction.ActionType.keys()[action.action_type], action.actor.movement.cell]))

	await game.start_faction_turn(Team.Faction.ENEMY)

	assert_int(queued[0]).override_failure_message("fixture: the enemy turn queued nothing").is_greater(0)
	assert_int(unlocked.size()).override_failure_message(
			"orders were queued while the board was the player's: %s" % [unlocked]).is_equal(0)
