class_name ForwardWidePattern
extends AttackPattern

@export var length := 1
# Tiles across the facing line — odd only, symmetric about the line. The editor offers odds
# only (see @export_enum); even widths can't be symmetric and produced an off-centre tile
# that highlighted but couldn't be targeted (#25).
@export_enum("1:1", "3:3", "5:5", "7:7", "9:9", "11:11", "13:13", "15:15", "17:17", "19:19", "21:21") var width := 3

func get_selectable_cells(user: Unit, origin_cell: Vector2i, facing_hint: Vector2i) -> Array[Vector2i]:
	var dir := GridUtils.cardinal_direction_i_between(origin_cell, facing_hint)
	if dir == Vector2i.ZERO:
		return []
	return _build_spread(origin_cell, dir)

func get_affected_cells(user: Unit, origin_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	return get_selectable_cells(user, origin_cell, target_cell)

func is_directional() -> bool:
	return true

func _build_spread(origin_cell: Vector2i, dir: Vector2i) -> Array[Vector2i]:
	var side := Vector2i(-dir.y, dir.x)
	var half := (width - 1) / 2   # int division; width is odd, so the row stays symmetric
	var cells: Array[Vector2i] = []

	for i in range(1, length + 1):
		var center := origin_cell + dir * i
		for w in range(-half, half + 1):
			cells.append(center + side * w)

	return cells
