extends Node
class_name MovementComponent

@export var cell: Vector2i
@export var move_speed := 120 #pixels per second

signal movement_finished

var grid: TileMapLayer
var path: Array[Vector2i] = []
var moving := false

func set_grid(grid_layer: TileMapLayer):
	grid = grid_layer
	
func set_cell(new_cell: Vector2i):
	cell = new_cell
	get_parent().position = grid.map_to_local(cell)

func move_along_path(new_path: Array[Vector2i]):
	if new_path.size() <= 1:
		moving = false
		movement_finished.emit()
		return
		
	path = new_path.duplicate()
	path.pop_front()
	moving = true
	
	_move_to_next_cell()
	
func _move_to_next_cell():
	if path.is_empty():
		moving = false
		movement_finished.emit()
		return
	
	var next_cell : Vector2i = path.pop_front()
	var target_pos := grid.map_to_local(next_cell)
	
	cell = next_cell
	
	var tween := create_tween()
	tween.tween_property(get_parent(), "position", target_pos, get_parent().position.distance_to(target_pos)/move_speed)
	
	tween.finished.connect(_move_to_next_cell)
	
