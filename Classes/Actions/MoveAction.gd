extends BaseAction
class_name MoveAction

var path: Array[Vector2i]
var destination: Vector2i
var destination_texture: Texture2D
var preview: Array[Sprite2D] = []
var is_hold_position := false

const GENERIC_TILE := preload("res://Art/Icons/GenericTileIcon.png")
const MOVE_ICON := preload("res://Art/Icons/MoveActionIcon.png")
const HOLD_ICON := preload("res://Art/Icons/ArrowIcons/nomove.png")
const ARROW_BASE_Z_INDEX = 3
const HOVERED_ARROW_Z_INDEX = 10

func init(unit: Unit, move_path: Array[Vector2i], destination_tile_texture: Texture2D):
	actor = unit 
	path = move_path
	destination = path.back()
	action_type = ActionType.MOVE
	if destination_tile_texture == null:
		destination_texture = GENERIC_TILE
	else:
		destination_texture = destination_tile_texture
	
func init_hold_position(unit: Unit, destination_tile_texture: Texture2D):
	actor = unit
	action_type = ActionType.MOVE
	path = []
	destination = unit.movement.cell
	is_hold_position = true
	if destination_tile_texture == null:
		destination_texture = GENERIC_TILE
	else:
		destination_texture = destination_tile_texture
	
func execute():
	begin_execution()
	clear_preview_sprites()
	actor.movement.move_along_path(path)
	
	if actor.movement.moving:
		await actor.movement.movement_finished
		
	finish_execution()
		
func get_action_icon() -> Texture2D:
	if is_hold_position:
		return HOLD_ICON
	return MOVE_ICON
	
func get_move_path() -> Array[Vector2i]:
	return path

func get_description() -> String:
	if is_hold_position:
		return "%s holds position" % actor.get_unit_name()
	return "%s moves to %s" % [actor.get_unit_name(), str(destination)]
	
func get_target_texture() -> Texture2D:
	return destination_texture
	
func get_destination() -> Vector2i:
	return destination
	
func clear_preview_sprites():
	for sprite in preview:
		if is_instance_valid(sprite):
			sprite.hide()
			sprite.queue_free()
	preview.clear()
	
func set_preview_z_index(value: int):
	for sprite in preview:
		if is_instance_valid(sprite):
			sprite.z_index = value
			
func reset_preview_z_index():
	set_preview_z_index(ARROW_BASE_Z_INDEX)
	
func add_preview_sprite(sprite: Sprite2D):
	preview.append(sprite)
