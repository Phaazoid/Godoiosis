extends Object
class_name UnitFactory

static func create_unit(data: UnitData, grid: TileMapLayer, pos : Vector2i) -> Unit:
	var unit_scene = preload("res://Scenes/unit.tscn")
	var unit = unit_scene.instantiate()
	
	
	unit.setup(grid, pos)
	unit.unit_data = data

	return unit
	
#TODO move builder functions from dev_overlay here

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
