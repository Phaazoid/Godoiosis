extends MarginContainer
class_name ItemEditorTool

@onready var editor_container := %ItemEditorVbox
@onready var type_dropdown: OptionButton = %ItemTypeDropdown
@onready var load_dropdown: OptionButton = %ItemLoadDropdown
@onready var name_input: LineEdit = %ItemNameInput

# Authors either a WeaponData or a RuneData (the equip slot takes both). The type dropdown
# lists weapon bases + prototypes + rune sizes; the field area renders the weapon reflectively
# or a bespoke rune inscribe-list. Carvings are authored in the Attack Editor tab.

var current_item: EquippableData = null
var _variants := {}

func _ready():
	for key in _base_catalog():
		type_dropdown.add_item(key)
	_refresh_variant_list()
	type_dropdown.select(0)
	_rebase_on_type(0)

# Weapon TYPES + a blank rune per size — the things "New"/the type dropdown can start from.
func _base_catalog() -> Dictionary:
	var bases := {}
	var weapons := WeaponCatalog.get_templates()
	for k in weapons:
		bases[k] = weapons[k]
	var runes := RuneCatalog.base_runes()
	for k in runes:
		bases[k] = runes[k]
	return bases

func _refresh_variant_list():
	load_dropdown.clear()
	_variants = {}
	var weapons := WeaponCatalog.get_saved()
	for v in weapons:
		_variants[v] = weapons[v]
	var runes := RuneCatalog.get_variants()
	for v in runes:
		_variants[v] = runes[v]
	for v in _variants:
		load_dropdown.add_item(v)

func _rebase_on_type(index: int):
	var bases := _base_catalog()
	var key = bases.keys()[index]
	var base = bases[key]
	current_item = WeaponInstance.make(base) if base is WeaponData else base.duplicate(true)
	populate()

func _on_type_selected(index: int):
	_rebase_on_type(index)

func _load_selected(index: int):
	if index < 0:
		return
	current_item = _variants[_variants.keys()[index]].copy_equippable()
	name_input.text = current_item.item_name
	populate()

func _on_new_pressed():
	_rebase_on_type(type_dropdown.selected)
	name_input.text = ""

func _on_save_pressed():
	if current_item == null:
		return
	var item_name := name_input.text.strip_edges()
	if item_name == "":
		push_warning("Item needs a name to save")
		return
	current_item.item_name = item_name
	var dir := RuneCatalog.VARIANT_DIR if current_item is RuneData else WeaponCatalog.SAVED_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(current_item, dir + item_name + ".tres")
	if err != OK:
		push_error("Failed to save item (error %s)" % err)
		return
	_refresh_variant_list()

func populate():
	for child in editor_container.get_children():
		editor_container.remove_child(child)
		child.queue_free()
	if current_item == null:
		return
	if current_item is RuneData:
		_populate_rune_editor(current_item)
	elif current_item is WeaponInstance:
		_populate_weapon_editor(current_item)
	else:
		DevWidgets.build_resource_editor(editor_container, current_item, populate, ["weapon_type", "item_name"])

# A rune is a size + a capacity-bounded list of inscribed carvings. We only choose WHICH carvings
# to inscribe (authored in the Attack Editor tab); inscribe() enforces the capacity budget.
func _populate_rune_editor(rune: RuneData):
	var on_size := func(v):
		rune.size = v
		populate()
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
			push_warning("Not enough capacity to inscribe %s" % key)
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
	DevWidgets.add_label(editor_container, "Family: %s" % (template.item_name if template.item_name != "" else WeaponData.WeaponType.keys()[template.weapon_type]))
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
