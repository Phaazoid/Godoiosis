class_name ForwardLinePattern
extends AttackPattern

@export var length := 2

func get_selectable_cells(user: Unit, origin_cell: Vector2i, facing_hint: Vector2i) -> Array[Vector2i]:
	var dir := GridUtils.cardinal_direction_i_between(origin_cell, facing_hint)
	if dir == Vector2i.ZERO:
		return []
	var cells: Array[Vector2i] = []

	for i in range(1, length + 1):
		cells.append(origin_cell + dir * i)

	return cells

func get_affected_cells(user: Unit, origin_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	return get_selectable_cells(user, origin_cell, target_cell)

func is_directional() -> bool:
	return true
