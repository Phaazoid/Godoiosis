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

# May this unit step FROM one cell TO an orthogonally adjacent one (#257)? The EDGE question, and
# the reason elevation needs one at all: can_traverse above answers "may this unit be on that cell",
# which cannot express "only via a ramp, and only along the ramp's slope".
#
# The rule is platforms-and-ramps, NOT Z arithmetic (dev reframe, docs/design/verticality.md): the
# only height maths here is equality and one LEVEL either way. A cliff of five is a staircase of
# five ramp cells or it is not climbable at all.
#
# A ramp's own elevation is its LOW side, so the climb happens LEAVING it and the descent happens
# ENTERING it -- which is why the two height clauses look at opposite cells.
static func can_step(from: Vector2i, to: Vector2i, unit: Unit, board: BoardContext) -> bool:
	if not can_traverse(to, unit, board):
		return false
	return height_step_ok(from, to, board)

# The height core of the edge question, extracted (#258) so melee's STEP rule ("same step, or a
# facing half step" -- dev, 2026-08-20) and movement answer it identically.
#
# ASK THE EDGE (#427 slice 3): two cells connect when the edge they share has the same two corner
# heights read from either side. That single comparison replaces a height DELTA measured against a
# ramp's climb, and it is not a widening -- it is the same question asked where it actually lives.
# Everything the old clauses said falls out of it:
#
# - flat to flat at one height: both edges (h, h). Connects.
# - a sheer edge of ANY size, half a level included ("half height still blocks movement and melee
#   range" -- dev, 2026-08-23): (h, h) against (h+n, h+n). Refused, with no clause of its own.
# - a ramp to the platform it climbs to: its high edge is (h+climb, h+climb) and so is the
#   platform's. Connects at whatever the ramp itself climbs, so the 45 and 26.6 degree slopes need
#   no separate arithmetic.
# - NO SIDEWAYS ENTRY, which used to be two guards in can_step: a north-rising ramp's east edge is
#   (high, low) against a flat neighbour's (low, low). Refused by the same comparison, so
#   Terrain.is_on_rise_axis is DELETED rather than relaxed.
#
# And one thing it says that the guards did not, which is a dev ruling rather than a side effect
# ("let's allow it. I'll feel test that afterwards" -- 2026-08-23): two ADJACENT SLOPES whose
# surfaces genuinely meet along the edge between them connect, so a unit may walk ACROSS a
# continuous slope rather than only up and down it. tests/rules/test_can_step.gd pins that
# explicitly, because both older sideways cases put a ramp beside FLAT ground and keep passing here.
static func height_step_ok(from: Vector2i, to: Vector2i, board: BoardContext) -> bool:
	var step := to - from
	return Terrain.edge_of_corners(board.corners_at(from), step) \
		== Terrain.edge_of_corners(board.corners_at(to), -step)

static func movement_cost(from: Vector2i, cell: Vector2i, unit: Unit, board: BoardContext) -> int:
	var data := board.grid.get_cell_tile_data(cell)
	if data == null:
		return OUT_OF_MAP_TILE
	# Takes `from` since #257: legality is an EDGE question. Deliberately REQUIRED rather than an
	# optional defaulting to `cell` -- an optional would give one question two answers depending on
	# who called, which is the exact drift #102 was built to end.
	if not can_step(from, cell, unit, board):
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
			var move_cost: int = movement_cost(current_cell, next, unit, board)

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

	# One cohesion field for the whole filter loop (#151) -- bounded at COH, so cheaper than the
	# search above it. Leaders skip it entirely; the filter below is gated on not is_leader.
	var coh_field := {}
	if not unit.is_leader():
		coh_field = SquadCohesion.field(unit.squad, leader_pos, unit, board)

	for cell in cost_so_far.keys():
		var other_unit := board.unit_at_cell(cell)

		# Occupancy FIRST: GroupMoveSolver reads squad_unreachable as its catch-up set, so that
		# bucket must not carry cells nobody can stand on. It used to be filled before these two.
		if not is_standable_for(unit, other_unit):
			continue

		if other_unit == unit:
			continue

		if not unit.is_leader() and not coh_field.has(cell):
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

static func gather_attack_victims(attacker: Unit, affected_cells: Array[Vector2i], board: BoardContext, attack: AttackData, allies_only := false) -> Array[Unit]:
	var victims: Array[Unit] = []
	for cell in affected_cells:
		# One question, one lookup (#105): who ENDS UP here. The old dance (physical occupant ->
		# discard if it's moving away -> else who's moving in) reconciled the forward and reverse
		# answers by hand, and could not see a knocked-back unit at all.
		var unit := board.projected_unit_at_cell(cell)
		if unit == null or victims.has(unit):
			continue
		if is_attack_victim(attacker, unit, attack, allies_only):
			victims.append(unit)
	return victims

# Would this attack hit that unit if it ended up in the footprint? Split out of the gather so
# SquadPlanValidator asks the identical question with no board. Friendly fire is a property of the
# ATTACK BEING FIRED, not of whatever the attacker last aimed with (#102).
#
# allies_only is an OPT-IN each caller states, the path_hops(block_on_occupancy) shape from #127 --
# and the default is the load-bearing half. Aiming a heal at an enemy stays legal on purpose (dev,
# #148): it is a niche the player may want. What is never legal is a DERIVED reaction heal landing
# on the attacker, so SquadManager's reaction expansion is the one caller that passes true.
static func is_attack_victim(attacker: Unit, unit: Unit, attack: AttackData, allies_only := false) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if unit == attacker:
		return attack != null and attack.hits_self
	if allies_only and can_target(attacker, unit):
		return false
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
#
# BOTH sides are projected (#126). This used to project the rescuer and read the body's LIVE cell,
# which was correct only by accident — a downed unit could not move. A 0-damage shove can now
# reposition one, and half-projecting it gets the answer exactly backwards: the menu offers the body
# on the cell it is about to vacate, and refuses the rescue aimed where it will actually land.
# With a plan (#124), "downed" widens to "downed BY THE TIME THE RESCUE RUNS": an active squadmate
# the pass predicts will drop to a counter is a legal pickup, because rescues execute in the side
# channel after every hit has landed. Plan-less callers (the AI's builder) keep the live rule.
static func adjacent_downed_allies(unit: Unit, board: BoardContext, plan: ResolvedPlan = null) -> Array[Unit]:
	var result: Array[Unit] = []
	var origin := unit.get_projected_destination()
	for cell in GridUtils.cells_within_manhattan_range(origin, 1):
		if cell == origin:
			continue
		var other := board.projected_unit_at_cell(cell)
		if other != null and other != unit and is_rescueable(other, plan) and not Team.is_enemy(unit.get_faction(), other.get_faction()):
			result.append(other)
	return result

# The LIFECYCLE half of "may this unit be picked up?" -- one seam for the menu's candidate list,
# the queue-time gate and the validator (#124). With a plan the question is asked of the pass's END
# state (the resolver's threaded hypo): a body nothing touches stays DOWNED, a squadmate the plan
# predicts will drop reads DOWNED by then, and a body a later hit finishes reads DEAD and drops out.
# (A predicted MAIM is a down too -- the resolver threads it as the same lifecycle. A Crisis-armed
# ally at the gate predicts CRISIS and so is never a candidate -- it stands back up, #158.)
# Without a plan, the live board answers, exactly as before #124.
static func is_rescueable(target: Unit, plan: ResolvedPlan) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if plan == null:
		return target.is_downed()
	return PlanResolver.projected_lifecycle(target, plan.hypo) == Unit.LifecycleState.DOWNED

# Living (active OR downed) enemies adjacent to where `unit` will END UP — same shape as
# adjacent_downed_allies above, projected on BOTH sides for the same reason (#126): intimidate is a
# side-channel verb too, so it meets its victim at the cell every shove this pass has already moved it
# to. Downed enemies stay legal intimidate targets on purpose: draining a body's Will can be worth a
# main action.
static func adjacent_enemies(unit: Unit, board: BoardContext) -> Array[Unit]:
	var result: Array[Unit] = []
	var origin := unit.get_projected_destination()
	for cell in GridUtils.cells_within_manhattan_range(origin, 1):
		if cell == origin:
			continue
		var other := board.projected_unit_at_cell(cell)
		if other != null and other != unit and not other.is_dead() and Team.is_enemy(unit.get_faction(), other.get_faction()):
			result.append(other)
	return result
	
# Who `unit` could become the bodyguard of right now (#414) — same shape as adjacent_enemies above,
# projected on BOTH sides for the same reason (#126): Guard arms after the move phase, so it meets
# its ward at the cell every queued move and every shove this pass has already moved it to.
#
# Allies, never enemies, and never yourself. A DOWNED ally stays a legal ward on purpose: a body
# waiting on a rescue is exactly what someone might stand over. Range is the guard's own
# (Unit.get_guard_range), not a hardcoded 1, so authored content widening it reaches the menu free.
static func guard_candidates(unit: Unit, board: BoardContext) -> Array[Unit]:
	var result: Array[Unit] = []
	var origin := unit.get_projected_destination()
	for cell in GridUtils.cells_within_manhattan_range(origin, unit.get_guard_range()):
		if cell == origin:
			continue
		var other := board.projected_unit_at_cell(cell)
		if other != null and other != unit and not other.is_dead() \
				and not Team.is_enemy(unit.get_faction(), other.get_faction()):
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
# water. Asks can_step and NOT movement_cost -- occupancy blocks a move but is not terrain and
# moves every turn. Letting an enemy body sever this field would change formations near any enemy,
# and would make a pursuing squad route around the very unit it is chasing.
#
# Still UNWEIGHTED after #257, and deliberately so: a ramp climb costs one hop like any other step.
# This measures how terrain CONNECTS, not what a move costs -- which is also why an unramped cliff
# breaks a squad's cohesion leash for free (dev ruling: a 1-block rise blocks squad range the way
# unwalkable terrain already does). Do not "fix" it by weighting climbs.
#
# `block_on_occupancy` (#127) is the opt-in exception, and the DEFAULT IS LOAD-BEARING: cohesion
# must keep the terrain-only field for the reason directly above (docs/performance.md states this
# as a rule; pinned by test_an_enemy_body_does_not_sever_the_cohesion_field, which calls the
# default form). What the AI's approach picker needs is the opposite: an estimate of the route it
# will actually walk, so a standing enemy really does have to be gone around. Both are the same
# question -- hop distance under a traversal rule -- so the rule is a PARAMETER each caller states,
# not a second BFS. The trap to know: passing true while routing TO enemy cells reads every enemy as
# UNREACHABLE, since an active enemy blocks passage. That is why AI target selection routes to each
# enemy's standable FIRING CELLS instead of its square -- see AITactics._approach_distances.
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
			if not can_step(cell, next, unit, board):
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
