# The Unit Editor's Equip checkbox (#1372): dev tools stay omnipotent, so Save puts the ticked item in
# hand even when the unit's own equip gate refuses it -- the way the Wear checkbox already treats
# armor. The filed bug: Save unequipped first, then asked the gated door, which said no, and the unit
# was left holding nothing.
#
# Also what a slot pick puts in the unit's bag (#1588): a carried vial or conduit must survive Save.
#
# Drives the REAL Equip CheckBox, slot picker and Save button in the built panel rather than the
# handlers (#131: a handler that exists and a signal that fires are two different facts).
#
# Fixture is tests/dev/test_unit_editor_lifecycle.gd's.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D
var _editor: UnitEditorTool


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(4):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	var overlay: DevOverlay = game.dev_overlay
	_editor = overlay.unit_editor
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn() -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(0, 0))
	assert_object(unit).is_not_null()
	return unit


# A blank rune fails every unit's gate ("This rune is blank"), whatever its aura or affinity, so it is
# the smallest item the gated door refuses outright.
func _dead_rune() -> RuneData:
	var rune := RuneData.new()
	rune.display_name = "Dead Rune"
	return rune


# Inventory slot `index`'s row, found by its "Slot N" label. Re-fetched on every use: the panel is
# rebuilt from scratch on each repaint.
func _slot_row(index: int) -> HBoxContainer:
	var want := "Slot %d" % (index + 1)
	for row: Node in _editor.unit_editor_container.find_children("*", "HBoxContainer", true, false):
		for child in row.get_children():
			if child is Label and (child as Label).text == want:
				return row as HBoxContainer
	return null


# The Equip/Wear CheckBox on inventory slot `index`'s row.
func _equip_box(index: int) -> CheckBox:
	return _slot_child(index, CheckBox) as CheckBox


# The item picker on inventory slot `index`'s row.
func _slot_picker(index: int) -> OptionButton:
	return _slot_child(index, OptionButton) as OptionButton


func _slot_child(index: int, type) -> Control:
	var row := _slot_row(index)
	if row == null:
		return null
	for child in row.get_children():
		if is_instance_of(child, type):
			return child as Control
	return null


func _save_button() -> Button:
	for node: Node in _editor.unit_editor_container.find_children("*", "Button", true, false):
		if not node is OptionButton and not node is CheckBox and (node as Button).text.begins_with("Save"):
			return node as Button
	return null


func test_equip_on_a_refused_rune_puts_it_in_hand_on_save() -> void:
	var unit := _spawn()
	var weapon := H.make_weapon()
	assert_bool(unit.add_item(weapon)).is_true()
	var rune := _dead_rune()
	assert_bool(unit.add_item(rune)).is_true()
	assert_object(unit.get_equipped_weapon()).override_failure_message(
		"precondition: the weapon should be in hand before the edit").is_same(weapon)
	assert_bool(rune.can_equip(unit.state)).override_failure_message(
		"precondition: the unit's own gate must refuse the rune, or this case proves nothing").is_false()

	_editor.edit_unit(unit)
	var rune_slot := unit.inventory.find(rune)
	var box := _equip_box(rune_slot)
	assert_object(box).override_failure_message("the rune's row draws no Equip checkbox").is_not_null()
	if box == null:
		return
	assert_bool(box.disabled).override_failure_message(
		"Equip must be live on any equippable -- dev tools stay omnipotent").is_false()
	box.button_pressed = true   # the real control: the setter emits toggled
	assert_object(unit.get_equipped_weapon()).override_failure_message(
		"a staged pick must not reach the unit before Save").is_same(weapon)

	var save := _save_button()
	assert_object(save).override_failure_message("the Unit Editor draws no Save button").is_not_null()
	if save == null:
		return
	save.pressed.emit()

	assert_object(unit.get_equipped_weapon()).override_failure_message(
		"Save must put the ticked rune in hand past its gate -- the gated door left the unit unarmed").is_same(rune)
	# Save re-captures and repaints: the panel must read back what the unit now holds.
	assert_bool(_equip_box(rune_slot).button_pressed).override_failure_message(
		"after Save the rune's Equip box should read ticked").is_true()


# #1588: the picker lists CARRIED kinds since #697, and the copy door cast every pick to
# EquippableData, so a vial or a conduit came back null -- the slot read (empty), and Save wrote
# that empty slot over whatever the unit held there. Picked through each slot's real OptionButton,
# saved through the real Save button.
func test_a_vial_or_conduit_pick_survives_save() -> void:
	var catalog := _editor._item_catalog()
	var keys: Array = catalog.keys()
	var unit := _spawn()
	_editor.edit_unit(unit)

	var picked: Dictionary[int, Item] = {}   # slot -> the catalog entry picked there
	var kinds: Array = [VialData, ConduitData]
	var kind_names: Array[String] = ["vial", "conduit"]
	for k in kinds.size():
		var key := ""
		for candidate: String in keys:
			if is_instance_of(catalog[candidate], kinds[k]):
				key = candidate
				break
		if key == "":   # content-absent: warn, never fail (tests/README.md rule 9)
			push_warning("no %s is authored, so that carried kind cannot be picked" % kind_names[k])
			continue
		var slot := 2 + picked.size()
		var picker := _slot_picker(slot)
		assert_object(picker).override_failure_message("slot %d draws no item picker" % (slot + 1)).is_not_null()
		if picker == null:
			return
		var option := keys.find(key) + 1   # row 0 is "(empty)"
		picker.select(option)
		picker.item_selected.emit(option)
		picked[slot] = catalog[key]
	if picked.is_empty():
		return

	var save := _save_button()
	assert_object(save).override_failure_message("the Unit Editor draws no Save button").is_not_null()
	if save == null:
		return
	save.pressed.emit()

	for slot: int in picked:
		var entry: Item = picked[slot]
		var held: Item = unit.inventory[slot]
		assert_object(held).override_failure_message(
			"picking %s saved an EMPTY slot -- the copy door dropped a carried kind" % entry.shown_name()).is_not_null()
		if held == null:
			continue
		assert_str(held.get_script().get_global_name()).is_equal(entry.get_script().get_global_name())
		assert_str(held.shown_name()).is_equal(entry.shown_name())
		assert_object(held).override_failure_message(
			"the unit holds the catalog's own %s rather than a copy" % entry.shown_name()).is_not_same(entry)
		assert_bool(_equip_box(slot).disabled).override_failure_message(
			"a carried %s fills no hand, so its Equip box must stay greyed" % entry.shown_name()).is_true()
