# Gas through the real game (#508): what the resolver says a pass leaves (test_gas_deposits.gd) is
# what the board shows before Execute and what the live store holds after it. Both ends were already
# correct in isolation once before in this project while nothing connected them (#103), so these cases
# drive the real queue, the real preview and the real execute_orders on the game scene.
#
# The board is hand-painted grass (the content razor); the gas is authored on the test's own attack.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const FOE_CELL := Vector2i(3, 1)
const LEVEL := Gas.Level.MEDIUM

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
		for y in range(4):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 40}, faction), cell)
	assert_object(unit).override_failure_message("fixture: nothing spawned at %s" % [cell]).is_not_null()
	unit.equipped_weapon = H.make_weapon(1)
	return unit


# A hero beside an enemy, its plain unit-only swing authored to leave steam, queued at the enemy.
func _steaming_swing() -> Unit:
	_spawn(ENEMY, FOE_CELL)
	var hero := _spawn(PLAYER, FOE_CELL + Vector2i.LEFT)
	(hero.get_equipped_weapon() as WeaponInstance).template.main_attack.gas_level = LEVEL
	game.squad_manager.active_squad = hero.squad
	var action := AttackAction.declare(hero, hero.movement.cell, FOE_CELL)
	assert_bool(game.squad_manager.queue_action(hero.squad, action)).override_failure_message(
			"fixture: the swing never queued (%s)" % [", ".join(action.validation_errors)]).is_true()
	game.refresh_action_queue(hero.squad)
	return hero


func _steam_at(cell: Vector2i) -> int:
	var field: GasField = game.gas_field
	return field.level_at(cell, Gas.Kind.STEAM)


func test_the_board_shows_where_the_steam_will_land_before_execute() -> void:
	_steaming_swing()
	assert_int(_steam_at(FOE_CELL)).override_failure_message("fixture: steam before anything ran").is_equal(0)
	var om: OverlayManager = game.overlay_manager
	var at := GridUtils.cell_world(om.board_tilemap, FOE_CELL)
	var ghosted := false
	for sprite: Sprite2D in om.terrain_preview_sprites:
		if is_instance_valid(sprite) and sprite.texture == GasPuffArt.icon(Gas.Kind.STEAM) \
				and sprite.global_position.is_equal_approx(at):
			ghosted = true
	assert_bool(ghosted).override_failure_message(
			"the queued swing leaves steam, but the board ghosts none on its cell").is_true()


# The wire: a deposit the resolver derives and nobody plays is #103's shape exactly.
func test_after_the_pass_the_steam_is_on_the_board() -> void:
	var hero := _steaming_swing()
	await game.order_executor.execute_orders(hero)
	assert_int(_steam_at(FOE_CELL)).is_equal(LEVEL)


# The round's wire: TurnManager.round_completed -> game._on_round_completed -> GasField.tick. The
# expectation is the store's own forecast of the round, so no level or timing is pinned here. One
# present faction wraps the cycle on a single hand-off (test_fire_wire.gd's arrangement).
func test_ending_the_round_spreads_the_steam() -> void:
	_spawn(PLAYER, Vector2i(0, 0))
	var field: GasField = game.gas_field
	field.set_level(Vector2i(4, 2), Gas.Kind.STEAM, Gas.Level.THICK)
	var board: BoardContext = game._board()
	var expected := field.next_round(board)
	assert_int(expected.size()).override_failure_message("fixture: the round would spread nothing").is_greater(1)
	await game.end_turn()
	await await_idle_frame()
	assert_int(field.cells().size()).override_failure_message("the round never ticked the gas").is_equal(expected.size())
	for cell: Vector2i in expected:
		assert_int(field.packed_at(cell)).is_equal(expected[cell])
