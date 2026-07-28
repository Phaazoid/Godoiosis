extends Object
class_name Reach

# Weapon-aware attack geometry: given a unit, an origin AND THE ATTACK BEING FIRED, which cells can
# it select, and which does a given aim actually affect.
#
# The attack is a PARAMETER, not a lookup (#102). Every query used to read Unit.get_fired_attack()
# for itself -- the live active_attack pick -- while the queued order carried its own frozen
# fired_attack stamp. Geometry and damage therefore answered from two different sources, and a pick
# left over from a previous aim silently re-shaped a stored order's blast, granted counter reach the
# counter could not fire with, and splashed allies a main attack never touches. Passing the attack
# makes that divergence unrepresentable -- each caller states its source:
#   aiming / previewing  -> unit.get_fired_attack()    (the live pick IS the question)
#   a stored order       -> action.fired_attack        (the frozen stamp)
#   a counter            -> unit.get_counter_attack()  (always main, for a weapon)
#
# Was CombatComponent, a Node on every Unit -- but it held no state (its lone @export, can_counter,
# was never authored on any unit, so its gate in SquadManager was permanently open and shadowed the
# real, authored AttackData.can_counter). Every method already began by fetching its owner back.
# Made static 2026-07-26, matching the RulesService/GridUtils precedent; the Unit is now just the
# first parameter, and the scene tree carries one fewer node per unit.
#
# A null attack, or one with no pattern (bare fists, a rune with nothing channelable), falls back to
# adjacency: selectable = Manhattan range 1, affected = the aimed cell alone. That fallback is
# load-bearing in the tests -- a pattern-less weapon is how they get trivial geometry.

static func get_attack_cells_from(unit: Unit, origin_cell: Vector2i, target_hint_cell: Vector2i, attack: AttackData) -> Array[Vector2i]:
	var pattern := _pattern_of(attack)
	if pattern == null:
		return GridUtils.cells_within_manhattan_range(origin_cell, 1)
	return pattern.get_selectable_cells(unit, origin_cell, target_hint_cell)

static func can_hit_cell_from(unit: Unit, origin_cell: Vector2i, target_cell: Vector2i, attack: AttackData) -> bool:
	return get_attack_cells_from(unit, origin_cell, target_cell, attack).has(target_cell)

# Union over all four facings — what the red targeting overlay draws.
static func get_all_attack_cells_from(unit: Unit, origin_cell: Vector2i, attack: AttackData) -> Array[Vector2i]:
	var pattern := _pattern_of(attack)
	if pattern == null:
		return GridUtils.cells_within_manhattan_range(origin_cell, 1)
	return pattern.get_all_selectable_cells(unit, origin_cell)

# The AoE footprint an aim at target_cell actually lands on.
static func get_affected_cells_from(unit: Unit, origin_cell: Vector2i, target_cell: Vector2i, attack: AttackData) -> Array[Vector2i]:
	var pattern := _pattern_of(attack)
	if pattern == null:
		return [target_cell]
	return pattern.get_affected_cells(unit, origin_cell, target_cell)

# Does this attack aim by facing (forward line/wide) rather than at a specific cell? The
# ATTACK_TARGETING click handler and hover preview both branch on this: a directional attack
# targets a DIRECTION (the whole spread fires), a point attack needs the clicked cell in range.
# Takes only the attack -- the unit was never consulted for this question. See #25.
static func is_directional_attack(attack: AttackData) -> bool:
	var pattern := _pattern_of(attack)
	return pattern != null and pattern.is_directional()

static func _pattern_of(attack: AttackData) -> AttackPattern:
	return attack.attack_pattern if attack != null else null
