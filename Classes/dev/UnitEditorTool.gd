extends MarginContainer
class_name UnitEditorTool

# Dev-only unit editor: the tab (in DevOverlay) for editing whichever unit is currently
# selected — stats, inventory, squad, and job assignment. Never shown to a player.
#
# Every control edits the STAGED buffer below, never the unit; Save is the only writer.
# UnitInstance can't serve as that buffer (its fields are plain vars, so duplicate() returns a
# blank), so state is captured field by field on select and applied in dependency order on Save.

@onready var unit_editor_container := %UnitEditorVbox
var editing_unit: Unit = null
var game   # injected by DevOverlay

var _dirty := false
var _stats: Dictionary[Stats.Stat, int] = {}
var _current_hp := 0
var _current_will := 0
var _faction: Team.Faction = Team.Faction.PLAYER
var _squad_name := ""
var _unit_name := ""
var _jobs: Array[String] = []
var _limb_states: Dictionary[UnitInstance.LimbSlot, UnitInstance.LimbState] = {}
var _limb_prosthetics: Dictionary[UnitInstance.LimbSlot, int] = {}   # slot -> _inventory index, or -1 (placeholder)
var _affinity: Array[Elemental.Element] = []
var _alkahest := false
var _aura: Dictionary[Elemental.Element, int] = {}
var _inventory: Array[Item] = []
var _equipped_index := -1
var _armor_index := -1

var _save_button: Button = null
var _revert_button: Button = null

func init(p_game):
	game = p_game

func edit_unit(unit):
	if unit != null and unit == editing_unit:
		return   # re-selecting the same unit must not wipe what's staged
	if _dirty and is_instance_valid(editing_unit):
		push_warning("Unit editor: discarded unsaved changes to %s" % editing_unit.get_unit_name())
	editing_unit = unit
	if unit != null:
		# Capture BEFORE _show_self(): its tab_changed fires refresh_catalogs() reentrantly,
		# which would index into a stale _inventory otherwise.
		_capture(unit)
		_show_self()
	else:
		_dirty = false
	populate_unit_editor(unit)

func _show_self():
	%DevTabs.current_tab = %DevTabs.get_tab_idx_from_control(self)

# Catalog data can change while this tab isn't current; a full repaint picks it up fresh.
func refresh_catalogs() -> void:
	if is_instance_valid(editing_unit):
		populate_unit_editor(editing_unit)

func _capture(unit: Unit) -> void:
	var inst: UnitInstance = unit.unit_instance
	_stats = inst.stats.duplicate()
	_current_hp = unit.get_current_hp()
	_current_will = inst.get_current_will()
	_faction = unit.get_faction()
	_squad_name = unit.squad.squad_name
	_unit_name = unit.get_unit_name()
	_jobs = inst.jobs.duplicate()
	_affinity = inst.affinity.duplicate()
	_alkahest = inst.is_alkahest_affine
	_aura = inst.aura.duplicate()

	_limb_states = {}
	for slot in UnitInstance.LimbSlot.values():
		_limb_states[slot] = inst.limbs[slot].state

	# Fixed-size slot array, so a plain copy stages it. Entries stay shared -- the tool only ever
	# swaps whole slots, never edits an item in place.
	_inventory = unit.inventory.duplicate()
	var equipped := unit.get_equipped_weapon()
	# find(null) would return the first EMPTY slot, so guard both lookups.
	_equipped_index = _inventory.find(equipped) if equipped != null else -1
	_armor_index = _inventory.find(unit.worn_armor) if unit.worn_armor != null else -1

	# Which carried item fills each PROSTHETIC slot, by inventory index. -1 = placeholder fitting.
	_limb_prosthetics = {}
	for slot in UnitInstance.LimbSlot.values():
		var fitting: UnitInstance.LimbFitting = inst.limbs[slot]
		if fitting.state == UnitInstance.LimbState.PROSTHETIC and fitting.prosthetic_item != null:
			_limb_prosthetics[slot] = _inventory.find(fitting.prosthetic_item)
		else:
			_limb_prosthetics[slot] = -1

	_dirty = false

# Order matters: stats before HP (they move its ceiling), inventory and armor before HP too (the
# clamp reads gear, #106), faction last so its repaint sees a finished unit.
func _apply(unit: Unit) -> void:
	var inst: UnitInstance = unit.unit_instance

	for stat in _stats:
		inst.stats[stat] = _stats[stat]
	inst.jobs = _jobs.duplicate()
	inst.affinity = _affinity.duplicate()
	inst.is_alkahest_affine = _alkahest
	inst.aura = _aura.duplicate()

	for slot in _limb_states:
		var fitting: UnitInstance.LimbFitting = inst.limbs[slot]
		var target_state: UnitInstance.LimbState = _limb_states[slot]
		var item_index: int = _limb_prosthetics.get(slot, -1)
		if target_state == UnitInstance.LimbState.PROSTHETIC and item_index >= 0:
			inst.install_prosthetic(slot, _inventory[item_index] as WeaponInstance)
		elif fitting.state != target_state or fitting.prosthetic_item != null:
			fitting.state = target_state
			fitting.prosthetic_stat = 0
			fitting.prosthetic_item = null

	for i in range(Unit.MAX_INVENTORY_SIZE):
		unit.inventory[i] = _inventory[i]
	# Dev tools stay omnipotent: this assigns directly, BYPASSING the equip/wear gates on purpose
	# so out-of-spec combos can be tested. The armor requirement is shown in the row label instead.
	unit.unequip_weapon()
	if _equipped_index >= 0 and _inventory[_equipped_index] is EquippableData:
		unit.set_equipped_weapon(_inventory[_equipped_index])
	if _armor_index >= 0:
		unit.worn_armor = _inventory[_armor_index] as ArmorData
	else:
		unit.worn_armor = null

	unit.set_current_hp(maxi(1, _current_hp))   # through the UNIT: only it can derive the ceiling
	inst.set_current_will(_current_will)

	if unit.get_faction() != _faction:
		unit.change_faction(_faction)
	unit.squad.squad_name = _squad_name
	var trimmed_name := _unit_name.strip_edges()
	if trimmed_name != "":
		unit.unit_data.display_name = trimmed_name
	elif _unit_name != unit.get_unit_name():
		push_warning("Unit editor: blank name ignored — keeping %s" % unit.get_unit_name())

	_dirty = false

func _on_save_pressed() -> void:
	if not is_instance_valid(editing_unit):
		return
	_apply(editing_unit)
	_capture(editing_unit)   # re-read: HP may have clamped against a max the edit just moved
	populate_unit_editor(editing_unit)

func _on_revert_pressed() -> void:
	if not is_instance_valid(editing_unit):
		return
	_capture(editing_unit)
	populate_unit_editor(editing_unit)

func _touch() -> void:
	_dirty = true
	_refresh_save_row()

func _refresh_save_row() -> void:
	if not is_instance_valid(_save_button):
		return
	_save_button.disabled = not _dirty
	_revert_button.disabled = not _dirty
	_save_button.text = "Save *" if _dirty else "Save"

# Top of the form on purpose: it is the only control that writes to the unit, so it has to stay
# reachable however far the sections below scroll.
func _add_save_row() -> void:
	var row := HBoxContainer.new()

	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.tooltip_text = "Write staged edits onto the unit"
	_save_button.pressed.connect(_on_save_pressed)
	row.add_child(_save_button)

	_revert_button = Button.new()
	_revert_button.text = "Revert"
	_revert_button.tooltip_text = "Throw staged edits away and re-read the unit"
	_revert_button.pressed.connect(_on_revert_pressed)
	row.add_child(_revert_button)

	unit_editor_container.add_child(row)
	_refresh_save_row()

func populate_unit_editor(unit):
	for child in unit_editor_container.get_children():
		unit_editor_container.remove_child(child)
		child.queue_free()
	_save_button = null
	_revert_button = null

	if unit == null or not is_instance_valid(unit):
		return

	DevWidgets.add_label(unit_editor_container, "Editing: " + unit.get_unit_name())
	_add_save_row()

	for stat in _stats:
		var key: Stats.Stat = stat
		DevWidgets.add_spinbox(unit_editor_container, Stats.Stat.keys()[key], _stats[key],
			func(v): _stage_stat(key, int(v)))
	DevWidgets.add_spinbox(unit_editor_container, "Current HP", _current_hp, func(v): _stage_hp(int(v)))
	DevWidgets.add_spinbox(unit_editor_container, "Current Will", _current_will, func(v): _stage_will(int(v)))
	DevWidgets.add_option(unit_editor_container, "Faction", Team.Faction.keys(), Team.Faction.keys()[_faction],
		func(s): _stage_faction(s))
	DevWidgets.add_lineedit(unit_editor_container, "Name", _unit_name, func(s): _stage_unit_name(s))
	DevWidgets.add_lineedit(unit_editor_container, "Squad Name", _squad_name, func(s): _stage_squad_name(s))
	
	_add_inventory_section()
	_add_jobs_section()
	_add_limbs_section(unit)
	_add_affinity_section()

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

	var down_button := Button.new()
	down_button.text = "Down Unit"
	down_button.tooltip_text = "Straight to downed — skips the ladder, so no Will spend, no maim, no Crisis"
	down_button.disabled = not unit.is_active()
	down_button.pressed.connect(func(): _down_unit(unit))
	unit_editor_container.add_child(down_button)

	var revive_button := Button.new()
	revive_button.text = "Revive Unit"
	revive_button.tooltip_text = "Stand a downed unit back up at 1 HP — the same call a rescue makes"
	revive_button.disabled = not unit.is_downed()
	revive_button.pressed.connect(func(): _revive_unit(unit))
	unit_editor_container.add_child(revive_button)

func _stage_stat(stat: Stats.Stat, value: int) -> void:
	_stats[stat] = value
	_touch()

func _stage_hp(value: int) -> void:
	_current_hp = maxi(1, value)
	_touch()

func _stage_will(value: int) -> void:
	_current_will = value
	_touch()

func _stage_faction(faction_name: String) -> void:
	_faction = Team.Faction[faction_name]
	_touch()

func _stage_squad_name(new_name: String) -> void:
	_squad_name = new_name
	_touch()
	
func _stage_unit_name(new_name: String) -> void:
	_unit_name = new_name
	_touch()

# Weapons, armor, and authored rune variants in one ordered list, so a unit can equip any of
# them. Built here and reused by both the picker and the pick handler so their indices stay in
# lockstep. #30 D.
func _equippable_catalog() -> Dictionary:
	var items := {}
	var weapons := WeaponCatalog.get_editable()
	for k in weapons:
		items[k] = weapons[k]
	var armors := ArmorCatalog.get_editable()
	for k in armors:
		items[k] = armors[k]
	var runes := RuneCatalog.get_editable()
	for k in runes:
		items[k] = runes[k]
	return items

func _add_inventory_section():
	DevWidgets.add_label(unit_editor_container, "Inventory")

	var weapons := _equippable_catalog()   # name -> EquippableData (weapons + authored runes)
	var weapon_keys := weapons.keys()
	var equip_group := ButtonGroup.new()

	for i in range(Unit.MAX_INVENTORY_SIZE):
		var slot_index := i
		var current_item = _inventory[slot_index]

		var row := HBoxContainer.new()

		var label := Label.new()
		label.text = "Slot %d" % (slot_index + 1)
		label.custom_minimum_size = Vector2(60, 0)
		row.add_child(label)

		var picker := OptionButton.new()
		picker.add_item("(empty)")
		for k in weapon_keys:
			picker.add_item(k)
		var sel := 0
		var matched := false
		if current_item != null:
			for k in range(weapon_keys.size()):
				if _entry_matches(weapons[weapon_keys[k]], current_item):
					sel = k + 1
					matched = true
					break
		picker.select(sel)
		picker.item_selected.connect(func(idx): _on_slot_picked(slot_index, idx))
		row.add_child(picker)

		if current_item != null and not matched:
			# Held item has no catalog match (e.g. a scenario-authored one-off weapon, #80) --
			# say so instead of leaving the picker stuck on a misleading "(empty)".
			var held_name: String = current_item.display_name
			if current_item is WeaponInstance:
				held_name = current_item.shown_name()
			var held_label := Label.new()
			held_label.text = "holds: %s" % held_name
			row.add_child(held_label)

		var is_armor := current_item is ArmorData
		var equip_btn := CheckBox.new()
		equip_btn.text = "Wear" if is_armor else "Equip"
		equip_btn.disabled = not (current_item is EquippableData)
		if is_armor:
			equip_btn.button_pressed = (slot_index == _armor_index)
			equip_btn.toggled.connect(func(pressed): _toggle_armor(slot_index, pressed))
		else:
			equip_btn.button_group = equip_group
			equip_btn.button_pressed = (current_item != null and slot_index == _equipped_index)
			equip_btn.toggled.connect(func(pressed): if pressed: _equip_slot(slot_index))
		row.add_child(equip_btn)

		if is_armor:
			var gate_label := Label.new()
			var gate: String = current_item.requirement_text()
			gate_label.text = "(%s)" % gate if gate != "" else "(no requirement)"
			row.add_child(gate_label)

		unit_editor_container.add_child(row)

func _toggle_armor(index: int, pressed: bool):
	if pressed:
		_armor_index = index
	elif _armor_index == index:
		_armor_index = -1
	_touch()
	populate_unit_editor(editing_unit)

func _entry_matches(entry, item) -> bool:
	# A template entry matches an instance built on it; saved instances / runes match by name.
	if entry is WeaponData and item is WeaponInstance:
		return item.template == entry
	if item is Item and entry is Item:
		return entry.display_name == item.display_name and item.display_name != ""
	return false

func _on_slot_picked(index: int, opt_index: int):
	if opt_index == 0:
		_set_slot(index, null)
	else:
		var items := _equippable_catalog()
		_set_slot(index, items[items.keys()[opt_index - 1]])

func _set_slot(index: int, entry: Resource):
	_inventory[index] = WeaponCatalog.instantiate_entry(entry) if entry != null else null
	if _equipped_index == index:
		_equipped_index = -1
	if _armor_index == index:
		_armor_index = -1
	for slot in _limb_prosthetics.keys():
		if _limb_prosthetics[slot] == index:
			_limb_prosthetics.erase(slot)   # the item that filled this limb just changed under it

	# Auto-equip into an empty weapon slot, but never armor -- that has its own Wear checkbox.
	if _inventory[index] is EquippableData and not (_inventory[index] is ArmorData) and _equipped_index == -1:
		_equipped_index = index
	_touch()
	populate_unit_editor(editing_unit)

func _equip_slot(index: int):
	if _inventory[index] is EquippableData:
		_equipped_index = index
	_touch()
	populate_unit_editor(editing_unit)

func _add_jobs_section():
	DevWidgets.add_label(unit_editor_container, "Jobs")

	var jobs := JobCatalog.get_editable()   # display_name -> JobData

	for job_id in _jobs:
		var id: String = job_id
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = _display_name_for(jobs, id)
		row.add_child(label)

		var remove_button := Button.new()
		remove_button.text = "Remove"
		remove_button.pressed.connect(func(): _remove_job(id))
		row.add_child(remove_button)

		unit_editor_container.add_child(row)

	_add_job_picker(jobs)

func _add_job_picker(jobs: Dictionary):
	var available: Array[String] = []
	for display_name in jobs:
		if not _jobs.has(jobs[display_name].id):
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
	button.pressed.connect(func(): _add_job(jobs[available[picker.selected]].id))
	row.add_child(button)

	unit_editor_container.add_child(row)

func _add_job(id: String) -> void:
	if not _jobs.has(id):
		_jobs.append(id)
	_touch()
	populate_unit_editor(editing_unit)

func _remove_job(id: String) -> void:
	_jobs.erase(id)
	_touch()
	populate_unit_editor(editing_unit)

func _display_name_for(jobs: Dictionary, id: String) -> String:
	for display_name in jobs:
		if jobs[display_name].id == id:
			return display_name
	return id   # catalog miss (shouldn't happen) — show the raw id rather than hiding it

func _add_limbs_section(unit: Unit):
	DevWidgets.add_label(unit_editor_container, "Limbs")

	var slot_names := UnitInstance.LimbSlot.keys()
	var state_names := UnitInstance.LimbState.keys()

	for slot in UnitInstance.LimbSlot.values():
		var key: UnitInstance.LimbSlot = slot
		DevWidgets.add_option(unit_editor_container, slot_names[key], state_names, state_names[_limb_states[key]],
			func(s): _on_limb_state_picked(key, s))
		if _limb_states[key] == UnitInstance.LimbState.PROSTHETIC:
			_add_limb_item_picker(key)

	# Derived through Unit (gear + effects), which the staging buffer deliberately doesn't model,
	# so these show what the unit IS, not what's staged.
	DevWidgets.add_label(unit_editor_container, "MOV: %d (saved)" % unit.get_mov())
	DevWidgets.add_label(unit_editor_container, "Effective STR: %d   DEX: %d (saved)" % [
		unit.get_effective_stat(Stats.Stat.STR), unit.get_effective_stat(Stats.Stat.DEX)])

func _on_limb_state_picked(slot: UnitInstance.LimbSlot, state_name: String):
	_limb_states[slot] = UnitInstance.LimbState[state_name]
	_touch()
	populate_unit_editor(editing_unit)

# Which carried item fills a PROSTHETIC slot -- candidates filtered to the same limb_kind gate
# install_prosthetic() enforces, so this list can never offer an item Save would then refuse.
func _add_limb_item_picker(slot: UnitInstance.LimbSlot):
	var candidates: Array[int] = []
	for i in range(_inventory.size()):
		var item := _inventory[i] as WeaponInstance
		if item != null and UnitInstance.can_install_as_prosthetic(slot, item):
			candidates.append(i)

	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "  -> item"
	row.add_child(label)

	var picker := OptionButton.new()
	picker.add_item("(placeholder -- no item)")
	for idx in candidates:
		picker.add_item("Slot %d: %s" % [idx + 1, (_inventory[idx] as WeaponInstance).shown_name()])
	var current: int = _limb_prosthetics.get(slot, -1)
	picker.select(candidates.find(current) + 1)   # -1 (placeholder) or not-found both land on 0
	picker.item_selected.connect(func(opt_index): _on_limb_item_picked(slot, opt_index, candidates))
	row.add_child(picker)

	unit_editor_container.add_child(row)

func _on_limb_item_picked(slot: UnitInstance.LimbSlot, opt_index: int, candidates: Array[int]):
	_limb_prosthetics[slot] = candidates[opt_index - 1] if opt_index > 0 else -1
	_touch()

func _add_affinity_section():
	DevWidgets.add_label(unit_editor_container, "Affinity")

	for element in Elemental.SIGIL_ELEMENTS:
		var e: Elemental.Element = element
		DevWidgets.add_checkbox(unit_editor_container, Elemental.Element.keys()[e], _affinity.has(e),
			func(pressed): _on_affinity_toggled(e, pressed))

	DevWidgets.add_checkbox(unit_editor_container, "Alkahest affine (hidden — Isaac only)", _alkahest,
		func(pressed): _stage_alkahest(pressed))

	var primary: Elemental.Element = _affinity[0] if not _affinity.is_empty() else Elemental.Element.NONE
	DevWidgets.add_label(unit_editor_container, "Primary: %s" % (Elemental.Element.keys()[primary] if primary != Elemental.Element.NONE else "(none — Rebecca)"))

	DevWidgets.add_label(unit_editor_container, "Aura")
	for element in Elemental.SIGIL_ELEMENTS:
		var e: Elemental.Element = element
		if _affinity.has(e):
			DevWidgets.add_spinbox(unit_editor_container, Elemental.Element.keys()[e], _aura.get(e, 0),
				func(v): _stage_aura(e, int(v)))
		else:
			DevWidgets.add_label(unit_editor_container, "%s: — (no affinity)" % Elemental.Element.keys()[e])

func _on_affinity_toggled(element: Elemental.Element, pressed: bool):
	if pressed:
		if not _affinity.has(element):
			_affinity.append(element)
	else:
		_affinity.erase(element)
		_aura.erase(element)   # can't hold aura outside affinity — Rebecca rule guard
	_touch()
	populate_unit_editor(editing_unit)

func _stage_alkahest(pressed: bool) -> void:
	_alkahest = pressed
	_touch()

func _stage_aura(element: Elemental.Element, value: int) -> void:
	_aura[element] = value
	_touch()

func _delete_unit(unit: Unit):
	if is_instance_valid(unit):
		unit.die()
	editing_unit = null
	_dirty = false
	populate_unit_editor(null)

# Ejection is DEFERRED to the end of a resolution pass (#103), and a button press has no pass to
# defer to -- so drain the queue went_downed just filled. That is the same drain execute_orders
# runs, not a third copy of what settling a down means.
func _down_unit(unit: Unit) -> void:
	if game == null or not is_instance_valid(unit) or not unit.is_active():
		return
	unit.force_down()
	game.order_executor._process_downed_pending()
	_resync(unit)

func _revive_unit(unit: Unit) -> void:
	if game == null or not is_instance_valid(unit) or not unit.is_downed():
		return
	unit.revive()   # the same call RescueAction makes; the body keeps its solo squad
	game.refresh_action_queue(game.squad_manager.active_squad)   # a rescue aimed here just went invalid
	_resync(unit)

# The unit moved underneath the staged buffer, so re-read it -- the trade Revert already makes.
# Skipping it would leave the panel showing pre-down HP, and a later Save would write it back.
func _resync(unit: Unit) -> void:
	if _dirty:
		push_warning("Unit editor: discarded unsaved changes to %s" % unit.get_unit_name())
	_capture(unit)
	populate_unit_editor(unit)

func _arm_move() -> void:
	if game != null and is_instance_valid(editing_unit):
		game.dev_controller.arm_move(editing_unit)

func _arm_duplicate() -> void:
	if game != null and is_instance_valid(editing_unit):
		game.dev_controller.arm_duplicate(editing_unit)
