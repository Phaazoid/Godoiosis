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
	CursorState.DEFAULT: preload("res://Art/Icons/CursorIcon.png"),
	CursorState.TARGET: preload("res://Art/Icons/SelectedIcon.png"),
	CursorState.INVALID: preload("res://Art/Icons/NegativeIcon.png"),
	CursorState.VALID: preload("res://Art/Icons/PositiveIcon.png")
}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	sprite.texture = CURSOR_TEXTURES[CursorState.DEFAULT]

func set_cursor_pos(cell: Vector2i):
	sprite.position = board_tilemap.map_to_local(cell)

func set_state(state: CursorState):
	sprite.texture = CURSOR_TEXTURES[state]

func hide_cursor():
	sprite.visible = false
	
func show_cursor():
	sprite.visible = true
