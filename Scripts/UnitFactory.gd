extends Object
class_name UnitFactory

static func create_unit(config: Dictionary) -> Unit:
	var unit_scene = preload("res://Scenes/unit.tscn")
	var unit = unit_scene.instantiate()
	
	unit.unit_data = config["data"]
	unit.faction = config["faction"] #Team.Faction enum
	
	return unit
	
	


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
