class_name ManhattanRangePattern
extends AttackPattern

@export var max_range := 1
@export var max_and_a_half := false   # .5 step: bevel in the diagonal corners of the max ring
@export var min_range := 1

func get_selectable_cells(user: Unit, origin_cell: Vector2i, facing_hint: Vector2i) -> Array[Vector2i]:
	var all_cells := GridUtils.cells_within_blended_range(origin_cell, max_range, max_and_a_half)
	return all_cells.filter(func(cell): return GridUtils.manhattan_distance(origin_cell, cell) >= min_range)

func get_all_selectable_cells(user: Unit, origin_cell: Vector2i) -> Array[Vector2i]:
	return get_selectable_cells(user, origin_cell, origin_cell)


# #473: the two range boxes read alike and sat either side of a checkbox, with nothing anywhere
# saying which was which. Min Range's entry carries the failure mode, because exceeding Max Range
# is silent -- the filter above simply keeps no cells.
static func property_tips() -> Dictionary:
	var tips := AttackPattern.property_tips()
	tips.merge({
		"max_range": "The FURTHEST cell this attack can reach, counted in Manhattan steps (no diagonals). RAISE THIS to make an attack longer-ranged.",
		"max_and_a_half": "Adds a half step to the outer ring, bevelling its diagonal corners -- a reach of 2 and a half rather than 2 or 3.",
		"min_range": "The CLOSEST cell this attack can reach. 1 = adjacent. Above 1 leaves a dead zone it cannot hit at all, which is how a carbine cannot shoot what has closed on it.\nMUST NOT EXCEED Max Range: nothing refuses the pair, the attack simply reaches no cells and stops showing any range at all.",
	})
	return tips
