extends Node
class_name OverlayManager

@onready var move_overlay = $MoveOverlay
@onready var attack_overlay = $AttackOverlay
@onready var hover_overlay = $HoverOverlay
@onready var squad_overlay = $SquadOverlay
@onready var icon_overlay = $IconOverlay
@onready var arrow_overlay = $ArrowOverlay
@onready var squadrange_overlay = $SquadRangeOverlay
@onready var invalidmove_overlay = $InvalidMoveOverlay
@onready var board_tilemap = $"../Grid"


const PATH_ERROR := Vector2i(2, 1)
const PATH_HORIZONTAL := Vector2i(3, 0)
const PATH_VERTICAL := Vector2i(2, 0)

const PATH_UP_RIGHT := Vector2i(4, 1)
const PATH_UP_LEFT := Vector2i(5, 1)
const PATH_DOWN_RIGHT := Vector2i(4, 0)
const PATH_DOWN_LEFT := Vector2i(5, 0)

const PATH_START_RIGHT := Vector2i(0, 0)
const PATH_START_LEFT := Vector2i(1, 1)
const PATH_START_UP := Vector2i(0, 1)
const PATH_START_DOWN := Vector2i(1, 0)

const PATH_ARROW_RIGHT := Vector2i(6, 0)
const PATH_ARROW_LEFT := Vector2i(7, 1)
const PATH_ARROW_UP := Vector2i(6, 1)
const PATH_ARROW_DOWN := Vector2i(7, 0)


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
var planned_cells_by_unit := {} #{Unit : Array[Vector2i]}
var squad_range_overlays := {} #{OverlayType : Array[Vector2i]}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	overlay_map = {
		OverlayType.MOVE: move_overlay,
		OverlayType.ATTACK: attack_overlay,
		OverlayType.HOVER: hover_overlay,
		OverlayType.SQUAD: squad_overlay,
		OverlayType.ARROW: arrow_overlay,
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
	
func cancel_path(unit: Unit):
	for member in planned_cells_by_unit.keys():
		if member == unit:
			planned_cells_by_unit.erase(unit)
	redraw_planned_paths()

func show_planned_path(unit: Unit, path: Array[Vector2i]):
	planned_cells_by_unit.erase(unit)
	planned_cells_by_unit[unit] = path #Ignore starting cell
	redraw_planned_paths()

func get_planned_destinations() -> Array[Vector2i]:
	var destinations: Array[Vector2i] = []
	for path in planned_cells_by_unit.values():
		destinations.append(path.back())
		
	return destinations

func get_units_with_plans() -> Array:
	return planned_cells_by_unit.keys()

func clear_planned_path(unit: Unit):
	var cells = planned_cells_by_unit.get(unit, [])
	for cell in cells:
		arrow_overlay.erase_cell(cell)
	planned_cells_by_unit.erase(unit)
	redraw_planned_paths()

func redraw_planned_paths():
	arrow_overlay.clear()
	for path in planned_cells_by_unit.values(): #Ignore starting cell
		draw_path_arrows(arrow_overlay, path)

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
	
func draw_path_arrows(layer: TileMapLayer, path: Array[Vector2i]):
	if path.is_empty():
		return
	
	if path.size() == 1:
		layer.set_cell(path[0], SOURCE_ID, PATH_ERROR)
		return
		
	for i in range(path.size()):
		var current := path[i]
		
		#Start tile
		if i == 0:
			var next := path[i + 1]
			var dir := next - current
			var atlas := _get_start_atlas(dir)
			layer.set_cell(current, SOURCE_ID, atlas)
			continue
		
		#End tile / arrowhead
		if i == path.size() - 1:
			var previous := path[i - 1]
			var dir := current - previous
			var atlas := _get_arrowhead_atlas(dir)
			layer.set_cell(current, SOURCE_ID, atlas)
			continue
		
		#Middle tile
		var previous := path[i - 1]
		var next := path[i + 1]
		
		var dir_to_prev := previous - current
		var dir_to_next := next - current
		
		var atlas := _get_path_segment_atlas(dir_to_prev, dir_to_next)
		layer.set_cell(current, SOURCE_ID, atlas)
	
	

func _get_arrowhead_atlas(dir: Vector2i) -> Vector2i:
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
			
func _get_start_atlas(dir: Vector2i) -> Vector2i:
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
			
func _get_path_segment_atlas(from_dir: Vector2i, to_dir: Vector2i) -> Vector2i:
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
	
