extends Object
class_name Reach

# Weapon-aware attack geometry: given a unit and an origin, which cells can it select, and which
# does a given aim actually affect. Every query centralizes through _active_pattern, which reads
# Unit.get_fired_attack() (#30/#72), so reach always matches whatever the unit would really fire.
#
# Was CombatComponent, a Node on every Unit — but it held no state (its lone @export, can_counter,
# was never authored on any unit, so its gate in SquadManager was permanently open and shadowed the
# real, authored AttackData.can_counter). Every method already began by fetching its owner back.
# Made static 2026-07-26, matching the RulesService/GridUtils precedent; the Unit is now just the
# first parameter, and the scene tree carries one fewer node per unit.
#
# No pattern (bare fists, or a rune with nothing channelable) falls back to adjacency: selectable =
# Manhattan range 1, affected = the aimed cell alone. That fallback is load-bearing in the tests —
# a pattern-less weapon is how they get trivial geometry.

static func get_attack_cells_from(unit: Unit, origin_cell: Vector2i, target_hint_cell: Vector2i) -> Array[Vector2i]:
	var pattern := _active_pattern(unit)
	if pattern == null:
		return GridUtils.cells_within_manhattan_range(origin_cell, 1)
	return pattern.get_selectable_cells(unit, origin_cell, target_hint_cell)

static func can_hit_cell_from(unit: Unit, origin_cell: Vector2i, target_cell: Vector2i) -> bool:
	return get_attack_cells_from(unit, origin_cell, target_cell).has(target_cell)

# Union over all four facings — what the red targeting overlay draws.
static func get_all_attack_cells_from(unit: Unit, origin_cell: Vector2i) -> Array[Vector2i]:
	var pattern := _active_pattern(unit)
	if pattern == null:
		return GridUtils.cells_within_manhattan_range(origin_cell, 1)
	return pattern.get_all_selectable_cells(unit, origin_cell)

# The AoE footprint an aim at target_cell actually lands on.
static func get_affected_cells_from(unit: Unit, origin_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	var pattern := _active_pattern(unit)
	if pattern == null:
		return [target_cell]
	return pattern.get_affected_cells(unit, origin_cell, target_cell)

# Does the equipped weapon aim by facing (forward line/wide) rather than at a specific cell? The
# ATTACK_TARGETING click handler and hover preview both branch on this: a directional attack
# targets a DIRECTION (the whole spread fires), a point attack needs the clicked cell in range.
static func is_directional_attack(unit: Unit) -> bool:
	var pattern := _active_pattern(unit)
	if pattern == null:
		return false
	return pattern.is_directional()

static func _active_pattern(unit: Unit) -> AttackPattern:
	if unit == null:
		return null
	var fired := unit.get_fired_attack()
	return fired.attack_pattern if fired != null else null
