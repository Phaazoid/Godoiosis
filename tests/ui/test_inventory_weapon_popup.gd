# #1072. Two suites already drive _show_action_popup -- test_equip_reason_surfaces.gd with armour,
# test_vial_use_verb.gd with a vial -- and NEITHER passes a WeaponInstance, which is the one item
# kind that reaches the Toss branch's `item is WeaponInstance` clause. So that clause called
# is_installed_prosthetic with a WeaponData where the signature has taken a WeaponInstance since
# #87, the VM aborted the builder ten lines before add_child(popup), and every carried weapon in
# the game opened NO popup at all for seven weeks -- reported as two unrelated bugs (a crash on
# equipping a spitter, and a carbine that could not be re-equipped after a rune).
#
# The first case is therefore about the WIRE and not about any one row: what shipped broken was
# the builder finishing. The rest pin #744's shape on the row that motivated the rework -- Toss
# reads Unit.remove_block_reason (#741) rather than re-asking the prosthetic rule, and renders
# disabled-wearing-the-sentence like the three branches above it rather than hiding.
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


static func _buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	for node: Node in _walk(root):
		var button := node as Button
		if button != null:
			out.append(button)
	return out


static func _button_starting(root: Node, prefix: String) -> Button:
	for button: Button in _buttons(root):
		if button.text.begins_with(prefix):
			return button
	return null


func _weapon(name_of_family := "Test Carbine") -> WeaponInstance:
	var template := WeaponData.new()
	template.display_name = name_of_family
	template.weapon_type = WeaponData.WeaponType.CARBINE
	return WeaponInstance.make(template)


# A DERIVED generic: the template is named and the instance carries no pet name of its own, which
# is the shape that made remove_block_reason's sentence headless while it read the raw field.
func _prosthetic_arm() -> WeaponInstance:
	var template := WeaponData.new()
	template.display_name = "Iron Arm"
	template.weapon_type = WeaponData.WeaponType.PROSTHETIC
	template.built_in_stat = 6
	var instance := WeaponInstance.make(template)
	instance.limb_kind = WeaponData.LimbKind.ARM
	return instance


func _open_popup_on(unit: Unit, item: Item) -> Node:
	game.unit_info_panel.set_unit(unit, true, game._board())
	await await_idle_frame()
	var panel = game.unit_info_panel.inventory_panel
	panel._show_action_popup(unit.inventory.find(item))
	await await_idle_frame()
	return panel


# --- the wire -----------------------------------------------------------------------------------

func test_clicking_a_carried_weapon_builds_its_popup_at_all() -> void:
	# The #1072 regression, and it is deliberately NOT an assertion about any one row: the builder
	# aborted partway, so what this asks is that it REACHED add_child(popup). Restoring the bad
	# argument reds it with an empty popup rather than a wrong button.
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 0))
	var carbine := _weapon()
	assert_bool(unit.add_item(carbine)).is_true()

	var panel = await _open_popup_on(unit, carbine)
	var texts := PackedStringArray()
	for button: Button in _buttons(panel):
		texts.append(button.text)

	assert_int(texts.size()).override_failure_message(
		"the weapon's action popup rendered no buttons, so _show_action_popup never finished"
		).is_greater(0)
	assert_array(Array(texts)).contains(["Cancel"])   # the last row the builder adds


func test_a_carried_weapon_offers_Equip_and_Toss() -> void:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 0))
	var carbine := _weapon()
	assert_bool(unit.add_item(carbine)).is_true()
	unit.unequip_weapon()   # add_item auto-equips the first equippable; we want the Equip verb

	var panel = await _open_popup_on(unit, carbine)

	var equip := _button_starting(panel, "Equip")
	assert_object(equip).override_failure_message("no Equip button was rendered").is_not_null()
	assert_bool(equip.disabled).is_false()

	var toss := _button_starting(panel, "Toss")
	assert_object(toss).override_failure_message("no Toss button was rendered").is_not_null()
	assert_bool(toss.disabled).is_false()
	assert_str(toss.text).is_equal("Toss")


# --- the gate -----------------------------------------------------------------------------------

func test_a_fitted_prosthetic_greys_Toss_and_wears_the_gates_own_words() -> void:
	# #744's shape on this row: the panel does not word the refusal, it reads Unit's. Asserted as
	# CONTAINS because the surface frames it ("Toss -- <reason>"); the mutant is a hardcoded string
	# here, or the old hide-the-button branch, which leaves no Toss row to find.
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 0))
	var arm := _prosthetic_arm()
	assert_bool(unit.add_item(arm)).is_true()
	assert_bool(unit.unit_instance.install_prosthetic(UnitInstance.LimbSlot.ARM_R, arm)).is_true()

	var index := unit.inventory.find(arm)
	var reason: String = unit.remove_block_reason(index)
	assert_str(reason).override_failure_message(
		"fixture: the gate does not refuse this slot, so the row has nothing to say").is_not_empty()

	var panel = await _open_popup_on(unit, arm)
	var toss := _button_starting(panel, "Toss")

	assert_object(toss).override_failure_message(
		"no Toss row at all -- a refused row is greyed with its reason, never hidden (#166)"
		).is_not_null()
	assert_bool(toss.disabled).is_true()
	assert_str(toss.text).override_failure_message(
		"the row words the refusal itself instead of reading the gate: %s" % toss.text
		).contains(reason)


func test_the_gates_sentence_names_a_derived_generic_by_its_template() -> void:
	# shown_name(), never display_name (#945). A prosthetic built as a derived generic carries no
	# pet name, so the raw field is "" and the sentence rendered headless -- invisible until this
	# row started showing it to the player.
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 0))
	var arm := _prosthetic_arm()
	assert_str(arm.display_name).override_failure_message(
		"fixture: this arm carries a pet name, so it cannot show the derived-generic gap").is_empty()
	assert_bool(unit.add_item(arm)).is_true()
	assert_bool(unit.unit_instance.install_prosthetic(UnitInstance.LimbSlot.ARM_R, arm)).is_true()

	assert_str(unit.remove_block_reason(unit.inventory.find(arm))).contains("Iron Arm")
