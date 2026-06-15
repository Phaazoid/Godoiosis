class_name ForwardWidePattern
extends AttackPattern

@export var length := 1
@export var width := 3 #use odd widths; the spread centers on the facing line

func get_selectable_cells(user: Unit, origin_cell: Vector2i, facing_hint: Vector2i) -> Array[Vector2i]:
	var dir := GridUtils.cardinal_direction_i_between(origin_cell, facing_hint)
	if dir == Vector2i.ZERO:
		return []
	return _build_spread(origin_cell, dir)

func get_affected_cells(user: Unit, origin_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	return get_selectable_cells(user, origin_cell, target_cell)

func _build_spread(origin_cell: Vector2i, dir: Vector2i) -> Array[Vector2i]:
	var side := Vector2i(-dir.y, dir.x)
	var half_width := width / 2
	var cells: Array[Vector2i] = []

	for i in range(1, length + 1):
		var center := origin_cell + dir * i
		for w in range(-half_width, half_width + 1):
			cells.append(center + side * w)

	return cells
