# An open aim ghosts what it would leave on the ground (#894), through the real hover on the game
# scene: the fire an attack lays where it hits shows before the click, over the aim fill that covers
# the same tiles, and closing the aim puts the queued plan's ghosts back. The ghosts are compared
# with the forecast's own deposits, never typed in.
#
# The board is hand-painted grass (the content razor); the tile effect is authored on the test's own
# attack, and that attack carries no element, so nothing but the laid fire can light a tile.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const STEAMED := Vector2i(3, 1)   # the queued swing's target
const LAID := Vector2i(3, 2)      # the aimed fire-layer's target

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
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 40}, faction), cell)
	assert_object(unit).override_failure_message("fixture: nothing spawned at %s" % [cell]).is_not_null()
	unit.equipped_weapon = H.make_weapon(1)
	return unit


# A layer that lays fire where it hits, beside its target.
func _fire_layer() -> Unit:
	_spawn(ENEMY, LAID)
	var layer := _spawn(PLAYER, LAID + Vector2i.LEFT)
	(layer.get_equipped_weapon() as WeaponInstance).template.main_attack.tile_effect = Elemental.Element.FIRE
	game.squad_manager.active_squad = layer.squad
	return layer


func _hover_aim(attacker: Unit, cell: Vector2i) -> void:
	game.hover_presenter.pointer_source = func() -> Vector2i: return cell
	game.selected_unit = attacker
	game.enter_attack_mode(attacker)
	game.hover_presenter.update_hover_visuals(cell)


func _ghost_at(icon: Texture2D, cell: Vector2i) -> Sprite2D:
	var om: OverlayManager = game.overlay_manager
	var at := GridUtils.cell_world(om.board_tilemap, cell)
	for sprite: Sprite2D in om.terrain_preview_sprites:
		if is_instance_valid(sprite) and sprite.texture == icon and sprite.global_position.is_equal_approx(at):
			return sprite
	return null


func _fire() -> Texture2D:
	return OverlayManager.TERRAIN_STATE_ICONS[Terrain.TileState.BURNING]


func _queued(unit: Unit) -> int:
	return unit.squad.action_queue.size()


func test_an_aim_ghosts_the_fire_it_would_lay_before_the_click() -> void:
	var layer := _fire_layer()
	_hover_aim(layer, LAID)
	await await_idle_frame()

	assert_int(_queued(layer)).override_failure_message("something was queued, so a ghost here is the queue's").is_equal(0)
	var forecast: ResolvedPlan = game.aim_forecast
	assert_object(forecast).override_failure_message("the aim forecast nothing").is_not_null()
	var laid := false
	for deposit: Dictionary in forecast.pending_deposits():
		laid = laid or (deposit.get("cell") == LAID and deposit.get("state") == Terrain.TileState.BURNING)
	assert_bool(laid).override_failure_message("fixture: the forecast lays no fire on the target").is_true()
	assert_object(_ghost_at(_fire(), LAID)).override_failure_message(
			"the aim lays fire on its target, but the board ghosts none before the click").is_not_null()


func test_the_ghost_draws_over_the_aim_fill_and_under_the_arrows() -> void:
	var layer := _fire_layer()
	_hover_aim(layer, LAID)
	await await_idle_frame()
	var ghost := _ghost_at(_fire(), LAID)
	assert_object(ghost).override_failure_message("no ghost, so its order proves nothing").is_not_null()

	# Equal z, so tree order decides: the fill, then the ghost, then the arrows.
	var om: OverlayManager = game.overlay_manager
	var fill := om.hover_overlay as CanvasItem
	assert_int(ghost.z_index).override_failure_message("the ghost left the aim fill's z").is_equal(fill.z_index)
	assert_int(MoveAction.ARROW_BASE_Z_INDEX).override_failure_message(
			"the arrows' z moved; decide the ghost's order deliberately").is_equal(fill.z_index)
	assert_bool(fill.get_index() < om.icon_overlay.get_index()).override_failure_message(
			"the aim fill draws after the ghost, so it hides it").is_true()
	assert_bool(om.icon_overlay.get_index() < om.arrow_icon_overlay.get_index()).override_failure_message(
			"the ghost draws after the arrows").is_true()


func test_closing_the_aim_puts_the_queued_plans_ghosts_back() -> void:
	var layer := _fire_layer()
	_spawn(ENEMY, STEAMED)
	var swinger := _spawn(PLAYER, STEAMED + Vector2i.LEFT)
	game.squad_manager.join_squad(swinger, layer.squad)
	(swinger.get_equipped_weapon() as WeaponInstance).template.main_attack.gases = {Gas.Kind.STEAM: Gas.Level.MEDIUM}
	var swing := AttackAction.declare(swinger, swinger.movement.cell, STEAMED)
	assert_bool(game.squad_manager.queue_action(layer.squad, swing)).override_failure_message(
			"fixture: the swing never queued (%s)" % [", ".join(swing.validation_errors)]).is_true()
	game.refresh_action_queue(layer.squad)
	var steam := GasPuffArt.icon(Gas.Kind.STEAM)

	_hover_aim(layer, LAID)
	await await_idle_frame()
	assert_object(_ghost_at(_fire(), LAID)).override_failure_message("the aim ghosts no fire").is_not_null()
	assert_object(_ghost_at(steam, STEAMED)).override_failure_message(
			"the aim's ghosts dropped the queued swing's steam").is_not_null()

	game.hover_presenter.update_hover_visuals(Vector2i(7, 0))   # a cell the aim cannot take
	await await_idle_frame()
	assert_object(_ghost_at(_fire(), LAID)).override_failure_message(
			"an aim that forecasts nothing still ghosts its fire").is_null()
	assert_object(_ghost_at(steam, STEAMED)).is_not_null()

	_hover_aim(layer, LAID)
	game.exit_current_mode()
	await await_idle_frame()
	assert_object(_ghost_at(_fire(), LAID)).override_failure_message("the aim's ghost outlived the aim").is_null()
	assert_object(_ghost_at(steam, STEAMED)).override_failure_message(
			"closing the aim took the queued plan's ghost with it").is_not_null()
