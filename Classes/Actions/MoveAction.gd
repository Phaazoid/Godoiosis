extends BaseAction
class_name MoveAction

var path: Array[Vector2i]
var destination: Vector2i
var destination_texture: Texture2D

const GENERIC_TILE := preload("res://Art/Icons/GenericTileIcon.png")
const MOVE_ICON := preload("res://Art/Icons/MoveActionIcon.png")

func init(unit: Unit, move_path: Array[Vector2i], destination_tile_texture: Texture2D = null):
	actor = unit
	path = move_path
	destination = path.back()
	action_type = ActionType.MOVE
	destination_texture = destination_tile_texture
	
func execute():
	actor.movement.move_along_path(path)
	
func get_action_icon() -> Texture2D:
	return MOVE_ICON
	
func get_description() -> String:
	return "%s moves to %s" % [actor.get_unit_name(), str(destination)]
	
func get_target_texture() -> Texture2D:
	return GENERIC_TILE
