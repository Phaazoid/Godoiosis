# ONE BODY, ONE PICTURE (#1574). A unit's real sprite hides behind a ghost for two reasons -- its queued
# move, and a predicted shove -- through one flag (UnitVisuals.projected). The shove preview letting go
# used to write "shown" whatever the move still owed, so cancelling an attack whose counter shoved a
# unit with a queued move drew that unit twice: the move's ghost at its destination, and its real
# sprite back at its start. UnitMirror reads the same flag, so both views did.
#
# Driven through the real doors: the ring's own picks (aim_at + commit), board clicks through
# game._on_left_click (the door the 3D host calls), and the cancel through the queue X's own signal.
#
# Fixture is tests/ui/test_tile_inspect.gd's.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const MD := preload("res://tests/support/menu_drive.gd")
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
		for y in range(5):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# A single-cell reach-1 poke; `knockback` is how far it shoves.
func _spawn(faction: Team.Faction, cell: Vector2i, knockback := 0) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 60, Stats.Stat.DEX: 10}, faction), cell)
	assert_object(unit).override_failure_message("fixture failed to spawn at %s" % str(cell)).is_not_null()
	var weapon := H.make_weapon(1)
	P.point(weapon.template.main_attack, 1)
	weapon.template.main_attack.knockback = knockback
	unit.equipped_weapon = weapon
	return unit


# Pick the ring leaf carrying `label` the way the mouse does -- aim into its slice, then commit.
func _pick(label: String) -> void:
	var ring := MD.controller_of(game)
	assert_object(ring).override_failure_message("no ring is open to pick '%s' from" % label).is_not_null()
	var path := MD.path_to(ring.level_nodes(), label)
	assert_bool(path.is_empty()).override_failure_message("the ring offers no '%s'" % label).is_false()
	for index in path:
		ring.aim_at(ring.point_in_slice(index))
		ring.commit()
	await await_idle_frame()


# The unit's first attack: the leaf inside its kit slice, or the slice itself when it collapsed to one.
func _attack_label(unit: Unit) -> String:
	var kit := MD.kit_category(game, unit)
	var leaf := MD.first_leaf_under(MD.controller_of(game).level_nodes(), kit)
	return String(leaf.get("name", kit))


func _click(cell: Vector2i) -> void:
	game._on_left_click(cell)
	await await_idle_frame()


func _order(unit: Unit, type: BaseAction.ActionType) -> BaseAction:
	for action: BaseAction in unit.squad.action_queue:
		if action.actor != unit or action.action_type != type:
			continue
		if action is MoveAction and (action as MoveAction).is_hold_position:
			continue
		return action
	return null


func test_cancelling_an_attack_whose_counter_shoved_a_mover_keeps_it_hidden_behind_its_move() -> void:
	var mover := _spawn(Team.Faction.PLAYER, Vector2i(1, 2))
	var shover := _spawn(Team.Faction.ENEMY, Vector2i(4, 2), 1)
	var beside := Vector2i(3, 2)

	await _click(mover.movement.cell)
	await _pick(String(MainActionMenu.ACTION_DATA[MainActionMenu.MOVE]["name"]))
	await _click(beside)
	var move := _order(mover, BaseAction.ActionType.MOVE)
	assert_object(move).override_failure_message("precondition: the move was not queued").is_not_null()

	await _click(beside)   # a queued mover is clicked where it will stand (#126)
	await _pick(_attack_label(mover))
	await _click(shover.movement.cell)
	var attack := _order(mover, BaseAction.ActionType.ATTACK)
	assert_object(attack).override_failure_message("precondition: the attack was not queued").is_not_null()
	assert_bool(game.overlay_manager.knockback_hidden_units.has(mover)).override_failure_message(
			"precondition: the counter's shove does not ghost the mover").is_true()

	game.squad_action_queue_control.cancel_requested.emit(attack)
	await await_idle_frame()

	assert_bool(mover.squad.action_queue.has(move)).override_failure_message(
			"precondition: cancelling the attack took the move with it").is_true()
	assert_bool(game.overlay_manager.knockback_hidden_units.has(mover)).override_failure_message(
			"precondition: the shove preview still stands for the mover").is_false()
	assert_bool(game.overlay_manager.projected_unit_sprites.has(mover)).override_failure_message(
			"the move's ghost is gone").is_true()
	assert_bool(mover.visuals.projected).override_failure_message(
			"the mover's real sprite is no longer hidden behind its move's ghost").is_true()
	assert_bool(mover.visuals.sprite.visible).override_failure_message(
			"the mover is drawn twice: its ghost at the move's end, and its real sprite at the start").is_false()
