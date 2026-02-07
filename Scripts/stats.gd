extends Node
class_name Stats_Component

@export var max_hp: int = 0
@export var move_range: int = 5

var hp: int

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	hp = max_hp

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
