extends Object
class_name RulesService

# Single source of truth for board-legality rules: movement reach, pathing, and
# attack-victim gathering. Extracted from game.gd so the game and the headless
# PlaySession share ONE implementation (protects Law #2 — the queue never lies).
# Pure functions of (unit, BoardContext); no node-tree or input dependencies.

const CANNOT_WALK_TILE := 99
const OUT_OF_MAP_TILE := 999

static func movement_cost(cell: Vector2i, unit: Unit, board: BoardContext) -> int:
	var data := board.grid.get_cell_tile_data(cell)
	if data == null:
		return OUT_OF_MAP_TILE
	if board.is_walkable(cell) == false:
		return CANNOT_WALK_TILE
	if not board.grid.get_used_rect().has_point(cell):
		return OUT_OF_MAP_TILE

	var cost: int = 0
	if data.has_custom_data("move_cost"):
		cost += data.get_custom_data("move_cost")

	var other := board.unit_at_cell(cell)
	if other != null:
		if Team.is_enemy(unit.get_faction(), other.get_faction()):
			return CANNOT_WALK_TILE

	return cost

static func compute_move_range(unit: Unit, board: BoardContext, leader_cell = null) -> Dictionary:
	var start := unit.movement.cell
	var max_cost := unit.movement.move_range

	var frontier := []
	var cost_so_far := {}
	var came_from := {}

	frontier.append({"cell": start, "cost": 0})
	cost_so_far[start] = 0
	came_from[start] = start

	while frontier.size() > 0:
		frontier.sort_custom(func(a, b): return a.cost < b.cost)
		var current = frontier.pop_front()
		var current_cell: Vector2i = current.cell

		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = current_cell + dir
			var move_cost: int = movement_cost(next, unit, board)

			if move_cost > CANNOT_WALK_TILE:
				continue
			if not board.grid.get_used_rect().has_point(next):
				continue

			var new_cost: int = cost_so_far[current_cell] + move_cost
			if new_cost > max_cost:
				continue
			if cost_so_far.has(next) and new_cost >= cost_so_far[next]:
				continue

			cost_so_far[next] = new_cost
			came_from[next] = current_cell
			frontier.append({"cell": next, "cost": new_cost})

	var reachable := {}
	var squad_unreachable := {}

	var leader_pos: Vector2i
	if leader_cell != null:
		leader_pos = leader_cell
	elif not unit.is_leader():
		leader_pos = unit.squad.get_leader().get_projected_destination()
	else:
		leader_pos = unit.movement.cell   # unused for leaders (filter below is gated on not is_leader)

	for cell in cost_so_far.keys():
		var other_unit := board.unit_at_cell(cell)

		if not unit.is_leader() and GridUtils.manhattan_distance(cell, leader_pos) > unit.squad.get_max_range():
			squad_unreachable[cell] = cost_so_far[cell]
			continue

		if other_unit != null and not unit.squad.get_members().has(other_unit):
			continue

		if other_unit == unit:
			continue

		reachable[cell] = cost_so_far[cell]

	return {
		"reachable": reachable,
		"came_from": came_from,
		"squad_unreachable": squad_unreachable
	}

static func reconstruct_path(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current := goal

	while current != start:
		path.push_front(current)
		current = came_from[current]

	path.push_front(start)
	return path

static func gather_attack_victims(attacker: Unit, affected_cells: Array[Vector2i], board: BoardContext) -> Array[Unit]:
	var victims: Array[Unit] = []
	var weapon := attacker.get_equipped_weapon()
	var hits_allies: bool = weapon != null and weapon.hits_allies

	for cell in affected_cells:
		var unit := board.unit_at_cell(cell)
		if unit != null and unit.get_projected_destination() != cell:
			unit = null
		if unit == null:
			unit = board.projected_unit_at_cell(cell)

		if unit == null or unit == attacker or victims.has(unit):
			continue

		if attacker.combat.can_attack(attacker, unit):
			victims.append(unit)
		elif hits_allies:
			victims.append(unit)

	return victims
