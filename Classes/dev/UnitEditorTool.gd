extends MarginContainer
class_name UnitEditorTool

# Dev-only unit editor: the tab (in DevOverlay) for editing whichever unit is currently
# selected — stats, inventory, squad, and job assignment. Never shown to a player.
# Laid out as three sub-tabs (Stats / Gear & Jobs / Body & Affinity) between an always-visible
# header+Save row and the action buttons (2026-08-11 dev ask; the two re-seed ones joined in #589).
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
var _active_subtab := 0   # survives the full-panel repaint every staged toggle triggers
var _page_scroll := 0     # ditto for the active page's scroll -- a rebuild resets it to the top

var _header: ScenarioHeader

func init(p_game, header: ScenarioHeader = null):
	game = p_game
	_header = header

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

# Through the window's one door (#382), so the click-a-unit jump also moves the TREE selection --
# writing current_tab raw would leave the tree pointing at the leaf you left.
func _show_self():
	game.dev_overlay.show_leaf(self)

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
	# The unit is board-local now (#259 rework): an authored save snapshots it instead of
	# re-referencing its character file, and the scenario header owes the dev a (modified).
	editing_unit.dev_edited = true
	if _header != null:
		_header.mark_modified()
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
	# The header lights the moment ANYTHING is staged (#259 rework round 2): the dev reads Update's
	# marker as "is there something to save", and staged edits ARE -- the header's capture flushes
	# them (flush_staged) so Update always writes exactly what this panel shows. Known corner:
	# stage-then-Revert leaves a stale (modified) until the next save clears it -- a nuisance,
	# never a lost edit.
	if _header != null:
		_header.mark_modified()


# Apply whatever is staged, as the header's save is about to capture the board -- the capturing
# signal's one listener (routed by DevOverlay, the file_changed pattern in reverse). Without this,
# an Update taken mid-edit would save a board that disagrees with the panel on screen.
func flush_staged() -> void:
	if _dirty and is_instance_valid(editing_unit):
		_on_save_pressed()

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
	var old_tabs: TabContainer = unit_editor_container.get_node_or_null("SubTabs")
	if old_tabs != null:
		_active_subtab = old_tabs.current_tab
		var old_page := old_tabs.get_tab_control(_active_subtab) as ScrollContainer
		if old_page != null:
			_page_scroll = old_page.scroll_vertical
	for child in unit_editor_container.get_children():
		unit_editor_container.remove_child(child)
		child.queue_free()
	_save_button = null
	_revert_button = null

	if unit == null or not is_instance_valid(unit):
		return

	DevWidgets.add_label(unit_editor_container, "Editing: " + unit.get_unit_name())
	_add_save_row()

	# The editing fields split across sub-tabs; the header, Save row and action buttons stay
	# DIRECT children of unit_editor_container -- the dev sees them from any tab, and the test
	# suites find them by a flat child scan.
	var tabs := TabContainer.new()
	tabs.name = "SubTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	unit_editor_container.add_child(tabs)

	_add_stats_section(_add_subtab(tabs, "Stats"))

	var gear_page := _add_subtab(tabs, "Gear & Jobs")
	_add_inventory_section(gear_page)
	_add_jobs_section(gear_page)
	_add_abilities_section(gear_page, unit)

	var body_page := _add_subtab(tabs, "Body & Affinity")
	_add_limbs_section(body_page, unit)
	_add_affinity_section(body_page)
	_add_element_state_section(body_page, unit)

	tabs.current_tab = clampi(_active_subtab, 0, tabs.get_tab_count() - 1)
	var page := tabs.get_tab_control(tabs.current_tab) as ScrollContainer
	if page != null:
		# Deferred: a freshly built ScrollContainer has no range until layout settles, and an
		# immediate write clamps to 0 -- the reported "scrollbar jumps away" (2026-08-11).
		page.set_deferred("scroll_vertical", _page_scroll)

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

	# The gear a unit is HOLDING is a copy made at spawn (#589), so an Item Editor fitting or a new
	# starting_inventory entry reaches it only by re-granting. The refusal is the unit's own words.
	var reseed_button := Button.new()
	reseed_button.text = "Re-seed Kit"
	var reason: String = unit.reseed_block_reason()   # `unit` is untyped here, so no inference
	reseed_button.disabled = reason != ""
	reseed_button.tooltip_text = reason if reason != "" else \
		"Throw this unit's gear away and re-grant it from its character file — picks up mods fitted and weapons added since it spawned. Ammo, rev and spring load reset."
	reseed_button.pressed.connect(func(): _reseed_unit(unit))
	unit_editor_container.add_child(reseed_button)

	var reseed_all_button := Button.new()
	reseed_all_button.text = "Re-seed All Kits"
	reseed_all_button.tooltip_text = "Re-seed every unit on the board that came from a character file. Units built in the Spawn form, or embedded in the scenario, are skipped."
	reseed_all_button.pressed.connect(_reseed_board)
	unit_editor_container.add_child(reseed_all_button)

func _add_subtab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title   # TabContainer reads the tab title off the child's node name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	tabs.add_child(scroll)
	return page

# The stat grid mirrors the inspect panel's StatsGrid shape (columns = 4: two name+field pairs
# per visual row), with SpinBoxes as the value cells.
func _add_stats_section(page: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	page.add_child(grid)

	for stat in _stats:
		var key: Stats.Stat = stat
		_add_grid_spinbox(grid, Stats.Stat.keys()[key], _stats[key], func(v): _stage_stat(key, int(v)))
	_add_grid_spinbox(grid, "Current HP", _current_hp, func(v): _stage_hp(int(v)))
	_add_grid_spinbox(grid, "Current Will", _current_will, func(v): _stage_will(int(v)))

	DevWidgets.add_option(page, "Faction", Team.Faction.keys(), Team.Faction.keys()[_faction],
		func(s): _stage_faction(s))
	DevWidgets.add_lineedit(page, "Name", _unit_name, func(s): _stage_unit_name(s))
	DevWidgets.add_lineedit(page, "Squad Name", _squad_name, func(s): _stage_squad_name(s))

func _add_grid_spinbox(grid: GridContainer, label_text: String, value: int, on_change: Callable) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = -999
	spin.max_value = 999
	spin.value = value
	spin.value_changed.connect(on_change)
	grid.add_child(spin)

# Read-only: abilities derive from jobs (JobData.ability_pool), so a listing is the honest
# control. "(saved)" per the limbs convention -- this reads the live unit, not the staged jobs.
func _add_abilities_section(page: VBoxContainer, unit: Unit) -> void:
	DevWidgets.add_label(page, "Abilities (saved)")
	var live: Array[AbilityData] = unit.get_live_abilities()
	if live.is_empty():
		DevWidgets.add_label(page, "  (none)")
		return
	for ability in live:
		var a: AbilityData = ability
		var kind_name: String = AbilityData.AbilityKind.keys()[a.kind].capitalize()
		DevWidgets.add_label(page, "  %s  (%s)" % [a.display_name, kind_name])

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
# Everything a unit can be given, by display name. NOT equippables only since #697 -- a vial is
# CARRIED and never slotted, and leaving it out made the four authored ones unreachable from any
# editor. The Equip/Wear checkbox beside each slot already reads `is EquippableData` and greys
# itself, so a carried non-equippable needs nothing else here.
func _item_catalog() -> Dictionary:
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
	var vials := VialCatalog.get_editable()
	for k in vials:
		items[k] = vials[k]
	return items

func _add_inventory_section(into: VBoxContainer):
	DevWidgets.add_label(into, "Inventory")

	var weapons := _item_catalog()   # name -> Item (weapons, armor, runes, vials)
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

		into.add_child(row)

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
		var items := _item_catalog()
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

func _add_jobs_section(into: VBoxContainer):
	DevWidgets.add_label(into, "Jobs")

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

		into.add_child(row)

	_add_job_picker(into, jobs)

func _add_job_picker(into: VBoxContainer, jobs: Dictionary):
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

	into.add_child(row)

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

func _add_limbs_section(into: VBoxContainer, unit: Unit):
	DevWidgets.add_label(into, "Limbs")

	var slot_names := UnitInstance.LimbSlot.keys()
	var state_names := UnitInstance.LimbState.keys()

	for slot in UnitInstance.LimbSlot.values():
		var key: UnitInstance.LimbSlot = slot
		DevWidgets.add_option(into, slot_names[key], state_names, state_names[_limb_states[key]],
			func(s): _on_limb_state_picked(key, s))
		if _limb_states[key] == UnitInstance.LimbState.PROSTHETIC:
			_add_limb_item_picker(into, key)

	# Derived through Unit (gear + effects), which the staging buffer deliberately doesn't model,
	# so these show what the unit IS, not what's staged.
	DevWidgets.add_label(into, "MOV: %d (saved)" % unit.get_mov())
	DevWidgets.add_label(into, "Effective STR: %d   DEX: %d (saved)" % [
		unit.get_effective_stat(Stats.Stat.STR), unit.get_effective_stat(Stats.Stat.DEX)])

func _on_limb_state_picked(slot: UnitInstance.LimbSlot, state_name: String):
	_limb_states[slot] = UnitInstance.LimbState[state_name]
	_touch()
	populate_unit_editor(editing_unit)

# Which carried item fills a PROSTHETIC slot -- candidates filtered to the same limb_kind gate
# install_prosthetic() enforces, so this list can never offer an item Save would then refuse.
func _add_limb_item_picker(into: VBoxContainer, slot: UnitInstance.LimbSlot):
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

	into.add_child(row)

func _on_limb_item_picked(slot: UnitInstance.LimbSlot, opt_index: int, candidates: Array[int]):
	_limb_prosthetics[slot] = candidates[opt_index - 1] if opt_index > 0 else -1
	_touch()

# One row per sigil element: the affinity checkbox and its aura pool together (condensed from two
# separate lists, dev ask 2026-08-11). The spinbox only exists while the affinity is held;
# unchecking still erases the aura through _on_affinity_toggled, exactly as before.
func _add_affinity_section(into: VBoxContainer):
	DevWidgets.add_label(into, "Affinity / Aura")

	for element in Elemental.SIGIL_ELEMENTS:
		var e: Elemental.Element = element
		var row := HBoxContainer.new()
		var box := CheckBox.new()
		box.text = Elemental.Element.keys()[e]
		box.button_pressed = _affinity.has(e)
		box.toggled.connect(func(pressed: bool): _on_affinity_toggled(e, pressed))
		row.add_child(box)
		if _affinity.has(e):
			var spin := SpinBox.new()
			spin.min_value = -999
			spin.max_value = 999
			spin.value = _aura.get(e, 0)
			spin.tooltip_text = "Aura points"
			spin.value_changed.connect(func(v): _stage_aura(e, int(v)))
			row.add_child(spin)
		into.add_child(row)

	DevWidgets.add_checkbox(into, "Alkahest affine (hidden — Isaac only)", _alkahest,
		func(pressed): _stage_alkahest(pressed))

	var primary: Elemental.Element = _affinity[0] if not _affinity.is_empty() else Elemental.Element.NONE
	DevWidgets.add_label(into, "Primary: %s" % (Elemental.Element.keys()[primary] if primary != Elemental.Element.NONE else "(none — Rebecca)"))

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

# Live element states (#174): IMMEDIATE writes to the transient Unit -- the Down/Revive pattern,
# not the staged buffer above. Battle-scoped test setup (soak, then fire SHOCK); never saved here.
func _add_element_state_section(into: VBoxContainer, unit: Unit) -> void:
	DevWidgets.add_label(into, "Element States (live)")
	for i in Elemental.State.size():
		var state: Elemental.State = Elemental.State.values()[i]
		if state == Elemental.State.NONE:
			continue
		var state_name: String = Elemental.State.keys()[i]
		DevWidgets.add_checkbox(into, state_name.capitalize(), unit.element_states.has(state),
			func(pressed: bool): _on_element_state_toggled(unit, state, pressed),
			"Applies to the live unit immediately -- no Save needed; a reaction can still consume it")

# A LIVE write skips the staged Save entirely, so it marks here (#259 rework round 2 -- the edit
# sweep): the header lights, and the unit diverges (dev_edited) when the write is unit state a
# snapshot carries -- an authored Update must not re-reference it away.
func _mark_live_edit(unit: Unit, diverges: bool) -> void:
	if diverges and is_instance_valid(unit):
		unit.dev_edited = true
	if _header != null:
		_header.mark_modified()

func _on_element_state_toggled(unit: Unit, state: Elemental.State, pressed: bool) -> void:
	if not is_instance_valid(unit):
		return
	if pressed:
		unit.add_element_state(state)
	else:
		unit.remove_element_state(state)
	_mark_live_edit(unit, true)

func _delete_unit(unit: Unit):
	if is_instance_valid(unit):
		unit.die()
	editing_unit = null
	_dirty = false
	_mark_live_edit(null, false)   # the roster changed; nothing left to diverge
	populate_unit_editor(null)

# Ejection is DEFERRED to the end of a resolution pass (#103), and a button press has no pass to
# defer to -- so drain the queue went_downed just filled. That is the same drain execute_orders
# runs, not a third copy of what settling a down means.
func _down_unit(unit: Unit) -> void:
	if game == null or not is_instance_valid(unit) or not unit.is_active():
		return
	unit.force_down()
	game.order_executor._process_downed_pending()
	_mark_live_edit(unit, true)
	_resync(unit)

func _revive_unit(unit: Unit) -> void:
	if game == null or not is_instance_valid(unit) or not unit.is_downed():
		return
	unit.revive()   # the same call RescueAction makes; the body keeps its solo squad
	game.refresh_action_queue(game.squad_manager.active_squad)   # a rescue aimed here just went invalid
	_mark_live_edit(unit, true)
	_resync(unit)

# Re-grant from the character file. Marks the unit dev_edited for the same reason Save does: its
# gear no longer matches what a re-reference would load, so an authored save has to snapshot it.
func _reseed_unit(unit: Unit) -> void:
	if not is_instance_valid(unit) or not unit.reseed_kit():
		return
	_mark_live_edit(unit, true)
	_resync(unit)

# The board sweep. Reports rather than refuses -- a board is normally a MIX, and "3 of 7" is the
# useful answer, not a refusal naming the four it skipped.
func _reseed_board() -> void:
	if game == null:
		return
	var done := 0
	var units: Array = game._all_units()
	for unit: Unit in units:
		if unit.can_reseed_kit() and unit.reseed_kit():
			unit.dev_edited = true
			done += 1
	if _header != null:
		_header.mark_modified()
	print("Re-seeded %d of %d units from their character files" % [done, units.size()])
	if is_instance_valid(editing_unit):
		_resync(editing_unit)

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
