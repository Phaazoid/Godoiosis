class_name ManhattanRangePattern
extends AttackPattern

@export var max_range := 1
@export var min_range := 1

func get_selectable_cells(user: Unit, origin_cell: Vector2i, facing_hint: Vector2i) -> Array[Vector2i]:
	var all_cells := GridUtils.cells_within_manhattan_range(origin_cell, max_range)
	return all_cells.filter(func(cell): return GridUtils.manhattan_distance(origin_cell, cell) >= min_range)

func get_all_selectable_cells(user: Unit, origin_cell: Vector2i) -> Array[Vector2i]:
	return get_selectable_cells(user, origin_cell, origin_cell)
