extends Object
class_name RulesService

# Single source of truth for board-legality rules: movement reach, pathing, and
# attack-victim gathering. Extracted from game.gd so the game and the headless
# PlaySession share ONE implementation (protects Law #2 — the queue never lies).
# Pure functions of (unit, BoardContext); no node-tree or input dependencies.

const CANNOT_WALK_TILE := 99
const OUT_OF_MAP_TILE := 999
const UNREACHABLE := 999999   # path_hops' "no route to here"; any real hop count is far below
const NEIGHBOURS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

# May THIS unit traverse this cell's TERRAIN? BoardContext.is_walkable answers the cell-only form
# ("may a unit stand here", #109); this is the per-unit layer on top, and #115 made it the ONE
# home for that layer — movement_cost and path_hops had been deciding separately,
# so Waterwalk worked when a unit moved alone and silently stopped working when it moved with its
# squad.
#
# Deliberately says NOTHING about occupancy. An enemy body blocks a MOVE (movement_cost adds that
# below) but is not a terrain fact and moves every turn — a connectivity field must see through it.
static func can_traverse(cell: Vector2i, unit: Unit, board: BoardContext) -> bool:
	if board.is_walkable(cell):
		return true
	# Waterwalk (Movement, docs/design/jobs.md "The ability chassis"): ignores water's
	# impassability for the holder — the same shape as is_walkable's FROZEN bypass, just per-unit
	# instead of per-cell, which is why it lives here where `unit` is in scope. Reached only when
	# the cell is ALREADY impassable, so the JobCatalog lookup stays off the hot path for ordinary
	# ground (it used to be computed for every cell — see docs/performance.md).
	return board.terrain_kind_at(cell) == Terrain.Kind.WATER \
		and unit.has_live_ability(Abilities.Id.WATERWALK)

static func movement_cost(cell: Vector2i, unit: Unit, board: BoardContext) -> int:
	var data := board.grid.get_cell_tile_data(cell)
	if data == null:
		return OUT_OF_MAP_TILE
	if not can_traverse(cell, unit, board):
		return CANNOT_WALK_TILE
	if not board.grid.get_used_rect().has_point(cell):
		return OUT_OF_MAP_TILE

	var cost: int = 0
	if data.has_custom_data("move_cost"):
		cost += data.get_custom_data("move_cost")

	if blocks_passage(unit, board.unit_at_cell(cell)):
		return CANNOT_WALK_TILE

	return cost

# The two occupancy questions, split because they have DIFFERENT answers and both already existed
# inline (#127 pulled them out so AITactics can ask them instead of re-deriving them; each still has
# exactly one definition). Both take the occupant rather than a cell -- the callers have already
# paid for the unit_at_cell scan, which is linear.
#
# May `mover` PASS THROUGH a cell holding `occupant` (null = empty)? Only a still-standing enemy
# stops you: a downed body is stepped over (#122), and any ally is squeezed past.
static func blocks_passage(mover: Unit, occupant: Unit) -> bool:
	if occupant == null:
		return false
	return Team.is_enemy(mover.get_faction(), occupant.get_faction()) and not occupant.is_downed()

# May `mover` STAND on it? Stricter: only a squadmate's cell is shareable, because squads rotate
# through each other on purpose. This is compute_move_range's destination filter.
static func is_standable_for(mover: Unit, occupant: Unit) -> bool:
	return occupant == null or mover.squad.get_members().has(occupant)

static func compute_move_range(unit: Unit, board: BoardContext, leader_cell = null) -> Dictionary:
	var start := unit.movement.cell
	var max_cost := unit.get_mov()

	var frontier: Array[Vector2i] = [start]
	var cost_so_far := {}
	var came_from := {}

	cost_so_far[start] = 0
	came_from[start] = start

	# Label-correcting search — no priority ordering needed: a cell that later gets a
	# cheaper cost is re-appended and re-relaxed (the strict `<` check below), so
	# distances converge exactly. The old per-pop frontier sort compared stale
	# enqueue-time costs anyway, and cost O(n log n) per iteration for nothing.
	while frontier.size() > 0:
		var current_cell: Vector2i = frontier.pop_front()

		for dir in NEIGHBOURS:
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
			frontier.append(next)

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

		# Occupancy FIRST: GroupMoveSolver reads squad_unreachable as its catch-up set, so that
		# bucket must not carry cells nobody can stand on. It used to be filled before these two.
		if not is_standable_for(unit, other_unit):
			continue

		if other_unit == unit:
			continue

		if not unit.is_leader() and GridUtils.manhattan_distance(cell, leader_pos) > unit.squad.get_max_squad_range():
			squad_unreachable[cell] = cost_so_far[cell]
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

static func gather_attack_victims(attacker: Unit, affected_cells: Array[Vector2i], board: BoardContext, attack: AttackData) -> Array[Unit]:
	var victims: Array[Unit] = []
	for cell in affected_cells:
		# One question, one lookup (#105): who ENDS UP here. The old dance (physical occupant ->
		# discard if it's moving away -> else who's moving in) reconciled the forward and reverse
		# answers by hand, and could not see a knocked-back unit at all.
		var unit := board.projected_unit_at_cell(cell)
		if unit == null or victims.has(unit):
			continue
		if is_attack_victim(attacker, unit, attack):
			victims.append(unit)
	return victims

# Would this attack hit that unit if it ended up in the footprint? Split out of the gather so
# SquadPlanValidator asks the identical question with no board. Friendly fire is a property of the
# ATTACK BEING FIRED, not of whatever the attacker last aimed with (#102).
static func is_attack_victim(attacker: Unit, unit: Unit, attack: AttackData) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if unit == attacker:
		return attack != null and attack.hits_self
	return can_target(attacker, unit) or (attack != null and attack.hits_allies)

# Hostility gate: never yourself, and only a faction you're at war with. Was
# CombatComponent.can_attack, which took the attacker as a parameter despite being an instance
# method on that very attacker — a static rule wearing a component's clothes.
static func can_target(attacker: Unit, target: Unit) -> bool:
	if attacker == target:
		return false
	return Team.is_enemy(attacker.get_faction(), target.get_faction())
	
# Downed allies orthogonally adjacent to where `unit` will END UP (projected position, so
# "move next to the body, then rescue" works). Faction-based, not squad-based — the downed
# unit was ejected into its own solo squad, but it's still on your team.
static func adjacent_downed_allies(unit: Unit, board: BoardContext) -> Array[Unit]:
	var result: Array[Unit] = []
	var origin := unit.get_projected_destination()
	for cell in GridUtils.cells_within_manhattan_range(origin, 1):
		if cell == origin:
			continue
		var other := board.unit_at_cell(cell)
		if other != null and other != unit and other.is_downed() and not Team.is_enemy(unit.get_faction(), other.get_faction()):
			result.append(other)
	return result

# Living (active OR downed) enemies adjacent to where `unit` will END UP — same shape as
# adjacent_downed_allies above. Downed enemies stay legal intimidate targets on purpose:
# draining a body's Will can be worth a main action.
static func adjacent_enemies(unit: Unit, board: BoardContext) -> Array[Unit]:
	var result: Array[Unit] = []
	var origin := unit.get_projected_destination()
	for cell in GridUtils.cells_within_manhattan_range(origin, 1):
		if cell == origin:
			continue
		var other := board.unit_at_cell(cell)
		if other != null and other != unit and not other.is_dead() and Team.is_enemy(unit.get_faction(), other.get_faction()):
			result.append(other)
	return result
	
# Every source of DEF for `unit` standing on `cell`, itemized (#84). ONE composition point: the
# resolver sums it to mitigate damage, the inspect panel shows it — so the readout can never claim
# a different number than the one actually subtracted (Law #2's spirit applied to a stat readout).
# A future DEF source (a Guard ability, a buff) gets added HERE and both sites pick it up free.
static func def_breakdown(unit: Unit, cell: Vector2i, board: BoardContext) -> Dictionary[String, int]:
	var armor := unit.get_effective_def()
	var cover := 0
	if board != null:
		cover = board.cover_def_at(cell)
	var result: Dictionary[String, int] = {"armor": armor, "cover": cover, "total": armor + cover}
	return result

# Hop-distance (BFS over cells `unit` can traverse) from `source` -> { cell: hops }. Unweighted by
# design: it answers how terrain CONNECTS, not what a move costs. Read it as the counterpart to
# compute_move_range -- that says where you can stand THIS turn, this says how much of the way is
# left. Squad cohesion asks it, and so does every AI approach; it lived on GroupMoveSolver as
# _path_hops until the second caller arrived (Law #4 -- one question, one answer).
#
# Takes the unit because traversal is per-unit (#115): a Waterwalker's connected region includes
# water. Asks can_traverse and NOT movement_cost -- occupancy blocks a move but is not terrain and
# moves every turn. Letting an enemy body sever this field would change formations near any enemy,
# and would make a pursuing squad route around the very unit it is chasing.
#
# `block_on_occupancy` (#127) is the opt-in exception, and the DEFAULT IS LOAD-BEARING: cohesion
# must keep the terrain-only field for the reason directly above (docs/performance.md states this
# as a rule; pinned by test_an_enemy_body_does_not_sever_the_cohesion_field, which calls the
# default form). What the AI's approach picker needs is the opposite: an estimate of the route it
# will actually walk, so a standing enemy really does have to be gone around. Both are the same
# question -- hop distance under a traversal rule -- so the rule is a PARAMETER each caller states,
# not a second BFS. `nearest_enemy` must NOT pass true: it routes TO enemy cells, so blocking on
# them would read every enemy as UNREACHABLE.
#
# No caller needs the whole field, so both stopping rules exist: `max_depth` past N hops, `until`
# once every cell in that set has a distance. Both only skip work whose answer was already going to
# be discarded, so results are unchanged. Why that holds: docs/performance.md -> Invariants.
static func path_hops(source: Vector2i, board: BoardContext, unit: Unit, max_depth: int = -1, until: Dictionary = {}, block_on_occupancy: bool = false) -> Dictionary:
	var dist := { source: 0 }

	var pending := 0
	for cell in until:
		if not dist.has(cell):
			pending += 1
	if not until.is_empty() and pending == 0:
		return dist

	var bounds := board.grid.get_used_rect()   # hoisted: this used to be re-fetched per neighbour
	var queue: Array[Vector2i] = [source]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var d: int = dist[cell] + 1
		if max_depth >= 0 and d > max_depth:
			break   # the queue is in nondecreasing distance order, so nothing after this is nearer
		for dir in NEIGHBOURS:
			var next: Vector2i = cell + dir
			if dist.has(next):
				continue
			if not bounds.has_point(next):
				continue
			if not can_traverse(next, unit, board):
				continue
			if block_on_occupancy and blocks_passage(unit, board.unit_at_cell(next)):
				continue
			dist[next] = d
			if not until.is_empty() and until.has(next):
				pending -= 1
				if pending == 0:
					return dist
			queue.append(next)
	return dist
