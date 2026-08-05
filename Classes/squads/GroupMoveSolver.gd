extends Object
class_name GroupMoveSolver

# The Group Move formation solver: given the leader's destination, assign every other member the
# cell that best preserves its path-distance offset to the leader. Deterministic (Law #1) and PURE,
# which is what lets one call drive both the hover preview and the committed order.
#
# Member reach is measured against the leader's NEW cell (compute_move_range's leader_cell override)
# rather than by queueing the leader first — the other half of staying non-committing.

static func plan(squad: Squad, leader_destination: Vector2i, board: BoardContext, allowed_cells = null) -> Array[MoveAction]:
	var moves: Array[MoveAction] = []
	var leader := squad.get_leader()
	var leader_start := leader.movement.cell
	var displacement := leader_destination - leader_start

	var leader_reach := RulesService.compute_move_range(leader, board)
	# Both player callers check this first, but an unreachable goal makes reconstruct_path walk a
	# came_from that has no entry for it — a cascade of engine errors and a null destination.
	if not leader_reach.reachable.has(leader_destination):
		return moves

	var leader_move := MoveAction.new()
	leader_move.init(leader, RulesService.reconstruct_path(leader_reach.came_from, leader_start, leader_destination),
		GridUtils.get_terrain_icon_at_cell(board.grid, leader_destination))
	moves.append(leader_move)

	var leash: int = squad.get_max_squad_range() * 2
	var followers: Array[Unit] = []
	var candidates := {}   # Unit -> {cell: move cost}
	var to_target := {}    # Unit -> {cell: hops from its ideal offset cell}
	var reaches := {}      # Unit -> its compute_move_range result, kept for came_from

	for member in squad.get_members():
		if member == leader:
			continue

		# Cohesion leash from the leader's new cell, bounded AT it since nothing reads a larger value.
		# Per-member (#115): one shared field rejected a Waterwalker's own near-shore water cells.
		var leader_field := RulesService.path_hops(leader_destination, board, member, leash)
		var reach := RulesService.compute_move_range(member, board, leader_destination)
		var here: Vector2i = member.movement.cell

		var options := _candidate_cells(reach, here, leader_destination, leader_field, leash, squad, allowed_cells)
		if options.is_empty():
			continue
		followers.append(member)
		candidates[member] = options
		reaches[member] = reach
		# Distance to this member's ideal offset cell, walked AFTER the candidates so it can stop
		# as soon as it has covered them.
		to_target[member] = RulesService.path_hops(here + displacement, board, member, -1, options)

	# MOST CONSTRAINED FIRST: assignment has no backtracking, so a member with two options must pick
	# before one with twelve or it finds both taken. Member order left 6 of one Castle Assault
	# squad's 16 destinations unplaceable; this leaves 0. Ties keep member order (Law #1).
	var order: Array[Unit] = followers.duplicate()
	order.sort_custom(func(x: Unit, y: Unit) -> bool:
		var cx: int = candidates[x].size()
		var cy: int = candidates[y].size()
		if cx != cy:
			return cx < cy
		return followers.find(x) < followers.find(y))

	var assigned := {}   # Unit -> cell
	var taken := { leader_destination: true }
	for member in order:
		var best := _best_candidate(candidates[member], to_target[member], taken)
		if best == GridUtils.NO_CELL:
			continue
		taken[best] = true
		assigned[member] = best

	# Emitted in MEMBER order, not assignment order, so the queue panel's rows do not reshuffle
	# just because someone was more constrained this turn.
	for member in followers:
		if not assigned.has(member):
			continue
		var here: Vector2i = member.movement.cell
		var best: Vector2i = assigned[member]
		if best == here:
			continue
		var member_move := MoveAction.new()
		member_move.init(member, RulesService.reconstruct_path(reaches[member].came_from, here, best),
			GridUtils.get_terrain_icon_at_cell(board.grid, best))
		member_move.is_trailing = GridUtils.manhattan_distance(best, leader_destination) \
			> GridUtils.manhattan_distance(here, leader_start)
		moves.append(member_move)

	return moves

# Which of the leader's own destinations the WHOLE squad can follow to — every non-leader member
# must be able to end inside the cohesion bubble there. Answered once for the whole overlay instead
# of per hovered tile: one compute_move_range per member, then every cell it could stand on marks
# the diamond of destinations that cell satisfies. Running the real plan() per destination is the
# same answer at ~4.1 ms a cell, i.e. 176 ms to filter a 44-cell range.
static func followable_destinations(squad: Squad, board: BoardContext, leader_destinations: Array) -> Dictionary:
	var followable := {}
	for cell in leader_destinations:
		followable[cell] = true

	var leader := squad.get_leader()
	var union_at := {}   # destination -> {cell: true}: every cell ANY member could take there
	for member in squad.get_members():
		if member == leader:
			continue

		# reachable + squad_unreachable is the member's WHOLE standable footprint: the split is only
		# about the clamp cell, and both are standable because occupancy is filtered first.
		var reach := RulesService.compute_move_range(member, board, leader.movement.cell)
		var standable := {}
		for cell in reach.reachable.keys():
			standable[cell] = true
		for cell in reach.squad_unreachable.keys():
			standable[cell] = true
		standable[member.movement.cell] = true   # staying put is a placement; compute_move_range omits it

		var satisfied := {}
		for cell in standable.keys():
			for destination in GridUtils.cells_within_manhattan_range(cell, squad.get_max_squad_range()):
				if not followable.has(destination) or cell == destination:
					continue   # the leader stands on `destination`; no member may take it
				satisfied[destination] = true
				if not union_at.has(destination):
					union_at[destination] = {}
				union_at[destination][cell] = true

		for destination in followable.keys():
			if not satisfied.has(destination):
				followable.erase(destination)

	# Each member needs its OWN cell: fewer distinct reachable cells than members means no formation
	# exists at all (a thin corridor collapses them). Necessary, not sufficient — it never asks which
	# member takes which — but it is the shape a corridor produces, and refused nothing on real maps.
	var needed: int = squad.get_members().size() - 1
	for destination in followable.keys():
		if union_at.get(destination, {}).size() < needed:
			followable.erase(destination)
	return followable

# Every cell this member may legally end on -> its move cost. Staying put counts at cost 0 when it
# clears the leash and the allow-list on its own. If nothing inside the leader's new bubble is
# within MOV, the LEASH drops rather than the move — it is a preference against splitting the squad
# around a wall, and followable_destinations cannot see path distance to agree with it.
static func _candidate_cells(reach: Dictionary, here: Vector2i, leader_destination: Vector2i,
		leader_field: Dictionary, leash: int, squad: Squad, allowed_cells) -> Dictionary:
	var candidates := _cells_within(reach, here, leader_destination, leader_field, leash, squad, allowed_cells)
	if not candidates.is_empty():
		return candidates
	return _cells_within(reach, here, leader_destination, leader_field, RulesService.UNREACHABLE, squad, allowed_cells)

# No `taken` filter: options are computed for every member BEFORE any of them is placed, because
# ordering the assignment by how constrained a member is means knowing that first.
static func _cells_within(reach: Dictionary, here: Vector2i, leader_destination: Vector2i,
		leader_field: Dictionary, leash: int, squad: Squad, allowed_cells) -> Dictionary:
	var candidates := {}
	for cell in reach.reachable.keys():
		if leader_field.get(cell, RulesService.UNREACHABLE) > leash:
			continue
		if allowed_cells != null and not allowed_cells.has(cell):
			continue
		candidates[cell] = reach.reachable[cell]

	if (allowed_cells == null or allowed_cells.has(here)) \
		and SquadPlanValidator.cohesion_ok(squad, leader_destination, here) \
		and leader_field.get(here, RulesService.UNREACHABLE) <= leash:
		candidates[here] = 0
	return candidates

# Closest to the member's ideal offset cell, then cheapest to reach, then row-major — a total order,
# so the solver never depends on dictionary iteration luck. NO_CELL when every option is spoken for.
static func _best_candidate(candidates: Dictionary, to_target: Dictionary, taken: Dictionary) -> Vector2i:
	var have_best := false
	var best: Vector2i = GridUtils.NO_CELL
	var best_to_target := 0
	var best_cost := 0
	for cell in candidates.keys():
		if taken.has(cell):
			continue
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
