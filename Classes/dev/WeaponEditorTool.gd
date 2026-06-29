extends MarginContainer
class_name WeaponEditorTool

@onready var weapon_editor_container := %WeaponEditorVbox
@onready var type_dropdown: OptionButton = %WeaponTypeDropdown
@onready var load_dropdown: OptionButton = %WeaponLoadDropdown
@onready var name_input: LineEdit = %WeaponNameInput

# Authors either a WeaponData or a RuneData (the equip slot takes both). Reuses the same scene
# nodes: the type dropdown lists weapon bases + rune sizes; the field area renders the weapon
# reflectively or a bespoke rune inscribe-list. Tab still reads "Weapon Editor" (rename = point 3).
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
	var weapons := WeaponCatalog.TYPES
	for k in weapons:
		bases[k] = weapons[k]
	var runes := RuneCatalog.base_runes()
	for k in runes:
		bases[k] = runes[k]
	return bases

func _refresh_variant_list():
	load_dropdown.clear()
	_variants = {}
	var weapons := WeaponCatalog.get_variants()
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
	current_item = bases[key].duplicate(true)
	populate()

func _on_type_selected(index: int):
	_rebase_on_type(index)

func _load_selected(index: int):
	if index < 0:
		return
	current_item = _variants[_variants.keys()[index]].duplicate(true)
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
	var dir := RuneCatalog.VARIANT_DIR if current_item is RuneData else WeaponCatalog.VARIANT_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(current_item, dir + item_name + ".tres")
	if err != OK:
		push_error("Failed to save item (error %s)" % err)
		return
	_refresh_variant_list()

func populate():
	for child in weapon_editor_container.get_children():
		weapon_editor_container.remove_child(child)
		child.queue_free()
	if current_item == null:
		return
	if current_item is RuneData:
		_populate_rune_editor(current_item)
	else:
		DevWidgets.build_resource_editor(weapon_editor_container, current_item, populate, ["weapon_type", "item_name"])

# A rune is a size + a capacity-bounded list of inscribed carvings. We only choose WHICH carvings
# to inscribe (they're authored as .tres elsewhere); inscribe() enforces the capacity budget.
func _populate_rune_editor(rune: RuneData):
	var on_size := func(v):
		rune.size = v
		populate()
	DevWidgets.add_enum_option(weapon_editor_container, "Size", ",".join(RuneData.Size.keys()), rune.size, on_size)
	DevWidgets.add_label(weapon_editor_container, "Capacity: %d / %d used" % [rune.used_capacity(), rune.capacity()])
	DevWidgets.add_label(weapon_editor_container, "Inscriptions:")

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
		weapon_editor_container.add_child(row)

	var carvings := TransmutationCatalog.get_all()
	if carvings.is_empty():
		DevWidgets.add_label(weapon_editor_container, "(no carvings in Resources/TransmutationData/)")
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
	weapon_editor_container.add_child(add_row)

func _carving_label(carving: TransmutationData) -> String:
	return carving.display_name if carving.display_name != "" else "carving"
