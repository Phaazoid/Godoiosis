extends Node2D
class_name Unit


#Core statas
@onready var stats: Stats_Component = $Stats_Component
@onready var movement: Movement_Component = $Movement_Component
var current_position: Vector2i
var selected := false

#Ownership
#0 = player, 1 = enemy, 2 = other
@export var team: int

func set_selected(value: bool) -> void:
	selected = value
	modulate = Color(1, 1, 1) if not value else Color(1, 1, 0)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
