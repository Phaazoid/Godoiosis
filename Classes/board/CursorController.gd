extends Node2D
class_name CursorController

@onready var sprite: Sprite2D = $CursorSprite
@onready var board_tilemap = $"../Grid"


enum CursorState {
	DEFAULT,
	TARGET,
	INVALID,
	VALID
}

const CURSOR_TEXTURES = {
	CursorState.DEFAULT: preload("res://Art/Icons/BoardIcons/CursorIcon.png"),
	CursorState.TARGET: preload("res://Art/Icons/BoardIcons/SelectedIcon.png"),
	CursorState.INVALID: preload("res://Art/Icons/BoardIcons/NegativeIcon.png"),
	CursorState.VALID: preload("res://Art/Icons/BoardIcons/PositiveIcon.png")
}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	sprite.texture = CURSOR_TEXTURES[CursorState.DEFAULT]

func set_cursor_pos(cell: Vector2i):
	sprite.position = board_tilemap.map_to_local(cell)

# The last state set. STORED, because the 3D bracket mirrors this answer instead of re-deriving
# "is the thing under the pointer valid" for itself -- two derivations of one question is exactly
# the #232 shape. This used to swap the texture and throw the fact away.
var state: CursorState = CursorState.DEFAULT

func set_state(new_state: CursorState):
	state = new_state
	sprite.texture = CURSOR_TEXTURES[new_state]

func hide_cursor():
	sprite.visible = false
	
func show_cursor():
	sprite.visible = true
