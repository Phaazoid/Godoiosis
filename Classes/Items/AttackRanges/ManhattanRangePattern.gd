class_name ManhattanRangePattern
extends AttackPattern

@export var max_range := 1

func get_selectable_cells(user: Unit, origin_cell: Vector2i, facing_hint: Vector2i) -> Array[Vector2i]:
	return GridUtils.cells_within_manhattan_range(origin_cell, max_range)
