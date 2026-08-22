class_name ForwardLinePattern
extends AttackPattern

# DECLARED overlap (#20, re-verified #104): ForwardWidePattern with width = 1 produces the
# IDENTICAL cell set. Kept as two concepts on purpose — forward-line reach vs sideways cleave —
# on the expectation they diverge as patterns grow. Neither is authoritative; they are siblings.
# If they still haven't diverged when the next pattern lands, consolidate rather than add a third.

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


static func property_tips() -> Dictionary:
	var tips := AttackPattern.property_tips()
	tips.merge({
		"length": "How many cells ahead the line runs, starting from the cell in front of the attacker. This attack aims by FACING -- the player points a direction and the whole line fires that way.",
	})
	return tips
