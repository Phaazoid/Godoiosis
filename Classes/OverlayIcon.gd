extends Node2D
class_name OverlayIcon

@onready var sprite = $Sprite2D
var icon_type
var target_cell: Vector2i

enum IconType {
	CURSOR,
	CROWN,
	TARGET,
	INVALID,
	SQUADMEMBER	
}

func setup(texture: Texture2D, cell: Vector2i, type: IconType):
	sprite.texture = texture
	target_cell = cell
	icon_type = type
	
func move_to(pos: Vector2i):
	target_cell = pos
