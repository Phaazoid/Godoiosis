# Guard's PLAYER SURFACE (#414), driven as the sequence a player performs: populate the menu, press
# the row, click a tile, assert on the queue.
#
# It exists for #126's lesson, which tests/ui/test_target_pick_projection.gd is the monument to:
# fixing "where is this unit?" at the rule layer is not finished until the PICK layer agrees, and a
# suite that calls the candidate query directly cannot tell the difference. RulesService.guard_
# candidates being right proves nothing about whether the row appears or the click queues anything.
#
# Fixture is the shared game-scene one -- see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

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
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, faction), cell)
	assert_object(unit).is_not_null()
	unit.equipped_weapon = H.make_weapon()
	return unit


func _queued_guard(squad: Squad) -> GuardAction:
	for action in squad.action_queue:
		if action is GuardAction:
			return action as GuardAction
	return null


# THE sequence: the row appears, pressing it enters pick mode with the ally marked, and the click
# queues a real, valid order naming both ends of the pair.
func test_pressing_guard_and_clicking_an_ally_queues_the_order() -> void:
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var _enemy := _spawn(Team.Faction.ENEMY, Vector2i(7, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(ward, blocker.squad)

	assert_array(game.main_action_menu.populate(blocker)) \
		.override_failure_message("the Guard row never appeared").contains([MainActionMenu.GUARD])

	game.main_action_menu.on_pressed(MainActionMenu.GUARD, blocker)
	assert_array(game.target_pick_cells) \
		.override_failure_message("the pick overlay never marked the ally").contains([Vector2i(2, 0)])

	game._click_picking_target(Vector2i(2, 0))

	var guard := _queued_guard(blocker.squad)
	assert_object(guard).override_failure_message("the click queued nothing").is_not_null()
	assert_object(guard.actor).is_same(blocker)
	assert_object(guard.target).is_same(ward)
	assert_bool(guard.is_valid).is_true()
	assert_int(guard.guard_range).is_equal(blocker.get_guard_range())


# The other half of the candidate rule: an enemy is never a ward, so a unit with only enemies beside
# it is offered nothing. Without this the case above passes against a version that offers everyone.
func test_an_enemy_beside_you_is_not_a_guard_candidate() -> void:
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var _enemy := _spawn(Team.Faction.ENEMY, Vector2i(2, 0))
	await await_idle_frame()

	assert_array(game.main_action_menu.populate(blocker)) \
		.override_failure_message("Guard was offered with nobody friendly in range") \
		.not_contains([MainActionMenu.GUARD])


# Guard is a MAIN action: taking one locks the rest, and it must sit after any move. Pinned through
# the menu rather than the registry so the two cannot drift.
func test_a_queued_guard_locks_out_the_other_main_actions() -> void:
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var _enemy := _spawn(Team.Faction.ENEMY, Vector2i(7, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(ward, blocker.squad)

	game.main_action_menu.on_pressed(MainActionMenu.GUARD, blocker)
	game._click_picking_target(Vector2i(2, 0))
	assert_object(_queued_guard(blocker.squad)).is_not_null()

	# Explicit type: `game` is untyped, so `:=` cannot infer through it (CLAUDE.md's Variant rule).
	var options: Array = game.main_action_menu.populate(blocker)
	assert_array(options).not_contains([MainActionMenu.GUARD])
	assert_array(options).not_contains([MainActionMenu.ATTACK])


# The validator's clause, through the real re-plan: a move that walks the blocker out of range does
# not silently arm a Guard covering nobody -- the row goes red instead.
func test_walking_out_of_range_invalidates_the_queued_guard() -> void:
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var _enemy := _spawn(Team.Faction.ENEMY, Vector2i(7, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(ward, blocker.squad)

	var guard := GuardAction.new()
	guard.init(blocker, ward)
	assert_bool(game.squad_manager.queue_action(blocker.squad, guard)) \
		.override_failure_message("fixture failed to queue the Guard").is_true()
	assert_bool(guard.is_valid).is_true()

	# The blocker is dragged five cells down the row by a re-plan it authored itself.
	var move := MoveAction.new()
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)]
	move.init(blocker, path, null)
	blocker.squad._queue_action(move)
	game.squad_manager.validate_squad_plan(blocker.squad)

	assert_bool(guard.is_valid) \
		.override_failure_message("a Guard covering nobody stayed green").is_false()
