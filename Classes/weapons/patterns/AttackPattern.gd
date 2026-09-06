extends Resource
class_name AttackPattern

# The geometry of an attack: a RANGE plus a STAMP (#803). Was an abstract base with three
# subclasses -- Manhattan, ForwardLine, ForwardWide -- whose own header (#20, re-verified #104) said
# to consolidate rather than add a third once the next pattern landed. Cone and cross were that
# pattern, and both are range plus a shape; so is a cleave, so is a line, so is a lob.
#
# RANGE (min / max / the half-step bevel) is where the attack may be AIMED, in Manhattan steps.
# STAMP is the set of cells it then covers, as offsets from the ANCHOR, authored in grid space
# where UP is forward (dev, 2026-09-06: "the top half of the grid intuitively represents forward").
#
# THE ANCHOR IS DERIVED FROM THE RANGE, never a flag (dev, 2026-09-06):
#   max_range == 0  -- the stamp sits on the ATTACKER and the aim is a FACING: the player points a
#                      cardinal and the whole stamp fires that way (the directional path, #25).
#   max_range >= 1  -- the stamp sits on the AIMED cell, and the aim is that cell.
# Either way the stamp is TURNED to the aim's cardinal -- the facing, or attacker-to-target through
# GridUtils' own diagonal tie-break. An aim at the attacker's OWN cell (min_range 0, a self-heal)
# has no cardinal and places the stamp unturned, grid-up as forward.
#
# EMISSION ORDER IS A RULE (dev, 2026-09-06): cells come NEAR TO FAR along the facing, then left to
# right across it. Victim order is volley order, so this reproduces the retired classes' sequences
# cell for cell; and Reach._truncate (#756) needs a predecessor emitted before its successor, which
# the sort guarantees for any stamp.
#
# The centre offset is a legal member (dev, 2026-09-06): at range 0 it is the attacker's own cell
# in the footprint, and whether they are then a VICTIM stays hits_self's question (RulesService).
# A stamp is a set; a duplicated offset counts once.
#
# Board-blind on purpose: this emits the shape and Reach decides what the terrain leaves standing.

const CARDINAL_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
# Grid space: the stamp is authored facing this way.
const FORWARD := Vector2i.UP

@export var min_range := 1
@export var max_range := 1
@export var max_and_a_half := false   # .5 step: bevel in the diagonal corners of the max ring
@export var stamp: Array[Vector2i] = [Vector2i.ZERO]


# Does this attack aim by FACING rather than at a cell? game.gd's targeting and the hover branch
# on it through Reach.is_directional_attack; the AI's watch picker loops the four facings. See #25.
func is_directional() -> bool:
	return max_range == 0


# The cells an aim may be DECLARED at. Self-anchored: the stamp placed for the facing the hint
# implies -- the pointed cell need not be a member, and a hint with no cardinal answers empty (a
# dud order, refused upstream). Anchored: the range ring, board-blind.
func get_selectable_cells(_user: Unit, origin_cell: Vector2i, facing_hint: Vector2i) -> Array[Vector2i]:
	if is_directional():
		var dir := GridUtils.cardinal_direction_i_between(origin_cell, facing_hint)
		if dir == Vector2i.ZERO:
			return []
		return place(origin_cell, dir)
	var all_cells := GridUtils.cells_within_blended_range(origin_cell, max_range, max_and_a_half)
	return all_cells.filter(func(cell): return GridUtils.manhattan_distance(origin_cell, cell) >= min_range)


# Union over the four facings -- what the red targeting overlay draws. An anchored pattern's ring
# does not turn with a facing, so it is asked once.
func get_all_selectable_cells(user: Unit, origin_cell: Vector2i) -> Array[Vector2i]:
	if not is_directional():
		return get_selectable_cells(user, origin_cell, origin_cell)
	var cells: Array[Vector2i] = []
	for dir in CARDINAL_DIRECTIONS:
		for cell in get_selectable_cells(user, origin_cell, origin_cell + dir):
			if not cells.has(cell):
				cells.append(cell)
	return cells


# The footprint an aim at target_cell lands on: the stamp on its anchor, turned to the aim.
func get_affected_cells(_user: Unit, origin_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	var dir := GridUtils.cardinal_direction_i_between(origin_cell, target_cell)
	if is_directional():
		if dir == Vector2i.ZERO:
			return []
		return place(origin_cell, dir)
	return place(target_cell, FORWARD if dir == Vector2i.ZERO else dir)


# The stamp turned to face `dir` and set down on `anchor`, in emission order. Grid space reads
# forward as -y and right as +x; world space uses the facing and its right-hand perpendicular --
# the `side` the retired wide pattern used -- so a stamp is ROTATED, never mirrored, and a row
# authored left to right stays left to right from the shooter's point of view.
func place(anchor: Vector2i, dir: Vector2i) -> Array[Vector2i]:
	var side := Vector2i(-dir.y, dir.x)
	var keyed: Dictionary[Vector2i, Vector2i] = {}   # (forward, across) -> world cell; a set, so a duplicate folds
	for offset in stamp:
		var forward := -offset.y
		var across := offset.x
		keyed[Vector2i(forward, across)] = anchor + dir * forward + side * across
	var keys := keyed.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y)
	var out: Array[Vector2i] = []
	for key in keys:
		out.append(keyed[key])
	return out


# Per-field text for the dev tools' reflective editor (#473) -- see AttackData.property_tips for
# why this is a function. Min Range's entry carries the failure mode, because exceeding Max Range
# is silent: the filter above simply keeps no cells.
static func property_tips() -> Dictionary:
	return {
		"min_range": "The CLOSEST cell this attack can be aimed at, in Manhattan steps. 1 = adjacent. 0 = the attacker's own cell as well (a self-heal). Above 1 leaves a dead zone it cannot hit at all, which is how a carbine cannot shoot what has closed on it.\nMUST NOT EXCEED Max Range: nothing refuses the pair, the attack simply reaches no cells and stops showing any range at all.",
		"max_range": "The FURTHEST cell this attack can be aimed at, in Manhattan steps (no diagonals). RAISE THIS to make an attack longer-ranged.\n0 is special: the stamp sits on the ATTACKER and the attack aims a FACING -- the player points a direction and the whole stamp fires that way. That is what a cleave or a line is.",
		"max_and_a_half": "Adds a half step to the outer ring, bevelling its diagonal corners -- a reach of 2 and a half rather than 2 or 3.",
		"stamp": "The cells the attack COVERS once aimed, as offsets from where it lands: 0,0 is the aimed cell (the attacker's own, at Max Range 0), UP is forward, so 0,-1 is one cell ahead and 1,-1 is ahead and to the right. Turned to face the aim. Typed here as 'x,y x,y ...' until the grid editor lands; 0,0 alone is a single-target attack, and an empty stamp covers nothing.",
	}
