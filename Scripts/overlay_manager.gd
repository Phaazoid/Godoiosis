extends Node
class_name OverlayManager

@onready var move_overlay = $MoveOverlay
@onready var attack_overlay = $AttackOverlay
@onready var hover_overlay = $HoverOverlay
@onready var squad_overlay = $SquadOverlay
@onready var icon_overlay = $IconOverlay
@onready var board_tilemap = $"../Grid"



const ICON_SCENE = preload("res://Scenes/OverlayIcon.tscn")
const SOURCE_ID = 0
const ATLAS_COORDS = Vector2i(0,0)

enum OverlayType {
	MOVE,
	ATTACK,
	HOVER,
	SQUAD
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
var game: Node



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	game = get_parent()
	assert(game != null)

	overlay_map = {
		OverlayType.MOVE: move_overlay,
		OverlayType.ATTACK: attack_overlay,
		OverlayType.HOVER: hover_overlay,
		OverlayType.SQUAD: squad_overlay
	}
	move_overlay.modulate = Color(1, 1, 0, .5)
	attack_overlay.modulate = Color(1, 0, 0, .5)
	hover_overlay.modulate = Color(1, 1, 0)
	squad_overlay.modulate = Color(0.6, 0.4, 0.8, 0.7)
	
func modulate_overlay(type: int, rgba: Color):
	overlay_map[type].modulate = rgba

func show_overlay(type: int, cells: Array[Vector2i], atlas_coord: Vector2i):
	var layer = overlay_map[type]
	layer.clear()
	draw_cells(layer, cells, atlas_coord)

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


func clear_all():
	move_overlay.clear()
	attack_overlay.clear()
	hover_overlay.clear()
	squad_overlay.clear()
	
	move_overlay.modulate = Color(1, 1, 0, .5)
	attack_overlay.modulate = Color(1, 0, 0, .5)
	hover_overlay.modulate = Color(1, 1, 0)
	
func draw_cells(layer: TileMapLayer, cells: Array[Vector2i], atlas_coord: Vector2i):
	for cell in cells:
		#if is_valid_cell(cell):
			layer.set_cell(cell, SOURCE_ID, atlas_coord)
		
func is_valid_cell(cell: Vector2i) -> bool:
	return move_overlay.get_used_rect().has_point(cell)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
