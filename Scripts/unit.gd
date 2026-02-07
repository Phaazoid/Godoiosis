extends Node2D
class_name Unit


#Core statas
@onready var stats: Stats_Component = $Stats_Component
@onready var movement: Movement_Component = $Movement_Component
var current_position: Vector2i
var selected := false

#Ownership
@export var faction: Team.Faction = Team.Faction.PLAYER

func set_selected(value: bool) -> void:
	selected = value

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	match faction:
		Team.Faction.PLAYER:
			modulate = Color.WHITE
		Team.Faction.ENEMY:
			modulate = Color(1, 0.6, 0.6)
		Team.Faction.ALLY:
			modulate = Color(0.6, 0.8, 1)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
