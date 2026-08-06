extends Object
class_name AITactics

# Shared board queries + the archetype-agnostic main-action chooser (#29, rebuilt #78).
# Archetypes own movement (their personality); AIArchetype's tables say WHAT each prefers;
# this file owns HOW candidates are built, scored, and queued. Everything rides the player's
# own surface -- get_selectable_attacks/active_attack/AttackAction.declare/queue_action
# (Law #3) -- so new content (attacks, carvings, readiness, strain) reaches the AI with no
# AI-side wiring. Scoring calls the REAL resolver on a throwaway volley (Law #2 as forecast).

const _REMOVAL_TIERS: Array[ResolvedOutcome.Lethality] = [
	ResolvedOutcome.Lethality.DOWNED,
	ResolvedOutcome.Lethality.MAIMED,
	ResolvedOutcome.Lethality.KILLED,
]

class _Pick:
	var attack: AttackData
	var aim_cell: Vector2i

# `within`: optional Dictionary set of cells -- only enemies standing in it count.
# NEAREST IS BY ROUTE, not raw distance: an enemy two cells away through a wall is further off than
# one eight cells down an open corridor, and picking the walled one commits the whole squad to
# walking at a wall. Distance survives only as the tie-break, which is what everything degrades to
# when no enemy is reachable at all (an island, a sealed room) -- the old answer, unchanged.
# Downed enemies are DEPRIORITIZED, not protected (#57, fork 3): any active enemy wins;
# a downed one is targeted only when nothing active matches (finishing off is legal).
static func nearest_enemy(from_unit: Unit, board: BoardContext, within = null) -> Unit:
	var route := _route_to_enemies(from_unit, board)
	var target := _nearest_enemy_matching(from_unit, board, within, false, route)
	if target == null:
		target = _nearest_enemy_matching(from_unit, board, within, true, route)
	return target

# One walk answers every enemy at once: `until` stops it the moment all their cells have a distance,
# so the common case (an enemy in the same room) costs a fraction of the board.
static func _route_to_enemies(from_unit: Unit, board: BoardContext) -> Dictionary:
	var enemy_cells := {}
	for unit in board.units:
		if not is_instance_valid(unit):
			continue
		if Team.is_enemy(from_unit.get_faction(), unit.get_faction()):
			enemy_cells[unit.movement.cell] = true
	if enemy_cells.is_empty():
		return {}
	return RulesService.path_hops(from_unit.movement.cell, board, from_unit, -1, enemy_cells)

static func _nearest_enemy_matching(from_unit: Unit, board: BoardContext, within, downed: bool, route: Dictionary) -> Unit:
	var nearest: Unit = null
	var best_hops := 0
	var best_dist := 0
	for unit in board.units:
		if not is_instance_valid(unit):
			continue
		if (unit.is_downed() if downed else unit.is_active()) == false:
			continue
		if not Team.is_enemy(from_unit.get_faction(), unit.get_faction()):
			continue
		if within != null and not within.has(unit.movement.cell):
			continue
		var hops: int = route.get(unit.movement.cell, RulesService.UNREACHABLE)
		var d := GridUtils.manhattan_distance(from_unit.movement.cell, unit.movement.cell)
		if nearest == null or hops < best_hops or (hops == best_hops and d < best_dist):
			nearest = unit
			best_hops = hops
			best_dist = d
	return nearest

# Walks the archetype's priority list (AIArchetype.MAIN_ACTION_PRIORITY); first type that
# yields a buildable candidate queues and wins. Everything funnels through queue_action,
# whose actor_can_perform() stays the Law #3 backstop behind every builder's own gate.
static func queue_main_action(unit: Unit, board: BoardContext, squad_manager: SquadManager, priority: Array) -> bool:
	if not unit.is_active() or unit.has_main_action_queued():
		return false
	for t in priority:
		var queued := false
		match t:
			BaseAction.ActionType.ATTACK:
				queued = _try_best_attack(unit, board, squad_manager)
			BaseAction.ActionType.RESCUE:
				queued = _try_rescue(unit, board, squad_manager)
			BaseAction.ActionType.RALLY:
				queued = _try_rally(unit, squad_manager)
			BaseAction.ActionType.INTIMIDATE:
				queued = _try_intimidate(unit, board, squad_manager)
			BaseAction.ActionType.RELOAD:
				queued = _try_reload(unit, squad_manager)
			_:
				push_error("No AI builder for ActionType %s" % BaseAction.ActionType.keys()[t])
		if queued:
			return true
	return false

# Attack choice (#78): probe every selectable+fireable attack via the player's own pick slot
# (active_attack), score each aim with a throwaway resolver pass, queue the best. Two passes
# preserve #57's downed deprioritization: downed enemies neither aim nor score until nothing
# active produced a candidate.
static func _try_best_attack(unit: Unit, board: BoardContext, squad_manager: SquadManager) -> bool:
	if not unit.can_wield_equipped():
		return false
	var origin := unit.get_projected_destination()
	var reactions := ReactionCatalog.get_all()   # hoisted -- the catalog dir-scans per call
	for include_downed in [false, true]:
		var pick := _best_attack_candidate(unit, board, origin, include_downed, reactions)
		if pick == null:
			continue
		unit.active_attack = pick.attack   # the winner stays live, mirroring a player pick
		var declared := AttackAction.declare(unit, origin, pick.aim_cell)
		return squad_manager.queue_action(unit.squad, declared)
	unit.active_attack = null   # no candidate -- don't leave a probe leftover behind
	return false

static func _best_attack_candidate(unit: Unit, board: BoardContext, origin: Vector2i, include_downed: bool, reactions: Array[ElementalReaction]) -> _Pick:
	var candidates: Array[AttackData] = unit.get_selectable_attacks()
	if candidates.is_empty():
		candidates = [null]   # unarmed (or aura-dry rune): null pick = bare-fist Manhattan-1, the resolver's STR fallback
	var best: _Pick = null
	var best_removals := 0
	var best_net := 0
	for attack in candidates:
		if not unit.is_attack_fireable(attack):
			continue
		# The candidate is passed straight to the geometry now (#102). This loop used to write it
		# into unit.active_attack purely so Reach/victim queries would pick it up — a side channel
		# that left a live pick behind and skewed later reads.
		var reach := Reach.get_all_attack_cells_from(unit, origin, attack)
		for other in board.units:
			if not is_instance_valid(other):
				continue
			if not Team.is_enemy(unit.get_faction(), other.get_faction()):
				continue
			if not (other.is_active() or (include_downed and other.is_downed())):
				continue
			if not reach.has(other.movement.cell):
				continue
			var affected := Reach.get_affected_cells_from(unit, origin, other.movement.cell, attack)
			var victims := RulesService.gather_attack_victims(unit, affected, board, attack)
			if victims.is_empty():
				continue
			var plan := ResolvedPlan.new()
			for a in AttackAction.create_volley(unit, origin, other.movement.cell, victims, attack):
				plan.attacks.append(a)
			PlanResolver.resolve(plan, reactions)   # throwaway plan, the queue's own math (Law #2); pure -- no live state touched
			var score := _score_volley(unit, plan, include_downed)
			if score.x > best_removals or (score.x == best_removals and score.y > best_net):
				best = _Pick.new()
				best.attack = attack
				best.aim_cell = other.movement.cell
				best_removals = score.x
				best_net = score.y
	return best

# Score one resolved throwaway volley -> Vector2i(x = net removals, y = net damage);
# removals outrank damage (lexicographic at the call site), and a candidate must beat
# (0,0) to queue at all. Active enemies count for; ANY ally counts against (net-damage
# doctrine, dev call 2026-07-22); downed enemies count only when count_downed (#57);
# CRISIS counts as nothing -- the target stands back up surged, so triggering it is
# neither prize nor penalty (revisit with smarter AI kinds).
static func _score_volley(unit: Unit, plan: ResolvedPlan, count_downed: bool) -> Vector2i:
	var removals := 0
	var net := 0
	for a in plan.attacks:
		var victim := a.target
		if victim == null or a.resolved == null:
			continue
		var removing := _REMOVAL_TIERS.has(a.resolved.lethality)
		if Team.is_enemy(unit.get_faction(), victim.get_faction()):
			if a.resolved.lethality == ResolvedOutcome.Lethality.CRISIS:
				continue
			if victim.is_downed() and not count_downed:
				continue
			net += a.resolved.damage
			if removing:
				removals += 1
		else:
			net -= a.resolved.damage
			if removing:
				removals -= 1
	return Vector2i(removals, net)

# Fallback builders -- each mirrors MainActionMenu's gate for its verb, then picks a
# deterministic target (Law #1: explicit tie-break, first-in-order wins).

static func _try_rescue(unit: Unit, board: BoardContext, squad_manager: SquadManager) -> bool:
	if not unit.can_rescue_carry():
		return false
	var target: Unit = null
	for ally in RulesService.adjacent_downed_allies(unit, board):
		if target == null or ally.downed_turns_remaining < target.downed_turns_remaining:
			target = ally   # most urgent clock first; ties keep the earliest
	if target == null:
		return false
	var rescue := RescueAction.new()
	rescue.init(unit, target)
	return squad_manager.queue_action(unit.squad, rescue)

static func _try_rally(unit: Unit, squad_manager: SquadManager) -> bool:
	if not unit.can_rally():
		return false
	var rally := RallyAction.new()
	rally.init(unit)
	return squad_manager.queue_action(unit.squad, rally)

static func _try_intimidate(unit: Unit, board: BoardContext, squad_manager: SquadManager) -> bool:
	if not unit.has_live_ability(Abilities.Id.INTIMIDATION):
		return false
	var target: Unit = null
	for enemy in RulesService.adjacent_enemies(unit, board):
		if enemy.unit_instance.get_current_will() <= 0:
			continue   # nothing left to drain -- a wasted action
		if target == null or enemy.unit_instance.get_current_will() < target.unit_instance.get_current_will():
			target = enemy   # lowest Will = closest to the maim cliff; ties keep the earliest
	if target == null:
		return false
	var action := IntimidateAction.new()
	action.init(unit, target)
	return squad_manager.queue_action(unit.squad, action)

static func _try_reload(unit: Unit, squad_manager: SquadManager) -> bool:
	if not unit.can_reload_weapon():
		return false
	var action := ReloadAction.new()
	action.init(unit)
	return squad_manager.queue_action(unit.squad, action)

# Where the leader should stand to fight `enemy`: a cell it can already attack from, else the cell
# furthest along the ROUTE to it. The route targets the nearest STANDABLE firing position, not
# enemy.movement.cell itself (#127) -- see _nearest_standable_attack_cell for why that distinction
# is load-bearing.
static func best_attack_destination(leader: Unit, enemy: Unit, board: BoardContext, allowed = null) -> Vector2i:
	var aiming := leader.get_fired_attack()
	var route_target := _nearest_standable_attack_cell(leader, enemy.movement.cell, aiming, board)
	return _best_approach(leader, enemy.movement.cell, board, allowed, true, route_target)


# Reachable cell that best approaches `goal_cell` -- Sentry's walk back to its post. Same walk with
# no attack term: a post is a place, not a target.
static func closest_reachable_cell_to(unit: Unit, goal_cell: Vector2i, board: BoardContext, allowed = null) -> Vector2i:
	return _best_approach(unit, goal_cell, board, allowed, false)


# The standable cell nearest `unit` from which it could hit whatever occupies `goal` -- #127. Ranking
# hops of route toward `goal` ITSELF is wrong for an attack approach: get_all_attack_cells_from is
# unioned over all 4 facings, so "X can hit goal" iff "goal can hit X" for every pattern this game
# authors, and RulesService.path_hops is deliberately occupancy-blind (it has to be, for the Group
# Move cohesion field) -- so it ranks a firing cell a downed body is standing on as "closest", the
# unit walks up to the body and parks there forever, because nothing about a dead-end changes
# between turns. Filtering to standable cells first (can_traverse for terrain, is_standable_for
# for occupancy -- the same two rules compute_move_range's own BFS already enforces, asked instead
# of re-derived) means the hop metric can only ever point at a cell the unit could actually finish
# reaching.
# Falls back to `goal` itself when no standable firing position exists at all -- _best_approach's
# existing "sealed off" ladder (straight-line distance) takes it from there, unchanged.
static func _nearest_standable_attack_cell(unit: Unit, goal: Vector2i, aiming: AttackData, board: BoardContext) -> Vector2i:
	var candidates := {}
	for cell in Reach.get_all_attack_cells_from(unit, goal, aiming):
		if not RulesService.can_traverse(cell, unit, board):
			continue   # a wall/off-map neighbour of goal is not a firing position either
		if RulesService.is_standable_for(unit, board.unit_at_cell(cell)):
			candidates[cell] = true
	if candidates.is_empty():
		return goal

	var route := RulesService.path_hops(unit.movement.cell, board, unit, -1, candidates, true)
	var best := goal
	var best_hops := RulesService.UNREACHABLE
	for cell in candidates:
		var hops: int = route.get(cell, RulesService.UNREACHABLE)
		if hops < best_hops:
			best = cell
			best_hops = hops
	return best


# The approach ladder both moving archetypes ride. Candidates rank by ROUTE -- hops of real path
# left to `goal` -- and NOT by straight-line distance, which is the whole fix: a cell on the wrong
# side of a wall is distance-near and route-far, so the old ranking found the squad's own cell was
# already the minimum and parked it against the wall. Not for a turn -- forever, because nothing
# about the situation changed between turns.
#
# Multi-turn pursuit needs no stored route. The hop field is EXACT, so the best cell reachable this
# turn is always a real step along the real path, and next turn re-derives against wherever the
# board has moved to. Nothing cached, nothing to invalidate.
#
# `route_target` (#127) lets a caller aim the hop metric at a different cell than `goal` -- Rushdown
# passes the nearest STANDABLE firing cell (see _nearest_standable_attack_cell), so the metric never
# gets fooled by a body parked on the nearest geometric firing position. Defaults to `goal`, so
# closest_reachable_cell_to (a post is a plain cell, no firing-position question to ask) is unchanged.
# The can_attack / straight-line terms below still test against the real `goal` either way.
static func _best_approach(unit: Unit, goal: Vector2i, board: BoardContext, allowed, prefer_attack: bool, route_target = null) -> Vector2i:
	var range := RulesService.compute_move_range(unit, board)
	var here: Vector2i = unit.movement.cell
	# Read once, like a player's aim -- destination-per-candidate-attack is still the #78 v1
	# approximation (docs/design/ai-tactics.md). Null when we aren't approaching a fight.
	var aiming: AttackData = unit.get_fired_attack() if prefer_attack else null

	# Bounded to exactly the cells we will score. compute_move_range omits the unit's own cell, so
	# add it back: standing still is always a candidate, and it's the fallback when nothing beats it.
	var wanted: Dictionary = range.reachable.duplicate()
	wanted[here] = true
	var hop_target: Vector2i = goal
	if route_target != null:
		hop_target = route_target
	# ALWAYS occupancy-aware (#127). Retargeting alone wasn't enough -- the RANKING still imagined
	# cutting straight through the bodies in the way -- and this half is not attack-specific: every
	# caller here is asking "how much closer does this cell get me", so the estimate has to describe
	# the route the unit will really walk. Sentry's walk home has the same shape (an enemy holding a
	# corridor), which is why this is unconditional rather than keyed off route_target.
	var route := RulesService.path_hops(hop_target, board, unit, -1, wanted, true)

	var best := here
	var best_can_attack: bool = prefer_attack and Reach.get_all_attack_cells_from(unit, here, aiming).has(goal)
	var best_hops: int = route.get(here, RulesService.UNREACHABLE)
	var best_dist: int = GridUtils.manhattan_distance(here, goal)
	var best_cost := 0

	for cell in range.reachable.keys():
		if allowed != null and not allowed.has(cell):
			continue
		var can_attack: bool = prefer_attack and Reach.get_all_attack_cells_from(unit, cell, aiming).has(goal)
		var hops: int = route.get(cell, RulesService.UNREACHABLE)
		var dist: int = GridUtils.manhattan_distance(cell, goal)
		var cost: int = range.reachable[cell]
		if _approach_beats(can_attack, hops, dist, cost, best_can_attack, best_hops, best_dist, best_cost):
			best = cell
			best_can_attack = can_attack
			best_hops = hops
			best_dist = dist
			best_cost = cost

	return best


# Ranked, best first: can I attack from here > fewer hops of route left > nearer in a straight line
# > cheaper to reach. Ties keep the earlier cell (Law #1: reachable's key order is the move-range
# search's own, so it is stable).
#
# The straight-line term earns its place in exactly one case: when the goal is sealed off entirely,
# every candidate scores UNREACHABLE and the ladder falls through to it -- so the squad crowds the
# nearest shore instead of reading "no route" as "stay home".
static func _approach_beats(can_attack: bool, hops: int, dist: int, cost: int,
		b_can_attack: bool, b_hops: int, b_dist: int, b_cost: int) -> bool:
	if can_attack != b_can_attack:
		return can_attack
	if hops != b_hops:
		return hops < b_hops
	if dist != b_dist:
		return dist < b_dist
	return cost < b_cost
