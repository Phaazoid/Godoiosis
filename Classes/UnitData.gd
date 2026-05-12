extends Resource
class_name UnitData

#This is the basics of what a UnitInstance has.  Each UnitInstance will have a unique version of this, and it should never change during runtime
#basically immutable design draft

@export var display_name: String = "Unit"
@export var portrait: Texture2D
@export var base_stats: Dictionary[String, int]
@export var growth_ranges: Dictionary[String, Vector2i]
@export var innate_abilities: Array[String]
@export var faction: Team.Faction


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
