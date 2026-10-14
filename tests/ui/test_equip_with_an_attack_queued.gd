# #1283's wire, on the real scene: the inspect dock's Equip button, pressed with an attack queued.
#
# The rule itself (a weapon fires only what it carries, and the validator re-asks it of stored
# orders) is tests/weapons/test_an_attack_belongs_to_its_weapon.gd's. What only the real scene can
# show is that the dock's button reaches it: the press must re-resolve and re-validate the queue
# (game wires loadout_changed to refresh_action_queue), or the order stays green while the mace is
# in hand and Execute plays a Slash with the mace's numbers.
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
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	game.scenario_manager.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


# The dock's Equip button for `item`, read off the popup the player opens by clicking its slot.
func _press_equip(unit: Unit, item: Item) -> void:
	game.unit_info_panel.set_unit(unit, true, game._board())
	await await_idle_frame()
	var panel = game.unit_info_panel.inventory_panel
	panel._show_action_popup(unit.inventory.find(item))
	await await_idle_frame()
	var equip: Button = null
	for node: Node in _walk(panel):
		var button := node as Button
		if button != null and button.text == "Equip":
			equip = button
	assert_object(equip).override_failure_message(
		"fixture: the dock offered no Equip for %s" % item.shown_name()).is_not_null()
	equip.pressed.emit()
	await await_idle_frame()


func test_the_docks_equip_reds_a_queued_attack_until_the_weapon_comes_back() -> void:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 0))
	var sword := H.make_weapon(3)
	var mace := H.make_weapon(5)
	unit.add_item(sword)   # the first weapon-shaped item auto-equips
	unit.add_item(mace)
	var foe: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 200}, Team.Faction.ENEMY), Vector2i(2, 0))

	game.squad_manager.active_squad = unit.squad
	var aim := AttackAction.declare(unit, unit.movement.cell, foe.movement.cell)
	assert_bool(game.squad_manager.queue_action(unit.squad, aim)) \
		.override_failure_message("fixture: the aim was refused at the queue").is_true()
	game.refresh_action_queue(unit.squad)
	assert_array(game.squad_manager.refused_orders(unit.squad)).override_failure_message(
		"fixture: the aim is red before any swap").is_empty()

	await _press_equip(unit, mace)
	assert_object(unit.get_equipped_weapon()).override_failure_message(
		"the Equip button did not actually swap the weapon").is_same(mace)
	assert_array(game.squad_manager.refused_orders(unit.squad)).override_failure_message(
		"the dock swapped in the mace and the sword's queued Slash is still green -- Execute would " +
		"play it with the mace's numbers").contains([aim])

	await _press_equip(unit, sword)
	assert_array(game.squad_manager.refused_orders(unit.squad)).override_failure_message(
		"the sword is back in hand and the queued Slash is still red").is_empty()
