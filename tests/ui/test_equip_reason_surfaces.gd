# #744's other half: the two surfaces that explain a refusal both READ the gate's own sentence rather
# than wording it themselves. Before this the in-battle equip button hardcoded "can't channel" -- true
# only while runes were the one kind that could refuse -- and the pre-mission card said "This unit
# cannot equip it", which is the bool restated.
#
# Asserted as CONTAINS, not equality, and that is not a weakening: each surface frames the sentence
# ("Wear -- <reason>", "<item name> -- <reason>"), so what is pinned is that the framed string carries
# the gate's words. The mutant is hardcoding a string back into either surface.
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


func _gated_plate() -> ArmorData:
	var plate := ArmorData.new()
	plate.display_name = "Test Plate"
	plate.def_power = 6
	plate.stat_minimums[Stats.Stat.CON] = 9
	return plate


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


func test_both_explaining_surfaces_carry_the_gates_own_words() -> void:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.CON: 4}, Team.Faction.PLAYER),
		Vector2i(1, 0))
	var plate := _gated_plate()
	assert_bool(unit.add_item(plate)).is_true()

	var reason: String = plate.can_equip_reason(unit)
	assert_str(reason).override_failure_message(
		"fixture: the plate does not actually refuse this body, so neither surface has anything to say"
		).is_not_empty()

	# --- the in-battle door: the slot's action popup ---
	game.unit_info_panel.set_unit(unit, true, game._board())
	await await_idle_frame()
	var inventory_panel = game.unit_info_panel.inventory_panel
	inventory_panel._show_action_popup(unit.inventory.find(plate))
	await await_idle_frame()

	var wear_text := ""
	for node: Node in _walk(inventory_panel):
		var button := node as Button
		if button != null and button.text.begins_with("Wear"):
			wear_text = button.text
	assert_str(wear_text).override_failure_message(
		"no Wear button was rendered, so this case pins nothing").is_not_empty()
	assert_str(wear_text).override_failure_message(
		"the equip button words the refusal itself instead of reading the gate: %s" % wear_text
		).contains(reason)

	# --- the pre-mission door: the unit card's item row ---
	var card := PreMissionCard.build(unit, game.mission_controller)
	add_child(card)
	await await_idle_frame()

	var row_tip := ""
	for node: Node in _walk(card):
		if node is PanelContainer and node.tooltip_text.contains(plate.display_name):
			row_tip = node.tooltip_text
	assert_str(row_tip).override_failure_message(
		"the card rendered no row for the carried plate").is_not_empty()
	assert_str(row_tip).override_failure_message(
		"the card words the refusal itself instead of reading the gate: %s" % row_tip
		).contains(reason)
	card.free()
