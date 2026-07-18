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

	_add_certify_picker(unit, jobs)

	var certified_names := _certified_display_names(jobs, inst)
	var certified_label := "(none)" if certified_names.is_empty() else ", ".join(certified_names)
	DevWidgets.add_label(unit_editor_container, "Certified: %s" % certified_label)

	var options := ["(none)"] + certified_names

	DevWidgets.add_option(unit_editor_container, "Main Job", options,
		_display_name_for(jobs, inst.main_job),
		func(s): _on_main_job_picked(unit, jobs, s))

	for i in range(2):
		var current_id := inst.sub_jobs[i] if i < inst.sub_jobs.size() else ""
		DevWidgets.add_option(unit_editor_container, "Sub %d" % (i + 1), options,
			_display_name_for(jobs, current_id),
			func(s): _on_sub_job_picked(unit, jobs, i, s))

	DevWidgets.add_spinbox(unit_editor_container, "Unlocked Sub Slots", inst.unlocked_sub_slots,
		func(v): _on_unlocked_slots_changed(unit, int(v)))

	_add_ceiling_preview(unit)

func _add_certify_picker(unit: Unit, jobs: Dictionary):
	var inst := unit.unit_instance
	var uncertified: Array[String] = []
	for display_name in jobs:
		if not inst.certified_jobs.has(jobs[display_name].id):
			uncertified.append(display_name)

	if uncertified.is_empty():
		return   # every catalog job is already certified

	var row := HBoxContainer.new()
	var picker := OptionButton.new()
	for display_name in uncertified:
		picker.add_item(display_name)
	row.add_child(picker)

	var button := Button.new()
	button.text = "Certify"
	button.pressed.connect(func():
		var picked: String = uncertified[picker.selected]
		inst.certify(jobs[picked].id, true)   # dev tool: force past is_locked
		populate_unit_editor(unit))
	row.add_child(button)

	unit_editor_container.add_child(row)

func _certified_display_names(jobs: Dictionary, inst: UnitInstance) -> Array[String]:
	var names: Array[String] = []
	for display_name in jobs:
		if inst.certified_jobs.has(jobs[display_name].id):
			names.append(display_name)
	return names

func _display_name_for(jobs: Dictionary, id: String) -> String:
	if id == "":
		return "(none)"
	for display_name in jobs:
		if jobs[display_name].id == id:
			return display_name
	return "(none)"

func _on_main_job_picked(unit: Unit, jobs: Dictionary, picked: String):
	var id = "" if picked == "(none)" else jobs[picked].id
	unit.unit_instance.set_main_job(id)
	populate_unit_editor(unit)

func _on_sub_job_picked(unit: Unit, jobs: Dictionary, index: int, picked: String):
	var id = "" if picked == "(none)" else jobs[picked].id
	unit.unit_instance.set_sub_job(index, id)
	populate_unit_editor(unit)

func _on_unlocked_slots_changed(unit: Unit, value: int):
	unit.unit_instance.set_unlocked_sub_slots(value)
	populate_unit_editor(unit)

func _add_ceiling_preview(unit: Unit):
	var inst := unit.unit_instance
	var job := JobCatalog.get_job(inst.main_job)
	if job == null:
		return
	for stat in job.stat_ceilings:
		var cap: int = job.stat_ceilings[stat]
		var pre := inst.get_stat_before_ceiling(stat)
		if pre > cap:
			DevWidgets.add_label(unit_editor_container, "CLAMPED: %s %d -> %d" % [Stats.Stat.keys()[stat], pre, cap])

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
