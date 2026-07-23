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
			BaseAction.ActionType.SPRING_LOAD:
				queued = _try_spring_load(unit, squad_manager)
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
		unit.active_attack = attack   # probe via the player's pick slot -- reach/victim/splash queries all read it
		var reach := unit.combat.get_all_attack_cells_from(origin)
		for other in board.units:
			if not is_instance_valid(other):
				continue
			if not Team.is_enemy(unit.get_faction(), other.get_faction()):
				continue
			if not (other.is_active() or (include_downed and other.is_downed())):
				continue
			if not reach.has(other.movement.cell):
				continue
			var affected := unit.combat.get_affected_cells_from(origin, other.movement.cell)
			var victims := RulesService.gather_attack_victims(unit, affected, board)
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
	if not unit.unit_instance.has_live_ability(Abilities.Id.INTIMIDATION):
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

static func _try_spring_load(unit: Unit, squad_manager: SquadManager) -> bool:
	if not unit.can_reload_weapon():
		return false
	var action := SpringLoadAction.new()
	action.init(unit)
	return squad_manager.queue_action(unit.squad, action)

# Closest reachable cell that puts `leader` in attack range of `enemy`; if none does, the
# closest reachable cell period. `allowed`: optional Dictionary set restricting destinations.
# Reach here reads the DEFAULT pick (AIController resets active_attack before planning) --
# destination-per-candidate-attack is a known v1 approximation, noted on #78.
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
