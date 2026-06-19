extends MarginContainer
class_name WeaponEditorTool

@onready var weapon_editor_container := %WeaponEditorVbox
@onready var type_dropdown: OptionButton = %WeaponTypeDropdown
@onready var load_dropdown: OptionButton = %WeaponLoadDropdown
@onready var name_input: LineEdit = %WeaponNameInput

var current_weapon: WeaponData = null
var _variants := {}

func _ready():
	for t in WeaponCatalog.TYPES:
		type_dropdown.add_item(t)
	_refresh_variant_list()
	type_dropdown.select(0)
	_rebase_on_type(0)

func _refresh_variant_list():
	load_dropdown.clear()
	_variants = WeaponCatalog.get_variants()
	for v in _variants:
		load_dropdown.add_item(v)

func _rebase_on_type(index: int):
	var key = WeaponCatalog.TYPES.keys()[index]
	current_weapon = WeaponCatalog.TYPES[key].duplicate(true)
	populate()
	
func _on_type_selected(index: int):
	_rebase_on_type(index)

func _load_selected(index: int):
	if index < 0:
		return
	current_weapon = _variants[_variants.keys()[index]].duplicate(true)
	name_input.text = current_weapon.item_name
	populate()
	
func _on_new_pressed():
	_rebase_on_type(type_dropdown.selected)
	name_input.text = ""

func _on_save_pressed():
	if current_weapon == null:
		return
	var weapon_name := name_input.text.strip_edges()
	if weapon_name == "":
		push_warning("Weapon needs a name to save")
		return
	current_weapon.item_name = weapon_name
	DirAccess.make_dir_recursive_absolute(WeaponCatalog.VARIANT_DIR)
	var err := ResourceSaver.save(current_weapon, WeaponCatalog.VARIANT_DIR + weapon_name + ".tres")
	if err != OK:
		push_error("Failed to save weapon (error %s)" % err)
		return
	_refresh_variant_list()

func populate():
	for child in weapon_editor_container.get_children():
		weapon_editor_container.remove_child(child)
		child.queue_free()
	if current_weapon == null:
		return
	DevWidgets.build_resource_editor(weapon_editor_container, current_weapon, populate, ["weapon_type", "item_name"])
