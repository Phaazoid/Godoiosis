# A downed body the ice holds is drawn frozen INTO it (#1506): standing, in its map art, inside
# FrozenInIce's ring of crystals, with a faint copy of the body drawn over the ice. Every case reaches
# the ice through the real pass -- a fire that melts the ice under an enemy (it sinks and goes down)
# and a frost that freezes the water again -- on the real Battle3D board, then reads the mirror.
#
# What NO case here can see is whether any of it LOOKS right: the dummy renderer draws nothing, so the
# glass, its sorting against the water and the gas, and how the grow reads in motion are the dev's
# to play.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const DEEP_WATER := Vector2i(5, 6)
const ICE := Vector2i(3, 1)

var _board := SharedBoard.new(SCENE_PATH)
var game: Node2D
var _mirror: UnitMirror
var _grow := 0.0
var _fade := 0.0


func before() -> void:
	await _board.open(self, _clear_the_board)


func _clear_the_board() -> void:
	_board.game.scenario_manager.clear_board()
	_board.game.game_state = _board.game.GameState.IDLE


func before_test() -> void:
	await _board.reset(self)
	game = _board.game
	# The sink's down is a battle-zoom moment, and the zoom's tear-out lifts the stage and the camera
	# with it; the ice is what these cases are about. SharedBoard resets the setting per case.
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.OFF)
	_mirror = _board.scene.get_node("UnitMirror") as UnitMirror
	_grow = StatusLook.in_ice_grow_time
	_fade = StatusLook.status_fade_time
	StatusLook.in_ice_grow_time = 0.0
	StatusLook.status_fade_time = 0.0


func after_test() -> void:
	StatusLook.in_ice_grow_time = _grow
	StatusLook.status_fade_time = _fade
	_mirror.camera_hidden.clear()
	await _board.check(self)


func after() -> void:
	_board.close()


# --- fixture -------------------------------------------------------------------------------------

# Two stills that cannot be mistaken for each other: the standing art tall, the downed art flat.
func _still(width: int, height: int) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.4, 0.3, 1.0))
	return ImageTexture.create_from_image(image)


func _spawn(faction: Team.Faction, cell: Vector2i, power := 3) -> Unit:
	var data := H.make_unit_data({Stats.Stat.MHP: 30}, faction)
	data.map_sprite = _still(8, 16)
	data.downed_sprite = _still(16, 6)
	var unit: Unit = game.spawn_unit(data, cell)
	assert_object(unit).override_failure_message("fixture: nothing spawned at %s" % [cell]).is_not_null()
	unit.equipped_weapon = H.make_weapon(power)
	return unit


func _imbue(unit: Unit, element: Elemental.Element, targets: EquippableData.TargetMode) -> void:
	var attack: WeaponAttackData = (unit.get_equipped_weapon() as WeaponInstance).template.main_attack
	attack.elemental_damage_type = element
	attack.targets = targets


func _queue(attacker: Unit, cell: Vector2i) -> void:
	game.squad_manager.active_squad = attacker.squad
	var action := AttackAction.declare(attacker, attacker.movement.cell, cell)
	assert_bool(game.squad_manager.queue_action(attacker.squad, action)).override_failure_message(
			"fixture: the attack at %s never queued (%s)" % [cell, ", ".join(action.validation_errors)]) \
		.is_true()
	game.refresh_action_queue(attacker.squad)


func _frozen(cell: Vector2i) -> bool:
	return (game.terrain_states as TerrainStateManager).has_state(cell, Terrain.TileState.FROZEN)


# Grass round deep water at ICE, iced over before anyone stands on it (spawn refuses water).
func _paint() -> void:
	var grid := game.grid as BoardGrid
	for x in range(0, 7):
		for y in range(0, 3):
			grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	grid.paint(ICE, GRASS_SOURCE, DEEP_WATER)
	var freeze := ResolvedCellEffect.new()
	freeze.cell = ICE
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	game.terrain_states.apply(freeze)


# The real pass: a fire melts the ice under an enemy, which sinks and goes down, and a frost on the
# tile alone (a hit on the body would finish it) freezes the water over it again.
func _sink_and_refreeze() -> Unit:
	_paint()
	# Out of everyone's reach, so the pass never routs the enemy side: a won board raises its card.
	_spawn(ENEMY, Vector2i(6, 2))
	var foe := _spawn(ENEMY, ICE)
	var hero := _spawn(PLAYER, Vector2i(2, 1))
	_imbue(hero, Elemental.Element.FIRE, EquippableData.TargetMode.BOTH)
	var froster := _spawn(PLAYER, Vector2i(4, 1))
	_imbue(froster, Elemental.Element.ICE, EquippableData.TargetMode.MAP)
	game.squad_manager.join_squad(froster, hero.squad)
	_queue(hero, ICE)
	_queue(froster, ICE)
	await game.order_executor.execute_orders(hero)
	assert_bool(foe.is_downed()).override_failure_message("fixture: the melt did not sink the enemy").is_true()
	assert_bool(_frozen(ICE)).override_failure_message("fixture: the frost did not close the ice").is_true()
	_mirror.reconcile(0.1)
	return foe


# --- the body in the ice -------------------------------------------------------------------------

func test_a_body_the_ice_closes_over_stands_frozen_in_it() -> void:
	var foe := await _sink_and_refreeze()
	var sprite := _mirror.sprite_for(foe)
	assert_bool(sprite.is_in_ice()).override_failure_message(
			"the mirror did not put the body the ice holds in the ice").is_true()
	assert_object(sprite.texture).override_failure_message(
			"a body frozen in the ice is drawn in its downed art, not standing").is_same(foe.unit_data.map_sprite)
	var level := _mirror.status_level(foe)
	assert_float(level.y).override_failure_message("a body in the ice does not wear the chill").is_equal(1.0)
	assert_float(level.x).override_failure_message(
			"a body in the ice still wears the wet the water left on it").is_equal(0.0)


func test_the_ring_and_the_body_copy_stand_on_their_own_layers() -> void:
	var foe := await _sink_and_refreeze()
	var id := foe.get_instance_id()
	var ice := _mirror.frozen_in_ice()
	var ring := ice.ring_for(id)
	var copy := ice.body_for(id)
	assert_object(ring).override_failure_message("no ring of crystals grew round the body").is_not_null()
	assert_object(copy).override_failure_message("no copy of the body is drawn over the ice").is_not_null()
	if ring == null or copy == null:
		return
	assert_int(ring.layers).override_failure_message(
			"the ring is not on the world layer alone, so overlay fills or the damp blot reach it") \
		.is_equal(BoardOverlays.WORLD_RENDER_LAYER)
	assert_int(copy.layers).is_equal(BoardOverlays.UNIT_RENDER_LAYER)
	assert_int(copy.render_priority).override_failure_message(
			"the copy does not sort over the ice it is meant to show through") \
		.is_greater(BoardOverlays.EFFECT_RENDER_PRIORITY)
	assert_object(copy.texture).override_failure_message("the copy draws a different art from the body") \
		.is_same(_mirror.sprite_for(foe).texture)
	assert_bool(ring.visible and copy.visible).override_failure_message(
			"the ice is up but not shown").is_true()


func test_the_ice_hides_with_the_body_the_battle_zoom_hides() -> void:
	var foe := await _sink_and_refreeze()
	var id := foe.get_instance_id()
	_mirror.camera_hidden[id] = true
	_mirror.reconcile(0.1)
	var ice := _mirror.frozen_in_ice()
	assert_object(ice.ring_for(id)).override_failure_message(
			"hiding the body took its ice down rather than hiding it").is_not_null()
	if ice.ring_for(id) == null:
		return
	assert_bool(ice.ring_for(id).visible or ice.body_for(id).visible).override_failure_message(
			"the ice still shows round a body the battle zoom hid").is_false()


func test_a_thaw_takes_the_ice_away() -> void:
	var foe := await _sink_and_refreeze()
	var id := foe.get_instance_id()
	assert_int(_mirror.frozen_in_ice().held_count()).override_failure_message(
			"fixture: no ice stood round the body to begin with").is_equal(1)
	# A second side's fire on the tile alone: the ice melts and the body goes under for good.
	var lighter := _spawn(PLAYER, Vector2i(3, 0))
	_imbue(lighter, Elemental.Element.FIRE, EquippableData.TargetMode.MAP)
	_queue(lighter, ICE)
	await game.order_executor.execute_orders(lighter)
	assert_bool(_frozen(ICE)).override_failure_message("fixture: the fire did not melt the ice").is_false()
	_mirror.reconcile(0.1)
	_mirror.reconcile(0.1)
	assert_object(_mirror.frozen_in_ice().ring_for(id)).override_failure_message(
			"the ice still stands round a body the thaw sank").is_null()
	# The thaw finishes the body, so the mirror may already have taken its sprite down.
	var sprite: UnitSprite3D = _mirror.sprite_for(foe) if is_instance_valid(foe) else null
	if sprite != null:
		assert_bool(sprite.is_in_ice()).override_failure_message(
				"the body is still drawn in ice that has melted").is_false()
