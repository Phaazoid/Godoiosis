extends VBoxContainer
class_name SpawnTool

# The dev overlay's unit spawner tab: authors a UnitData from its own fields (name, faction,
# stats, sprite, starting weapon) and hands it to game.spawn_unit on a dev-mode click.

@onready var faction_group := ButtonGroup.new()

var game

const CUSTOM_LABEL := "(custom)"

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
# Character spawning (#177): a cast member picked from Resources/Units/ spawns from its FILE
# resource, so provenance survives and an authored save references it. null = the form flow.
var _characters := {}
var selected_character: UnitData = null
var _character_dropdown: OptionButton = null

var _header: ScenarioHeader

func init(p_game, header: ScenarioHeader = null):
	_header = header
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
	sprite_catalog = build_sprite_catalog()
	var sprite_dropdown := %SpriteDropdown
	for sprite_name in sprite_catalog:
		sprite_dropdown.add_item(sprite_name)
	_on_sprite_dropdown_item_selected(sprite_dropdown.selected)

	# The cast picker (#177). "(custom)" keeps the form flow; a character spawns from its file
	# with the faction radio as an override. Built inline rather than DevWidgets.add_option so
	# refresh_characters() can rebuild the list -- add_option's handler closes over a snapshot
	# of its options array, which a rebuild would silently strand (#179).
	var character_row := HBoxContainer.new()
	var character_label := Label.new()
	character_label.text = "Character"
	character_row.add_child(character_label)
	_character_dropdown = OptionButton.new()
	_character_dropdown.item_selected.connect(_on_character_selected)
	character_row.add_child(_character_dropdown)
	add_child(character_row)
	move_child(character_row, 0)
	refresh_characters()

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

# Rebuild the cast dropdown from disk, keeping the selection -- called on entering this tab, so
# a character authored in the Character tab appears without a restart (#179). Mirrors
# refresh_weapons; a vanished selection falls back to "(custom)".
func refresh_characters():
	var prev_key := ""
	if _character_dropdown.selected > 0 and _character_dropdown.selected - 1 < _characters.size():
		prev_key = _characters.keys()[_character_dropdown.selected - 1]
	_character_dropdown.clear()
	_characters = UnitCatalog.get_characters()
	_character_dropdown.add_item(CUSTOM_LABEL)
	for character_name in _characters:
		_character_dropdown.add_item(character_name)
	var new_idx: int = _characters.keys().find(prev_key)
	_character_dropdown.select(new_idx + 1 if new_idx >= 0 else 0)
	_on_character_selected(_character_dropdown.selected)

func _on_character_selected(index: int) -> void:
	if index <= 0 or index - 1 >= _characters.size():
		selected_character = null
		return
	selected_character = _characters[_characters.keys()[index - 1]]

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
	if selected_character != null:
		# The FILE resource, un-copied: UnitFactory copies it and stamps unit_data_source (#177).
		# The character's own starting kit seeds in _ready — the form's weapon pick doesn't apply.
		set_selected_faction()
		var unit = game.spawn_unit(selected_character, cell)
		if unit != null and unit.get_faction() != faction:
			unit.change_faction(faction)
			# Cast off the file's own side = a dev edit (#259 rework): an authored save must
			# snapshot this unit, or the reference loads back on the character's faction.
			unit.dev_edited = true
		_mark_authoring_edit(unit != null)
		return
	_validate()
	if valid:
		build_unit_data()
		var unit = game.spawn_unit(data, cell)
		if unit != null and selected_weapon != null:
			unit.add_item(WeaponCatalog.instantiate_entry(selected_weapon))
		_mark_authoring_edit(unit != null)
	else:
		print(error_message)
		error_message = ""

# A spawn changes what the scenario CONTAINS — the header's (modified) rule (#259 rework closing
# the marker gap: only field edits and terrain marked before; the unit-shaped edits never did).
func _mark_authoring_edit(spawned: bool) -> void:
	if spawned and _header != null:
		_header.mark_modified()

func _on_weapon_dropdown_item_selected(index: int):
	if index < 0 or index >= _spawnable.size():
		selected_weapon = null
		return
	selected_weapon = _spawnable[_spawnable.keys()[index]]

func _on_sprite_dropdown_item_selected(index: int) -> void:
	if index < 0 or index >= sprite_catalog.size():
		selected_sprite = {}
		return
	var key = sprite_catalog.keys()[index]
	selected_sprite = sprite_catalog[key]

func _on_unit_name_input_text_changed(new_text: String) -> void:
	unit_name = new_text

# The idle/moving/downed sprite triples under Art/Units/MapSprites/, keyed by base name.
# Static and shared: the Character editor's art picker reads this same scan (#179, Law #4).
static func build_sprite_catalog() -> Dictionary:
	const SPRITE_DIR := "res://Art/Units/MapSprites/"
	var catalog := {}
	for file in ResourceDir.files_with_extension(SPRITE_DIR, ".png"):
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
		catalog[sprite_name] = {"idle": idle, "moving": moving, "downed": downed}
	return catalog
