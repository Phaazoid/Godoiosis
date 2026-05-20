extends Object
class_name GridUtils

static func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

static func cells_within_manhattan_range(origin: Vector2i, range: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	
	for x in range(origin.x - range, origin.x + range + 1):
		for y in range(origin.y - range, origin.y + range + 1):
			var cell = Vector2i(x, y)
			var dist = abs(cell.x - origin.x) + abs(cell.y - origin.y)
			
			if dist <= range:
				cells.append(cell)
	return cells
