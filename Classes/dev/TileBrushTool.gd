extends VBoxContainer
class_name TileBrushTool

# Dev-overlay tab for authoring the board: paints terrain tiles, dynamic tile states (#174),
# named zones, and per-cell elevation + ramps (#260) — left-drag paints, right-drag erases in
# every mode — plus map resize.
# Terrain choices are scanned from the tileset itself, never hardcoded: every tile carrying a
# terrain_type kind or an authored terrain_name is paintable, across all atlas sources.
# Zone mode carries a picker (2026-08-12): a dropdown of every painted zone, so authoring can
# see what exists and continue a zone instead of accidentally forking a new one; the picked
# zone's cells are lifted on the board via OverlayManager.redraw_zone_highlight.
# Elevation is NOT a mode (#340, reversing #260's shape): the level and the ramp rise ride the
# TERRAIN brush, so one click paints a tile AT a height. Height stays in a per-cell store for the
# reason #260 gave — a per-tile elevation would need one grass tile per level — but "how high" was
# never a different QUESTION from "which tile", only a different store, and a mode per store made
# authoring a raised cell two gestures. Raising a cell is now repainting it at a new level.
# The rise is refused for a tile that stands up (see selected_rise): a rock has no face to tilt.

const KIND_LABELS := ["Patrol", "Capture", "Extraction"]   # index == ZoneManager.Kind value
const MODE_LABELS := ["Terrain", "Zones", "Tile States"]   # index == PaintMode value

var brush_active := false
var selected_tile := Vector2i(5, 0)
var selected_source := 0
var game   # injected by DevOverlay.init
enum PaintMode { TERRAIN, ZONE, STATE }
var paint_mode := PaintMode.TERRAIN
const NEW_ZONE_LABEL := "(new zone)"
var _zone_name := ""
var _zone_name_row: HBoxContainer
var _zone_name_edit: LineEdit
var _zone_kind_row: HBoxContainer
var _zone_kind_option: OptionButton
var _zone_kind := ZoneManager.Kind.PATROL   # the user's pick; applies to NEW zones only
var _zone_row: HBoxContainer
var zone_dropdown: OptionButton
# Parallel to the dropdown rows past "(new zone)": names index the store, labels are the
# rendered rows and double as the rebuild diff (a drag emits zones_changed per cell).
var _zone_dropdown_names: Array[String] = []
var _zone_dropdown_labels: Array[String] = []
var _tile_state := Terrain.TileState.BURNING
var _state_row: HBoxContainer
var _clear_states_button: Button
var _state_labels: Array[String] = []
var _state_values: Array[Terrain.TileState] = []

# The terrain brush's elevation half (#260, merged in by #340): the height the next click places at,
# which way that cell rises, and — since #427 slice 2 — how far.
# One click writes all THREE, because BoardHeights.set_cell takes them together; separate brushes
# would be separate ways to author one cell. NOT clamped at 0: a dip has to be authorable without
# lifting the whole map (dev, 2026-08-15).
#
# Direction and amount are separate controls by dev call (2026-08-23), against folding them into one
# nine-entry dropdown: Z/C stay a four-step compass turn, and steepness is the rarely-touched
# setting it actually is.
var _elevation := 0
var _rise := Terrain.RampRise.NONE
var _climb := Terrain.UNITS_PER_LEVEL
var _depth := Terrain.UNITS_PER_LEVEL
var _elevation_row: HBoxContainer
var _elevation_spin: SpinBox
var _rise_row: HBoxContainer
var _rise_option: OptionButton
var _climb_row: HBoxContainer
var _climb_option: OptionButton
var _depth_row: HBoxContainer
var _depth_option: OptionButton

# How far a ramp climbs, steepest first so the historical default sits at index 0. The list is both
# the picker's row order and the X key's cycle order, RISE_CYCLE's rule one field along.
const CLIMB_CYCLE: Array[int] = [Terrain.UNITS_PER_LEVEL, 1]
const CLIMB_LABELS := ["Full (45°)", "Half (26.6°)"]   # index == CLIMB_CYCLE index

# How deep the 3D selector reads, in the store's own units — the same list shape one field along, so
# the dropdown and the V key cannot disagree about what comes next. A LEVEL first: that is the slab a
# paint makes, and it is the default for the same reason.
#
# Deliberately NOT a passenger on CLIMB_CYCLE despite reading the same two numbers (dev call,
# 2026-08-23). How deep the selector reads and how steep a ramp climbs are different questions, and
# folding them would leave no way to get a one-unit selector while painting flat ground — which is
# most of the time it matters.
const DEPTH_CYCLE: Array[int] = [Terrain.UNITS_PER_LEVEL, 1]
const DEPTH_LABELS := ["Level (whole block)", "Half (one unit)"]   # index == DEPTH_CYCLE index

# COMPASS order, not enum order, and it is both the picker's row order and the Z/C cycle order —
# one list, so the dropdown and the keys cannot disagree about what comes next. Turning has to read
# as turning (N -> E -> S -> W), where the enum declares N/S then E/W; NONE rides along so flat
# ground is reachable without a menu trip, which is the whole point of the keys.
# tests/dev/test_height_brush.gd pins it against Terrain.RampRise, so a new direction cannot ship
# missing from the picker.
const RISE_CYCLE: Array[Terrain.RampRise] = [
	Terrain.RampRise.NONE,
	Terrain.RampRise.NORTH,
	Terrain.RampRise.EAST,
	Terrain.RampRise.SOUTH,
	Terrain.RampRise.WEST
]

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
var _undo_button: Button
var _redo_button: Button

func _ready():
	_build_extra_controls()

# Called by DevOverlay once the Game ref exists — the scan needs game.grid.tile_set, which
# isn't available at _ready. Mirrors spawn.init / unit_editor.init.
func init(game_ref) -> void:
	game = game_ref
	_populate_tile_dropdown()
	# One wire covers every zone mutation path -- brush paint/erase, scenario load, clear_board,
	# F2 reset -- so the picker can never list a board that no longer exists.
	game.zone_manager.zones_changed.connect(_on_zones_changed)
	refresh_zone_list()
	# Pushed, not polled (#391): every writer of the history is DevController, so it can say when.
	game.dev_controller.history_changed.connect(_refresh_undo_row)
	_refresh_undo_row()

func _on_zones_changed() -> void:
	refresh_zone_list()
	update_zone_highlight()

func _on_undo_pressed() -> void:
	if game != null:
		game.dev_controller.undo_board()

func _on_redo_pressed() -> void:
	if game != null:
		game.dev_controller.redo_board()

# Greyed rather than hidden: a row that vanishes at the bottom of the history moves every control
# under it. Built before init() runs, so this has to answer with no game ref too.
func _refresh_undo_row() -> void:
	if _undo_button == null:
		return
	var can_undo := false
	var can_redo := false
	if game != null:
		var history: BoardHistory = game.dev_controller.history   # typed: game is untyped
		can_undo = history.can_undo()
		can_redo = history.can_redo()
	_undo_button.disabled = not can_undo
	_redo_button.disabled = not can_redo

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
	_sync_rise_availability()

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
	var tile_name := GridUtils.authored_tile_display_name(data)
	if kind == Terrain.Kind.NONE and tile_name == "":
		return null
	var entry := PaletteEntry.new()
	entry.kind = kind
	entry.source_id = source_id
	entry.coords = coords
	entry.label = tile_name if tile_name != "" \
		else "%s (%d:%d)" % [Terrain.kind_display_name(kind), coords.x, coords.y]
	entry.icon = GridUtils.tile_sprite(source, coords)
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
		_sync_rise_availability()

# Grey the rise picker for a tile that cannot slope, so selected_rise's refusal is VISIBLE rather
# than a setting that silently does nothing.
func _sync_rise_availability() -> void:
	var flat := selected_tile_is_flat()
	if _rise_option != null:
		_rise_option.disabled = not flat
	if _climb_option != null:
		_climb_option.disabled = not flat

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
	note.text = "Left-drag paints  ·  right-drag erases"
	add_child(note)

	# The undo row (#391), directly under the gesture it undoes. A visible door beside Ctrl+Z, and
	# the only one that works with the pointer over this window rather than the board.
	var undo_row := HBoxContainer.new()
	_undo_button = Button.new()
	_undo_button.text = "Undo"
	_undo_button.tooltip_text = "Undo the last board edit — a whole drag, not one cell (Ctrl+Z)"
	_undo_button.pressed.connect(_on_undo_pressed)
	undo_row.add_child(_undo_button)
	_redo_button = Button.new()
	_redo_button.text = "Redo"
	_redo_button.tooltip_text = "Redo the edit you just undid (Ctrl+Shift+Z or Ctrl+Y)"
	_redo_button.pressed.connect(_on_redo_pressed)
	undo_row.add_child(_redo_button)
	add_child(undo_row)
	_refresh_undo_row()

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
	# Zone picker rows, hand-built rather than DevWidgets.add_option: these refresh and
	# enable/disable live, and add_option builds a one-shot list (the #179 trap).
	_zone_row = HBoxContainer.new()
	var zone_label := Label.new()
	zone_label.text = "Zone"
	_zone_row.add_child(zone_label)
	zone_dropdown = OptionButton.new()
	zone_dropdown.item_selected.connect(_on_zone_dropdown_item_selected)
	_zone_row.add_child(zone_dropdown)
	add_child(_zone_row)

	_zone_kind_row = HBoxContainer.new()
	var kind_label := Label.new()
	kind_label.text = "Zone Kind"
	_zone_kind_row.add_child(kind_label)
	_zone_kind_option = OptionButton.new()
	for label in KIND_LABELS:
		_zone_kind_option.add_item(label)
	_zone_kind_option.select(0)
	_zone_kind_option.item_selected.connect(func(idx: int): _zone_kind = idx as ZoneManager.Kind)
	_zone_kind_row.add_child(_zone_kind_option)
	add_child(_zone_kind_row)

	_zone_name_row = HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Zone Name"
	_zone_name_row.add_child(name_label)
	_zone_name_edit = LineEdit.new()
	_zone_name_edit.custom_minimum_size = Vector2(100, 0)
	_zone_name_edit.text_changed.connect(_on_zone_name_changed)
	_zone_name_row.add_child(_zone_name_edit)
	add_child(_zone_name_row)

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

	# Part 5: the elevation brush (#260). Hand-built rather than DevWidgets.add_spinbox/add_option
	# for the reason the zone rows are: the wheel writes the level back INTO the SpinBox, and
	# add_option builds a one-shot list (the #179 trap).
	_elevation_row = HBoxContainer.new()
	var level_label := Label.new()
	level_label.text = "Height"
	_elevation_row.add_child(level_label)
	_elevation_spin = SpinBox.new()
	_elevation_spin.min_value = -99 * Terrain.UNITS_PER_LEVEL
	_elevation_spin.max_value = 99 * Terrain.UNITS_PER_LEVEL
	# ONE UNIT per notch since #427 slice 2 -- the mirror's rows are half levels now, so a half-level
	# platform is something the renderer can say and the door no longer has to hold it back.
	_elevation_spin.step = 1
	_elevation_spin.value = _elevation
	_elevation_spin.value_changed.connect(func(v: float): set_elevation(int(v)))
	_elevation_row.add_child(_elevation_spin)
	var reset := Button.new()
	reset.text = "Reset to flat (0)"
	reset.pressed.connect(reset_elevation)
	_elevation_row.add_child(reset)
	add_child(_elevation_row)
	DevWidgets.apply_tooltip(_elevation_row, DevWidgets.wrap_tooltip(
		"Height the brush paints at, in half-level units — one full level is %d, so an odd number is "
		% Terrain.UNITS_PER_LEVEL
		+ "a half-level platform. Scroll the mouse wheel over the board to change it, one unit per "
		+ "notch -- hold Ctrl to zoom the camera instead. Reset returns the brush to flat ground: "
		+ "height 0, no ramp. Negative heights are dips."))

	_rise_row = HBoxContainer.new()
	var rise_label := Label.new()
	rise_label.text = "Ramp Rise"
	_rise_row.add_child(rise_label)
	_rise_option = OptionButton.new()
	for rise in RISE_CYCLE:
		_rise_option.add_item(Terrain.ramp_rise_display_name(rise))
	_rise_option.select(RISE_CYCLE.find(_rise))
	_rise_option.item_selected.connect(func(idx: int): set_rise(RISE_CYCLE[idx]))
	_rise_row.add_child(_rise_option)
	add_child(_rise_row)
	DevWidgets.apply_tooltip(_rise_row, DevWidgets.wrap_tooltip(
		"Which way this cell RISES — Z and C turn it, the way Q and E turn the board. A ramp's own "
		+ "height is its LOW side, so a ramp at height 4 rising North connects height 4 to whatever "
		+ "its Rise Amount climbs to. None = ordinary flat ground. Greyed out for a tile that stands "
		+ "up (a rock, a lantern): only flat ground can slope, and the ramp wears whatever ground you "
		+ "paint on it."))

	_climb_row = HBoxContainer.new()
	var climb_label := Label.new()
	climb_label.text = "Rise Amount"
	_climb_row.add_child(climb_label)
	_climb_option = OptionButton.new()
	for label in CLIMB_LABELS:
		_climb_option.add_item(label)
	_climb_option.select(CLIMB_CYCLE.find(_climb))
	_climb_option.item_selected.connect(func(idx: int): set_climb(CLIMB_CYCLE[idx]))
	_climb_row.add_child(_climb_option)
	add_child(_climb_row)
	DevWidgets.apply_tooltip(_climb_row, DevWidgets.wrap_tooltip(
		"How FAR a ramp climbs — X cycles it, between Z and C so the three read as one gesture. "
		+ "Full is the 45-degree ramp that has always existed: %d units, a whole level over one cell. "
		% Terrain.UNITS_PER_LEVEL
		+ "Half is the gentle slope, one unit over one cell, so two of them stacked climb a level "
		+ "across two cells. Greyed out with the direction, for the same reason."))

	_depth_row = HBoxContainer.new()
	var depth_label := Label.new()
	depth_label.text = "Selector Depth"
	_depth_row.add_child(depth_label)
	_depth_option = OptionButton.new()
	for label in DEPTH_LABELS:
		_depth_option.add_item(label)
	_depth_option.select(DEPTH_CYCLE.find(_depth))
	_depth_option.item_selected.connect(func(idx: int): set_depth(DEPTH_CYCLE[idx]))
	_depth_row.add_child(_depth_option)
	add_child(_depth_row)
	DevWidgets.apply_tooltip(_depth_row, DevWidgets.wrap_tooltip(
		"How deep the 3D selector reads — V cycles it. Level covers the whole block a paint makes "
		+ "(%d units); Half covers one unit, the amount a wheel notch moves. It changes only what the "
		% Terrain.UNITS_PER_LEVEL
		+ "preview COVERS, never what the click paints, and both settings sit their top face on the "
		+ "surface you are about to author. A ramp ignores it — a wedge already shows its own volume."))

	_set_paint_mode(PaintMode.TERRAIN)

func selected_elevation() -> int:
	return _elevation

# What the next click would actually SLOPE — not simply the picker's value (#340). A standing tile
# has no top face to tilt, so a rock or a lantern paints flat however the picker is set.
#
# The gate lives HERE rather than at the paint site because the GHOST reads this too: gated one level
# down, the preview would show a sloping rock that the paint then refuses, which is #285's rule that
# a preview must answer "what would this click PRODUCE". `_rise` itself is untouched, so picking a
# prop and coming back to grass restores the direction you had.
func selected_rise() -> Terrain.RampRise:
	return _rise if selected_tile_is_flat() else Terrain.RampRise.NONE

# How far that slope climbs. NOT gated on the flat tile the way selected_rise is: a refused rise is
# already NONE, and corners_of_ramp ignores the climb entirely then — gating both would be two
# spellings of one refusal.
func selected_climb() -> int:
	return _climb

# How deep the 3D selector draws. Ungated for the same reason selected_climb is: it describes the
# PREVIEW rather than the paint, so there is no tile it could be wrong for.
func selected_depth() -> int:
	return _depth

# Whether the PICKED tile is ground rather than something standing on it. GridUtils.stands_up_of is
# the one answer (derived from prop_shape); an unresolvable pick reads flat, the same permissive
# default an unauthored tile gets there.
func selected_tile_is_flat() -> bool:
	if game == null or game.grid == null or game.grid.tile_set == null:
		return true
	var source := game.grid.tile_set.get_source(selected_source) as TileSetAtlasSource
	if source == null or not source.has_tile(selected_tile):
		return true
	return not GridUtils.stands_up_of(source.get_tile_data(selected_tile, 0))

# The ONE writer of the brush level: the wheel, the SpinBox and Reset all land here, so the widget
# and the value the brush paints with cannot drift. set_value_no_signal, or the SpinBox's own
# value_changed would call straight back into this.
func set_elevation(value: int) -> void:
	_elevation = value
	if _elevation_spin != null:
		_elevation_spin.set_value_no_signal(value)

# One wheel notch is one UNIT -- half a level -- matching the SpinBox's step exactly. It moved a
# whole LEVEL when #427 slice 2 landed, on the theory that the wheel is the gesture and the SpinBox
# the resolution. That was wrong and the dev found it immediately: the wheel is the only thing that
# changes height MID-STROKE, so a two-cell gentle slope (heights 0 then 1) was unbuildable with it
# -- "I have no way to connect more than one half slope together, or to anything else."
func nudge_elevation(delta: int) -> void:
	set_elevation(_elevation + delta)

# The ONE writer of the rise, the set_elevation twin: the dropdown, the Z/C keys and Reset all land
# here, so the picker always shows what the next click will paint.
func set_rise(rise: Terrain.RampRise) -> void:
	_rise = rise
	if _rise_option != null:
		_rise_option.select(RISE_CYCLE.find(rise))

# The same for how far it climbs (#427 slice 2) — the dropdown and the X key.
func set_climb(climb: int) -> void:
	_climb = climb
	if _climb_option != null:
		_climb_option.select(CLIMB_CYCLE.find(climb))

# Turn the rise one step (dev ask 2026-08-15: a menu trip per direction is the wrong cost for
# something you change constantly). Wraps, so the keys alone reach every value including flat.
func cycle_rise(delta: int) -> void:
	var index := RISE_CYCLE.find(_rise)
	if index == -1:
		index = 0
	set_rise(RISE_CYCLE[posmod(index + delta, RISE_CYCLE.size())])

# Same wrap, one list along: X alternates the two steepnesses.
func cycle_climb() -> void:
	var index := CLIMB_CYCLE.find(_climb)
	if index == -1:
		index = 0
	set_climb(CLIMB_CYCLE[posmod(index + 1, CLIMB_CYCLE.size())])

# The same for how deep the selector reads — the dropdown and the V key.
func set_depth(depth: int) -> void:
	_depth = depth
	if _depth_option != null:
		_depth_option.select(DEPTH_CYCLE.find(depth))

# And the same wrap again: V alternates the two selector depths.
func cycle_depth() -> void:
	var index := DEPTH_CYCLE.find(_depth)
	if index == -1:
		index = 0
	set_depth(DEPTH_CYCLE[posmod(index + 1, DEPTH_CYCLE.size())])

# Back to plain flat ground, which is height AND direction: a reset that left the rise armed would
# still paint ramps, and "flat" is what the button is for. The CLIMB deliberately survives — it is a
# steepness preference rather than a piece of the shape, and re-picking it every reset is the
# friction the separate control exists to avoid. So does the selector DEPTH, more plainly still: it
# is not part of the shape at all, only of how the preview draws one.
func reset_elevation() -> void:
	set_elevation(0)
	set_rise(Terrain.RampRise.NONE)

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

# Rebuild the picker from the store. Diffed against the rendered labels first: a paint drag emits
# zones_changed per cell, and identical rows mean nothing to rebuild. Selection re-binds by NAME
# after the select(-1) reset (add_item auto-selects row 0 -- the OptionButton sharp edge); a
# vanished pick falls back to "(new zone)" with the typed name kept.
func refresh_zone_list() -> void:
	if game == null:
		return
	var names: Array[String] = game.zone_manager.zone_names()
	var labels: Array[String] = []
	for name in names:
		labels.append("%s (%s)" % [name, KIND_LABELS[game.zone_manager.kind_of(name)]])
	if labels == _zone_dropdown_labels:
		return
	_zone_dropdown_names = names
	_zone_dropdown_labels = labels
	zone_dropdown.clear()
	zone_dropdown.add_item(NEW_ZONE_LABEL)
	for label in labels:
		zone_dropdown.add_item(label)
	zone_dropdown.select(-1)
	var idx := _zone_dropdown_names.find(selected_zone_name())
	zone_dropdown.select(idx + 1 if idx >= 0 else 0)
	_sync_kind_row()

func _on_zone_dropdown_item_selected(index: int) -> void:
	if index <= 0:
		# "(new zone)": clear the name, or the old pick would re-bind on the next keystroke.
		_zone_name = ""
		_zone_name_edit.text = ""
	else:
		_zone_name = _zone_dropdown_names[index - 1]
		_zone_name_edit.text = _zone_name
	_sync_kind_row()
	update_zone_highlight()

# Typing a name that exactly matches a painted zone IS picking it -- painting under an existing
# name always continues that zone, so the picker must say so before the first click does it.
func _on_zone_name_changed(text: String) -> void:
	_zone_name = text
	var idx := _zone_dropdown_names.find(selected_zone_name())
	zone_dropdown.select(idx + 1 if idx >= 0 else 0)
	_sync_kind_row()
	update_zone_highlight()

# Kind is authored at zone creation only (dev call 2026-08-12; repainting used to silently retype
# the whole zone). While the current name is a painted zone the picker shows that zone's real kind
# and greys out -- a control only greys what it can explain (#166 shape).
func _sync_kind_row() -> void:
	var existing: bool = game != null and game.zone_manager.zone_names().has(selected_zone_name())
	_zone_kind_option.disabled = existing
	if existing:
		_zone_kind_option.select(game.zone_manager.kind_of(selected_zone_name()))
		_zone_kind_option.tooltip_text = "Kind locks when a zone is first painted — pick a new name to choose a kind."
	else:
		_zone_kind_option.select(_zone_kind)
		_zone_kind_option.tooltip_text = ""

# The picked zone's cells, lifted on the board. Public: DevController re-pushes it after every
# zone paint/erase, since the cells change under an unchanged pick.
func update_zone_highlight() -> void:
	if game == null:
		return
	var cells: Array[Vector2i] = []
	if paint_mode == PaintMode.ZONE:
		cells = game.zone_manager.cells_in(selected_zone_name())
	game.overlay_manager.redraw_zone_highlight(cells)

func selected_tile_state() -> Terrain.TileState:
	return _tile_state

func _set_paint_mode(mode: PaintMode) -> void:
	paint_mode = mode
	_tile_row.visible = mode == PaintMode.TERRAIN
	_zone_row.visible = mode == PaintMode.ZONE
	_zone_kind_row.visible = mode == PaintMode.ZONE
	_zone_name_row.visible = mode == PaintMode.ZONE
	_state_row.visible = mode == PaintMode.STATE
	_clear_states_button.visible = mode == PaintMode.STATE
	# Level and rise ride the TERRAIN brush rather than a mode of their own (#340): a tile is painted
	# AT a height, so asking how high is part of asking which tile, not a separate question.
	_elevation_row.visible = mode == PaintMode.TERRAIN
	_rise_row.visible = mode == PaintMode.TERRAIN
	update_zone_highlight()   # draws on entering ZONE mode, clears on leaving it

# NB the height readout is NOT lit from here. Painting height into an invisible store is blind, so it
# follows the brush — but "is the level brush live?" is DevController's predicate, and it polls it
# (_sync_height_readout). A mode compare here would be a second answer that cannot see the checkbox.

# The board-wide wipe (dev ask 2026-08-11); per-cell erase stays right-click. Confirmed because
# unsaved paint dies with it; the wipe pair is clear_board's own (clear + full redraw).
func _on_clear_states_pressed() -> void:
	DevWidgets.confirm_delete(self, "every tile state on the board", _clear_states_confirmed)

func _clear_states_confirmed() -> void:
	if game == null:
		return
	game.dev_controller.clear_tile_states()   # through the controller so the wipe is one undo step (#391)
