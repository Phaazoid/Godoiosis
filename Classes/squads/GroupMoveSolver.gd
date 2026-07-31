extends Object
class_name GroupMoveSolver

# The Group Move formation solver: given the leader's destination, assign every other member the
# cell that best preserves its path-distance offset to the leader. Deterministic (Law #1) and
# PURE — it queues nothing and mutates nothing — which is exactly what lets one call drive both
# the live hover preview and the committed order (SquadManager.queue_group_move).
#
# Lived in game.gd, then moved into SquadManager (#22/#4); split out on its own 2026-07-26. It
# shares nothing with squad lifecycle but its inputs, and `board` already carries the grid, so
# it needs no node context and is entirely static.
#
# Member reach is computed against the leader's NEW cell (compute_move_range's leader_cell
# override) rather than by queueing the leader first — the other half of what keeps this
# non-committing.

static func plan(squad: Squad, leader_destination: Vector2i, board: BoardContext, allowed_cells = null) -> Array[MoveAction]:
	var moves: Array[MoveAction] = []
	var leader := squad.get_leader()
	var leader_start := leader.movement.cell
	var displacement := leader_destination - leader_start

	var leader_path := RulesService.reconstruct_path(RulesService.compute_move_range(leader, board).came_from, leader_start, leader_destination)
	var leader_move := MoveAction.new()
	leader_move.init(leader, leader_path, GridUtils.get_terrain_icon_at_cell(board.grid, leader_destination))
	moves.append(leader_move)

	var leash: int = squad.get_max_squad_range() * 2
	var taken := { leader_destination: true }

	for member in squad.get_members():
		if member == leader:
			continue

		# Cohesion leash from the leader's new cell (path-far cells split the squad around walls).
		# Bounded AT the leash: this field is only ever compared against it, so a cell further away
		# is rejected whether or not we know its true distance.
		#
		# Measured with THIS member's own traversal (#115). It used to be one shared field built
		# from the bare cell predicate: a Waterwalker's `reach` below correctly included near-shore
		# water, and then the leash rejected exactly those cells as UNREACHABLE. Per-member costs a
		# handful of extra depth-bounded walks — negligible beside the compute_move_range call
		# right under it, which is essentially all of plan()'s time (docs/performance.md).
		var leader_field := RulesService.path_hops(leader_destination, board, member, leash)

		var reach := RulesService.compute_move_range(member, board, leader_destination)
		var here: Vector2i = member.movement.cell

		var candidates := _candidate_cells(reach, here, leader_destination, leader_field, leash, taken, squad, allowed_cells)
		if candidates.is_empty():
			continue

		# Distances to this member's ideal offset cell — computed AFTER the candidates so the walk
		# can stop the moment it has covered them. It used to cross the whole board to answer a
		# couple of dozen queries, once per member.
		var target: Vector2i = here + displacement
		var to_target := RulesService.path_hops(target, board, member, -1, candidates)

		var best := _best_candidate(candidates, to_target, here)
		taken[best] = true
		if best == here:
			continue

		var member_path := RulesService.reconstruct_path(reach.came_from, here, best)
		var member_move := MoveAction.new()
		member_move.init(member, member_path, GridUtils.get_terrain_icon_at_cell(board.grid, best))
		moves.append(member_move)

	return moves

# Every cell this member may legally end on -> its move cost. Staying put counts as a candidate
# (cost 0) only when it independently satisfies the leash and the allow-list.
static func _candidate_cells(reach: Dictionary, here: Vector2i, leader_destination: Vector2i,
		leader_field: Dictionary, leash: int, taken: Dictionary, squad: Squad, allowed_cells) -> Dictionary:
	var candidates := {}
	for cell in reach.reachable.keys():
		if taken.has(cell):
			continue
		if leader_field.get(cell, RulesService.UNREACHABLE) > leash:
			continue
		if allowed_cells != null and not allowed_cells.has(cell):
			continue
		candidates[cell] = reach.reachable[cell]

	if not taken.has(here) \
		and GridUtils.manhattan_distance(here, leader_destination) <= squad.get_max_squad_range() \
		and leader_field.get(here, RulesService.UNREACHABLE) <= leash:
		if allowed_cells == null or allowed_cells.has(here):
			candidates[here] = 0
	return candidates

# Closest to the member's ideal offset cell, then cheapest to reach, then row-major — a total
# order, so the solver never depends on dictionary iteration luck.
static func _best_candidate(candidates: Dictionary, to_target: Dictionary, here: Vector2i) -> Vector2i:
	var have_best := false
	var best: Vector2i = here
	var best_to_target := 0
	var best_cost := 0
	for cell in candidates.keys():
		var d: int = to_target.get(cell, RulesService.UNREACHABLE)
		var cost: int = candidates[cell]
		if not have_best \
			or d < best_to_target \
			or (d == best_to_target and cost < best_cost) \
			or (d == best_to_target and cost == best_cost and _cell_before(cell, best)):
			have_best = true
			best = cell
			best_to_target = d
			best_cost = cost
	return best

static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	# Row-major tie-break so the solver is fully deterministic.
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
