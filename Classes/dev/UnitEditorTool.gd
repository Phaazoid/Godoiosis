extends MarginContainer
class_name UnitEditorTool

# Dev-only unit editor: the tab (in DevOverlay) for editing whichever unit is currently
# selected — stats, inventory, squad, and job assignment. Never shown to a player.

@onready var unit_editor_container := %UnitEditorVbox
var editing_unit: Unit = null
var game   # injected by DevOverlay

func init(p_game):
	game = p_game

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
	DevWidgets.add_spinbox(unit_editor_container, "Current Will", unit.unit_instance.get_current_will(), func(v): unit.unit_instance.set_current_will(int(v)))
	DevWidgets.add_option(unit_editor_container, "Faction", Team.Faction.keys(), Team.Faction.keys()[unit.get_faction()], func(s): _set_unit_faction(unit, s))
	DevWidgets.add_lineedit(unit_editor_container, "Squad Name", unit.squad.squad_name, func(s): unit.squad.squad_name = s)

	_add_inventory_section(unit)
	_add_jobs_section(unit)
	_add_limbs_section(unit)
	_add_affinity_section(unit)


	var delete_button := Button.new()
	delete_button.text = "Delete Unit"
	delete_button.pressed.connect(func(): _delete_unit(unit))
	unit_editor_container.add_child(delete_button)

	var move_button := Button.new()
	move_button.text = "Move (then click a cell)"
	move_button.pressed.connect(func(): _arm_move())
	unit_editor_container.add_child(move_button)

	var dup_button := Button.new()
	dup_button.text = "Duplicate (then click a cell)"
	dup_button.pressed.connect(func(): _arm_duplicate())
	unit_editor_container.add_child(dup_button)

# Weapons + authored rune variants, in one ordered list, so a unit can equip either. Built here
# and reused by both the picker and the pick handler so their indices stay in lockstep. #30 D.
func _equippable_catalog() -> Dictionary:
	var items := {}
	var weapons := WeaponCatalog.get_editable()
	for k in weapons:
		items[k] = weapons[k]
	var runes := RuneCatalog.get_editable()
	for k in runes:
		items[k] = runes[k]
	return items

func _add_inventory_section(unit: Unit):
	DevWidgets.add_label(unit_editor_container, "Inventory")

	var weapons := _equippable_catalog()   # name -> EquippableData (weapons + authored runes)
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
				if _entry_matches(weapons[weapon_keys[k]], current_item):
					sel = k + 1
					break
		picker.select(sel)
		picker.item_selected.connect(func(idx): _on_slot_picked(unit, i, idx))
		row.add_child(picker)

		var equip_btn := CheckBox.new()
		equip_btn.text = "Equip"
		equip_btn.button_group = equip_group
		equip_btn.disabled = not (current_item is EquippableData)
		equip_btn.button_pressed = (current_item != null and current_item == unit.get_equipped_weapon())
		equip_btn.toggled.connect(func(pressed): if pressed: _equip_slot(unit, i))
		row.add_child(equip_btn)

		unit_editor_container.add_child(row)

func _entry_matches(entry, item) -> bool:
	# A template entry matches an instance built on it; saved instances / runes match by name.
	if entry is WeaponData and item is WeaponInstance:
		return item.template == entry
	if item is Item and entry is Item:
		return entry.item_name == item.item_name and item.item_name != ""
	return false

func _add_jobs_section(unit: Unit):
	DevWidgets.add_label(unit_editor_container, "Jobs")

	var inst := unit.unit_instance
	var jobs := JobCatalog.get_editable()   # display_name -> JobData

	for job_id in inst.jobs:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = _display_name_for(jobs, job_id)
		row.add_child(label)

		var remove_button := Button.new()
		remove_button.text = "Remove"
		remove_button.pressed.connect(func():
			inst.remove_job(job_id)
			populate_unit_editor(unit))
		row.add_child(remove_button)

		unit_editor_container.add_child(row)

	_add_job_picker(unit, jobs)

func _add_job_picker(unit: Unit, jobs: Dictionary):
	var inst := unit.unit_instance
	var available: Array[String] = []
	for display_name in jobs:
		if not inst.has_job(jobs[display_name].id):
			available.append(display_name)

	if available.is_empty():
		return   # every catalog job is already held

	var row := HBoxContainer.new()
	var picker := OptionButton.new()
	for display_name in available:
		picker.add_item(display_name)
	row.add_child(picker)

	var button := Button.new()
	button.text = "Add"
	button.pressed.connect(func():
		var picked: String = available[picker.selected]
		inst.add_job(jobs[picked].id)
		populate_unit_editor(unit))
	row.add_child(button)

	unit_editor_container.add_child(row)

func _display_name_for(jobs: Dictionary, id: String) -> String:
	for display_name in jobs:
		if jobs[display_name].id == id:
			return display_name
	return id   # catalog miss (shouldn't happen) — show the raw id rather than hiding it

func _add_limbs_section(unit: Unit):
	DevWidgets.add_label(unit_editor_container, "Limbs")

	var inst := unit.unit_instance
	var slot_names := UnitInstance.LimbSlot.keys()
	var state_names := UnitInstance.LimbState.keys()

	for slot in UnitInstance.LimbSlot.values():
		var fitting: UnitInstance.LimbFitting = inst.limbs[slot]
		DevWidgets.add_option(unit_editor_container, slot_names[slot], state_names, state_names[fitting.state],
			func(s): _on_limb_state_picked(unit, slot, s))

	DevWidgets.add_label(unit_editor_container, "MOV: %d" % inst.get_mov())
	DevWidgets.add_label(unit_editor_container, "Effective STR: %d   DEX: %d" % [
		inst.get_effective_stat(Stats.Stat.STR), inst.get_effective_stat(Stats.Stat.DEX)])

func _add_affinity_section(unit: Unit):
	DevWidgets.add_label(unit_editor_container, "Affinity")

	var inst := unit.unit_instance
	for element in Elemental.SIGIL_ELEMENTS:
		var name = Elemental.Element.keys()[element]
		DevWidgets.add_checkbox(unit_editor_container, name, inst.has_affinity(element),
			func(pressed): _on_affinity_toggled(unit, element, pressed))

	DevWidgets.add_checkbox(unit_editor_container, "Alkahest affine (hidden — Isaac only)", inst.is_alkahest_affine,
		func(pressed): inst.is_alkahest_affine = pressed)

	var primary := inst.primary_affinity()
	DevWidgets.add_label(unit_editor_container, "Primary: %s" % (Elemental.Element.keys()[primary] if primary != Elemental.Element.NONE else "(none — Rebecca)"))

	DevWidgets.add_label(unit_editor_container, "Aura")
	for element in Elemental.SIGIL_ELEMENTS:
		var name = Elemental.Element.keys()[element]
		if inst.has_affinity(element):
			DevWidgets.add_spinbox(unit_editor_container, name, inst.get_element_aura(element),
				func(v): inst.aura[element] = int(v))
		else:
			DevWidgets.add_label(unit_editor_container, "%s: — (no affinity)" % name)

func _on_affinity_toggled(unit: Unit, element: Elemental.Element, pressed: bool):
	var inst := unit.unit_instance
	if pressed:
		if not inst.affinity.has(element):
			inst.affinity.append(element)
	else:
		inst.affinity.erase(element)
		inst.aura.erase(element)   # can't hold aura outside affinity — Rebecca rule guard
	populate_unit_editor(unit)

func _on_limb_state_picked(unit: Unit, slot: int, state_name: String):
	var fitting: UnitInstance.LimbFitting = unit.unit_instance.limbs[slot]
	fitting.state = UnitInstance.LimbState[state_name]
	fitting.prosthetic_stat = 0
	fitting.prosthetic_item = null
	populate_unit_editor(unit)

func _on_slot_picked(unit: Unit, index: int, opt_index: int):
	if opt_index == 0:
		_set_slot(unit, index, null)
	else:
		var items := _equippable_catalog()
		_set_slot(unit, index, items[items.keys()[opt_index - 1]])

func _set_slot(unit: Unit, index: int, entry: Resource):
	var was_equipped = (unit.inventory[index] != null and unit.inventory[index] == unit.get_equipped_weapon())
	unit.inventory[index] = WeaponCatalog.instantiate_entry(entry) if entry != null else null
	if was_equipped:
		unit.unequip_weapon()
	if unit.inventory[index] is EquippableData and unit.get_equipped_weapon() == null:
		unit.set_equipped_weapon(unit.inventory[index])
	populate_unit_editor(unit)

func _equip_slot(unit: Unit, index: int):
	var item = unit.inventory[index]
	if item is EquippableData:
		unit.set_equipped_weapon(item)
	populate_unit_editor(unit)

func _set_unit_faction(unit: Unit, faction_name: String):
	unit.change_faction(Team.Faction[faction_name])

func _delete_unit(unit: Unit):
	if is_instance_valid(unit):
		unit.die()
	editing_unit = null
	populate_unit_editor(null)
	
func _arm_move() -> void:
	if game != null and is_instance_valid(editing_unit):
		game.dev_controller.arm_move(editing_unit)

func _arm_duplicate() -> void:
	if game != null and is_instance_valid(editing_unit):
		game.dev_controller.arm_duplicate(editing_unit)
