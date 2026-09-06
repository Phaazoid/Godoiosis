extends MarginContainer
class_name CharacterEditorTool

# Dev-only character editor (#179): authors the standalone UnitData files under Resources/Units/
# -- the cast (#177). An authored save REFERENCES those files, so Update rewrites the character
# in every mission that references it; the file IS the character. Load/Update/Delete/Save As
# ride the Item Editor's pool chrome; Capture stages the live unit selected in the Unit Editor
# tab as a new character. Kit slots stage catalog FILE resources, so saves write ExtResource
# references (UnitData's own authoring guidance) and a path-less entry is called out as inline
# rather than silently embedded.

const KEEP_LABEL := "(keep current)"
const PORTRAIT_DIR := "res://Art/Units/Portraits/"

@onready var editor_container := %CharacterEditorVbox
@onready var load_dropdown: OptionButton = %CharacterLoadDropdown
@onready var name_input: LineEdit = %CharacterNameInput
@onready var update_button: Button = %UpdateCharacterButton
@onready var delete_button: Button = %DeleteCharacterButton
@onready var status_label: Label = %CharacterStatusLabel

var current: UnitData = null
var _items := {}
# Which catalog entry current was loaded from ("" = a New character). Load stages a COPY with no
# resource_path, so nothing else records this -- and Update's load-gate needs it.
var _loaded_name := ""

func _ready():
	_refresh_list()
	_on_new_pressed()

func _refresh_list(select_name := ""):
	load_dropdown.clear()
	_items = UnitCatalog.get_characters()
	for k in _items:
		load_dropdown.add_item(k)

	# add_item auto-selects index 0 -- Update must never aim at an entry nobody picked.
	load_dropdown.select(-1)
	for i in load_dropdown.item_count:
		if load_dropdown.get_item_text(i) == select_name:
			load_dropdown.select(i)
			break
	_refresh_buttons()

func _refresh_buttons():
	DevWidgets.refresh_update_button(update_button, DevWidgets.selected_name(load_dropdown), "character", _update_block_reason())
	DevWidgets.refresh_delete_button(delete_button, DevWidgets.selected_name(load_dropdown), "character")

# "" = allowed. Update only overwrites the character that is actually LOADED (#166 shape) -- and
# here an overwrite reaches every mission referencing the file, the blast radius that made the
# gate a rule in the first place.
func _update_block_reason() -> String:
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "" or target == _loaded_name:
		return ""
	return "Load '%s' first -- Update overwrites it with whatever is in the editor" % target

func _on_load_dropdown_item_selected(_index: int):
	_refresh_buttons()

func _on_new_pressed():
	current = UnitData.new()
	_loaded_name = ""
	name_input.text = ""
	status_label.text = ""
	load_dropdown.select(-1)
	_refresh_buttons()
	populate()

func _on_load_pressed():
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "" or not _items.has(target):
		return
	# duplicate(true) deep-copies the typed dicts (staged edits can't write through the resource
	# cache) while path'd sub-resources -- textures, catalog kit entries -- stay SHARED and
	# re-save as ExtResource. Safe only while the form swaps whole slots and never edits an
	# item's internals; re-verify if in-place item editing is ever added here.
	var picked: UnitData = _items[target]
	current = picked.duplicate(true)
	_loaded_name = target
	name_input.text = ""
	_refresh_buttons()
	status_label.text = _load_notes()
	populate()

# The spawn path silently drops aura held outside affinity (the Rebecca rule, enforced in
# UnitInstance.initialize) -- surfaced at load instead, where it can actually be fixed.
func _load_notes() -> String:
	var outside: Array[String] = []
	for element in current.base_aura:
		if not current.base_affinity.has(element):
			outside.append(Elemental.Element.keys()[element])
	if outside.is_empty():
		return ""
	return "Aura in %s sits outside affinity and drops at spawn -- check the affinity box or zero it" % ", ".join(outside)

func _on_update_pressed():
	var target := DevWidgets.selected_name(load_dropdown)
	if current == null or target == "":
		return
	# The handler is the real gate -- the disabled button is only its surface (#166 shape).
	var reason := _update_block_reason()
	if reason != "":
		status_label.text = reason
		return
	# Overwrite the file the entry actually came from -- a path rebuilt from the dropdown key
	# would miss any file whose basename differs from the display name.
	var path: String = _items[target].resource_path
	if path == "":
		var msg := "%s has no file on disk to update" % target
		push_warning(msg)
		status_label.text = msg
		return
	# Confirmed as well as load-gated (#380's convention): the gate cannot catch a mis-click at
	# the character you DID load.
	DevWidgets.confirm_overwrite(self, "character '%s'" % target, "the editor's values",
		func() -> void: _update_confirmed(path))


func _update_confirmed(path: String) -> void:
	_trim_kit()
	if DevWidgets.save_over(current, path, status_label):
		_loaded_name = current.display_name   # a rename moves the loaded identity with it
		_refresh_list(current.display_name)
		_note_missing_art()

func _on_delete_pressed():
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "":
		return
	DevWidgets.confirm_delete(self, "character '%s'" % target, func(): _delete_confirmed(target))

func _delete_confirmed(target: String) -> void:
	if not _items.has(target):
		return   # catalog moved between the press and the Yes
	if DevWidgets.delete_saved_file(_items[target].resource_path, "character", status_label):
		if target == _loaded_name:
			_loaded_name = ""
		_refresh_list()

func _on_save_as_pressed():
	if current == null:
		return
	var entered_name := name_input.text.strip_edges()
	if entered_name == "":
		var msg := "Character needs a name to save"
		push_warning(msg)
		status_label.text = msg
		return
	if DevWidgets.refuse_illegal_name(entered_name, "character", status_label):
		return
	var path := UnitCatalog.CHARACTER_DIR + entered_name + ".tres"
	if DevWidgets.refuse_existing_file(path, "character", status_label):
		return
	current.display_name = entered_name
	_trim_kit()
	if DevWidgets.save_over(current, path, status_label):
		_loaded_name = entered_name   # save_over take_over_path'd it: the editor now holds this file
		name_input.text = ""
		_refresh_list(entered_name)
		_note_missing_art()
		populate()   # the display-name field changed underneath the form

# Trailing empty slots are form scaffolding, not content -- trimmed so an all-empty kit reads as
# NO kit (has_starting_kit checks emptiness) and files stay minimal. Only trailing nulls go, so
# every equip/wear/prosthetic index keeps its meaning.
func _trim_kit() -> void:
	while not current.starting_inventory.is_empty() and current.starting_inventory.back() == null:
		current.starting_inventory.pop_back()

func _note_missing_art() -> void:
	if current.map_sprite == null:
		status_label.text = "Saved, but no map sprite is set -- the unit will be invisible on the board"

# Stage the live unit selected in the Unit Editor tab (dev-mode click) as a character. Identity
# comes off unit.unit_data; carried state rides ScenarioUnitEntry.capture_unit_state -- the one
# compaction of a unit into a dense inventory + indices (Law #4) -- projected onto the kit block.
# Staged only: name it and press Save As.
func _on_capture_pressed():
	var unit_editor: UnitEditorTool = get_node("%Unit Editor")
	if not is_instance_valid(unit_editor.editing_unit):
		status_label.text = "No unit selected -- click one on the board in dev mode first"
		return
	var unit: Unit = unit_editor.editing_unit

	var data := UnitData.new()
	var source: UnitData = unit.unit_data
	data.display_name = source.display_name
	data.portrait = source.portrait
	data.map_sprite = source.map_sprite
	data.move_sprite = source.move_sprite
	data.downed_sprite = source.downed_sprite
	data.faction = unit.get_faction()
	data.innate_abilities = source.innate_abilities.duplicate()

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(unit)
	data.base_stats = entry.stats
	data.base_aura = entry.aura
	data.base_affinity = entry.affinity
	data.base_is_alkahest_affine = entry.is_alkahest_affine
	data.starting_jobs = entry.jobs
	data.starting_inventory = entry.inventory
	data.starting_equipped_index = entry.equipped_index
	data.starting_worn_index = entry.worn_armor_index
	data.starting_proficiency = entry.weapon_proficiency
	data.starting_prosthetics = entry.limb_prosthetic_items

	current = data
	_loaded_name = ""
	load_dropdown.select(-1)
	if name_input.text.strip_edges() == "":
		name_input.text = data.display_name
	_refresh_buttons()
	status_label.text = _capture_notes(unit, entry)
	populate()

# What a character FILE cannot represent out of what the snapshot caught -- said out loud, never
# silently dropped.
func _capture_notes(unit: Unit, entry: ScenarioUnitEntry) -> String:
	var notes: Array[String] = []
	var carried := 0
	for item in entry.inventory:
		if item != null:
			carried += 1
	if carried > 0:
		notes.append("%d carried item(s) embed inline on save; re-pick slots from the catalogs to reference Item Editor files" % carried)
	if entry.inventory.size() > Unit.MAX_INVENTORY_SIZE:
		notes.append("%d items exceed the %d-slot kit and drop at spawn" % [entry.inventory.size(), Unit.MAX_INVENTORY_SIZE])
	if entry.equipped_index == -1 and _kit_has_weapon(entry.inventory):
		notes.append("was unarmed, but a kit auto-equips the first weapon at spawn")
	for limb_slot in entry.limb_states:
		var state: UnitInstance.LimbState = entry.limb_states[limb_slot]
		if state != UnitInstance.LimbState.NATURAL and not entry.limb_prosthetic_items.has(limb_slot):
			notes.append("%s is %s -- a character file can't carry limb state, so it spawns whole" % [
				UnitInstance.LimbSlot.keys()[limb_slot], UnitInstance.LimbState.keys()[state]])
	var msg := "Captured %s -- name it and press Save As" % unit.get_unit_name()
	if not notes.is_empty():
		msg += ". Note: " + "; ".join(notes)
	return msg

func _kit_has_weapon(inventory: Array[EquippableData]) -> bool:
	for item in inventory:
		if item != null and not (item is ArmorData):
			return true
	return false

# ==============================================================================
#  The form
# ==============================================================================

func populate():
	for child in editor_container.get_children():
		editor_container.remove_child(child)
		child.queue_free()
	if current == null:
		return
	var edited := current
	DevWidgets.add_lineedit(editor_container, "Display name", edited.display_name, func(s: String): edited.display_name = s)
	DevWidgets.add_option(editor_container, "Faction", Team.Faction.keys(), Team.Faction.keys()[edited.faction],
		func(s: String): edited.faction = Team.Faction[s])
	_add_art_section()
	_add_stats_section()
	_add_affinity_section()
	_add_abilities_section()
	_add_jobs_section()
	_add_kit_section()
	_add_prosthetics_section()
	_add_proficiency_section()

# Map sprites come as idle/moving/downed triples off SpawnTool's one folder scan (Law #4);
# portraits are this tool's own flat scan. "(keep current)" is a no-op, never a clear -- there
# is no legitimate reason to author a sprite-less character.
func _add_art_section() -> void:
	var sprites := SpawnTool.build_sprite_catalog()
	var current_sprite := KEEP_LABEL
	for sprite_name in sprites:
		if sprites[sprite_name]["idle"] == current.map_sprite:
			current_sprite = sprite_name
			break
	var sprite_options: Array = [KEEP_LABEL]
	sprite_options.append_array(sprites.keys())
	DevWidgets.add_option(editor_container, "Map sprite", sprite_options, current_sprite,
		func(label: String): _on_sprite_picked(sprites, label))

	var portraits := _portrait_catalog()
	var current_portrait := KEEP_LABEL
	for portrait_name in portraits:
		if portraits[portrait_name] == current.portrait:
			current_portrait = portrait_name
			break
	var portrait_options: Array = [KEEP_LABEL]
	portrait_options.append_array(portraits.keys())
	DevWidgets.add_option(editor_container, "Portrait", portrait_options, current_portrait,
		func(label: String): _on_portrait_picked(portraits, label))

func _on_sprite_picked(sprites: Dictionary, label: String) -> void:
	if not sprites.has(label):
		return   # "(keep current)"
	var triple: Dictionary = sprites[label]
	current.map_sprite = triple["idle"]
	current.move_sprite = triple["moving"]
	current.downed_sprite = triple["downed"]

func _on_portrait_picked(portraits: Dictionary, label: String) -> void:
	if portraits.has(label):
		current.portrait = portraits[label]

func _portrait_catalog() -> Dictionary:
	var portraits := {}
	for file in ResourceDir.files_with_extension(PORTRAIT_DIR, ".png"):
		portraits[file.get_basename()] = load(PORTRAIT_DIR + file)
	return portraits

# Sparse on purpose: a stat the dev never touches stays unauthored and keeps reading its default.
func _add_stats_section() -> void:
	DevWidgets.add_label(editor_container, "Base stats")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	editor_container.add_child(grid)
	for stat in Stats.STAT_DEFAULTS:
		var key: Stats.Stat = stat
		var label := Label.new()
		label.text = Stats.Stat.keys()[key]
		grid.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = -999
		spin.max_value = 999
		spin.value = current.base_stats.get(key, Stats.STAT_DEFAULTS[key])
		spin.value_changed.connect(func(v): current.base_stats[key] = int(v))
		grid.add_child(spin)

# The Unit Editor's affinity/aura row shape: the aura spinbox only exists while the affinity is
# held, and unchecking erases the aura -- the Rebecca-rule guard, which is what makes the
# illegal aura the shipped cast files carry unauthorable here.
func _add_affinity_section() -> void:
	DevWidgets.add_label(editor_container, "Affinity / Aura")
	for element in Elemental.SIGIL_ELEMENTS:
		var e: Elemental.Element = element
		var row := HBoxContainer.new()
		var box := CheckBox.new()
		box.text = Elemental.Element.keys()[e]
		box.button_pressed = current.base_affinity.has(e)
		box.toggled.connect(func(pressed: bool): _on_affinity_toggled(e, pressed))
		row.add_child(box)
		if current.base_affinity.has(e):
			var spin := SpinBox.new()
			spin.min_value = -999
			spin.max_value = 999
			spin.value = current.base_aura.get(e, 0)
			spin.tooltip_text = "Aura points"
			spin.value_changed.connect(func(v): current.base_aura[e] = int(v))
			row.add_child(spin)
		editor_container.add_child(row)
	DevWidgets.add_checkbox(editor_container, "Alkahest affine (hidden -- Isaac only)", current.base_is_alkahest_affine,
		func(pressed: bool): current.base_is_alkahest_affine = pressed)

func _on_affinity_toggled(element: Elemental.Element, pressed: bool) -> void:
	if pressed:
		if not current.base_affinity.has(element):
			current.base_affinity.append(element)
	else:
		current.base_affinity.erase(element)
		current.base_aura.erase(element)   # can't hold aura outside affinity -- Rebecca rule guard
	populate()

func _add_abilities_section() -> void:
	DevWidgets.add_label(editor_container, "Innate abilities")
	var abilities := AbilityCatalog.get_abilities()
	if abilities.is_empty():
		DevWidgets.add_label(editor_container, "  (none in Resources/Abilities/)")
		return
	for ability_name in abilities:
		var ability: AbilityData = abilities[ability_name]
		DevWidgets.add_checkbox(editor_container, ability_name, current.innate_abilities.has(ability),
			func(pressed: bool): _on_ability_toggled(ability, pressed))

func _on_ability_toggled(ability: AbilityData, pressed: bool) -> void:
	if pressed:
		if not current.innate_abilities.has(ability):
			current.innate_abilities.append(ability)
	else:
		current.innate_abilities.erase(ability)

func _add_jobs_section() -> void:
	DevWidgets.add_label(editor_container, "Starting jobs")
	var jobs := JobCatalog.get_editable()   # display_name -> JobData; the kit stores IDS
	for job_name in jobs:
		var job: JobData = jobs[job_name]
		DevWidgets.add_checkbox(editor_container, job_name, current.starting_jobs.has(job.id),
			func(pressed: bool): _on_job_toggled(job.id, pressed))

func _on_job_toggled(id: String, pressed: bool) -> void:
	if pressed:
		if not current.starting_jobs.has(id):
			current.starting_jobs.append(id)
	else:
		current.starting_jobs.erase(id)

# The Unit Editor's weapons+armor+runes merge, CALLED rather than copied (Law #4) -- one answer
# to "what can a dev put in a hand".
func _equippable_catalog() -> Dictionary:
	var unit_editor: UnitEditorTool = get_node("%Unit Editor")
	return unit_editor._equippable_catalog()

# The kit: what the character carries into any board, seeded through the gated doors at spawn
# (#177). Slot picks stage the catalog FILE resource itself -- no copy -- so a save writes an
# ExtResource reference and the spawn grants copy_for_grant() copies off it.
func _add_kit_section() -> void:
	DevWidgets.add_label(editor_container, "Starting inventory (no Equip checked = auto-equip decides)")
	var catalog := _equippable_catalog()
	var keys: Array = catalog.keys()
	var equip_group := ButtonGroup.new()
	equip_group.allow_unpress = true

	for i in range(Unit.MAX_INVENTORY_SIZE):
		var slot_index := i
		var slot_item: EquippableData = null
		if slot_index < current.starting_inventory.size():
			slot_item = current.starting_inventory[slot_index]

		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "Slot %d" % (slot_index + 1)
		label.custom_minimum_size = Vector2(60, 0)
		row.add_child(label)

		var picker := OptionButton.new()
		picker.add_item("(empty)")
		for k in keys:
			picker.add_item(k)
		var sel := 0
		if slot_item != null:
			for k_index in range(keys.size()):
				if catalog[keys[k_index]] == slot_item:
					sel = k_index + 1
					break
		picker.select(sel)
		picker.item_selected.connect(func(opt_index: int): _on_slot_picked(slot_index, opt_index))
		row.add_child(picker)

		if slot_item != null and sel == 0:
			# No catalog file backs this entry (a captured copy, or one inlined by hand) -- it
			# embeds inside the character file on save. The Unit Editor's "holds:" honesty.
			var held_label := Label.new()
			held_label.text = "inline: %s" % slot_item.display_name
			row.add_child(held_label)

		var is_armor := slot_item is ArmorData
		var equip_btn := CheckBox.new()
		if is_armor:
			equip_btn.text = "Wear"
			equip_btn.button_pressed = slot_index == current.starting_worn_index
			equip_btn.toggled.connect(func(pressed: bool): _on_worn_toggled(slot_index, pressed))
		else:
			equip_btn.text = "Equip"
			equip_btn.button_group = equip_group
			equip_btn.button_pressed = slot_item != null and slot_index == current.starting_equipped_index
			equip_btn.toggled.connect(func(pressed: bool): _on_equip_toggled(slot_index, pressed))
		equip_btn.disabled = slot_item == null
		row.add_child(equip_btn)

		editor_container.add_child(row)

	for i in range(Unit.MAX_INVENTORY_SIZE, current.starting_inventory.size()):
		var extra: EquippableData = current.starting_inventory[i]
		if extra != null:
			DevWidgets.add_label(editor_container, "  overflow: %s -- past the %d-slot cap, drops at spawn" % [extra.display_name, Unit.MAX_INVENTORY_SIZE])

func _on_slot_picked(index: int, opt_index: int) -> void:
	if current.starting_inventory.size() < Unit.MAX_INVENTORY_SIZE:
		current.starting_inventory.resize(Unit.MAX_INVENTORY_SIZE)
	var entry: EquippableData = null
	if opt_index > 0:
		var catalog := _equippable_catalog()
		entry = catalog[catalog.keys()[opt_index - 1]]
	current.starting_inventory[index] = entry
	if current.starting_equipped_index == index:
		current.starting_equipped_index = -1
	if current.starting_worn_index == index:
		current.starting_worn_index = -1
	for slot in current.starting_prosthetics.keys():
		if current.starting_prosthetics[slot] == index:
			current.starting_prosthetics.erase(slot)   # the item that filled this limb just changed under it
	populate()

func _on_equip_toggled(index: int, pressed: bool) -> void:
	if pressed:
		current.starting_equipped_index = index
	elif current.starting_equipped_index == index:
		current.starting_equipped_index = -1   # unpressed: back to "auto-equip decides"

func _on_worn_toggled(index: int, pressed: bool) -> void:
	if pressed:
		current.starting_worn_index = index
	elif current.starting_worn_index == index:
		current.starting_worn_index = -1
	populate()

# Which kit entry fills each limb -- candidates ride the same gate install_prosthetic enforces
# (can_install_as_prosthetic), so the list can never offer an entry the spawn would refuse.
func _add_prosthetics_section() -> void:
	DevWidgets.add_label(editor_container, "Starting prosthetics")
	var slot_names := UnitInstance.LimbSlot.keys()
	for limb_slot in UnitInstance.LimbSlot.values():
		var slot: UnitInstance.LimbSlot = limb_slot
		var candidates: Array[int] = []
		for i in range(current.starting_inventory.size()):
			var item := current.starting_inventory[i] as WeaponInstance
			if item != null and UnitInstance.can_install_as_prosthetic(slot, item):
				candidates.append(i)

		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = slot_names[slot]
		label.custom_minimum_size = Vector2(60, 0)
		row.add_child(label)

		var picker := OptionButton.new()
		picker.add_item("(natural)")
		for idx in candidates:
			picker.add_item("Slot %d: %s" % [idx + 1, current.starting_inventory[idx].display_name])
		var chosen: int = current.starting_prosthetics.get(slot, -1)
		picker.select(candidates.find(chosen) + 1)   # -1 / not-found both land on 0
		picker.item_selected.connect(func(opt_index: int): _on_prosthetic_picked(slot, opt_index, candidates))
		row.add_child(picker)

		editor_container.add_child(row)

func _on_prosthetic_picked(slot: UnitInstance.LimbSlot, opt_index: int, candidates: Array[int]) -> void:
	if opt_index > 0:
		current.starting_prosthetics[slot] = candidates[opt_index - 1]
	else:
		current.starting_prosthetics.erase(slot)

# Absent key = no reduction (every mod space active) -- only a deliberate reduction is worth
# authoring, so a value set back to the top of the range is erased rather than written. The top
# is the WIDEST template on disk since #486: with spaces authored, the range cannot be a const,
# and a fixed 3 would have made a 5-space prototype's last two spaces unauthorable.
func _add_proficiency_section() -> void:
	var widest := WeaponCatalog.max_mod_spaces()
	DevWidgets.add_label(editor_container, "Proficiency (0-%d; %d = default, no reduction)" % [widest, widest])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	editor_container.add_child(grid)
	for weapon_type in WeaponData.WeaponType.values():
		var family: WeaponData.WeaponType = weapon_type
		if family == WeaponData.WeaponType.NONE:
			continue
		var label := Label.new()
		label.text = WeaponData.WeaponType.keys()[family]
		grid.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = widest
		spin.value = current.starting_proficiency.get(family, widest)
		spin.value_changed.connect(func(v): _on_proficiency_changed(family, int(v)))
		grid.add_child(spin)

func _on_proficiency_changed(family: WeaponData.WeaponType, value: int) -> void:
	if value >= WeaponCatalog.max_mod_spaces():
		current.starting_proficiency.erase(family)
	else:
		current.starting_proficiency[family] = value
