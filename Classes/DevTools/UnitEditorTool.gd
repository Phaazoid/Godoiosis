extends MarginContainer
class_name UnitEditorTool

@onready var unit_editor_container := %UnitEditorVbox
var editing_unit: Unit = null

func edit_unit(unit):
	editing_unit = unit
	if unit != null:
		_show_self()
	populate_unit_editor(unit)

func _show_self():
	%DevTabs.current_tab = %DevTabs.get_tab_idx_from_control(self)

func populate_unit_editor(unit):
	for child in unit_editor_container.get_children():
		unit_editor_container.remove_child(child)
		child.queue_free()

	if unit == null or not is_instance_valid(unit):
		return

	DevWidgets.add_label(unit_editor_container, "Editing: " + unit.get_unit_name())

	for stat in unit.unit_instance.stats:
		DevWidgets.add_spinbox(unit_editor_container, Stats.Stat.keys()[stat], unit.unit_instance.stats[stat], func(v): unit.unit_instance.stats[stat] = int(v))

	DevWidgets.add_spinbox(unit_editor_container, "Current HP", unit.get_current_hp(), func(v): unit.unit_instance.set_current_hp(maxi(1, int(v))))

	DevWidgets.add_option(unit_editor_container, "Faction", Team.Faction.keys(), Team.Faction.keys()[unit.get_faction()], func(s): _set_unit_faction(unit, s))

	_add_inventory_section(unit)

	var delete_button := Button.new()
	delete_button.text = "Delete Unit"
	delete_button.pressed.connect(func(): _delete_unit(unit))
	unit_editor_container.add_child(delete_button)

func _add_inventory_section(unit: Unit):
	DevWidgets.add_label(unit_editor_container, "Inventory")

	var weapons := WeaponCatalog.get_editable()   # name -> WeaponData (no "None")
	var weapon_keys := weapons.keys()
	var equip_group := ButtonGroup.new()

	for i in range(Unit.MAX_INVENTORY_SIZE):
		var current_item = unit.inventory[i]

		var row := HBoxContainer.new()

		var label := Label.new()
		label.text = "Slot %d" % (i + 1)
		label.custom_minimum_size = Vector2(60, 0)
		row.add_child(label)

		var picker := OptionButton.new()
		picker.add_item("(empty)")
		for k in weapon_keys:
			picker.add_item(k)
		var sel := 0
		if current_item != null:
			for k in range(weapon_keys.size()):
				if weapons[weapon_keys[k]].item_name == current_item.item_name:
					sel = k + 1
					break
		picker.select(sel)
		picker.item_selected.connect(func(idx): _on_slot_picked(unit, i, idx))
		row.add_child(picker)

		var equip_btn := CheckBox.new()
		equip_btn.text = "Equip"
		equip_btn.button_group = equip_group
		equip_btn.disabled = not (current_item is WeaponData)
		equip_btn.button_pressed = (current_item != null and current_item == unit.get_equipped_weapon())
		equip_btn.toggled.connect(func(pressed): if pressed: _equip_slot(unit, i))
		row.add_child(equip_btn)

		unit_editor_container.add_child(row)

func _on_slot_picked(unit: Unit, index: int, opt_index: int):
	if opt_index == 0:
		_set_slot(unit, index, null)
	else:
		var weapons := WeaponCatalog.get_editable()
		_set_slot(unit, index, weapons[weapons.keys()[opt_index - 1]])

func _set_slot(unit: Unit, index: int, weapon: WeaponData):
	var was_equipped = (unit.inventory[index] != null and unit.inventory[index] == unit.get_equipped_weapon())
	unit.inventory[index] = weapon.duplicate(true) if weapon != null else null
	if was_equipped:
		unit.unequip_weapon()
	if unit.inventory[index] is WeaponData and unit.get_equipped_weapon() == null:
		unit.set_equipped_weapon(unit.inventory[index])
	populate_unit_editor(unit)

func _equip_slot(unit: Unit, index: int):
	var item = unit.inventory[index]
	if item is WeaponData:
		unit.set_equipped_weapon(item)
	populate_unit_editor(unit)

func _set_unit_faction(unit: Unit, faction_name: String):
	unit.change_faction(Team.Faction[faction_name])

func _delete_unit(unit: Unit):
	if is_instance_valid(unit):
		unit.die()
	editing_unit = null
	populate_unit_editor(null)
