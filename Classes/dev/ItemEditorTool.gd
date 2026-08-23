extends MarginContainer
class_name ItemEditorTool

@onready var editor_container := %ItemEditorVbox
@onready var type_dropdown: OptionButton = %ItemTypeDropdown
@onready var load_dropdown: OptionButton = %ItemLoadDropdown
@onready var name_input: LineEdit = %ItemNameInput
@onready var update_button: Button = %UpdateItemButton
@onready var delete_button: Button = %DeleteItemButton
@onready var status_label: Label = %ItemStatusLabel

# Authors a WeaponInstance, a RuneData, or a WeaponModData. The first two fill the equip slot;
# the third is a COMPONENT fitted into one of a weapon's spaces, and it lives here (#74) because
# this is already where a mod gets fitted -- authoring one anywhere else would mean two tabs to
# make one weapon. The type dropdown lists weapon bases + prototypes + rune sizes + the blank mod;
# the field area renders a bespoke editor per kind. Carvings are authored in the Attack Editor tab.
#
# current_item is a Resource rather than an EquippableData because a mod is deliberately NOT one --
# WeaponModData is its own content root off Resource, beside Item/AttackData/JobData (CLAUDE.md),
# and making it an Item to satisfy this field would be the model bending to fit its editor. The
# cost is that display_name is reached through _edited_name/_set_edited_name instead of directly.
var current_item: Resource = null
var _variants := {}
# Which catalog entry current_item was loaded from ("" = a New item). Load hands out a COPY with
# no resource_path, so nothing else records this -- and Update's load-gate needs it (2026-08-11).
var _loaded_name := ""

func _ready():
	for key in _base_catalog():
		type_dropdown.add_item(key)
	_refresh_variant_list()
	type_dropdown.select(0)
	_rebase_on_type(0)

# Weapon TYPES + a blank rune per size + a blank mod — the things "New"/the type dropdown can
# start from. A mod has no varieties to enumerate (no family field yet, #74 keeps that half), so
# it contributes exactly one entry.
const NEW_MOD_KEY := "Weapon Mod (blank)"

func _base_catalog() -> Dictionary:
	var bases := {}
	var weapons := WeaponCatalog.get_templates()
	for k in weapons:
		bases[k] = weapons[k]
	var runes := RuneCatalog.base_runes()
	for k in runes:
		bases[k] = runes[k]
	bases[NEW_MOD_KEY] = WeaponModData.new()
	return bases

func _refresh_variant_list(select_name := ""):
	load_dropdown.clear()
	_variants = {}
	var weapons := WeaponCatalog.get_saved()
	for v in weapons:
		_variants[v] = weapons[v]
	var runes := RuneCatalog.get_variants()
	for v in runes:
		_variants[v] = runes[v]
	var mods := WeaponModCatalog.get_mods()
	for v in mods:
		_variants[v] = mods[v]
	for v in _variants:
		load_dropdown.add_item(v)

	# add_item auto-selects index 0 -- Update must never aim at an entry nobody picked.
	load_dropdown.select(-1)
	for i in load_dropdown.item_count:
		if load_dropdown.get_item_text(i) == select_name:
			load_dropdown.select(i)
			break
	_refresh_update_button()

func _refresh_update_button():
	DevWidgets.refresh_update_button(update_button, DevWidgets.selected_name(load_dropdown), "item", _update_block_reason())
	DevWidgets.refresh_delete_button(delete_button, DevWidgets.selected_name(load_dropdown), "item")

# "" = allowed. Update only overwrites the entry that is actually LOADED (dev call 2026-08-11).
func _update_block_reason() -> String:
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "" or target == _loaded_name:
		return ""
	return "Load '%s' first -- Update overwrites it with whatever is in the editor" % target

func _rebase_on_type(index: int):
	var bases := _base_catalog()
	var key = bases.keys()[index]
	var base = bases[key]
	current_item = WeaponInstance.make(base) if base is WeaponData else base.duplicate(true)
	_loaded_name = ""
	load_dropdown.select(-1)
	_refresh_update_button()
	populate()

func _on_type_selected(index: int):
	_rebase_on_type(index)

func _on_new_pressed():
	_rebase_on_type(type_dropdown.selected)
	name_input.text = ""

func _on_load_dropdown_item_selected(_index: int):
	_refresh_update_button()

func _on_load_pressed():
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "":
		return
	current_item = _editable_copy(_variants[target])
	_loaded_name = target
	_refresh_update_button()
	populate()

# Load hands out a COPY so editing is not editing the catalog's live object. An equippable says how
# to copy itself (WeaponInstance's keeps its template shared); a mod is plain data with no such
# rule, so it deep-copies.
func _editable_copy(entry: Resource) -> Resource:
	var equippable := entry as EquippableData
	return equippable.copy_equippable() if equippable != null else entry.duplicate(true)

# display_name is declared separately on Item and on WeaponModData -- two content roots that agree
# on the name but share no base (CLAUDE.md), so a Resource-typed field cannot reach it statically.
func _edited_name() -> String:
	var mod := current_item as WeaponModData
	if mod != null:
		return mod.display_name
	var item := current_item as Item
	return item.display_name if item != null else ""

func _set_edited_name(value: String) -> void:
	var mod := current_item as WeaponModData
	if mod != null:
		mod.display_name = value
		return
	var item := current_item as Item
	if item != null:
		item.display_name = value

func _on_update_pressed():
	var target := DevWidgets.selected_name(load_dropdown)
	if current_item == null or target == "":
		return
	# The handler is the real gate -- the disabled button is only its surface (#166 shape).
	var reason := _update_block_reason()
	if reason != "":
		status_label.text = reason
		return
	# Overwrite the file the entry actually came from. The dropdown key is the item's NAME, and a
	# path rebuilt from it would miss any file whose basename differs.
	var path: String = _variants[target].resource_path
	if path == "":
		var msg := "%s has no file on disk to update" % target
		push_warning(msg)
		status_label.text = msg
		return
	# Confirmed as well as load-gated (#380's convention): the gate cannot catch a mis-click at
	# the item you DID load.
	DevWidgets.confirm_overwrite(self, "item '%s'" % target, "the editor's values",
		func() -> void: _update_confirmed(path))


func _update_confirmed(path: String) -> void:
	if DevWidgets.save_over(current_item, path, status_label):
		_loaded_name = _edited_name()   # a rename moves the loaded identity with it
		_refresh_variant_list(_edited_name())

func _on_delete_pressed():
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "":
		return
	DevWidgets.confirm_delete(self, "item '%s'" % target, func(): _delete_confirmed(target))

func _delete_confirmed(target: String) -> void:
	if not _variants.has(target):
		return   # catalog moved between the press and the Yes
	if DevWidgets.delete_saved_file(_variants[target].resource_path, "item", status_label):
		if target == _loaded_name:
			_loaded_name = ""
		_refresh_variant_list()

func _on_save_as_pressed():
	if current_item == null:
		return
	var entered_name := name_input.text.strip_edges()
	if entered_name == "":
		var msg := "Item needs a name to save"
		push_warning(msg)
		status_label.text = msg
		return
	if DevWidgets.refuse_illegal_name(entered_name, "item", status_label):
		return
	var dir := _save_dir_for(current_item)
	var path := dir + entered_name + ".tres"
	if DevWidgets.refuse_existing_file(path, "item", status_label):
		return
	_set_edited_name(entered_name)
	if DevWidgets.save_over(current_item, path, status_label):
		_loaded_name = entered_name   # save_over take_over_path'd it: the editor now holds this file
		name_input.text = ""
		_refresh_variant_list(entered_name)

func populate():
	for child in editor_container.get_children():
		editor_container.remove_child(child)
		child.queue_free()
	if current_item == null:
		return
	DevWidgets.add_lineedit(editor_container, "Item name", _edited_name(), func(s: String): _set_edited_name(s))
	if current_item is RuneData:
		_populate_rune_editor(current_item)
	elif current_item is WeaponInstance:
		_populate_weapon_editor(current_item)
	elif current_item is WeaponModData:
		_populate_mod_editor(current_item)
	else:
		DevWidgets.build_resource_editor(editor_container, current_item, populate, ["weapon_type", "display_name"])

# A rune is a size + a capacity-bounded list of inscribed carvings. We only choose WHICH carvings
# to inscribe (authored in the Attack Editor tab); inscribe() enforces the capacity budget.
func _populate_rune_editor(rune: RuneData):
	var on_size := func(v):
		rune.size = v
		populate()

	var temper_label := "(blank — the first carving sets it, permanently)"
	if rune.temper != Elemental.Element.NONE:
		temper_label = Elemental.Element.keys()[rune.temper]
	DevWidgets.add_label(editor_container, "Temper: %s" % temper_label)
	if not rune.is_legal():
		DevWidgets.add_label(editor_container, "ILLEGAL: over a knob or breaks the temper rule — won't load from disk")

	DevWidgets.add_enum_option(editor_container, "Size", ",".join(RuneData.Size.keys()), rune.size, on_size)
	DevWidgets.add_label(editor_container, "Capacity: %d / %d used" % [rune.used_capacity(), rune.capacity()])
	DevWidgets.add_label(editor_container, "Inscriptions:")

	for i in range(rune.inscriptions.size()):
		var carving: TransmutationData = rune.inscriptions[i]
		var idx := i
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s (cost %d)" % [_carving_label(carving), carving.cost()]
		label.custom_minimum_size = Vector2(160, 0)
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(func():
			rune.inscriptions.remove_at(idx)
			populate()
		)
		row.add_child(remove)
		editor_container.add_child(row)

	var carvings := TransmutationCatalog.get_all()
	if carvings.is_empty():
		DevWidgets.add_label(editor_container, "(no carvings in Resources/TransmutationData/)")
		return
	var add_row := HBoxContainer.new()
	var picker := OptionButton.new()
	for k in carvings:
		picker.add_item(k)
	add_row.add_child(picker)
	var add_btn := Button.new()
	add_btn.text = "Inscribe"
	add_btn.pressed.connect(func():
		var key = carvings.keys()[picker.selected]
		if rune.inscribe(carvings[key].duplicate(true)):
			populate()
		else:
			push_warning("Won't fit %s: capacity, circle cap, or temper rule" % key)
		)
	add_row.add_child(add_btn)
	editor_container.add_child(add_row)

func _carving_label(carving: TransmutationData) -> String:
	return carving.display_name if carving.display_name != "" else "carving"

# A weapon's per-item state is just its fitted mods (item 6/7, weapons.md). The template
# is shown read-only, never as a nested editable form — that's what the old reflection
# path got wrong: it silently let you mutate the shared family .tres through any one
# item's editor. Mirrors _populate_rune_editor's capacity-bounded fit/remove shape.
func _populate_weapon_editor(weapon: WeaponInstance) -> void:
	var template := weapon.template
	if template == null:
		DevWidgets.add_label(editor_container, "(no template)")
		return
	DevWidgets.add_label(editor_container, "Family: %s" % (template.display_name if template.display_name != "" else WeaponData.WeaponType.keys()[template.weapon_type]))
	DevWidgets.add_label(editor_container, "Weight: %d" % weapon.get_effective_weight())

	if template.weapon_type == WeaponData.WeaponType.PROSTHETIC:
		DevWidgets.add_option(editor_container, "Limb Kind", WeaponData.LimbKind.keys(), WeaponData.LimbKind.keys()[weapon.limb_kind],
			func(s): _on_limb_kind_picked(weapon, s))

	var mods := WeaponModCatalog.get_mods()
	for i in range(weapon.space_count()):
		_populate_mod_space(weapon, i, mods)

func _on_limb_kind_picked(weapon: WeaponInstance, kind_name: String) -> void:
	weapon.limb_kind = WeaponData.LimbKind[kind_name]
	populate()

func _populate_mod_space(weapon: WeaponInstance, index: int, mods: Dictionary) -> void:
	var capacity: int = weapon.template.space_capacities()[index]
	DevWidgets.add_label(editor_container, "Space %d: %d / %d used" % [index + 1, weapon.used_capacity(index), capacity])

	var fitted := weapon.space(index)
	for i in range(fitted.size()):
		var mod := fitted[i]
		var idx := i
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s (size %d)" % [mod.display_name if mod.display_name != "" else mod.id, mod.size]
		label.custom_minimum_size = Vector2(160, 0)
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(func():
			fitted.remove_at(idx)
			populate()
		)
		row.add_child(remove)
		editor_container.add_child(row)

	if mods.is_empty():
		DevWidgets.add_label(editor_container, "(no mods in Resources/WeaponMods/)")
		return
	var add_row := HBoxContainer.new()
	var picker := OptionButton.new()
	for k in mods:
		picker.add_item(k)
	add_row.add_child(picker)
	var add_btn := Button.new()
	add_btn.text = "Fit"
	add_btn.pressed.connect(func():
		var key = mods.keys()[picker.selected]
		if weapon.fit(index, mods[key]):   # a direct ref, not a duplicate — WeaponModCatalog's header comment already documents mods as live-shared, same model as templates
			populate()
		else:
			push_warning("Not enough capacity in space %d to fit %s" % [index + 1, key])
	)
	add_row.add_child(add_btn)
	editor_container.add_child(add_row)

# A mod is scalars + two grant LISTS + two stat dictionaries. The reflective editor draws the
# scalars; the other four get bespoke UI here, because build_resource_editor has no arm for an
# Array or a Dictionary and silently draws nothing for either.
#
# scaling_nudge is in that second group and PREDATES #74 -- it has been undrawn since the field was
# written, so this is the first build in which every field of a mod is actually editable.
const MOD_SKIP := ["display_name", "scaling_nudge", "stat_modifiers", "granted_attacks", "granted_abilities"]

func _populate_mod_editor(mod: WeaponModData) -> void:
	DevWidgets.build_resource_editor(editor_container, mod, populate, MOD_SKIP)
	DevWidgets.add_stat_dict(editor_container, "Scaling nudge (blend %)", mod.scaling_nudge,
		DevWidgets.property_tip(mod, "scaling_nudge"))
	DevWidgets.add_stat_dict(editor_container, "Wielder stat modifiers", mod.stat_modifiers,
		DevWidgets.property_tip(mod, "stat_modifiers"))
	_populate_grant_list("Granted attacks:", mod.granted_attacks, WeaponAttackCatalog.get_library(),
		"(no attacks in %s)" % WeaponAttackCatalog.LIBRARY_DIR, DevWidgets.property_tip(mod, "granted_attacks"))
	_populate_grant_list("Granted abilities:", mod.granted_abilities, AbilityCatalog.get_abilities(),
		"(no abilities in %s)" % AbilityCatalog.ABILITY_DIR, DevWidgets.property_tip(mod, "granted_abilities"))

# One "list + remove + pick-and-add" block, used for both grant lists. Same shape as the rune
# inscribe list and the mod fitting list above, minus their capacity budget: a grant costs nothing
# on its own, since what a mod costs is its own `size` in the space it is fitted to.
func _populate_grant_list(title: String, entries: Array, catalog: Dictionary, empty_text: String, tooltip: String) -> void:
	var first := editor_container.get_child_count()
	DevWidgets.add_label(editor_container, title)
	for i in range(entries.size()):
		var idx := i
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = _grant_label(entries[idx])
		label.custom_minimum_size = Vector2(160, 0)
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(func():
			entries.remove_at(idx)
			populate()
		)
		row.add_child(remove)
		editor_container.add_child(row)

	if catalog.is_empty():
		DevWidgets.add_label(editor_container, empty_text)
		_tip_from(first, tooltip)
		return
	var add_row := HBoxContainer.new()
	var picker := OptionButton.new()
	for k in catalog:
		picker.add_item(k)
	add_row.add_child(picker)
	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(func():
		var key = catalog.keys()[picker.selected]
		var picked: Resource = catalog[key]
		# A direct ref, not a duplicate -- same live-sync model as a fitted mod, so editing the
		# authored attack or ability updates every mod granting it.
		if picked != null and not entries.has(picked):
			entries.append(picked)
			populate()
	)
	add_row.add_child(add_btn)
	editor_container.add_child(add_row)
	_tip_from(first, tooltip)

# Tooltip every control this block just added -- Godot does not walk up to a parent, so the row is
# identified by the children that appeared (DevWidgets._tip_rows_from's shape, which is private).
func _tip_from(first: int, tooltip: String) -> void:
	if tooltip == "":
		return
	for i in range(first, editor_container.get_child_count()):
		DevWidgets.apply_tooltip(editor_container.get_child(i), tooltip)

# Both grant kinds carry a display_name, but off different roots (AttackData / AbilityData), so
# there is no shared base to read it from.
func _grant_label(entry: Resource) -> String:
	var attack := entry as AttackData
	if attack != null:
		return attack.display_name if attack.display_name != "" else "attack"
	var ability := entry as AbilityData
	if ability != null:
		return ability.display_name if ability.display_name != "" else "ability"
	return "(unknown)"

# Which catalog folder a new file belongs in. Each kind is scanned from its own directory, so the
# fork is the catalogs' own rather than this tool's invention.
func _save_dir_for(item: Resource) -> String:
	if item is RuneData:
		return RuneCatalog.VARIANT_DIR
	if item is WeaponModData:
		return WeaponModCatalog.MOD_DIR
	return WeaponCatalog.SAVED_DIR
