class_name ForwardWidePattern
extends AttackPattern

@export var length := 1
@export var width := 3

func get_selectable_cells(user: Unit, origin_cell: Vector2i, facing_hint: Vector2i) -> Array[Vector2i]:
	var dir := GridUtils.cardinal_direction_i_between(origin_cell, facing_hint)
	return [origin_cell + dir]

func get_affected_cells(user: Unit, origin_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	var dir := GridUtils.cardinal_direction_i_between(origin_cell, target_cell)
	var side := Vector2i(-dir.y, dir.x)

	return [
		origin_cell + dir,
		origin_cell + dir + side,
		origin_cell + dir - side
	]
