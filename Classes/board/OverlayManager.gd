extends Node
class_name OverlayManager

@onready var move_overlay = $MoveOverlay
@onready var attack_overlay = $AttackOverlay
@onready var hover_overlay = $HoverOverlay
@onready var squad_overlay = $SquadOverlay
@onready var icon_overlay = $IconOverlay
@onready var arrow_icon_overlay: Node2D = $ArrowIconOverlay
@onready var projected_unit_overlay: Node2D = $ProjectedUnitOverlay
@onready var squadrange_overlay = $SquadRangeOverlay
@onready var invalidmove_overlay = $InvalidMoveOverlay
@onready var board_tilemap = $"../Grid"
@onready var zone_overlay = $ZoneOverlay
@onready var capture_overlay = $CaptureOverlay
@onready var extraction_overlay = $ExtractionOverlay

const PATH_ERROR := preload("res://Art/Icons/ArrowIcons/ERROR.png")
const PATH_HORIZONTAL := preload("res://Art/Icons/ArrowIcons/horizontal.png")
const PATH_VERTICAL := preload("res://Art/Icons/ArrowIcons/vertical.png")

const PATH_UP_RIGHT := preload("res://Art/Icons/ArrowIcons/topright.png")
const PATH_UP_LEFT := preload("res://Art/Icons/ArrowIcons/topleft.png")
const PATH_DOWN_RIGHT := preload("res://Art/Icons/ArrowIcons/bottomright.png")
const PATH_DOWN_LEFT := preload("res://Art/Icons/ArrowIcons/bottomleft.png")

const PATH_START_RIGHT := preload("res://Art/Icons/ArrowIcons/startright.png")
const PATH_START_LEFT := preload("res://Art/Icons/ArrowIcons/startleft.png")
const PATH_START_UP := preload("res://Art/Icons/ArrowIcons/starttop.png")
const PATH_START_DOWN := preload("res://Art/Icons/ArrowIcons/startbottom.png")

const PATH_ARROW_RIGHT := preload("res://Art/Icons/ArrowIcons/endfromleft.png")
const PATH_ARROW_LEFT := preload("res://Art/Icons/ArrowIcons/endfromright.png")
const PATH_ARROW_UP := preload("res://Art/Icons/ArrowIcons/endfrombottom.png")
const PATH_ARROW_DOWN := preload("res://Art/Icons/ArrowIcons/endfromtop.png")

const TERRAIN_STATE_ICONS: Dictionary = {
	Terrain.TileState.BURNING: preload("res://Art/Icons/TerrainIcons/Fire.png"),
	Terrain.TileState.FROZEN: preload("res://Art/Icons/TerrainIcons/Ice.png"),
	Terrain.TileState.COVER: preload("res://Art/Icons/TerrainIcons/Cover.png"),
}

const TERRAIN_Z_INDEX := 1                                # above the board, below unit sprites — tweak by eye
const TERRAIN_PREVIEW_MODULATE := Color(1, 1, 1, 0.5)     # ghost the pending-ignite marker (Part B)

const ICON_SCENE = preload("res://Scenes/OverlayIcon.tscn")
const SOURCE_ID = 0
# The overlay tileset's atlas coordinates, and the single home for them: game.gd used to keep a
# duplicate `OVERLAY_DEFAULT_ATLAS = Vector2i(0,0)` plus five more that were never referenced.
const ATLAS_COORDS = Vector2i(0,0)          # plain fill — what every overlay layer draws with
const TARGET_ATLAS_COORDS = Vector2i(3, 0)  # the "pick this unit" marker (PICKING_TARGET)
const ICON_Z_INDEX = 15

const PROJECTED_MODULATE := Color(0.7, 0.9, 1, 0.75)        # the planning-ghost tint
const PROJECTED_HIGHLIGHT := Color(1.4, 1.4, 1.0, 1.0)      # brightened + opaque on hover
const HOVER_MODULATE := Color(1, 1, 0)                  # the aim-footprint fill
const HOVER_PULSE_MODULATE := Color(1, 1, 0, 0.3)       # its pulsed low point


enum OverlayType {
	MOVE,
	ATTACK,
	HOVER,
	SQUAD,
	ARROW,
	SQUADRANGE,
	INVALIDMOVE
}

const ICON_TEXTURES = {
	OverlayIcon.IconType.CURSOR: preload("res://Art/Icons/BoardIcons/CursorIcon.png"),
	OverlayIcon.IconType.CROWN: preload("res://Art/Icons/BoardIcons/CrownIcon.png"),
	OverlayIcon.IconType.TARGET: preload("res://Art/Icons/BoardIcons/SelectedIcon.png"),
	OverlayIcon.IconType.INVALID: preload("res://Art/Icons/BoardIcons/NegativeIcon.png"),
	OverlayIcon.IconType.SQUADMEMBER: preload("res://Art/Icons/BoardIcons/SquadHighlightIcon.png")
}

var overlay_map = {}
var icons_by_unit := {} # { Unit : { IconType : OverlayIcon } }
var planned_move_by_unit := {} #{Unit : MoveAction}
var terrain_live_sprites: Array[Sprite2D] = []       # live terrain icons (persist across selection)
var terrain_preview_sprites: Array[Sprite2D] = []    # ephemeral plan-time ghosts (Part B)
var hover_move_preview: MoveAction = null
var hover_move_previews: Array[MoveAction] = []
var projected_unit_sprites := {} # { Unit : Sprite2D }
var knockback_preview_sprites: Array[Node2D] = []
# ZoneManager.Kind -> the TileMapLayer that draws it. A layer per kind rather than a method per
# kind: colour is `modulate`, which is per-LAYER, so a kind that needs its own colour needs its
# own layer. Adding a kind is one line here.
var zone_layer_map := {}
# Knockback preview (#84): a ghosted arrow (target cell -> landing cell) plus a planning-ghost of
# the shoved unit where it lands. Same "resolve the plan, show it pending" rail as the terrain
# preview; its own sprite list so a plan change clears and redraws it cleanly.
var knockback_hidden_units: Array[Unit] = []   # shoved units whose real sprite we hid behind a ghost
var _pulsing_units: Array[Unit] = []
var _tile_pulse: Tween = null



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	overlay_map = {
		OverlayType.MOVE: move_overlay,
		OverlayType.ATTACK: attack_overlay,
		OverlayType.HOVER: hover_overlay,
		OverlayType.SQUAD: squad_overlay,
		OverlayType.ARROW: arrow_icon_overlay,
		OverlayType.SQUADRANGE: squadrange_overlay,
		OverlayType.INVALIDMOVE: invalidmove_overlay
	}
	
	move_overlay.modulate = Color(1, 1, 0, .5)
	attack_overlay.modulate = Color(1, 0, 0, .5)
	hover_overlay.modulate = HOVER_MODULATE
	squad_overlay.modulate = Color(1, 0.5, 0, 0.5)
	squadrange_overlay.modulate = Color(1, 0.5, 0, 0.5)
	invalidmove_overlay.modulate = Color(0.5, 0.36, 0.4, .5)
	zone_overlay.modulate = Color(1, 0.5, 0, 0.35)
	zone_overlay.visible = false   # authoring-only visual; DevOverlay shows it with the Tile Brush tab
	capture_overlay.modulate = Color(0.3, 0.9, 1, 0.5)
	extraction_overlay.modulate = Color(0.4, 1, 0.5, 0.5)
	# PATROL is an authoring aid (DevOverlay shows it with the Tile Brush tab); CAPTURE is live
	# objective information and stays visible for the whole battle.
	zone_layer_map = {
		ZoneManager.Kind.PATROL: zone_overlay,
		ZoneManager.Kind.CAPTURE: capture_overlay,
		ZoneManager.Kind.EXTRACTION: extraction_overlay,
	}

func show_overlay(type: int, cells: Array, atlas_coord: Vector2i):
	var layer = overlay_map[type]
	layer.clear()
	draw_cells(layer, cells, atlas_coord)

	# Move overlay always wins tiles it shares with squad tint (avoids alpha-stacked orange+yellow
	# bleed where a unit's move range overlaps its squad's leader range).
	if type == OverlayType.MOVE:
		for cell in cells:
			squad_overlay.erase_cell(cell)
			squadrange_overlay.erase_cell(cell)

# PATROL only -- capture zones are objective info, not an authoring overlay.
func set_zone_visibility(shown: bool) -> void:
	zone_overlay.visible = shown

# One method for every zone kind: each zone draws into the layer registered for its kind, and a
# kind with no layer simply isn't drawn. `hidden` drops zones that are done with (a captured
# point stops glowing) without needing a second redraw entry point.
func redraw_zones(zones: ZoneManager, hidden: Array[String] = []) -> void:
	for layer in zone_layer_map.values():
		layer.clear()
	for name in zones.zone_names():
		if hidden.has(name):
			continue
		var layer = zone_layer_map.get(zones.kind_of(name))
		if layer == null:
			continue
		draw_cells(layer, zones.cells_in(name), ATLAS_COORDS)

# The aim's live feedback: what the CURRENT aim would affect pulses, while the red reach layer never
# changes. WHICH channel pulses is the attack's own `targets` -- units, tiles or both -- so the kind
# of attack being aimed reads at a glance. Diffed against the previous set, not restarted: this runs
# on every hover change, and killing a tween per mouse-move strobes.
func set_target_pulse(units: Array[Unit], pulse_tiles: bool) -> void:
	for unit in _pulsing_units:
		if is_instance_valid(unit) and not units.has(unit):
			unit.visuals.stop_pulse()
	for unit in units:
		if is_instance_valid(unit) and not _pulsing_units.has(unit):
			unit.visuals.start_pulse()
	_pulsing_units = units.duplicate()

	if pulse_tiles and _tile_pulse == null:
		_tile_pulse = Pulse.start(self, hover_overlay, HOVER_MODULATE, HOVER_PULSE_MODULATE)
	elif not pulse_tiles and _tile_pulse != null:
		Pulse.stop(_tile_pulse, hover_overlay, HOVER_MODULATE)
		_tile_pulse = null

# The typed local is load-bearing: a bare [] literal passed to an Array[Unit] parameter fails at
# RUNTIME, not parse time (CLAUDE.md "Sharp edges").
func clear_target_pulse() -> void:
	var none: Array[Unit] = []
	set_target_pulse(none, false)

func show_hover_move_path(move: MoveAction):
	clear_hover_move_path()
	hover_move_preview = move
	draw_path_arrows(hover_move_preview)
	hover_move_preview.set_preview_z_index(MoveAction.HOVERED_ARROW_Z_INDEX)
	
func clear_hover_move_path():
	if hover_move_preview != null:
		hover_move_preview.clear_preview_sprites()
		hover_move_preview = null
	for m in hover_move_previews:
		m.clear_preview_sprites()
	hover_move_previews.clear()

# Plan-time preview of pending deposits (Law #2 — the board shows the ignite/entrenchment BEFORE
# you execute). Takes {"cell": Vector2i, "state": Terrain.TileState} entries (mirrors
# show_knockback_preview's shape) so each deposit draws its OWN icon — was BURNING-only until
# Burrow (#84) made a second previewable state real. Ephemeral: redrawn on plan change.
func show_terrain_preview(deposits: Array) -> void:
	clear_terrain_preview()
	for deposit in deposits:
		var state: Terrain.TileState = deposit["state"]
		if not TERRAIN_STATE_ICONS.has(state):
			continue
		var cell: Vector2i = deposit["cell"]
		var sprite := Sprite2D.new()
		sprite.texture = TERRAIN_STATE_ICONS[state]
		sprite.global_position = board_tilemap.to_global(board_tilemap.map_to_local(cell))
		sprite.z_index = TERRAIN_Z_INDEX
		sprite.modulate = TERRAIN_PREVIEW_MODULATE
		icon_overlay.add_child(sprite)
		terrain_preview_sprites.append(sprite)

func clear_terrain_preview() -> void:
	for sprite in terrain_preview_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	terrain_preview_sprites.clear()

# One entry per SHOVE ({"target", "from", "to"}), in resolve order. A unit can be shoved more than
# once in a plan (#105 — two maces, or a mace plus a counter), so this draws an arrow PER HIT but
# exactly ONE ghost per target, at the cell the chain ends on. Drawing a ghost per hit would leave a
# copy of the unit standing on every waypoint.
func show_knockback_preview(shoves: Array) -> void:
	clear_knockback_preview()

	var final_cell := {}   # Unit -> Vector2i; entries arrive in resolve order, so the last one wins
	for shove in shoves:
		final_cell[shove["target"]] = shove["to"]

	for shove in shoves:
		var from: Vector2i = shove["from"]
		var to: Vector2i = shove["to"]
		# The FACING, not the displacement: a shove of 2+ tiles (and, before #105, a mis-sourced
		# start cell) makes to - from a vector the arrow atlas has no texture for, so it fell
		# through to PATH_ERROR. Same helper the resolver picks the shove direction with.
		var dir := GridUtils.cardinal_direction_i_between(from, to)
		# arrow: start tile where the shove began, arrowhead on the landing cell (move atlases)
		knockback_preview_sprites.append(_create_arrow_sprite(from, _get_start_atlas(dir), Color.WHITE))
		knockback_preview_sprites.append(_create_arrow_sprite(to, _get_arrowhead_atlas(dir), Color.WHITE))

	# Hide each real sprite while its ghost stands in at the FINAL landing cell — the same pairing
	# redraw_projected_units uses for moves (set_projected hides, show_projected_unit draws).
	for target in final_cell:
		var unit: Unit = target
		unit.visuals.set_projected(true)
		knockback_hidden_units.append(unit)
		var ghost := Sprite2D.new()
		ghost.texture = unit.get_move_texture()
		ghost.global_position = board_tilemap.to_global(board_tilemap.map_to_local(final_cell[target]))
		ghost.z_index = Unit.BASE_SPRITE_INDEX
		ghost.modulate = PROJECTED_MODULATE
		ghost.offset = Vector2i(0, -8)
		projected_unit_overlay.add_child(ghost)
		knockback_preview_sprites.append(ghost)

func clear_knockback_preview() -> void:
	for unit in knockback_hidden_units:
		if is_instance_valid(unit):
			unit.visuals.set_projected(false)   # restore the real sprite
	knockback_hidden_units.clear()
	for sprite in knockback_preview_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	knockback_preview_sprites.clear()

func show_planned_path(unit: Unit, move: MoveAction):
	if planned_move_by_unit.has(unit):
		var old_move: MoveAction = planned_move_by_unit[unit]
		old_move.clear_preview_sprites()
		
	planned_move_by_unit[unit] = move
	redraw_planned_paths()

func clear_planned_path(unit: Unit):
	if planned_move_by_unit.has(unit):
		var move: MoveAction = planned_move_by_unit[unit]
		move.clear_preview_sprites()
	
	planned_move_by_unit.erase(unit)
	redraw_planned_paths()

func clear_all_planned_paths():
	clear_hover_move_path()
	
	for move: MoveAction in planned_move_by_unit.values():
		move.clear_preview_sprites()
	planned_move_by_unit.clear()

func redraw_planned_paths():
	for action: MoveAction in planned_move_by_unit.values():
		action.clear_preview_sprites()
		
	for action in planned_move_by_unit.values():
		draw_path_arrows(action)

func create_unit_icon(unit: Unit, type: OverlayIcon.IconType, offset := Vector2i.ZERO) -> OverlayIcon:
	if unit == null:
		return null
		
	if not icons_by_unit.has(unit):
		icons_by_unit[unit] = {}
		
	if icons_by_unit[unit].has(type):
		return icons_by_unit[unit][type]
		
	var icon := ICON_SCENE.instantiate()
	icon_overlay.add_child(icon)
	var cell := unit.get_projected_destination()
	icon.setup(ICON_TEXTURES[type], cell, type)
	icon.position = board_tilemap.map_to_local(cell) #+ offset
	
	icons_by_unit[unit][type] = icon
	return icon

func clear_unit_icon(unit: Unit, type: OverlayIcon.IconType):
	if not icons_by_unit.has(unit):
		return
		
	if not icons_by_unit[unit].has(type):
		return
		
	var icon: OverlayIcon = icons_by_unit[unit][type]
	if is_instance_valid(icon):
		icon.hide()
		icon.queue_free()
	
	icons_by_unit[unit].erase(type)
	if icons_by_unit[unit].is_empty():
		icons_by_unit.erase(unit)

func clear_unit_icons(unit: Unit):
	if not icons_by_unit.has(unit):
		return
		
	for type in icons_by_unit[unit].keys().duplicate():
		clear_unit_icon(unit, type)
	
func clear_unit_icon_types(types: Array[OverlayIcon.IconType]):
	for unit in icons_by_unit.keys().duplicate():
		if not is_instance_valid(unit):
			_purge_unit_entry(unit)
			continue
		for type in types:
			clear_unit_icon(unit, type)

func redraw_squad_unit_icons(squad: Squad):
	clear_unit_icon_types([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER])
	for member in squad.get_members():
		create_unit_icon(member, OverlayIcon.IconType.SQUADMEMBER)
		if member == squad.get_leader():
			create_unit_icon(member, OverlayIcon.IconType.CROWN)
				
func clear_selection_overlays():
	move_overlay.clear()
	attack_overlay.clear()
	hover_overlay.clear()
	squad_overlay.clear()
	invalidmove_overlay.clear()
	squadrange_overlay.clear()

# The live terrain state on the board (#50). Drawn from TerrainStateManager after execution,
# NOT cleared by clear_selection_overlays (or any selection change) — a burning tile stays burning regardless of what
# you click. Its own sprite dict, so the icon/overlay clears never touch it.
func redraw_terrain_live(states: TerrainStateManager) -> void:
	_clear_terrain_live()
	for state in TERRAIN_STATE_ICONS:
		var icon: Texture2D = TERRAIN_STATE_ICONS[state]
		for cell in states.cells_with(state):
			var sprite := Sprite2D.new()
			sprite.texture = icon
			sprite.global_position = board_tilemap.to_global(board_tilemap.map_to_local(cell))
			sprite.z_index = TERRAIN_Z_INDEX
			icon_overlay.add_child(sprite)
			terrain_live_sprites.append(sprite)

func _clear_terrain_live() -> void:
	for sprite in terrain_live_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	terrain_live_sprites.clear()

func clear_squad_range():
	squadrange_overlay.clear()
	
func draw_cells(layer: TileMapLayer, cells: Array, atlas_coord: Vector2i):
	for cell in cells:
		#if is_valid_cell(cell):
			layer.set_cell(cell, SOURCE_ID, atlas_coord)
		
func is_valid_cell(cell: Vector2i) -> bool:
	return move_overlay.get_used_rect().has_point(cell)

func draw_path_arrows(move: MoveAction):
	var path: Array[Vector2i] = move.get_move_path()
	var tint := _arrow_modulate(move)

	if move.is_hold_position:
		if not move.is_valid:
			var sprite := _create_arrow_sprite(move.destination, PATH_ERROR, tint)
			move.add_preview_sprite(sprite)
		return

	if path.is_empty():
		return

	if path.size() == 1:
		var sprite := _create_arrow_sprite(path[0], PATH_ERROR, tint)
		move.add_preview_sprite(sprite)
		return

	for i in range(path.size()):
		var current := path[i]
		var texture: Texture2D

		#Start tile
		if i == 0:
			var next := path[i + 1]
			var dir := next - current
			texture = _get_start_atlas(dir)

		#End tile / arrowhead
		elif i == path.size() - 1:
			var previous := path[i - 1]
			var dir := current - previous
			texture = _get_arrowhead_atlas(dir)

		#Middle tiles
		else:
			var previous := path[i - 1]
			var next := path[i + 1]
			var dir_to_prev := previous - current
			var dir_to_next := next - current
			texture = _get_path_segment_atlas(dir_to_prev, dir_to_next)

		var sprite := _create_arrow_sprite(current, texture, tint)
		move.add_preview_sprite(sprite)

func _get_arrowhead_atlas(dir: Vector2i) -> Texture2D:
	match dir:
		Vector2i.UP:
			return PATH_ARROW_UP
		Vector2i.RIGHT:
			return PATH_ARROW_RIGHT
		Vector2i.DOWN:
			return PATH_ARROW_DOWN
		Vector2i.LEFT:
			return PATH_ARROW_LEFT
		_:
			return PATH_ERROR
			
func _get_start_atlas(dir: Vector2i) -> Texture2D:
	match dir:
		Vector2i.UP:
			return PATH_START_UP
		Vector2i.DOWN:
			return PATH_START_DOWN
		Vector2i.LEFT:
			return PATH_START_LEFT
		Vector2i.RIGHT:
			return PATH_START_RIGHT
		_:
			return PATH_ERROR
			
func _get_path_segment_atlas(from_dir: Vector2i, to_dir: Vector2i) -> Texture2D:
	#Horizontal
	if _dirs_match(from_dir, to_dir, Vector2i.LEFT, Vector2i.RIGHT):
		return PATH_HORIZONTAL
	
	#Vertical
	if _dirs_match(from_dir, to_dir, Vector2i.UP, Vector2i.DOWN):
		return PATH_VERTICAL
		
	#Corners
	if _dirs_match(from_dir, to_dir, Vector2i.UP, Vector2i.RIGHT):
		return PATH_UP_RIGHT
	if _dirs_match(from_dir, to_dir, Vector2i.RIGHT, Vector2i.DOWN):
		return PATH_DOWN_RIGHT
	if _dirs_match(from_dir, to_dir, Vector2i.DOWN, Vector2i.LEFT):
		return PATH_DOWN_LEFT
	if _dirs_match(from_dir, to_dir, Vector2i.LEFT, Vector2i.UP):
		return PATH_UP_LEFT

	return PATH_ERROR

#Just to keep my cases tighter
func _dirs_match(a: Vector2i, b: Vector2i, dir1: Vector2i, dir2: Vector2i) -> bool:
	return (a == dir1 and b == dir2) or (a == dir2 and b == dir1)
	
# Arrow tint, worst-first: refused, following-but-falling-behind (Case 1), keeping formation.
# Separate from _create_arrow_sprite because the knockback preview draws the same arrows for a
# shove, which has no MoveAction to ask.
func _arrow_modulate(move: MoveAction) -> Color:
	if not move.is_valid:
		return Color(1, .25, .25, .85)
	if move.is_trailing:
		return Color(.4, 1, .45, .9)
	return Color.WHITE

func _create_arrow_sprite(cell: Vector2i, texture: Texture2D, tint: Color) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.z_index = MoveAction.ARROW_BASE_Z_INDEX
	sprite.global_position = board_tilemap.to_global(board_tilemap.map_to_local(cell))
	sprite.modulate = tint
	arrow_icon_overlay.add_child(sprite)
	return sprite
	
func on_hovered_unit_changed(previous_unit: Unit, new_unit: Unit):
	if previous_unit != null and is_instance_valid(previous_unit):
		set_unit_path_hovered(previous_unit, false)
	
	if new_unit != null and is_instance_valid(new_unit):
		set_unit_path_hovered(new_unit, true)
	
func set_unit_path_hovered(unit: Unit, hovered: bool):
	if not planned_move_by_unit.has(unit):
		return
		
	var move: MoveAction = planned_move_by_unit[unit]
	move.set_preview_z_index(MoveAction.HOVERED_ARROW_Z_INDEX if hovered else MoveAction.ARROW_BASE_Z_INDEX)
	
func show_projected_unit(unit: Unit, cell: Vector2i):
	clear_projected_unit(unit)
	
	var sprite := Sprite2D.new()
	sprite.texture = unit.get_move_texture()
	sprite.global_position = board_tilemap.to_global(board_tilemap.map_to_local(cell))
	sprite.z_index = Unit.BASE_SPRITE_INDEX
	
	#Planning sprite modulation
	sprite.modulate = PROJECTED_MODULATE
	var offset = Vector2i(0, -8)
	sprite.offset = offset
	projected_unit_overlay.add_child(sprite)
	projected_unit_sprites[unit] = sprite

func has_projected_unit(unit: Unit) -> bool:
	return projected_unit_sprites.has(unit)

func set_projected_unit_highlighted(unit: Unit, value: bool) -> void:
	if not projected_unit_sprites.has(unit):
		return
	var sprite: Sprite2D = projected_unit_sprites[unit]
	if not is_instance_valid(sprite):
		return
	sprite.modulate = PROJECTED_HIGHLIGHT if value else PROJECTED_MODULATE

func clear_projected_unit(unit: Unit):
	if not projected_unit_sprites.has(unit):
		return
	
	var sprite: Sprite2D = projected_unit_sprites[unit]
	
	if is_instance_valid(sprite):
		sprite.hide()
		sprite.queue_free()
		
	projected_unit_sprites.erase(unit)
	
func clear_all_projected_sprites():
	for unit in projected_unit_sprites.keys().duplicate():
		clear_projected_unit(unit)
		
func redraw_projected_units():
	clear_all_projected_sprites()

	for unit in planned_move_by_unit.keys().duplicate():
		var move: MoveAction = planned_move_by_unit[unit]
		if not is_instance_valid(unit):
			move.clear_preview_sprites()
			planned_move_by_unit.erase(unit)
			continue

		unit.visuals.set_projected(move.is_valid)
		if move.is_valid:
			show_projected_unit(unit, move.destination)
			
func handle_unit_death(unit: Unit):
	clear_unit_icons(unit)
	clear_planned_path(unit)
	clear_projected_unit(unit)
	if hover_move_preview != null and hover_move_preview.actor == unit:
		clear_hover_move_path()
		
#Untyped parameter on purpose: freed objects cannot pass a typed Unit parameter
func _purge_unit_entry(unit):
	if not icons_by_unit.has(unit):
		return
	for icon in icons_by_unit[unit].values():
		if is_instance_valid(icon):
			icon.queue_free()
	icons_by_unit.erase(unit)
	
func show_hover_move_paths(moves: Array[MoveAction]):
	clear_hover_move_path()
	hover_move_previews = moves
	for m in hover_move_previews:
		draw_path_arrows(m)
		m.set_preview_z_index(MoveAction.HOVERED_ARROW_Z_INDEX)
