extends Node
class_name OverlayManager

@onready var move_overlay = $MoveOverlay
@onready var attack_overlay = $AttackOverlay
@onready var hover_overlay = $HoverOverlay
@onready var squad_overlay = $SquadOverlay
@onready var icon_overlay = $IconOverlay
@onready var arrow_icon_overlay: Node2D = $ArrowIconOverlay
@onready var squadrange_overlay = $SquadRangeOverlay
@onready var invalidmove_overlay = $InvalidMoveOverlay
@onready var board_tilemap = $"../Grid"


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


const ICON_SCENE = preload("res://Scenes/OverlayIcon.tscn")
const SOURCE_ID = 0
const ATLAS_COORDS = Vector2i(0,0)

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
	OverlayIcon.IconType.CURSOR: preload("res://Art/Icons/CursorIcon.png"),
	OverlayIcon.IconType.CROWN: preload("res://Art/Icons/CrownIcon.png"),
	OverlayIcon.IconType.TARGET: preload("res://Art/Icons/SelectedIcon.png"),
	OverlayIcon.IconType.INVALID: preload("res://Art/Icons/NegativeIcon.png"),
	OverlayIcon.IconType.SQUADMEMBER: preload("res://Art/Icons/SquadHighlighIcon.png")
}

var overlay_map = {}
var icons_by_cell = {} # {Cell : { IconType : Icon } } 
var planned_move_by_unit := {} #{Unit : MoveAction}
var squad_range_overlays := {} #{OverlayType : Array[Vector2i]}
var hover_move_preview: MoveAction = null

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
	hover_overlay.modulate = Color(1, 1, 0)
	squad_overlay.modulate = Color(0.6, 0.4, 0.8, 0.7)
	invalidmove_overlay.modulate = Color(0.5, 0.36, 0.4, .5)
	
func modulate_overlay(type: int, rgba: Color):
	overlay_map[type].modulate = rgba

func show_overlay(type: int, cells: Array, atlas_coord: Vector2i):
	var layer = overlay_map[type]
	layer.clear()
	draw_cells(layer, cells, atlas_coord)

func show_hover_move_path(move: MoveAction):
	clear_hover_move_path()
	hover_move_preview = move
	draw_path_arrows(hover_move_preview)
	hover_move_preview.set_preview_z_index(MoveAction.HOVERED_ARROW_Z_INDEX)
	
func clear_hover_move_path():
	if hover_move_preview == null:
		return
		
	hover_move_preview.clear_preview_sprites()
	hover_move_preview = null
	
func show_planned_path(unit: Unit, move: MoveAction):
	if planned_move_by_unit.has(unit):
		var old_move: MoveAction = planned_move_by_unit[unit]
		old_move.clear_preview_sprites()
		
	planned_move_by_unit[unit] = move
	redraw_planned_paths()

func get_planned_destinations() -> Array[Vector2i]:
	var destinations: Array[Vector2i] = []
	
	for move: MoveAction in planned_move_by_unit.values():
		destinations.append(move.back())
		
	return destinations

func get_units_with_plans() -> Array:
	return planned_move_by_unit.keys()

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

func create_icon(cell: Vector2i, type: OverlayIcon.IconType, offset := Vector2i.ZERO) -> OverlayIcon:
	if icons_by_cell.has(cell):
		if icons_by_cell[cell].has(type):
			return icons_by_cell[cell][type]
	
	var icon = ICON_SCENE.instantiate()
	icon_overlay.add_child(icon)
	icon.setup(ICON_TEXTURES[type], cell, type)
	icon.position = board_tilemap.map_to_local(cell) #+ offset
	
	if !icons_by_cell.has(cell):
		icons_by_cell[cell] = {}
		
	icons_by_cell[cell][type] = icon
	return icon
	
func move_icon(icon: OverlayIcon, pos: Vector2i):
	icon.move_to(pos)
	
func clear_icon_types(icontypes: Array[OverlayIcon.IconType]):
	var cells = icons_by_cell.keys().duplicate()

	for cell: Vector2i in cells:
		for type: OverlayIcon.IconType in icontypes:
			if icons_by_cell.has(cell) and icons_by_cell[cell].has(type):
				var icon = icons_by_cell[cell][type]
				icon.hide()
				icon.queue_free()
				icons_by_cell[cell].erase(type)
				if icons_by_cell[cell].is_empty():
					icons_by_cell.erase(cell)

func clear_target_icon_by_cell(target_cell: Vector2i, type: OverlayIcon.IconType):
	if icons_by_cell.has(target_cell) and icons_by_cell[target_cell].has(type):
		var icon = icons_by_cell[target_cell][type]
		icon.hide()
		icon.queue_free()
		icons_by_cell[target_cell].erase(type)
		if icons_by_cell[target_cell].is_empty():
			icons_by_cell.erase(target_cell)

func clear_all():
	move_overlay.clear()
	attack_overlay.clear()
	hover_overlay.clear()
	squad_overlay.clear()
	invalidmove_overlay.clear()
	
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
	
	if path.is_empty():
		return
	
	if path.size() == 1:
		var sprite := _create_arrow_sprite(path[0], PATH_ERROR, move.is_valid)
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
			
		var sprite := _create_arrow_sprite(current, texture, move.is_valid)
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
	
func _create_arrow_sprite(cell: Vector2i, texture: Texture2D, valid: bool) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.z_index = MoveAction.ARROW_BASE_Z_INDEX
	sprite.global_position = board_tilemap.to_global(board_tilemap.map_to_local(cell))
	
	if valid:
		sprite.modulate = Color.WHITE
	else:
		sprite.modulate = Color(1, .25, .25, .85)
		
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
	
	
	
