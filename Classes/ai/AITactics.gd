extends Object
class_name AITactics

# `within`: optional Dictionary set of cells -- only enemies standing in it count.
# Downed enemies are DEPRIORITIZED, not protected (#57, fork 3): any active enemy wins;
# a downed one is targeted only when nothing active matches (finishing off is legal).
static func nearest_enemy(from_unit: Unit, board: BoardContext, within = null) -> Unit:
	var target := _nearest_enemy_matching(from_unit, board, within, false)
	if target == null:
		target = _nearest_enemy_matching(from_unit, board, within, true)
	return target

static func _nearest_enemy_matching(from_unit: Unit, board: BoardContext, within, downed: bool) -> Unit:
	var nearest: Unit = null
	var best := -1
	for unit in board.units:
		if not is_instance_valid(unit):
			continue
		if (unit.is_downed() if downed else unit.is_active()) == false:
			continue
		if not Team.is_enemy(from_unit.get_faction(), unit.get_faction()):
			continue
		if within != null and not within.has(unit.movement.cell):
			continue
		var d := GridUtils.manhattan_distance(from_unit.movement.cell, unit.movement.cell)
		if nearest == null or d < best:
			nearest = unit
			best = d
	return nearest

# Queues an attack if ANY enemy is within `unit`'s reach from its (possibly just-moved)
# projected position -- checks reach membership directly rather than "is the nearest enemy
# reachable," since a directional weapon's spread isn't radially symmetric (the closest
# enemy by raw distance can sit outside every facing while a farther one is lined up).
# Returns true if an attack was queued.
static func attack_if_possible(unit: Unit, board: BoardContext, squad_manager: SquadManager) -> bool:
	if not unit.is_active() or unit.has_main_action_queued():
		return false

	var origin := unit.get_projected_destination()
	var reach := unit.combat.get_all_attack_cells_from(origin)
	var target := _nearest_reachable_enemy(unit, board, origin, reach)
	if target == null:
		return false

	var enemy_cell := target.movement.cell
	var affected := unit.combat.get_affected_cells_from(origin, enemy_cell)
	if RulesService.gather_attack_victims(unit, affected, board).is_empty():
		return false

	var attack := AttackAction.create(unit, origin, null, enemy_cell)
	return squad_manager.queue_action(unit.squad, attack)

static func _nearest_reachable_enemy(unit: Unit, board: BoardContext, origin: Vector2i, reach: Array[Vector2i]) -> Unit:
	var target := _nearest_reachable_matching(unit, board, origin, reach, false)
	if target == null:
		target = _nearest_reachable_matching(unit, board, origin, reach, true)
	return target

static func _nearest_reachable_matching(unit: Unit, board: BoardContext, origin: Vector2i, reach: Array[Vector2i], downed: bool) -> Unit:
	var nearest: Unit = null
	var best := -1
	for other in board.units:
		if not is_instance_valid(other):
			continue
		if (other.is_downed() if downed else other.is_active()) == false:
			continue
		if not Team.is_enemy(unit.get_faction(), other.get_faction()):
			continue
		if not reach.has(other.movement.cell):
			continue
		var d := GridUtils.manhattan_distance(origin, other.movement.cell)
		if nearest == null or d < best:
			nearest = other
			best = d
	return nearest

# Closest reachable cell that puts `leader` in attack range of `enemy`; if none does, the
# closest reachable cell period. `allowed`: optional Dictionary set restricting destinations.
static func best_attack_destination(leader: Unit, enemy: Unit, board: BoardContext, allowed = null) -> Vector2i:
	var range := RulesService.compute_move_range(leader, board)
	var enemy_cell := enemy.movement.cell
	var best: Vector2i = leader.movement.cell
	var best_can_attack: bool = leader.combat.get_all_attack_cells_from(best).has(enemy_cell)
	var best_dist: int = GridUtils.manhattan_distance(best, enemy_cell)

	for cell in range.reachable.keys():
		if allowed != null and not allowed.has(cell):
			continue
		var can_attack: bool = leader.combat.get_all_attack_cells_from(cell).has(enemy_cell)
		var dist: int = GridUtils.manhattan_distance(cell, enemy_cell)
		if can_attack and not best_can_attack:
			best = cell
			best_can_attack = true
			best_dist = dist
		elif can_attack == best_can_attack and dist < best_dist:
			best = cell
			best_dist = dist

	return best

# Reachable cell that best approaches `goal_cell` (ties broken by move cost). Falls back to
# staying put when nothing allowed improves on the current cell.
static func closest_reachable_cell_to(unit: Unit, goal_cell: Vector2i, board: BoardContext, allowed = null) -> Vector2i:
	var range := RulesService.compute_move_range(unit, board)
	var best: Vector2i = unit.movement.cell
	var best_dist := GridUtils.manhattan_distance(best, goal_cell)
	var best_cost := 0

	for cell in range.reachable.keys():
		if allowed != null and not allowed.has(cell):
			continue
		var dist: int = GridUtils.manhattan_distance(cell, goal_cell)
		var cost: int = range.reachable[cell]
		if dist < best_dist or (dist == best_dist and cost < best_cost):
			best = cell
			best_dist = dist
			best_cost = cost

	return best
