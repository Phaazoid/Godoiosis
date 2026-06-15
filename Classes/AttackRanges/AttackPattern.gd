extends Resource
class_name AttackPattern
const CARDINAL_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

func get_all_selectable_cells(user: Unit, origin_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dir in CARDINAL_DIRECTIONS:
		for cell in get_selectable_cells(user, origin_cell, origin_cell + dir):
			if not cells.has(cell):
				cells.append(cell)
	return cells
	
func get_selectable_cells(user: Unit, origin_cell: Vector2i, facing_hint: Vector2i) -> Array[Vector2i]:
	return []

func get_affected_cells(user: Unit, origin_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	return [target_cell]
