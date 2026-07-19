extends VBoxContainer
class_name TileBrushTool

# Dev-overlay tab for authoring the board: paints terrain tiles (left-drag, right-erase),
# resizes the map, and paints named AI zones (Sentry regions). Terrain choices are scanned
# from the tileset itself, never hardcoded.

const SOURCE_ID := 0

var brush_active := false
var selected_tile := Vector2i(5, 0)
var game   # injected by DevOverlay.init
enum PaintMode { TERRAIN, ZONE }
var paint_mode := PaintMode.TERRAIN
var _zone_name := ""
var _zone_name_row: HBoxContainer

# Parallel to the dropdown: the atlas coords each entry paints. Built by scanning the
# board tileset for tiles carrying a terrain_type kind, so any terrain tile authored in
# the TileSet (grass/mud/rock/tree/water/...) shows up automatically, with no hardcoded
# coords to drift out of sync. (#50 dev tooling.)
var _tile_coords: Array[Vector2i] = []

var _width_spin: SpinBox
var _height_spin: SpinBox

@onready var tile_dropdown: OptionButton = %TileDropdown

func _ready():
	_build_extra_controls()

# Called by DevOverlay once the Game ref exists — the scan needs game.grid.tile_set, which
# isn't available at _ready. Mirrors spawn.init / unit_editor.init.
func init(game_ref) -> void:
	game = game_ref
	_populate_tile_dropdown()

func _populate_tile_dropdown() -> void:
	tile_dropdown.clear()
	_tile_coords.clear()
	if game == null or game.grid == null or game.grid.tile_set == null:
		return
	var source := game.grid.tile_set.get_source(SOURCE_ID) as TileSetAtlasSource
	if source == null:
		return
	var seen: Dictionary[Terrain.Kind, bool] = {}
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var data := source.get_tile_data(coords, 0)
		if data == null or not data.has_custom_data("terrain_type"):
			continue
		var raw: int = data.get_custom_data("terrain_type")
		var kind := raw as Terrain.Kind
		if kind == Terrain.Kind.NONE or seen.has(kind):
			continue
		seen[kind] = true
		_tile_coords.append(coords)
		var kind_name: String = Terrain.Kind.keys()[kind]
		tile_dropdown.add_item(kind_name.capitalize())
	if not _tile_coords.is_empty():
		selected_tile = _tile_coords[0]

func _on_tile_brush_toggled(pressed: bool):
	brush_active = pressed

func _on_tile_dropdown_item_selected(index: int):
	if index >= 0 and index < _tile_coords.size():
		selected_tile = _tile_coords[index]

func deactivate():
	$Panel/TileBrushRow/TileBoxCheck.button_pressed = false

func _on_resize_pressed() -> void:
	if game == null:
		return
	game.dev_controller.resize_map(int(_width_spin.value), int(_height_spin.value), selected_tile)
	
func selected_zone_name() -> String:
	return _zone_name.strip_edges()

func _build_extra_controls() -> void:
	# Part 2: visible erase hint (the tab tooltip already says it, but this is in-panel).
	var note := Label.new()
	note.text = "Left-drag paints  ·  right-click erases"
	add_child(note)

	# Part 1: map-resize row.
	var row := HBoxContainer.new()

	var size_label := Label.new()
	size_label.text = "Map size (cells)"
	row.add_child(size_label)

	_width_spin = SpinBox.new()
	_width_spin.min_value = 1
	_width_spin.max_value = 200
	_width_spin.value = 20
	row.add_child(_width_spin)

	_height_spin = SpinBox.new()
	_height_spin.min_value = 1
	_height_spin.max_value = 200
	_height_spin.value = 12
	row.add_child(_height_spin)

	var apply := Button.new()
	apply.text = "Resize Map"
	apply.pressed.connect(_on_resize_pressed)
	row.add_child(apply)

	add_child(row)

	# Part 3: zone paint mode (Sentry archetype regions).
	# Part 3: zone paint mode (Sentry archetype regions). The terrain dropdown and the zone
	# name field are mode-specific -- show whichever the active mode uses.
	DevWidgets.add_checkbox(self, "Paint Zones (instead of terrain)", false, _on_zone_mode_toggled)
	_zone_name_row = DevWidgets.add_lineedit(self, "Zone Name", "", func(s): _zone_name = s)
	_zone_name_row.visible = false
	
func _on_zone_mode_toggled(pressed: bool) -> void:
	paint_mode = PaintMode.ZONE if pressed else PaintMode.TERRAIN
	tile_dropdown.visible = not pressed
	_zone_name_row.visible = pressed
