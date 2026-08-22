class_name ForwardWidePattern
extends AttackPattern

# DECLARED overlap (#20, re-verified #104): at width = 1 this is cell-for-cell identical to
# ForwardLinePattern. See that file's header for the standing decision to keep both.

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


static func property_tips() -> Dictionary:
	var tips := AttackPattern.property_tips()
	tips.merge({
		"length": "How many cells ahead the spread runs, starting from the cell in front of the attacker. This attack aims by FACING -- the player points a direction and the whole spread fires that way.",
		"width": "Cells across the facing line, symmetric about it. Odd only: an even width cannot be centred, and produced a tile that highlighted but could not be targeted.",
	})
	return tips
