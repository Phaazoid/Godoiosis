extends VBoxContainer
class_name TileBrushTool

# Dev-overlay tab for authoring the board: paints terrain tiles, dynamic tile states (#174),
# and named AI zones (left-drag paints, right-click erases in every mode), plus map resize.
# Terrain choices are scanned from the tileset itself, never hardcoded: every tile carrying a
# terrain_type kind or an authored terrain_name is paintable, across all atlas sources.

const KIND_LABELS := ["Patrol", "Capture", "Extraction"]   # index == ZoneManager.Kind value
const MODE_LABELS := ["Terrain", "Zones", "Tile States"]   # index == PaintMode value

var brush_active := false
var selected_tile := Vector2i(5, 0)
var selected_source := 0
var game   # injected by DevOverlay.init
enum PaintMode { TERRAIN, ZONE, STATE }
var paint_mode := PaintMode.TERRAIN
var _zone_name := ""
var _zone_name_row: HBoxContainer
var _zone_kind_row: HBoxContainer
var _zone_kind := ZoneManager.Kind.PATROL
var _tile_state := Terrain.TileState.BURNING
var _state_row: HBoxContainer
var _clear_states_button: Button
var _state_labels: Array[String] = []
var _state_values: Array[Terrain.TileState] = []

# Parallel to the dropdown: the atlas source + coords each entry paints. Built by scanning
# every atlas source for tiles that say what they ARE -- a terrain_type kind, an authored
# terrain_name, or both -- so kind variants and named scenery all show up automatically,
# with no hardcoded coords to drift out of sync. (#50 dev tooling; one entry per authored
# TILE, no longer one per kind, 2026-08-12.)
var _tile_coords: Array[Vector2i] = []
var _tile_sources: Array[int] = []

# One dropdown row: what to paint (source + coords) and how to list it (kind for grouping,
# label, and the tile's own sprite region as the row icon).
class PaletteEntry:
	var kind: Terrain.Kind = Terrain.Kind.NONE
	var source_id := 0
	var coords := Vector2i.ZERO
	var label := ""
	var icon: Texture2D = null

var _width_spin: SpinBox
var _height_spin: SpinBox

# Code-built beside the other mode pickers (2026-08-11 dev ask -- it used to sit in the scene next
# to the on/off checkbox, the one mode control that didn't live below the Paint picker).
var tile_dropdown: OptionButton
var _tile_row: HBoxContainer

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
	_tile_sources.clear()
	if game == null or game.grid == null or game.grid.tile_set == null:
		return
	var tiles: TileSet = game.grid.tile_set
	var entries: Array[PaletteEntry] = []
	for s in tiles.get_source_count():
		var source := tiles.get_source(tiles.get_source_id(s)) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var entry := _palette_entry(tiles.get_source_id(s), source, source.get_tile_id(i))
			if entry != null:
				entries.append(entry)
	entries.sort_custom(_palette_order)
	for entry in entries:
		_tile_sources.append(entry.source_id)
		_tile_coords.append(entry.coords)
		tile_dropdown.add_icon_item(entry.icon, entry.label)
	if not _tile_coords.is_empty():
		selected_source = _tile_sources[0]
		selected_tile = _tile_coords[0]

# A tile earns a palette slot by saying what it IS: a non-NONE terrain_type kind, an authored
# terrain_name, or both. Unnamed bare decoration stays unpaintable. Labels prefer the authored
# name; unnamed terrain falls back to kind + atlas coords. Null = not a palette tile.
func _palette_entry(source_id: int, source: TileSetAtlasSource, coords: Vector2i) -> PaletteEntry:
	var data := source.get_tile_data(coords, 0)
	if data == null:
		return null
	var kind := Terrain.Kind.NONE
	if data.has_custom_data("terrain_type"):
		var raw: int = data.get_custom_data("terrain_type")
		if raw >= 0 and raw < Terrain.Kind.size():
			kind = raw as Terrain.Kind
		else:
			push_warning("TileBrushTool: tile %s carries terrain_type %d, not in Terrain.Kind; treating as scenery" % [coords, raw])
	var tile_name := ""
	if data.has_custom_data("terrain_name"):
		tile_name = data.get_custom_data("terrain_name")
	if kind == Terrain.Kind.NONE and tile_name == "":
		return null
	var entry := PaletteEntry.new()
	entry.kind = kind
	entry.source_id = source_id
	entry.coords = coords
	entry.label = tile_name.capitalize() if tile_name != "" \
		else "%s (%d:%d)" % [Terrain.kind_display_name(kind), coords.x, coords.y]
	var icon := AtlasTexture.new()
	icon.atlas = source.texture
	icon.region = source.get_tile_texture_region(coords)
	entry.icon = icon
	return entry

# Real terrain first (grouped by kind, enum order), named scenery last; stable within a kind
# by source then sheet position.
static func _palette_order(a: PaletteEntry, b: PaletteEntry) -> bool:
	var a_scenery := a.kind == Terrain.Kind.NONE
	var b_scenery := b.kind == Terrain.Kind.NONE
	if a_scenery != b_scenery:
		return b_scenery
	if a.kind != b.kind:
		return a.kind < b.kind
	if a.source_id != b.source_id:
		return a.source_id < b.source_id
	if a.coords.y != b.coords.y:
		return a.coords.y < b.coords.y
	return a.coords.x < b.coords.x

func _on_tile_brush_toggled(pressed: bool):
	brush_active = pressed

func _on_tile_dropdown_item_selected(index: int):
	if index >= 0 and index < _tile_coords.size():
		selected_tile = _tile_coords[index]
		selected_source = _tile_sources[index]

func deactivate():
	$Panel/TileBrushRow/TileBoxCheck.button_pressed = false

func _on_resize_pressed() -> void:
	if game == null:
		return
	game.dev_controller.resize_map(int(_width_spin.value), int(_height_spin.value), selected_source, selected_tile)
	
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

	# Part 3: the paint-mode picker (#174 made it three-way; a checkbox can't hold a third mode).
	# A capture point is a zone of kind CAPTURE, so zones stay ONE mode with a kind picker rather
	# than a mode per objective type. Each mode's own controls hide with it.
	DevWidgets.add_option(self, "Paint", MODE_LABELS, MODE_LABELS[0],
		func(label: String): _set_paint_mode(MODE_LABELS.find(label) as PaintMode))
	_tile_row = HBoxContainer.new()
	var tile_label := Label.new()
	tile_label.text = "Terrain Tile"
	_tile_row.add_child(tile_label)
	tile_dropdown = OptionButton.new()
	tile_dropdown.item_selected.connect(_on_tile_dropdown_item_selected)
	_tile_row.add_child(tile_dropdown)
	add_child(_tile_row)
	_zone_kind_row = DevWidgets.add_option(self, "Zone Kind", KIND_LABELS, KIND_LABELS[0],
		func(label: String): _zone_kind = KIND_LABELS.find(label) as ZoneManager.Kind)
	_zone_name_row = DevWidgets.add_lineedit(self, "Zone Name", "", func(s): _zone_name = s)

	# Part 4: dynamic tile-state painting (#174). Options scan the enum, so a new state shows up
	# here automatically; NONE means "unset" and is not paintable.
	_build_state_options()
	_state_row = DevWidgets.add_option(self, "Tile State", _state_labels, _state_labels[0],
		func(label: String): _tile_state = _state_values[_state_labels.find(label)])
	_clear_states_button = Button.new()
	_clear_states_button.text = "Clear All Tile States"
	_clear_states_button.tooltip_text = "Wipe every dynamic tile state on the board (fire/ice/cover). Unsaved paint is lost."
	_clear_states_button.pressed.connect(_on_clear_states_pressed)
	add_child(_clear_states_button)
	_set_paint_mode(PaintMode.TERRAIN)

func _build_state_options() -> void:
	for i in Terrain.TileState.size():
		var state: Terrain.TileState = Terrain.TileState.values()[i]
		if state == Terrain.TileState.NONE:
			continue
		var state_name: String = Terrain.TileState.keys()[i]
		_state_values.append(state)
		_state_labels.append(state_name.capitalize())

func selected_zone_kind() -> ZoneManager.Kind:
	return _zone_kind

func selected_tile_state() -> Terrain.TileState:
	return _tile_state

func _set_paint_mode(mode: PaintMode) -> void:
	paint_mode = mode
	_tile_row.visible = mode == PaintMode.TERRAIN
	_zone_kind_row.visible = mode == PaintMode.ZONE
	_zone_name_row.visible = mode == PaintMode.ZONE
	_state_row.visible = mode == PaintMode.STATE
	_clear_states_button.visible = mode == PaintMode.STATE

# The board-wide wipe (dev ask 2026-08-11); per-cell erase stays right-click. Confirmed because
# unsaved paint dies with it; the wipe pair is clear_board's own (clear + full redraw).
func _on_clear_states_pressed() -> void:
	DevWidgets.confirm_delete(self, "every tile state on the board", _clear_states_confirmed)

func _clear_states_confirmed() -> void:
	if game == null:
		return
	game.terrain_states.clear()
	game.overlay_manager.redraw_terrain_live(game.terrain_states)
