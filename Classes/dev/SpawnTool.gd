extends VBoxContainer
class_name SpawnTool

@onready var faction_group := ButtonGroup.new()

var game

var stat_values: Dictionary[Stats.Stat, int] = {}
var unit_name
var faction: Team.Faction
var selected_weapon: WeaponInstance = null
var sprite_catalog := {}
var selected_sprite := {}
var data: UnitData
var valid := false
var error_message := ""
var soldier_increment := 1
var _spawnable := {}

func init(p_game):
	game = p_game

	var stat_grid := %StatInput
	for stat in Stats.STAT_DEFAULTS:
		stat_values[stat] = Stats.STAT_DEFAULTS[stat]
		var label := Label.new()
		label.text = Stats.Stat.keys()[stat]
		stat_grid.add_child(label)
		var box := SpinBox.new()
		box.min_value = 0
		box.max_value = 100
		box.value = stat_values[stat]
		box.value_changed.connect(func(v): stat_values[stat] = int(v))
		stat_grid.add_child(box)
		
	unit_name = %UnitNameInput.text
	faction = Team.Faction.PLAYER
	%PlayerCheckBox.button_group = faction_group
	%EnemyCheckBox.button_group = faction_group
	%OtherCheckBox.button_group = faction_group
	
	refresh_weapons()
	_build_sprite_catalog()
	var sprite_dropdown := %SpriteDropdown
	for sprite_name in sprite_catalog:
		sprite_dropdown.add_item(sprite_name)
	_on_sprite_dropdown_item_selected(sprite_dropdown.selected)

func refresh_weapons():
	var dropdown := %WeaponDropdown
	var prev_key := ""
	if dropdown.selected >= 0 and dropdown.selected < _spawnable.size():
		prev_key = _spawnable.keys()[dropdown.selected]
	dropdown.clear()
	_spawnable = WeaponCatalog.get_spawnable()
	for weapon_name in _spawnable:
		dropdown.add_item(weapon_name)
	var new_idx = _spawnable.keys().find(prev_key)
	if new_idx >= 0:
		dropdown.select(new_idx)
	_on_weapon_dropdown_item_selected(dropdown.selected)

func _validate():
	set_selected_faction()
	valid = true
	if unit_name == "":
		unit_name = "Error_Soldier"
	unit_name = _unique_unit_name(unit_name)
	for stat in stat_values:
		if stat_values[stat] < 0 or stat_values[stat] > 100:
			error_message += "and invalid %s " % Stats.Stat.keys()[stat]
			valid = false
	if faction == null:
		error_message += "and invalid faction "
		valid = false
		
func _unique_unit_name(desired: String) -> String:
	var taken := {}
	for unit in game.units_root.get_children():
		taken[unit.get_unit_name()] = true
	if not taken.has(desired):
		return desired
	# Peel a trailing number off the base, then increment until unique.
	var base := desired
	var digits := ""
	while base.length() > 0 and base.right(1).is_valid_int():
		digits = base.right(1) + digits
		base = base.left(base.length() - 1)
	var n := 2
	if digits != "":
		n = int(digits) + 1
	while taken.has(base + str(n)):
		n += 1
	return base + str(n)

func set_selected_faction():
	var pressed = faction_group.get_pressed_button()
	match pressed.name:
		"PlayerCheckBox":
			faction = Team.Faction.PLAYER
		"EnemyCheckBox":
			faction = Team.Faction.ENEMY
		"OtherCheckBox":
			faction = Team.Faction.OTHER

func build_unit_data():
	data = UnitFactory.create_unit_data(
		stat_values.duplicate(),
		unit_name,
		faction,
		selected_sprite["idle"],
		selected_sprite["moving"],
		selected_sprite["downed"])

func try_spawn_at(cell: Vector2i) -> void:
	_validate()
	if valid:
		build_unit_data()
		var unit = game.spawn_unit(data, cell)
		if unit != null and selected_weapon != null:
			unit.add_item(WeaponCatalog.instantiate_entry(selected_weapon))
	else:
		print(error_message)
		error_message = ""

func _on_weapon_dropdown_item_selected(index: int):
	selected_weapon = _spawnable[_spawnable.keys()[index]]

func _on_sprite_dropdown_item_selected(index: int) -> void:
	var key = sprite_catalog.keys()[index]
	selected_sprite = sprite_catalog[key]

func _on_unit_name_input_text_changed(new_text: String) -> void:
	unit_name = new_text

func _build_sprite_catalog() -> void:
	const SPRITE_DIR := "res://Art/Units/MapSprites/"
	for file in DirAccess.get_files_at(SPRITE_DIR):
		if not file.ends_with(".png"):
			continue
		if file.ends_with("_Moving.png"):
			continue
		if file.ends_with("_Downed.png"):
			continue
		var sprite_name := file.get_basename()
		var idle: Texture2D = load(SPRITE_DIR + file)
		var moving_path := SPRITE_DIR + sprite_name + "_Moving.png"
		var moving: Texture2D = load(moving_path) if ResourceLoader.exists(moving_path) else idle
		var downed_path := SPRITE_DIR + sprite_name + "_Downed.png"
		var downed: Texture2D = load(downed_path) if ResourceLoader.exists(downed_path) else null
		sprite_catalog[sprite_name] = {"idle": idle, "moving": moving, "downed": downed}
