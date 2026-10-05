extends Object
class_name AITactics

# Shared board queries + the archetype-agnostic main-action chooser (#29, rebuilt #78).
# Archetypes own movement (their personality); AIArchetype's tables say WHAT each prefers;
# this file owns HOW candidates are built, scored, and queued. Everything rides the player's
# own surface -- get_selectable_attacks/active_attack/AttackAction.declare/queue_action
# (Law #3) -- so new content (attacks, carvings, readiness, strain) reaches the AI with no
# AI-side wiring. Scoring resolves the squad's REAL plan with a candidate added (Law #2 as
# forecast), so a candidate is priced by what it adds to what the squad is already doing (#117).
#
# (_REMOVAL_TIERS -- the DOWNED/MAIMED/KILLED rung list -- is gone with that change: a removal is
# now a CHANGE OF STANDING across the plan, read off LethalityRules.lifecycle_for's own threading
# via PlanResolver.plan_fells, which covers the same three rungs and cannot double-count
# a second hit on the same body -- and, since #708, the fresh CRISIS the ladder does not move a
# lifecycle for. See _score_plan.)

# WHO THE SQUAD FIGHTS -- and it is TWO SYSTEMS, forked on one question: is anybody attackable
# this turn? (Dev ruling, 2026-09-02, from playtest.)
#
#   SOMEBODY IS -> pick the best EXCHANGE. Distance is only the tie-break. His words: "the closest
#   possible unit isn't what should be picked, but the best possible trade for the attacker...
#   absolute distance was not even, but that should not matter since both attacks were in range
#   that turn." The reported case: an enemy adjacent to a spearman that could counter, with a mage
#   one step beyond that could not, and it took the spearman.
#
#   NOBODY IS -> pursue the NEAREST, unchanged. That is Rushdown's identity and it is deliberate:
#   a rusher that hunts the softest target across the board is the BALANCED archetype wearing the
#   wrong name (see "Not this layer" in ai-tactics.md), it stops the player being rewarded for
#   screening a mage behind a frontline, and it is unreadable -- "it goes for whoever is closest"
#   is a rule you can bait and funnel, "it goes for its best target" is a computation you cannot see.
#
# A BODY COUNTS AS ATTACKABLE (#720, dev 2026-09-03: "the same level of prioritization as other
# attacks, it just loses to other attacks in the head to head"). Both selectors used to answer only
# about the STANDING, so a squad with a body in reach and nothing else read the fork as "nobody" and
# fell into pursuit -- which then preferred any standing enemy anywhere, including one it had no
# route to. That is thirteen rounds of Castle Assault revving beside a downed general.
#
# STANDING IS THE TOP KEY AND SITS ABOVE SAFETY, which is the whole of what makes it a ranking
# rather than a reversal: a body can never counter, so it is unconditionally "safe" and would win
# every comparison it entered. Ordered this way it wins only what nobody upright is competing for.
#
# The exchange term is a BOOLEAN -- can they answer me from the cell I would attack from -- and not
# a scored one. A hypothetical MOVE moves nobody (SquadManager._resolve_actions reads positions off
# the LIVE queue), so this layer cannot resolve the fight it is choosing; the ATTACK pick can, and
# would be throwing information away. Scoring a cell IS possible by standing the unit on it, which
# is what seek_positions does (#760) -- but only for a removal or a squad break, by ruling, so who
# to fight stays this boolean. Declared in ai-tactics.md rather than left to be discovered.
static func choose_engagement_target(leader: Unit, board: BoardContext, squad_manager: SquadManager,
		within = null, allowed = null) -> Unit:
	var engageable := _engageable_enemies(leader, board, within, allowed)
	if engageable.is_empty():
		return nearest_enemy(leader, board, within)   # pursuit: nobody in reach, distance is the answer

	var best: Unit = null
	var best_standing := false
	var best_safe := false
	var best_hops := 0
	for enemy: Unit in engageable:
		var plan: _Engagement = engageable[enemy]
		# Asked at the cell we would attack FROM, so this layer and the approach cannot disagree
		# about where the fight happens.
		var standing := enemy.is_active()
		var safe := not squad_manager.can_counter(enemy, leader, board, plan.from)
		if best == null or _engagement_beats(standing, safe, plan.hops, best_standing, best_safe, best_hops):
			best = enemy
			best_standing = standing
			best_safe = safe
			best_hops = plan.hops
	return best


# Ranked, best first: still on their feet > cannot answer me > fewer hops of route. Ties keep the
# earlier enemy (Law #1 -- board order, and the caller's dictionary preserves it).
static func _engagement_beats(standing: bool, safe: bool, hops: int,
		b_standing: bool, b_safe: bool, b_hops: int) -> bool:
	if standing != b_standing:
		return standing
	if safe != b_safe:
		return safe
	return hops < b_hops


# Enemy -> the cell this leader would attack it from, for every enemy it could reach and attack
# THIS TURN -- a body among them since #720, since a body is an ordinary target that loses head to
# head. `within` tests the enemy's OWN cell exactly as pursuit does -- without it a Sentry engages
# an enemy standing OUTSIDE its zone because a cell inside the zone can reach it, i.e. a lured
# sentry, which is the one thing that archetype exists to refuse.
#
# A leader with squadmates engages only from a cell its squad can FOLLOW it to (#1220) -- the same
# refusal the player's Move overlay paints grey (#1069). It was optimistic until then: the leader's
# unclamped range, so cohesion could refuse the group move and the squad stood still.
class _Engagement:
	var from: Vector2i   # the cell we would attack from -- the same one the approach will route to
	var hops: int        # route to it, the tie-break


static func _engageable_enemies(leader: Unit, board: BoardContext, within, allowed) -> Dictionary:
	allowed = _leader_allowed(leader, board, allowed)
	var aiming := leader.get_fired_attack()
	var reach_set: Dictionary = RulesService.compute_move_range(leader, board).reachable.duplicate()
	reach_set[leader.movement.cell] = true   # standing still counts; compute_move_range omits the start cell

	# Every firing cell this leader may LEGALLY use against each enemy -- filtered BEFORE the walk,
	# not after. Asking _nearest_standable_attack_cell for the globally nearest and then testing IT
	# is wrong twice over: it excludes an enemy whose nearest firing cell is outside the leash even
	# when another one inside it would serve, and it pays a whole BFS per enemy (measured: +21% on
	# Castle Assault, over the budget this was planned against).
	var per_enemy := {}
	var wanted := {}
	for enemy in board.units:
		if not is_instance_valid(enemy) or not (enemy.is_active() or enemy.is_downed()):
			continue
		if not Team.is_enemy(leader.get_faction(), enemy.get_faction()):
			continue
		if within != null and not within.has(enemy.movement.cell):
			continue
		var legal := {}
		for cell in _standable_attack_cells(leader, enemy.movement.cell, aiming, board):
			if not reach_set.has(cell):
				continue
			if allowed != null and not allowed.has(cell):
				continue
			legal[cell] = true
		if not legal.is_empty():
			per_enemy[enemy] = legal
			wanted.merge(legal)
	if wanted.is_empty():
		return {}

	# ONE walk for every candidate cell at once, _approach_distances' own trick: the `until` set is
	# the union, so the search stops as soon as they all have a distance.
	var field := RulesService.path_hops(leader.movement.cell, board, leader, -1, wanted, true)
	var out := {}
	for enemy: Unit in per_enemy:
		var best := _Engagement.new()
		best.hops = RulesService.UNREACHABLE
		for cell in per_enemy[enemy]:
			var hops: int = field.get(cell, RulesService.UNREACHABLE)
			if hops < best.hops:
				best.from = cell
				best.hops = hops
		if best.hops < RulesService.UNREACHABLE:
			out[enemy] = best   # in move-COST range but with no occupancy-honest route is not engageable
	return out


# `within`: optional Dictionary set of cells -- only enemies standing in it count.
# NEAREST IS BY ROUTE, not raw distance: an enemy two cells away through a wall is further off than
# one eight cells down an open corridor, and picking the walled one commits the whole squad to
# walking at a wall. Distance survives only as the tie-break, which is what everything degrades to
# when no enemy is reachable at all (an island, a sealed room) -- the old answer, unchanged.
#
# ONE RANKING OVER EVERYONE, bodies included (#720, dev 2026-09-03). This was two walks -- every
# active enemy first, downed ones consulted only if that found nobody -- which made "deprioritized"
# mean ABSOLUTE precedence in the layer that decides where to STAND: a body one step away lost to a
# standing enemy on the far side of a wall, the squad committed its turn to a route that does not
# exist, and every candidate cell scored UNREACHABLE so the straight-line fallback answered with the
# cell it was already on. It parked there for the rest of the battle. Now a body ranks like anyone
# else and simply loses the head-to-head: standing is the tie-break BELOW route, so it decides only
# when the walk is equally long.
# ACTIVE_ONLY is the caller's to state (#751), the path_hops(block_on_occupancy) shape: one question
# -- which enemy is nearest -- with the lifecycle admission passed in rather than a second walk.
# PURSUIT wants a body (it is an ordinary target, #720); a WATCH cannot use one, because a corpse
# never enters anything and _watch_triggered_by refuses a non-ACTIVE entrant outright. Left false so
# every existing caller is unchanged.
#
# `hypo` is the squad's plan so far, for the WATCH caller (#1209): it runs after the squad's attacks
# are queued, so "standing" has to mean standing once those land. Empty is the live board, which is
# every other caller -- the movement layer runs before the squad queues anything.
static func nearest_enemy(from_unit: Unit, board: BoardContext, within = null, active_only := false,
		hypo: Dictionary = {}) -> Unit:
	var route := _approach_distances(from_unit, board)
	var nearest: Unit = null
	var best_hops := 0
	var best_standing := false
	var best_dist := 0
	for unit in board.units:
		if not is_instance_valid(unit):
			continue
		var life := PlanResolver.projected_lifecycle(unit, hypo)
		var standing := life == Unit.LifecycleState.ACTIVE
		if not (standing or (life == Unit.LifecycleState.DOWNED and not active_only)):
			continue
		if not Team.is_enemy(from_unit.get_faction(), unit.get_faction()):
			continue
		# `within` still tests the enemy's OWN cell -- "is this enemy inside my zone" is a different
		# question from "how far is a firing position on it", and Sentry's leash means the first.
		if within != null and not within.has(unit.movement.cell):
			continue
		var hops: int = route.get(unit, RulesService.UNREACHABLE)
		var d := GridUtils.manhattan_distance(from_unit.movement.cell, unit.movement.cell)
		if nearest == null or _pursuit_beats(hops, standing, d, best_hops, best_standing, best_dist):
			nearest = unit
			best_hops = hops
			best_standing = standing
			best_dist = d
	return nearest


# Ranked, best first: fewer hops of route > still on their feet > nearer in a straight line. The
# standing term sits BELOW route and ABOVE distance on purpose -- above route it is the two-walk
# precedence again, below distance it never speaks, since two enemies at equal hops are rarely at
# equal distance too. Ties keep the earlier unit (Law #1: board order).
static func _pursuit_beats(hops: int, standing: bool, dist: int,
		b_hops: int, b_standing: bool, b_dist: int) -> bool:
	if hops != b_hops:
		return hops < b_hops
	if standing != b_standing:
		return standing
	return dist < b_dist

# Enemy -> hops to the nearest cell this unit could FIGHT it from. Keyed by the unit rather than by
# its cell, because the distance that decides a target has to be the distance to a firing position,
# not to the target's own square (#127): those differ by the whole detour whenever a body is parked
# on the near firing cell, and answering with the square is what let target selection and the
# approach picker disagree about which enemy was closest.
#
# Occupancy-aware, unlike the field this replaced -- and note it CANNOT simply be
# path_hops(..., enemy_cells, true): an active enemy blocks passage, so routing to enemy squares
# with occupancy on would score every enemy UNREACHABLE and collapse selection to the raw-distance
# tie-break. Routing to their approach cells is what makes the honest metric usable here at all.
#
# Still ONE walk for every enemy at once: the `until` set is the union of all their firing cells, so
# the search stops the moment they all have a distance. An enemy with no standable firing cell (or
# no route to one) is absent -> UNREACHABLE -> it falls to the distance tie-break, the same
# degradation the sealed-room case has always had.
static func _approach_distances(from_unit: Unit, board: BoardContext) -> Dictionary:
	# One hoisted pick, matching _best_approach's own v1 approximation (docs/design/ai-tactics.md).
	var aiming := from_unit.get_fired_attack()
	var per_enemy := {}
	var wanted := {}
	for unit in board.units:
		if not is_instance_valid(unit):
			continue
		if not Team.is_enemy(from_unit.get_faction(), unit.get_faction()):
			continue
		var cells := _standable_attack_cells(from_unit, unit.movement.cell, aiming, board)
		per_enemy[unit] = cells
		wanted.merge(cells)
	if wanted.is_empty():
		return {}

	var field := RulesService.path_hops(from_unit.movement.cell, board, from_unit, -1, wanted, true)
	var result := {}
	for unit in per_enemy:
		var best := RulesService.UNREACHABLE
		for cell in per_enemy[unit]:
			var hops: int = field.get(cell, RulesService.UNREACHABLE)
			if hops < best:
				best = hops
		result[unit] = best
	return result

# Walks the archetype's priority list (AIArchetype.MAIN_ACTION_PRIORITY); first type that
# yields a buildable candidate queues and wins. Everything funnels through queue_action,
# whose actor_can_perform() stays the Law #3 backstop behind every builder's own gate.
static func queue_main_action(unit: Unit, board: BoardContext, squad_manager: SquadManager, priority: Array) -> bool:
	if not unit.is_active() or unit.has_main_action_queued():
		return false
	var routine := AIWeaponRoutine.for_unit(unit)
	for t in priority:
		var verb: BaseAction.ActionType = t
		# The family's own say on its own verbs (#726): a weapon routine may refuse a preparation
		# that is not worth it right now -- the same shape as can_reload() answering false, a
		# builder gate rather than a skip of the walk. Asked about the weapon self-abilities only;
		# rescue is not a weapon's to veto.
		if AIWeaponRoutine.WEAPON_VERBS.has(verb) and not routine.allows_preparation(unit, verb, board):
			continue
		var queued := false
		match verb:
			BaseAction.ActionType.ATTACK:
				queued = _try_best_attack(unit, board, squad_manager)
			BaseAction.ActionType.RESCUE:
				queued = _try_rescue(unit, board, squad_manager)
			BaseAction.ActionType.RELOAD:
				queued = _try_reload(unit, squad_manager)
			BaseAction.ActionType.REV:
				queued = _try_rev(unit, squad_manager)
			BaseAction.ActionType.BURROW:
				queued = _try_burrow(unit, squad_manager)
			BaseAction.ActionType.OVERWATCH:
				queued = _try_overwatch(unit, board, squad_manager)
			BaseAction.ActionType.GUARD:
				queued = _try_guard(unit, board, squad_manager)
			_:
				push_error("No AI builder for ActionType %s" % BaseAction.ActionType.keys()[verb])
		if queued:
			return true
	return false

# Attack choice (#78, rebuilt #117): probe every selectable+fireable attack, score each aim as its
# MARGINAL GAIN to the squad's own plan, queue the best. The per-unit door -- one member, deciding
# alone. The squad walks these jointly instead; see _queue_attacks_jointly.
static func _try_best_attack(unit: Unit, board: BoardContext, squad_manager: SquadManager) -> bool:
	if not unit.can_wield_equipped() or unit.squad == null:
		return false
	var reactions := ReactionCatalog.get_all()   # hoisted -- a scoring pass resolves many times, and
	var terrain := TerrainReactionCatalog.get_all()   # each call copies the cached list (#1213)
	var squad := unit.squad
	var base_plan := squad_manager.resolve_plan(squad, board, reactions, terrain)
	var alone: Array[Unit] = [unit]
	var stakes := _stakes_for(squad, board, base_plan)
	var pick := _best_candidate_for(unit, squad, board, base_plan, squad_manager, reactions, terrain, {}, true,
			_candidates_by_member(alone, board, base_plan, stakes), stakes)
	var queued := false
	if pick != null:
		unit.active_attack = pick.action.fired_attack   # the winner stays live, mirroring a player pick
		# The board must be back on the real queue before the gate sees it -- see the note at
		# _queue_attacks_jointly's own restore for what a leftover shove does to the whiff clause.
		squad_manager.resolve_plan(squad, board, reactions, terrain)
		queued = squad_manager.queue_action(squad, pick.action)
	# ...and afterwards, because a hypothetical publishes projections onto units.
	squad_manager.resolve_plan(squad, board, reactions, terrain)
	return queued


# EVERY member's candidate list, built in one pass over the squad against ONE plan (#709).
#
# It fixes an ORDER rather than saving work. `_best_candidate_for` resolves a hypothetical per
# candidate and the joint pass restores the real plan only before it QUEUES, so a list built inside
# the member loop was built while the previous member's last REJECTED hypothetical was still
# published on the units -- and `_attack_candidates` reads projected occupancy twice over, at the
# aim (#709) and again through `gather_attack_victims` (#105). The second member was therefore not
# reading a projection at all; it was reading a plan nobody gave, and its candidates could be
# refused as whiffs against the restored board and have their keys poisoned in `refused` for the
# rest of the turn.
#
# THE ELIGIBILITY GATE LIVES HERE, and a missing entry is its whole answer -- so the two readers
# below cannot drift about who is still choosing. Rebuilt per ROUND by the caller, because
# `has_main_action_queued` changes as the round queues and the entry must go with it; within a
# round nothing is committed until the single queue, so no entry can go stale before it is used.
static func _candidates_by_member(members: Array[Unit], board: BoardContext, base_plan: ResolvedPlan,
		stakes: _Stakes = null) -> Dictionary:
	var out := {}
	for member in members:
		if not member.is_active() or member.has_main_action_queued() or not member.can_wield_equipped():
			continue
		out[member] = _attack_candidates(member, board, member.get_projected_destination(), base_plan.hypo, stakes)
	return out


# Every attack `unit` could declare from `origin`, built as REAL declared orders through
# AttackAction.declare -- the one stamp factory (#78) -- so the thing scored and the thing queued are
# the same object rather than two descriptions of one.
#
# WHERE IT AIMS (#1220): a DIRECTIONAL attack tries all four facings, aimed one step out the way the
# watch lanes are, because a facing is what the player picks -- aiming "at an enemy" asked the
# cardinal between two cells, which named the wrong facing for a spread's side lane. A POINT attack
# tries every cell of its ring, so a placed blast can be dropped beside a target rather than on it.
# An aim is kept only when its sweep pays: a hostile victim, or for a HEAL a heal target (an ally
# below full HP, or a body nobody can rescue this turn -- rulings 3 and 16). A heal is therefore
# never AIMED at an enemy; an enemy its splash catches is priced against it by the score. Aims that
# reach the same victims across the same cells are one candidate.
#
# A MAP-ONLY attack hits no unit (#1135), so its aim is kept only for what it does THIS pass: the
# current it carries, the payloads it drops, or the ice it melts under a hostile. Ground it merely
# leaves burning or soaked for later is not priced, declared on #117.
#
# The sweep reads wetness LIVE, as the queue's whiff gate does (SquadPlanValidator.aim_finds_a_target),
# so a candidate is never one the gate would refuse.
#
# ONE LIST, standing and downed alike (#720): the overkill clamp prices finishing a body at +1, so a
# body wins only when nothing upright is offered. WHAT THE PLAN HAS ALREADY KILLED IS NOT A TARGET
# (#719): planning does not execute, so a unit a squadmate felled this round is still on the live
# board, and the base plan's hypo is the honest answer. DOWNED in the hypo is still a target; DEAD is
# nobody. `victims_out`, when given, receives each candidate's paying victims.
static func _attack_candidates(unit: Unit, board: BoardContext, origin: Vector2i,
		base_hypo: Dictionary, stakes: _Stakes = null, victims_out = null) -> Array[AttackAction]:
	var out: Array[AttackAction] = []
	var seen := {}
	var hostiles := {}   # cell -> true where a hostile the plan has not killed stands
	var patients := {}   # cell -> true where a heal target stands
	for other in board.units:
		if not is_instance_valid(other):
			continue
		var at := PlanResolver.projected_position(other, base_hypo)
		if Team.is_enemy(unit.get_faction(), other.get_faction()):
			if PlanResolver.projected_lifecycle(other, base_hypo) != Unit.LifecycleState.DEAD:
				hostiles[at] = true
		elif _is_heal_target(other, base_hypo, stakes):
			patients[at] = true
	# Nothing selectable (unarmed, an aura-dry rune) means no candidate, as the player's ring offers
	# none (#1215) -- never a null pick, which the resolver would read as bare fists.
	for attack in unit.get_selectable_attacks():
		if not unit.is_attack_fireable(attack):
			continue
		var marks: Dictionary = patients if attack.heals else hostiles
		if marks.is_empty() and not _may_pay_unmarked(unit, attack):
			continue
		for aim in _aim_cells(unit, origin, attack, board, marks):
			var sweep := Conduction.sweep(unit, origin, aim, attack, board)
			var paying := _paying_victims(unit, attack, sweep, base_hypo, stakes)
			if paying.is_empty() and not _map_pays(unit, attack, sweep, board, base_hypo):
				continue
			var key := _aim_key(attack, sweep)
			if seen.has(key):
				continue
			seen[key] = true
			unit.active_attack = attack   # declare()'s stamp only (#102)
			var action := AttackAction.declare(unit, origin, aim)
			out.append(action)
			if victims_out != null:
				victims_out[action] = paying
	unit.active_attack = null   # no probe left behind (#102)
	return out


# Who a heal may be aimed for: our side, and either standing below full HP or a body the clock is
# still running on that nobody can rescue this turn (ruling 16).
static func _is_heal_target(other: Unit, hypo: Dictionary, stakes: _Stakes) -> bool:
	match PlanResolver.projected_lifecycle(other, hypo):
		Unit.LifecycleState.ACTIVE:
			return PlanResolver.projected_hp(other, hypo) < other.get_max_hp()
		Unit.LifecycleState.DOWNED:
			return other.is_downed() and other.downed_turns_remaining >= 0 \
					and (stakes == null or not stakes.rescuable.has(other))
	return false


# Can this aim pay FAR from anybody it could pay on? A payload goes off where the hit lands and a
# current runs through water; everything else pays only on a body inside its own footprint.
static func _may_pay_unmarked(unit: Unit, attack: AttackData) -> bool:
	return attack.payload != null or PlanResolver.elements_of(unit, attack, false).has(Elemental.Element.SHOCK)


# The cells worth sweeping. A facing for a directional attack; for a point attack the ring, narrowed
# to cells near a mark whenever only a body in the footprint can pay: within the shape's own reach of
# one, which is exact for a one-cell attack and a superset for a blast.
static func _aim_cells(unit: Unit, origin: Vector2i, attack: AttackData, board: BoardContext,
		marks: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if Reach.is_directional_attack(attack):
		for dir in GridUtils.CARDINAL_DIRECTIONS:
			if Reach.can_aim_at(unit, origin, origin + dir, attack, board):
				out.append(origin + dir)
		return out
	var narrow := not _may_pay_unmarked(unit, attack)
	var radius := 0
	if attack.attack_shape != null:
		for offset in attack.attack_shape.tiles():
			radius = maxi(radius, absi(offset.x) + absi(offset.y))
	var ring := Reach.get_all_attack_cells_from(unit, origin, attack)
	if narrow and radius == 0:
		# A one-cell attack pays only ON a mark, so it is aimed at the marks in board order -- the order
		# this builder always offered them in, which is what equal candidates fall back to.
		for mark: Vector2i in marks:
			if ring.has(mark) and Reach.vertical_aim_ok(attack, origin, mark, board):
				out.append(mark)
		return out
	for cell in ring:
		if narrow and not _near_a_mark(cell, marks, radius):
			continue
		# The player's vertical gate, mirrored (#258): an aim the click would refuse is never authored.
		if not Reach.vertical_aim_ok(attack, origin, cell, board):
			continue
		out.append(cell)
	return out


static func _near_a_mark(cell: Vector2i, marks: Dictionary, radius: int) -> bool:
	if radius == 0:
		return marks.has(cell)
	for mark: Vector2i in marks:
		if absi(mark.x - cell.x) + absi(mark.y - cell.y) <= radius:
			return true
	return false


# The victims that make this aim worth anything: hostiles the plan has not killed, or for a heal the
# heal targets it reaches.
static func _paying_victims(unit: Unit, attack: AttackData, sweep: Conduction.Sweep, hypo: Dictionary,
		stakes: _Stakes) -> Array[Unit]:
	var out: Array[Unit] = []
	for victim in sweep.victims:
		if not is_instance_valid(victim) or out.has(victim):
			continue
		if attack.heals:
			if not Team.is_enemy(unit.get_faction(), victim.get_faction()) and _is_heal_target(victim, hypo, stakes):
				out.append(victim)
		elif Team.is_enemy(unit.get_faction(), victim.get_faction()) \
				and PlanResolver.projected_lifecycle(victim, hypo) != Unit.LifecycleState.DEAD:
			out.append(victim)
	return out


# What a map-only aim does this pass with no victim of its own: a payload that catches a hostile, or
# a deposit that takes the ice from under one. Geometry only -- the resolve prices it.
static func _map_pays(unit: Unit, attack: AttackData, sweep: Conduction.Sweep, board: BoardContext,
		hypo: Dictionary) -> bool:
	if not attack.hits_map():
		return false
	if attack.payload != null:
		for cell in sweep.struck:
			var drop := Conduction.sweep_payload(unit, cell, attack.payload, board, hypo,
					sweep.struck_facings.get(cell, Vector2i.ZERO))
			for victim in drop.victims:
				if is_instance_valid(victim) and Team.is_enemy(unit.get_faction(), victim.get_faction()):
					return true
	var elements := PlanResolver.elements_of(unit, attack, false)
	if elements.is_empty() or board.terrain_states == null:
		return false
	var terrain := TerrainReactionCatalog.get_all()
	for cell in sweep.struck:
		var standing := board.projected_unit_at_cell(cell)
		if standing == null or not Team.is_enemy(unit.get_faction(), standing.get_faction()):
			continue
		var effect := PlanResolver._resolve_cell_effect_at(cell, elements, board, terrain)
		if effect == null:
			continue
		var deposits: Array[ResolvedCellEffect] = [effect]
		if RulesService.drowns_in(cell, standing, board.with_deposits(deposits)) \
				and not RulesService.drowns_in(cell, standing, board):
			return true
	return false


static func _aim_key(attack: AttackData, sweep: Conduction.Sweep) -> String:
	var ids: Array[int] = []
	for victim in sweep.victims:
		if is_instance_valid(victim):
			ids.append(victim.get_instance_id())
	ids.sort()
	var cells := sweep.cells.duplicate()
	cells.sort()
	return "%d|%s|%s" % [attack.get_instance_id(), str(ids), str(cells)]


# Score a whole RESOLVED PLAN -> an AIScore: (mission, removals, squad breaks, saves, damage,
# damage taken), compared lexicographically (#1220 widened it from four terms). The MARGINAL a
# candidate adds is what ranks it, and since #711 there is no bar it has to clear -- the score
# orders, it never gates.
#
# A MISSION-ENDING KILL RANKS ABOVE EVERYTHING (#1220 ruling 2): a unit the mission says must survive,
# killed by this plan while the mission's lose conditions hold PROTECTED_UNIT_LOST. Read off the hypo,
# so a downed escort finished and a standing one felled in a single blow both count. The sign is the
# PLAYER's loss, since the mission is the player's: good for anyone hostile to the player.
#
# A HEAL IS PRICED LIKE DAMAGE (ruling 3): the HP it actually restores joins the damage term for our
# side and against us on an enemy's, so overheal is worth nothing by the same arithmetic that makes
# overkill worth nothing. A heal on a BODY is a SAVE instead (ruling 16) -- it stops the clock -- and
# counts only when nobody could rescue that body this turn (stakes.rescuable), once per body, ranked
# above damage and below a squad break.
#
# A UNIT THE PASS'S OWN MELT DROWNS (#922) is a victim like any other: plan.sinks seeds the ledger,
# so the removal and the damage are priced through the ordinary rules below.
#
# A SQUAD BREAK SITS ABOVE DAMAGE AND BELOW A REMOVAL (#761, dev 2026-10-03), so a shove that knocks
# somebody out of their squad beats a harder hit that does not. Counted off SplitForecast -- the
# forecast behind the queue's Split chip, so the AI prices the settle execution runs -- per unit,
# enemy +1 and ours -1. A unit the plan also REMOVES is skipped: splits lists a downed unit's
# ejection, and the removal already paid for it.
#
# The rule is #78's, widened from one throwaway volley to the squad's whole plan, and the widening
# is what buys squad play: the plan holds every squadmate's queued swing (so a finishing blow is
# visible as one), the threaded hypo (so a soak already in the plan is priced into the shock behind
# it), and the DERIVED counters and watch shots -- which is how "counters aren't scored" closes.
#
# ONE sign rule covers all three lists: a victim hostile to `faction` counts FOR, anyone else counts
# AGAINST. That is the net-damage doctrine (dev, 2026-07-22), and it lands the derived rows
# correctly with no second clause -- an enemy AoE counter splashing its own side adds.
#
# A REACTION'S DAMAGE NEVER JOINS z -- ONLY ITS REMOVALS (dev ruling, 2026-09-02). Priced at par
# it cancels exactly: two units with the same weapon trade 3 for 3, every even exchange scores
# (0,0), and an AI facing mirror-statted enemies declines every attack and reloads instead. That is
# not caution, it is a parked squad, and it is the common matchup. So a counter that FELLS one of
# ours is a real loss and lands in x, while chip damage taken is the price of engaging.
#
# ...BUT IT IS THE TIE-BREAK w (dev, 2026-09-02, from playtest): "when all else is even, they
# should go for optimal exchanges." Sitting strictly BELOW damage dealt is what keeps it from
# reviving the parked squad -- a mirror matchup still scores (0, 0, 8, -8) and beats (0,0,0,0),
# because w only ever speaks when every higher term ties exactly. It is also what stops the ATTACK
# pick undoing the TARGET pick: once the squad has walked to the harmless target, the dangerous one
# may still be in reach from the settled cell, and without w that choice ties on damage and falls to
# board order. See choose_engagement_target for the other half.
#
# THE AI IS BLIND TO CRISIS (dev ruling, 2026-09-04, explicitly provisional): a hit the ladder
# sentences to CRISIS is priced at the damage AND the removal it would have earned if the gambit did
# not exist. His words: "the ai simply won't see crisis mode until they have to react to a unit
# currently in it." It counted as NOTHING before -- the damage was skipped here and CRISIS threads
# ACTIVE so no removal followed -- which under #711's no-bar rule is not a refusal but a LOSING
# candidate, so an armed Berserker was the last thing an AI would swing at. (#708, whose own
# "a neutral verdict means never" reading died with the bar.)
#
# Neither half needs new arithmetic. The damage is the raw pre-Crisis number (the resolver fixes
# outcome.damage before the rung is named and the Crisis branch rewrites only hp/in_crisis),
# and the overkill clamp below caps it at the HP they had going in -- which a would-be-down met by
# definition. The removal comes from _plan_removes asking PlanResolver.plan_fells.
#
# BLIND TO THE GAMBIT, SIGHTED TO WHAT IT DRAWS (dev, same day). A Crisis'd defender is still ACTIVE
# and so COUNTERS where a downed one cannot, and that counter's damage still lands in w -- so
# between two otherwise identical targets the AI prefers the one that cannot answer. Declared rather
# than accidental: blinding w too is a different edit in the reaction loop, and "it takes the
# finishing blow, even into a Crisis" is the sentence the predictability contract wants.

#
# A DOWNED VICTIM IS PRICED LIKE ANY OTHER, and the parameter that used to suppress that is gone
# (#716, dev 2026-09-03). The score used to skip damage on an already-downed enemy during pass 1,
# which erased the incidental value of an attack that catches a body on its way to a standing
# target: a general with an AoE that would hit an upright enemy AND finish a corpse scored it
# identically to one that hit only the upright enemy, and the tie fell to candidate order. Reported
# from play as the AI "playing for the wrong team". His ruling: prioritize the standing, but never
# DE-prioritize an otherwise better attack for having a body in it.
#
# THIS IS NOW THE WHOLE OF THAT PRIORITY, and the justification #716 shipped with is not -- it read
# "_attack_candidates already refuses to AIM at a body while anyone is standing, and that is the
# whole rule", which #720 deleted a day later. The rule survives its reason: what keeps a body from
# outranking somebody upright is the arithmetic below rather than a gate above it: the overkill
# clamp values finishing a body at exactly +1 damage -- enough to break a tie, never enough to
# outrank a real swing -- and _plan_removes answers false for a body, so it cannot earn a removal
# either. That +1 came from the body CLINGING at 1 HP until #1002 let a heal raise one, and the
# clamp now caps a body at 1 outright so the ruling survives the state that would have broken it.
static func _score_plan(faction: Team.Faction, plan: ResolvedPlan, stakes: _Stakes = null) -> AIScore:
	var dealt := {}   # Unit -> damage this plan lands on them, before the overkill clamp
	var restored := {}   # Unit -> HP a heal actually gave them (a standing unit; a body is a save)
	var stabilised := {}   # body -> true
	for a in plan.attacks:
		var victim: Unit = a.target
		if victim == null or a.resolved == null or not is_instance_valid(victim):
			continue
		if a.fired_attack != null and a.fired_attack.heals:
			var gained := maxi(a.resolved.target_hp_after - a.resolved.hp_before, 0)
			if not victim.is_downed():
				restored[victim] = int(restored.get(victim, 0)) + gained
			elif gained > 0 and victim.downed_turns_remaining >= 0 \
					and (stakes == null or not stakes.rescuable.has(victim)):
				stabilised[victim] = true
			continue
		dealt[victim] = int(dealt.get(victim, 0)) + a.resolved.damage
	for sink in plan.sinks:
		var drowned: Unit = sink.actor
		if drowned == null or sink.resolved == null or not is_instance_valid(drowned):
			continue
		dealt[drowned] = int(dealt.get(drowned, 0)) + sink.resolved.damage

	# The REACTIONS this plan draws -- counters and any watch shots it sets off. Their victims join
	# the removal ledger, and what they land on OUR side accumulates as the w tie-break. Damage a
	# reaction deals to an ENEMY (an AoE counter splashing its own party) is deliberately outside
	# the term rather than counted as a bonus, so w means exactly one thing: what engaging costs us.
	var taken := 0
	for a in _reaction_rows(plan):
		var victim: Unit = a.target
		if victim == null or a.resolved == null or not is_instance_valid(victim):
			continue
		if not Team.is_enemy(faction, victim.get_faction()):
			taken += a.resolved.damage
		if not dealt.has(victim):
			dealt[victim] = 0

	# OVERKILL IS WORTH NOTHING: a victim's damage is capped at the HP they had going in, so you
	# cannot get more value out of a person than taking them out of the fight. Without this the
	# removal ledger below fixes only half the double-spend -- a second member swinging at someone
	# the first already downed still banked full damage, which ties exactly with hitting an
	# untouched enemy for the same number, leaving focus-fire to be decided by board order. The cap
	# binds only on overkill, so chipping a healthy unit is unaffected. Live HP is plan-start HP.
	#
	# A BODY IS CAPPED AT 1 WHATEVER IT HOLDS (#1002, keeping #720's ruling literal). That "+1" was
	# never a constant -- it is this clamp, worth 1 only because a body clung at 1 HP -- so once a
	# heal can leave one at 15 the same arithmetic prices finishing it above chipping a standing
	# enemy, which is exactly the head-to-head the dev ruled a body must lose. Asked of the LIVE
	# board like the clamp it belongs to: a body the PLAN fells is a removal, not this.
	var net := 0
	for victim: Unit in dealt:
		var cap: int = 1 if victim.is_downed() else maxi(victim.get_current_hp(), 0)
		var counted: int = mini(int(dealt[victim]), cap)
		net += counted if Team.is_enemy(faction, victim.get_faction()) else -counted
	for patient: Unit in restored:
		var gained: int = restored[patient]
		net += -gained if Team.is_enemy(faction, patient.get_faction()) else gained
	var saves := 0
	for body: Unit in stabilised:
		saves += -1 if Team.is_enemy(faction, body.get_faction()) else 1

	# A REMOVAL IS PER VICTIM, NOT PER HIT, and that is the whole of squad focus-fire. Counting the
	# lethality rung of each row instead double-pays: the ladder answers KILLED on a body once the
	# damage MEETS its HP (LethalityRules.predict), and a body the plan just felled clings at 1, so a
	# second member swinging at someone the first already downed scored a fresh removal and the two
	# happily overkilled one target while a second enemy went untouched. Asked as a CHANGE OF STANDING -- on its feet before the plan,
	# off them after -- so it is the plan's effect on a person, which is what a removal means.
	var removals := 0
	for victim: Unit in dealt:
		if not _plan_removes(victim, plan):
			continue
		removals += 1 if Team.is_enemy(faction, victim.get_faction()) else -1

	var splits := 0
	for unit: Unit in SplitForecast.leavers(plan):
		if _plan_removes(unit, plan):
			continue
		splits += 1 if Team.is_enemy(faction, unit.get_faction()) else -1

	var mission := 0
	if stakes != null and stakes.protected_counts:
		for victim: Unit in dealt:
			if victim.must_survive and not victim.is_dead() \
					and PlanResolver.projected_lifecycle(victim, plan.hypo) == Unit.LifecycleState.DEAD:
				mission += 1 if Team.is_enemy(faction, Team.Faction.PLAYER) else -1
	return AIScore.of(mission, removals, splits, saves, net, taken)


# The DERIVED rows: counters the plan drew, plus any watch shots it set off. Deliberately NOT
# ResolvedPlan.attacks_for_playback() -- that splices the shots into `attacks` for the ANIMATOR, so
# reading both lists would count every shot twice.
static func _reaction_rows(plan: ResolvedPlan) -> Array[AttackAction]:
	var rows: Array[AttackAction] = []
	for c in plan.counters:
		rows.append(c)
	rows.append_array(plan.watch_shots)
	return rows


# Does this plan take `victim` off its feet? Standing now (the live board IS plan-start) and not
# standing once the plan resolves. A CRISIS prediction lands ACTIVE, so the gambit falls out here
# too rather than needing a clause of its own.
static func _plan_removes(victim: Unit, plan: ResolvedPlan) -> bool:
	if not victim.is_active():
		return false
	return PlanResolver.plan_fells(victim, plan.hypo)


# What a squad's scoring knows beyond the plan itself (#1220), built once per squad decision: whether
# the mission ends on a protected unit's death, and which bodies a squadmate could rescue this turn
# (a heal on one of those saves nothing). Null scores a plan with neither -- a sandbox board.
class _Stakes:
	var protected_counts := false
	var rescuable := {}   # body -> true


static func _stakes_for(squad: Squad, board: BoardContext, plan: ResolvedPlan) -> _Stakes:
	var out := _Stakes.new()
	out.protected_counts = board.mission != null \
			and board.mission.lose_conditions.has(MissionRules.LoseCondition.PROTECTED_UNIT_LOST)
	if squad == null or not AIArchetype.main_action_priority(squad.archetype).has(BaseAction.ActionType.RESCUE):
		return out
	for member in squad.get_members():
		if not member.is_active() or not member.can_rescue_carry():
			continue
		for body in RulesService.adjacent_downed_allies(member, board, plan):
			out.rescuable[body] = true
	return out


# Does this candidate's own work fell somebody on our side (#1220 ruling 1: the AI never fells its
# own)? Its own rows are the volley it derived and any unit its deposits drowned; a COUNTER it draws is
# not its work, so "a free finish beats a suicidal swing" stands. Measured against `base` -- the plan
# without it -- so a squadmate a counter was already going to fell is not laid at this candidate's
# door. A predicted CRISIS counts as the fall it would have been: the AI is blind to the gambit.
static func _fells_own(aims: Array, faction: Team.Faction, base: ResolvedPlan, plan: ResolvedPlan) -> bool:
	for a in plan.attacks:
		if not aims.has(a.source_aim) or a.resolved == null:
			continue
		if _newly_felled(a.target, faction, base, plan) \
				or (a.resolved.lethality == ResolvedOutcome.Lethality.CRISIS and _own_side(a.target, faction)):
			return true
	for sink in plan.sinks:
		if sink.cause == null or not (aims.has(sink.cause) or aims.has(sink.cause.source_aim)):
			continue
		if _newly_felled(sink.actor, faction, base, plan):
			return true
	return false


static func _own_side(unit: Unit, faction: Team.Faction) -> bool:
	return unit != null and is_instance_valid(unit) and not Team.is_enemy(faction, unit.get_faction())


static func _newly_felled(unit: Unit, faction: Team.Faction, base: ResolvedPlan, plan: ResolvedPlan) -> bool:
	if not _own_side(unit, faction):
		return false
	return PlanResolver.projected_lifecycle(unit, plan.hypo) > PlanResolver.projected_lifecycle(unit, base.hypo)

# Fallback builders -- each mirrors MainActionMenu's gate for its verb, then picks a
# deterministic target (Law #1: explicit tie-break, first-in-order wins).

# How soon a body is lost, lowest first. A body a heal STABILISED has no clock (#1002), and the
# stored -1 read as a number is the most urgent value there is — so it sorts past every real clock
# instead of ahead of an ally two turns from death.
static func _rescue_urgency(body: Unit) -> int:
	if body.downed_turns_remaining < 0:
		return Unit.DOWNED_TURNS + 1
	return body.downed_turns_remaining


# A body the squad's own pass is about to make counts (#1220): asked of the plan as it stands, so a
# squadmate a counter fells this pass is rescued in the same pass -- the player's rule (#124).
static func _try_rescue(unit: Unit, board: BoardContext, squad_manager: SquadManager) -> bool:
	if not unit.can_rescue_carry():
		return false
	var target: Unit = null
	var plan := squad_manager.resolve_plan(unit.squad, board)
	for ally in RulesService.adjacent_downed_allies(unit, board, plan):
		if target == null or _rescue_urgency(ally) < _rescue_urgency(target):
			target = ally   # most urgent clock first; ties keep the earliest
	if target == null:
		return false
	# The AI has no tile pick, so it takes the FIRST landing -- which is exactly the answer the rule
	# gave everyone before the player was handed the choice (#116), NEIGHBOURS declaration order.
	# Non-empty by construction: adjacent_downed_allies already refuses a body with no landing.
	var landings := RulesService.rescue_landings(unit, target, board)
	var rescue := RescueAction.new()
	rescue.init(unit, target, landings[0])
	return squad_manager.queue_action(unit.squad, rescue)

static func _try_reload(unit: Unit, squad_manager: SquadManager) -> bool:
	if not unit.can_reload_weapon():
		return false
	var action := ReloadAction.new()
	action.init(unit)
	return squad_manager.queue_action(unit.squad, action)

static func _try_rev(unit: Unit, squad_manager: SquadManager) -> bool:
	if not unit.can_rev_weapon():
		return false
	var action := RevAction.new()
	action.init(unit)
	return squad_manager.queue_action(unit.squad, action)

# Burrow (#726): the rev pair's shape once more. WHETHER it is worth digging here is the Drill's
# own call (DrillWeaponRoutine), asked by queue_main_action before this builder runs.
static func _try_burrow(unit: Unit, squad_manager: SquadManager) -> bool:
	if not unit.can_burrow_weapon():
		return false
	var action := BurrowAction.new()
	action.init(unit)
	return squad_manager.queue_action(unit.squad, action)

# Overwatch (#751): AIM the attack instead of firing it, down the way an enemy would come.
#
# A PREPARATION, so it is a RULE and never a score term (#726's doctrine, second application). It
# sits below ATTACK for the same reason REV does: no preemption.
#
# Its reason USED to be that the shot lands on somebody else's turn, which `_score_plan`
# structurally cannot reach. #1003 made that false -- a watch armed onto a cell an enemy already
# occupies fires in this pass -- and the rule stands anyway, on the doctrine's other half: a
# preparation is a legible sentence, and the predictability contract prefers one to a score term.
# What the change is worth knowing for is that `_watch_aim` floods FROM the enemy's own cell, so a
# lane containing it scores zero hops and wins -- the AI already prefers aiming where the enemy is
# standing, and that aim is now a shot. ATTACK sitting above this keeps it rare ONLY where the two
# cover the same cells, which since #590 they need not: the Carbine's Shot is range exactly 2 and its
# watch lane runs 1 to 4, so the watch is that unit's shot at 1, 3 and 4 (#1197; whether it should
# be is #752's). ThreatField draws these lanes for that reason.
#
# THE AIM MUST BE ACTIVE-ONLY, and this is #720's pathology one door over. `nearest_enemy` ranks a
# BODY as an ordinary target, but `PlanResolver._watch_triggered_by` refuses a non-ACTIVE entrant and
# a corpse never moves -- so a watcher beside a downed enemy would aim at its "approach" every quiet
# turn for the rest of the battle, watching something that can never arrive.
#
# ON THE BOARD THE SQUAD'S PLAN LEAVES (#1209). This runs after the squad's attacks are queued, so the
# live board is the wrong one: an enemy a squadmate fells is no target, and one a squadmate shoves
# comes from where it lands. Every unit is stood on its planned cell for the decision (#710's
# snapshot) and put back before the queue, which must never see a teleported board.
static func _try_overwatch(unit: Unit, board: BoardContext, squad_manager: SquadManager) -> bool:
	var attack := watch_attack_for(unit)
	if attack == null:
		return false
	var origin := unit.get_projected_destination()   # the fallback walk runs AFTER the group move is queued
	var plan := squad_manager.resolve_plan(unit.squad, board)
	var saved := AIController.stand_on_projected(squad_manager)
	var aim := origin
	var enemy := nearest_enemy(unit, board, null, true, plan.hypo)
	if enemy != null:
		aim = _watch_aim(unit, origin, attack, enemy, board)
	AIController.restore_cells(saved)
	if aim == origin:
		return false   # nobody left to watch for, or no facing covers a cell the enemy can reach -- see _watch_aim
	var action := OverwatchAction.new()
	action.init(unit, aim, attack)
	return squad_manager.queue_action(unit.squad, action)


# The attack this unit would watch with right now, or null. One watch per weapon (dev, 2026-08-26),
# so the first is the deterministic pick; and the menu's own gate, so a dry Carbine cannot watch
# either -- Overwatch requires readiness. ThreatField asks this too (#1197), so the lanes it draws
# are the lanes this builder could arm.
static func watch_attack_for(unit: Unit) -> AttackData:
	var watchable := unit.overwatch_attacks()
	if watchable.is_empty():
		return null
	var attack: AttackData = watchable[0]
	if unit.attack_block_reason(attack) != "":
		return null
	return attack


# The cells each facing's watch would cover from `origin` (dir -> cells), truncation included
# (#756). A facing that covers nothing is absent. _watch_aim ranks these; ThreatField unions them.
static func watch_lanes(unit: Unit, origin: Vector2i, attack: AttackData, board: BoardContext) -> Dictionary:
	var lanes := {}
	for dir in GridUtils.CARDINAL_DIRECTIONS:
		var cells := Reach.get_affected_cells_from(unit, origin, origin + dir, attack, board)
		if not cells.is_empty():
			lanes[dir] = cells
	return lanes


# Which cell to aim the watch at -- a FACING for a directional attack (Overwatch.tres is
# self-anchored, max range 0), the cell itself for a point one. The return is always `origin + dir`, and
# stays adjacent: OverwatchAction re-derives the facing from it and the queue row names it.
#
# RANKED OVER THE WHOLE FOOTPRINT, never the cell in front (#769). A watch fires when an enemy
# enters ANY cell it covers, so that is what the route question has to be asked about: fewest hops
# to any cell of the lane the enemy can reach, then the MOST such cells, then CARDINAL_DIRECTIONS
# order (Law #1). Reading `origin + dir` alone was #127's shape a third time -- a metric measuring
# one cell of the thing it ranks -- and it cost three answers. A lane #756 had truncated to a stub
# tied with a whole one. A facing whose near cell was merely OCCUPIED was refused outright, and the
# walk ran from THE ENEMY'S side with occupancy on, so the blocker was usually the watcher's own
# squadmate. And on a diagonal approach every facing tied at its near cell and fell through to
# cardinal order -- watching north while the enemy walked in from the east.
#
# THE APPROACH FIELD SEES THROUGH BODIES (#946), which is the whole-field form of that second
# answer and survived it. #769 made an occupied NEAR CELL cost one cell instead of a facing; a body
# on a CHOKEPOINT still sealed the map, and the report was four archers aiming into a fence because
# three of their own squadmates were standing in the board's only ford two hundred cells away. It is
# `can_traverse`'s own doctrine -- "an enemy body blocks a MOVE but is not a terrain fact and moves
# every turn; a connectivity field must see through it" -- and the tense makes it sharper here than
# anywhere: a watch stands until the watcher's faction's NEXT turn, so every body this flood would
# refuse to see through has moved before the watch can possibly fire.
#
# The coverage term only ever breaks a tie, which is why the answer barely moves: wherever the old
# read produced one, the minimum sat on the near cell and still does.
#
# ONE HOP FIELD, hoisted -- all four facings ask the same source, so this was four floods that each
# had to reach the watcher's neighbourhood anyway. `until` stops early only once EVERY cell in it
# has a distance, and a lane routinely holds one that never will (off the map, since truncation asks
# elevation and the trace but never bounds; or a wall the shot may hit and nobody may stand on), so
# the hoisted call floods the component. That is the tie-break's price and the lever if it ever
# bites -- `nearest_enemy` one frame up already floods the same class, so this path was never
# flood-free.
#
# A DUD AIM MUST NEVER BE QUEUED. A self-anchored `Reach.get_attack_cells_from` answers empty
# for a hint that yields no cardinal direction, and from there the failure is entirely silent -- the resolver
# arms nothing, `Unit.arm_watch` refuses on an empty footprint, and no queue gate looks at an
# OverwatchAction at all, so the unit would spend its main action on air behind a legal-looking row.
# Returning `origin` is this function's way of saying "no facing works", and the caller refuses.
#
# A sealed board falls back to simply facing the enemy, reusing GridUtils' own diagonal tie-break
# rather than inventing a second. That hatch NARROWED without being touched: it used to open when no
# near cell was reachable, and now waits until no lane cell is. **AND IT MAY NOT AIM AT A WALL**
# (#946): its only dud-guard was a non-empty lane, and a lane truncated to the one cell of fence
# beside the shooter is not empty. The ranked pass gets that test for free -- `path_hops` cannot put
# an untraversable cell in the field, so such a facing already scores `covered == 0` -- and the
# fallback, which consults no field, has to ask it out loud. Reading the lane out of `footprints`
# rather than re-deriving it is the same edit: the geometry was being computed twice.
#
# WHO STANDS IN THE LANE IS NOT ASKED (dev, 2026-09-05: "the overwatch is an attack"). An
# ally-hitting watch shoots its own squad, and that is the attack behaving as authored.
static func _watch_aim(unit: Unit, origin: Vector2i, attack: AttackData, enemy: Unit, board: BoardContext) -> Vector2i:
	var footprints := watch_lanes(unit, origin, attack, board)
	var wanted := {}       # their union, and the hop field's `until`
	for dir in footprints:
		for cell: Vector2i in footprints[dir]:
			wanted[cell] = true
	if footprints.is_empty():
		return origin

	var field := RulesService.path_hops(enemy.movement.cell, board, enemy, -1, wanted, false)
	var best := origin
	var best_hops := -1
	var best_covered := 0
	for dir in GridUtils.CARDINAL_DIRECTIONS:
		if not footprints.has(dir):
			continue
		var lane: Array[Vector2i] = footprints[dir]
		var hops := -1
		var covered := 0
		for cell in lane:
			if not field.has(cell):
				continue
			covered += 1
			var d: int = field[cell]
			if hops < 0 or d < hops:
				hops = d
		if covered == 0:
			continue   # nothing this facing covers is somewhere the enemy can get to
		if best_hops < 0 or hops < best_hops or (hops == best_hops and covered > best_covered):
			best = origin + dir
			best_hops = hops
			best_covered = covered
	if best_hops >= 0:
		return best
	var facing := GridUtils.cardinal_direction_i_between(origin, enemy.movement.cell)
	if facing != Vector2i.ZERO and footprints.has(facing):
		var toward: Array[Vector2i] = footprints[facing]
		if _lane_can_be_entered(toward, enemy, board):
			return origin + facing
	return origin


# Can anything ever ENTER this lane? A watch fires when an ACTIVE enemy MOVES INTO a cell it covers,
# so a lane of cells nobody may stand on can never fire however it is pointed -- the fence beside the
# shooter is a legal thing to shoot AT and not a legal thing to watch. Asked of the ENEMY rather than
# of the cell, because that is the traversal rule the hop field above uses, so the fallback and the
# ranked pass cannot disagree about what counts as a cell somebody can reach -- and a lake an enemy
# Waterwalker crosses is a lane worth watching that `BoardContext.is_walkable` would have refused.
static func _lane_can_be_entered(lane: Array[Vector2i], enemy: Unit, board: BoardContext) -> bool:
	for cell in lane:
		if RulesService.can_traverse(cell, enemy, board):
			return true
	return false


# Guard (#751): ward the ally the most enemies can reach. The other preparation whose payoff lands on
# somebody else's turn, so it is a rule for the same reason Overwatch is.
#
# ZERO EXPOSURE REFUSES. "Shields whoever is most exposed" presumes exposure above zero -- without
# the refusal a Guard would spend the action on a purposeless ward whenever any ally happened to
# be standing beside it.
#
# A DOWNED ally is in `guard_candidates` by design, but RESCUE sits above GUARD in the walk and
# rescue adjacency IS the guard range, so a body is normally carried before this is asked.
#
# Ties keep guard_candidates' own order (Law #1), which walks cells_within_manhattan_range.
#
# Exposure is counted on the board the squad's plan leaves (#1209), _try_overwatch's reason: an enemy a
# squadmate fells this turn reaches nobody, and one it shoves reaches from where it lands.
static func _try_guard(unit: Unit, board: BoardContext, squad_manager: SquadManager) -> bool:
	var candidates := RulesService.guard_candidates(unit, board)
	if candidates.is_empty():
		return false
	var plan := squad_manager.resolve_plan(unit.squad, board)
	var saved := AIController.stand_on_projected(squad_manager)
	var exposure := _exposure_counts(candidates, board, unit.get_faction(), plan.hypo)
	AIController.restore_cells(saved)
	var ward: Unit = null
	var most := 0
	for ally in candidates:
		var count: int = int(exposure.get(ally, 0))
		if count > most:
			most = count
			ward = ally
	if ward == null:
		return false
	var action := GuardAction.new()
	action.init(unit, ward)
	return squad_manager.queue_action(unit.squad, action)


# How many enemies could reach AND hit each of these allies -- one move-range search per enemy,
# reused across every candidate, rather than one per pair.
#
# DECLARED APPROXIMATION, inherited from the seam this composes: the search honours the enemy's own
# cohesion leash, so an enemy that could only reach the ally by breaking formation does not count.
# Occupancy is whatever board the caller stood up -- _try_guard's is the plan's (#1209). The cost is
# one search per enemy left ACTIVE by `hypo`, paid only once a unit has reached GUARD in the walk --
# second to last, so after every other verb has declined.
static func _exposure_counts(allies: Array[Unit], board: BoardContext, faction: Team.Faction,
		hypo: Dictionary = {}) -> Dictionary:
	var counts := {}
	for other in board.units:
		if not PlanResolver.actor_is_live(other, hypo):
			continue
		if not Team.is_enemy(faction, other.get_faction()):
			continue
		if other.get_selectable_attacks().is_empty():
			continue   # it can fire nothing, so it threatens nobody (#1215)
		var walk: Dictionary = RulesService.compute_move_range(other, board)
		var reachable: Dictionary = walk["reachable"]
		var aiming := other.get_fired_attack()
		for ally in allies:
			var firing := _standable_attack_cells(other, ally.get_projected_destination(), aiming, board)
			for cell in firing:
				if cell == other.movement.cell or reachable.has(cell):
					counts[ally] = int(counts.get(ally, 0)) + 1
					break
	return counts


# Where the leader should stand to fight `enemy`: a cell it can already attack from, else the cell
# furthest along the ROUTE to it. The route targets the nearest STANDABLE firing position, not
# enemy.movement.cell itself (#127) -- see _nearest_standable_attack_cell for why that distinction
# is load-bearing. Only cells its squad can follow it to (#1220).
static func best_attack_destination(leader: Unit, enemy: Unit, board: BoardContext, allowed = null) -> Vector2i:
	var aiming := leader.get_fired_attack()
	var route_target := _nearest_standable_attack_cell(leader, enemy.movement.cell, aiming, board)
	return _best_approach(leader, enemy.movement.cell, board, _leader_allowed(leader, board, allowed), true, route_target)


# The leader cells a squad can follow to, as `allowed` narrowed by them; `allowed` itself for a squad
# of one, which can stand anywhere its leader can.
static func _leader_allowed(leader: Unit, board: BoardContext, allowed):
	var follow = _followable(leader.squad, board)
	if follow == null:
		return allowed
	if allowed == null:
		return follow
	var both := {}
	for cell: Vector2i in follow:
		if allowed.has(cell):
			both[cell] = true
	return both


# GroupMoveSolver.followable_destinations over the leader's whole range, plus where it stands -- asked
# ONCE per squad decision and shared by the engagement pick, the approach and the seek, since it is
# a sweep per member. Kept for the board it was asked on and the cells the squad stood on; a squad of
# one answers null.
static var _follow_key := ""
static var _follow_cells := {}


static func _followable(squad: Squad, board: BoardContext):
	if squad == null or squad.get_members().size() <= 1:
		return null
	var leader := squad.get_leader()
	var key := "%d|%d" % [squad.get_instance_id(), board.get_instance_id()]
	for member in squad.get_members():
		key += "|%s" % [member.movement.cell]
	if key != _follow_key:
		var cells: Array = RulesService.compute_move_range(leader, board).reachable.keys()
		cells.append(leader.movement.cell)
		_follow_cells = GroupMoveSolver.followable_destinations(squad, board, cells)
		_follow_cells[leader.movement.cell] = true
		_follow_key = key
	return _follow_cells


# Fights `target`: destination pick -> the seek -> conditional group move -> every member tries a
# main action. The shared shape behind Rushdown's whole turn and Sentry's intruder branch -- was
# hand-duplicated in both files with no third caller (AI generalization sweep, finding #2).
# `within` is a Sentry's zone: the seek only goes looking for an intruder.
static func engage(squad: Squad, target: Unit, board: BoardContext, squad_manager: SquadManager, allowed = null,
		within = null) -> void:
	var leader := squad.get_leader()
	var seek := seek_positions(squad, best_attack_destination(leader, target, board, allowed), board,
			squad_manager, allowed, within)
	if seek.destination != leader.movement.cell or not seek.pins.is_empty():
		squad_manager.queue_group_move(squad, seek.destination, board, allowed, seek.pins)
	queue_main_actions_for_squad(squad, board, squad_manager)


# WHERE THE SQUAD STANDS TO TAKE A REMOVAL OR A SQUAD BREAK it can reach this turn (#760; dev rulings
# 2026-10-03, on the issue). Only those two -- the terms the score ranks above damage -- pull anyone
# off the cell the approach and the formation would give them, so all other positioning is today's.
#
# THE SQUAD IS ONE UNIT, and the priority is the search order: the leader first (its cell decides
# everyone's cohesion), then in rounds the CLOSEST member that can do something, each scored against
# what the earlier ones will already do. A unit's own default cell is asked first and the first
# removal ends its search; a squad break is only kept while a removal is still being looked for.
#
# A CELL IS SCORED BY STANDING THERE -- the positional snapshot the threat preview opens, through the
# same teleport door -- and it is the only way: the resolve re-expands every aim from its ACTOR's
# projected cell (#15), not from the origin the aim was declared with, so an aim "from" a cell its
# actor is not on resolves as nothing. With the queue empty a unit set on a cell projects to it, so
# the volley, the counters and the lethality all read the cell it would really fire from. Every cell
# is put back and the real plan re-resolved before anything is queued. The attack itself is still
# the joint pass's to choose; this decides only where people stand.
class SeekResult:
	var destination: Vector2i
	var pins := {}   # Unit -> cell, for GroupMoveSolver.plan


# What a seeker found, best first: ending the mission (#1220), a removal, a squad break.
enum Tier { BREAK, REMOVAL, MISSION }


class _Opportunity:
	var unit: Unit
	var cell: Vector2i
	var cost: int
	var action: AttackAction
	var tier: Tier


static func seek_positions(squad: Squad, default_destination: Vector2i, board: BoardContext,
		squad_manager: SquadManager, allowed = null, within = null) -> SeekResult:
	var out := SeekResult.new()
	out.destination = default_destination
	var leader := squad.get_leader()
	# Honest only with nothing queued: a queued move would out-project the cell the unit is set on.
	if leader == null or not squad.action_queue.is_empty():
		return out
	var reactions := ReactionCatalog.get_all()
	var terrain := TerrainReactionCatalog.get_all()
	var live := {}
	for member in squad.get_members():
		live[member] = member.movement.cell
	var wins: Array[BaseAction] = []
	var stakes := _stakes_for(null, board, null)

	if _can_seek(leader):
		var lead := _first_opportunity(leader, _leader_cells(squad, leader, default_destination, board, allowed),
				squad, board, squad_manager, wins, within, reactions, terrain, stakes)
		if lead != null:
			out.destination = lead.cell
			wins.append(lead.action)

	var waiting: Array[Unit] = []
	for member in squad.get_members():
		if member != leader and _can_seek(member):
			waiting.append(member)
	while not waiting.is_empty():
		AIController.restore_cells(live)
		var placed := _formation(squad, out.destination, board, allowed, out.pins)
		var options := {}
		for member in waiting:
			options[member] = _member_cells(squad, member, out.destination, board, allowed, out.pins, placed)
		_stand(squad, leader, out.destination, placed)
		var best: _Opportunity = null
		for member in waiting:
			var found := _first_opportunity(member, options[member], squad, board, squad_manager, wins, within,
					reactions, terrain, stakes)
			if found != null and (best == null or _opportunity_beats(found, best)):
				best = found
		if best == null:
			break
		out.pins[best.unit] = best.cell
		wins.append(best.action)
		waiting.erase(best.unit)

	AIController.restore_cells(live)
	squad_manager.resolve_plan(squad, board, reactions, terrain)
	return out


static func _can_seek(unit: Unit) -> bool:
	return unit.is_active() and unit.can_wield_equipped()


# The higher tier wins; then the closest -- the cheaper move -- does it; ties keep member order.
static func _opportunity_beats(a: _Opportunity, b: _Opportunity) -> bool:
	if a.tier != b.tier:
		return a.tier > b.tier
	return a.cost < b.cost


# The leader's cells in search order, as [cell, cost] pairs: the default destination, then cheapest,
# then row-major. Only cells its squad can follow it to, inside the leash, and nobody else's.
static func _leader_cells(squad: Squad, leader: Unit, default_destination: Vector2i, board: BoardContext,
		allowed) -> Array:
	var costs: Dictionary = RulesService.compute_move_range(leader, board).reachable.duplicate()
	costs[leader.movement.cell] = 0
	var cells: Array = []
	for cell: Vector2i in costs:
		if allowed != null and not allowed.has(cell):
			continue
		var occupant := board.unit_at_cell(cell)
		if occupant != null and occupant != leader:
			continue
		cells.append(cell)
	var followable = _followable(squad, board)
	if followable != null:
		cells = cells.filter(func(c: Vector2i) -> bool: return followable.has(c))
	return _search_order(cells, costs, default_destination)


# A member's cells for this leader destination, as [cell, cost] pairs: its formation cell first, then
# cheapest. Never the leader's cell, a pinned cell or another member's formation cell.
static func _member_cells(squad: Squad, member: Unit, leader_destination: Vector2i, board: BoardContext,
		allowed, pins: Dictionary, placed: Dictionary) -> Array:
	var costs := GroupMoveSolver.follow_cells(squad, member, leader_destination, board, allowed)
	var held := { leader_destination: true }
	for other: Unit in placed:
		if other != member:
			held[placed[other]] = true
	var cells: Array = []
	for cell: Vector2i in costs:
		if not held.has(cell):
			cells.append(cell)
	return _search_order(cells, costs, placed.get(member, member.movement.cell))


static func _search_order(cells: Array, costs: Dictionary, first: Vector2i) -> Array:
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if (a == first) != (b == first):
			return a == first
		var ca: int = costs.get(a, 0)
		var cb: int = costs.get(b, 0)
		if ca != cb:
			return ca < cb
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out: Array = []
	for cell: Vector2i in cells:
		out.append([cell, int(costs.get(cell, 0))])
	return out


# Where everyone else ends for this leader destination: the solver's placements (pins included), and
# a member it moves nowhere stays where it stands. Asked on the LIVE board -- the solver walks from
# where members really are.
static func _formation(squad: Squad, leader_destination: Vector2i, board: BoardContext, allowed,
		pins: Dictionary) -> Dictionary:
	var placed := {}
	for member in squad.get_members():
		placed[member] = member.movement.cell
	for move in GroupMoveSolver.plan(squad, leader_destination, board, allowed, pins):
		placed[move.actor] = move.destination
	placed[squad.get_leader()] = leader_destination
	return placed


static func _stand(squad: Squad, leader: Unit, leader_destination: Vector2i, placed: Dictionary) -> void:
	for member in squad.get_members():
		member.movement.set_cell(placed.get(member, member.movement.cell))
	leader.movement.set_cell(leader_destination)


# The first cell in `cells` from which `unit` ends the mission, else the first that takes a removal,
# else the first that breaks a squad. The mission tier is looked for only while the mission can end
# on a kill -- otherwise a removal ends the search as it always has. Each cell is scored by standing
# there, as a marginal over what `wins` already does; `unit` is put back where it started. A
# candidate that would fell our own side is never an opportunity (#1220 ruling 1).
#
# One resolve stands for a GROUP of cells: see _group_key. A group whose first resolve shows its
# single victim neither removed nor broken is skipped from then on, since every cell in it hands that
# victim the same fate. A good fate that still nets a loss -- a counter fells us -- tries the next
# cell, because counters are the one thing that differs inside a group.
static func _first_opportunity(unit: Unit, cells: Array, squad: Squad, board: BoardContext,
		squad_manager: SquadManager, wins: Array[BaseAction], within,
		reactions: Array[ElementalReaction], terrain: Array[TerrainReaction], stakes: _Stakes) -> _Opportunity:
	var start := unit.movement.cell
	var faction := unit.get_faction()
	var base_plan := squad_manager.resolve_hypothetical(squad, wins, board, reactions, terrain)
	var stale := false
	var dead := {}
	var top: Tier = Tier.MISSION if stakes.protected_counts else Tier.REMOVAL
	var found: _Opportunity = null
	for entry: Array in cells:
		var cell: Vector2i = entry[0]
		unit.movement.set_cell(cell)
		# A trial leaves its shove PUBLISHED, and the candidate builder reads published positions
		# (#709), so the base goes back before the next cell's candidates are built. With earlier
		# seekers' attacks in it, the base is re-read anyway: standing here can make this unit their
		# counter target, or the cell one of their shoves lands on.
		if stale or not wins.is_empty():
			base_plan = squad_manager.resolve_hypothetical(squad, wins, board, reactions, terrain)
			stale = false
		var paying := {}
		var candidates := _attack_candidates(unit, board, cell, base_plan.hypo, stakes, paying)
		if candidates.is_empty():
			continue
		var base := _score_plan(faction, base_plan, stakes)
		for candidate in candidates:
			if within != null and not _reaches_into(paying.get(candidate, []), within, base_plan.hypo):
				continue
			var key := _group_key(candidate, board)
			if dead.has(key):
				continue
			var trial: Array[BaseAction] = wins.duplicate()
			trial.append(candidate)
			var plan := squad_manager.resolve_hypothetical(squad, trial, board, reactions, terrain)
			stale = true
			if _fells_own([candidate], faction, base_plan, plan):
				continue
			var tier := _tier_of(_score_plan(faction, plan, stakes).minus(base))
			if tier < 0:
				if not _fate_can_pay(candidate, plan):
					dead[key] = true
				continue
			if found == null or tier > found.tier:
				found = _opportunity(unit, cell, int(entry[1]), candidate, tier as Tier)
			if found.tier == top:
				break
		if found != null and found.tier == top:
			break
	unit.movement.set_cell(start)
	return found


# A Sentry seeks only an intruder: does this candidate pay on somebody standing inside its zone?
static func _reaches_into(victims: Array, within, hypo: Dictionary) -> bool:
	for victim: Unit in victims:
		if within.has(PlanResolver.projected_position(victim, hypo)):
			return true
	return false


# Which seek tier a marginal reaches, or -1 when it reaches none. A removal or a mission win that a
# loss elsewhere in the same plan cancels (a counter fells us) is not one.
static func _tier_of(score: AIScore) -> int:
	if score.mission > 0:
		return Tier.MISSION
	if score.mission < 0:
		return -1
	if score.removals > 0:
		return Tier.REMOVAL
	if score.removals == 0 and score.splits > 0:
		return Tier.BREAK
	return -1


static func _opportunity(unit: Unit, cell: Vector2i, cost: int, action: AttackAction, tier: Tier) -> _Opportunity:
	var out := _Opportunity.new()
	out.unit = unit
	out.cell = cell
	out.cost = cost
	out.action = action
	out.tier = tier
	return out


# Cells that hand a candidate's victim the same fate share a key. What the resolver reads off an
# attacker's cell is exactly three things -- the shove direction, the height, and a carving's
# empowerment -- so those, plus the attack and the aim, are the key. A DIRECTIONAL attack's footprint
# moves with the origin, so its cell joins the key outright. A rule that ever reads more of the origin
# (backstrike) has to join it here, or the seek skips a real opportunity without a word.
static func _group_key(candidate: AttackAction, board: BoardContext) -> String:
	var attack := candidate.fired_attack
	var origin := candidate.origin_cell
	var empowered := ""
	if attack is TransmutationData:
		empowered = str(Materia.empowered_at(origin, board))
	var anchor := str(origin) if Reach.is_directional_attack(attack) else ""
	return "%d|%s|%s|%d|%s|%s" % [attack.get_instance_id() if attack != null else 0, candidate.target_cell,
			GridUtils.cardinal_direction_i_between(origin, candidate.target_cell), board.elevation_at(origin),
			empowered, anchor]


# Could another cell of this candidate's group still pay? Only a single-victim volley is shareable --
# a wider one's other victims are shoved in directions the key does not pin -- and then only if that
# victim was removed or knocked out of its squad here.
static func _fate_can_pay(candidate: AttackAction, plan: ResolvedPlan) -> bool:
	var victims: Array[Unit] = []
	for a in plan.attacks:
		if a.source_aim == candidate and a.target != null and is_instance_valid(a.target) and not victims.has(a.target):
			victims.append(a.target)
	if victims.size() != 1:
		return true
	return _plan_removes(victims[0], plan) or SplitForecast.leavers(plan).has(victims[0])


# Every member takes a main action. The tail of engage() and the whole of HoldArchetype's turn --
# and, since finding #3, Rushdown's no-target branch too.
#
# TWO PASSES, and the split is the point (#117). ATTACK is decided for the squad JOINTLY, because
# an attack's worth depends on what the rest of the squad is already doing; the remaining verbs
# stay the ratified per-unit priority walk (dev, 2026-07-22 -- rescue/reload/rev are a
# lexical order, not a score). The fallback list therefore has ATTACK REMOVED: leaving it in would
# let a member the joint pass deliberately declined re-decide alone and undo that judgement.
static func queue_main_actions_for_squad(squad: Squad, board: BoardContext, squad_manager: SquadManager) -> void:
	var priority: Array = AIArchetype.main_action_priority(squad.archetype)
	if priority.has(BaseAction.ActionType.ATTACK):
		_queue_attacks_jointly(squad, board, squad_manager)
	queue_fallback_actions_for_squad(squad, board, squad_manager)


# The second pass alone: every member walks the archetype's list with ATTACK removed. Also the
# whole of a Sentry's turn AT ITS POST with nobody in the zone (#726, dev 2026-09-03) -- a drill
# digs in, a chainsword revs, a carbine tops off, and nobody swings at bait outside the zone.
static func queue_fallback_actions_for_squad(squad: Squad, board: BoardContext, squad_manager: SquadManager) -> void:
	var fallback: Array = AIArchetype.main_action_priority(squad.archetype).duplicate()
	fallback.erase(BaseAction.ActionType.ATTACK)
	for member in squad.get_members():
		queue_main_action(member, board, squad_manager, fallback)


# The squad's attacks, chosen together. Each ROUND re-resolves the squad's real plan, scores every
# remaining member's every candidate as a marginal against it, and queues the single best -- so the
# second member decides knowing what the first just committed to. Repeats until nothing beats (0,0).
#
# Ties resolve to the earlier member and then the earlier candidate (Law #1): _beats is strict, so
# the first to reach a score keeps it, and both loops walk their own declaration order.
static func _queue_attacks_jointly(squad: Squad, board: BoardContext, squad_manager: SquadManager) -> void:
	var leader := squad.get_leader()
	if leader == null or not is_instance_valid(leader):
		return
	var reactions := ReactionCatalog.get_all()
	var terrain := TerrainReactionCatalog.get_all()
	var refused := {}   # candidate key -> true; queue_action turned this one down, don't re-pick it

	while true:
		var base_plan := squad_manager.resolve_plan(squad, board, reactions, terrain)
		# EVERY member's candidates, built here against the REAL plan and before the first
		# hypothetical (#709). Scoring resolves a hypothetical per candidate and this pass restores
		# only before it QUEUES, so a list built inside the member loop was built while the previous
		# member's last rejected hypothetical was still published -- and the reads that produce a
		# candidate go through the board's projected occupancy, so the second member was aiming at
		# a plan nobody gave. Rebuilt each round, which is what keeps it as fresh as the base plan:
		# nothing is committed within a round, so no candidate can go stale before the single queue
		# below, and the next round sees the commitment through its own base resolve.
		var stakes := _stakes_for(squad, board, base_plan)
		var by_member := _candidates_by_member(squad.get_members(), board, base_plan, stakes)
		var best: _Scored = null
		for member in squad.get_members():
			var pick := _best_candidate_for(member, squad, board, base_plan, squad_manager, reactions, terrain, refused, true, by_member, stakes)
			if pick != null and (best == null or pick.score.beats(best.score)):
				best = pick
		if best == null:
			break
		best.action.actor.active_attack = best.action.fired_attack
		# RESTORE BEFORE QUEUEING, not merely at the end. queue_action's whiff gate asks
		# SquadPlanValidator.aim_finds_a_target, and it is correct there ONLY because that knockback
		# is the already-queued aims' shoves. Scoring has just published a LOSING candidate's shove,
		# so without this the gate looks for the target on the cell some rejected hypothetical would
		# have thrown it to, finds nobody, and refuses the winner as a whiff -- which made a shoving
		# attack unqueueable by this pass entirely.
		#
		# THAT GATE IS NOT THE ONLY READER, and this comment said it was until #709:
		# gather_attack_victims resolves occupants projected too (#105), so the candidate BUILDER
		# reads the same published shove. Restoring here fixed the gate and left the builder, which
		# is why the lists are hoisted above -- see _candidates_by_member.
		squad_manager.resolve_plan(squad, board, reactions, terrain)
		if not squad_manager.queue_action(squad, best.action):
			refused[_candidate_key(best.action)] = true   # bounded: candidates are finite and keys are stable across rounds

	# ...and once more on the way out: the loop breaks with a hypothetical as its last resolve.
	# DECLARED UNPINNED -- no case here goes red when this line is deleted, and two attempts at one
	# failed. Kept for what it MEANS rather than for a behaviour a test can currently see: the pass
	# must not hand the board back dressed for a plan nobody gave. Everything downstream happens to
	# re-resolve (the queue panel's refresh, OrderExecutor's own pass), so the residue is masked
	# rather than harmless -- delete this and the masking becomes load-bearing.
	squad_manager.resolve_plan(squad, board, reactions, terrain)


class _Scored:
	var action: AttackAction
	var score: AIScore


# One member's best candidate, or null when it has nothing it can legally aim.
#
# THE SCORE ORDERS, IT NEVER GATES (#711, dev ruling 2026-09-02): "the AI should ALWAYS attack if
# there is an option to, and if all the options are weighed bad, it has to pick its least bad
# option." So there is no bar to beat and the argmax wins at any sign -- a squad frozen by a
# counter bill it could not net positive against is the shape that deleted the bar.
#
# ONE PASS OVER EVERY TARGET, a body among them (#720, dev 2026-09-03: "the same level of
# prioritization as other attacks, it just loses to other attacks in the head to head"). This was
# two, falling through to bodies only when nothing upright produced a candidate -- #57's
# deprioritization as a HARD PRECEDENCE. What replaces it is the score, which was already saying the
# same thing more precisely: the overkill clamp caps a body at 1 -- the cling at 1 HP until #1002
# let a heal raise one -- so finishing a body is worth +1 and earns no removal, and any swing at
# somebody on their feet outranks it. (This SUPERSEDES "felling someone
# standing always beats finishing a body", dev 2026-09-02 -- kept as a ranking, dropped as a gate.)
#
# The one corner where the two rulings disagree is a body in reach beside a standing target whose
# counter would FELL the attacker, and the score decides it (dev, 2026-09-03): a free finish at
# (0,0,+1,0) beats a suicidal swing at (-1,0,d,-x). That is the only comparison a body wins.
#
# REFUSAL still removes a candidate before it can count: one `queue_action` turned down is skipped,
# so it was never a real option. That is the surviving half of "pass 2 needs an empty pass 1". So
# does a candidate that would fell our own side (#1220 ruling 1): never an option, not a bad one.
static func _best_candidate_for(member: Unit, squad: Squad, board: BoardContext, base_plan: ResolvedPlan,
		squad_manager: SquadManager, reactions: Array[ElementalReaction],
		terrain: Array[TerrainReaction], refused: Dictionary, allow_lookahead: bool,
		by_member: Dictionary, stakes: _Stakes) -> _Scored:
	if not by_member.has(member):
		return null   # the eligibility gate ran when the table was built -- _candidates_by_member
	var faction := member.get_faction()
	var base := _score_plan(faction, base_plan, stakes)
	var routine := AIWeaponRoutine.for_unit(member)
	var best: _Scored = null
	var last_resort: _Scored = null   # the best of what the family DEFERRED -- see below
	var candidates: Array[AttackAction] = by_member[member]
	for candidate in candidates:
		if refused.has(_candidate_key(candidate)):
			continue
		var one: Array[BaseAction] = [candidate]
		var plan := squad_manager.resolve_hypothetical(squad, one, board, reactions, terrain)
		if _fells_own([candidate], faction, base_plan, plan):
			continue
		var score := _score_plan(faction, plan, stakes).minus(base)
		# A SET-UP is worth nothing by itself and everything to the swing behind it: Splash deals
		# no damage, so soaking a target scores (0,0) and a greedy chooser could never OPEN a
		# combo. One step of lookahead prices it by what a squadmate could then do (dev call,
		# pairs in v1, 2026-09-02), FLOORED AT ITS OWN SOLO SCORE -- see _lookahead for why
		# inventing a zero there inverts the ranking now that a negative score can still win.
		if not score.beats(AIScore.zero()) and allow_lookahead and _applies_state_to_an_enemy(faction, plan):
			score = _lookahead(member, candidate, score, squad, board, base_plan, squad_manager, reactions, terrain, refused, by_member, stakes)
		# A DEFERRED candidate is the family's own last resort (#726): it loses to every candidate
		# this member has NOT deferred and is still taken when it has nothing else, so #711 stays
		# literal -- the AI always attacks. MEMBER-LOCAL on purpose: decided here, never carried on
		# _Scored into the joint loop, where it would become a precedence across members (the
		# two-tier shape #720 deleted) and let one family's routine reorder another family's swing.
		if routine.defers_candidate(member, candidate, plan, score):
			if last_resort == null or score.beats(last_resort.score):
				last_resort = _scored(candidate, score)
			continue
		if best == null or score.beats(best.score):
			best = _scored(candidate, score)
	if best != null:
		return best
	return last_resort


static func _scored(action: AttackAction, score: AIScore) -> _Scored:
	var out := _Scored.new()
	out.action = action
	out.score = score
	return out


# What the best squadmate follow-up makes this set-up worth. Scored as the PAIR against the same
# base, so a set-up is credited with the whole combo's gain; the follow-up is NOT committed -- the
# next round finds it on its own merits, against a plan that now really holds the set-up.
#
# Bounded by its trigger rather than by a depth counter: only a candidate that scores nothing alone
# AND applies a state to an enemy gets here, so a squad of plain weapons pays nothing at all.
#
# THE ACCUMULATOR STARTS AT THE SET-UP'S OWN SOLO SCORE, never at a zero score (#711). A zero floor
# was invisible while a candidate had to BEAT zero to queue -- it only ever turned a refusal into a
# refusal. With no bar it LAUNDERS: a set-up really worth (-1, 0, -5) came back (0,0,0) and then
# outranked an honest plain swing at (-1, 8, -4) on the first term, so a member facing a lethal
# counter soaked instead of hitting and died dealing nothing. A set-up is worth the better of what
# it does alone and what it enables; zero is not one of those two and must not be invented here.
static func _lookahead(setup_unit: Unit, setup: AttackAction, solo: AIScore, squad: Squad, board: BoardContext,
		base_plan: ResolvedPlan, squad_manager: SquadManager, reactions: Array[ElementalReaction],
		terrain: Array[TerrainReaction], refused: Dictionary, by_member: Dictionary, stakes: _Stakes) -> AIScore:
	var faction := setup_unit.get_faction()
	var base := _score_plan(faction, base_plan, stakes)
	var best := solo
	for mate in squad.get_members():
		if mate == setup_unit or not by_member.has(mate):
			continue   # a missing entry IS the eligibility gate, run once at the table build
		var follows: Array[AttackAction] = by_member[mate]
		for follow in follows:
			if refused.has(_candidate_key(follow)):
				continue
			var pair: Array[BaseAction] = [setup, follow]
			var plan := squad_manager.resolve_hypothetical(squad, pair, board, reactions, terrain)
			if _fells_own(pair, faction, base_plan, plan):
				continue
			var score := _score_plan(faction, plan, stakes).minus(base)
			if score.beats(best):
				best = score
	return best


# Does this plan put a state on somebody hostile? The lookahead's trigger -- the mark of a set-up,
# read off the resolver's own outcome rather than off the attack's authored sigils, so a state that
# an insulation or a reaction cancelled correctly reads as no set-up at all.
static func _applies_state_to_an_enemy(faction: Team.Faction, plan: ResolvedPlan) -> bool:
	for a in plan.attacks:
		if a.target == null or a.resolved == null or not is_instance_valid(a.target):
			continue
		if not Team.is_enemy(faction, a.target.get_faction()):
			continue
		if not a.resolved.states_added.is_empty():
			return true
	return false


# Identity of a candidate ACROSS ROUNDS -- who fires what at where. The candidate objects are
# rebuilt every round, so a refusal has to be remembered by what it names, not by the instance.
static func _candidate_key(a: AttackAction) -> String:
	var attack_id: int = a.fired_attack.get_instance_id() if a.fired_attack != null else 0
	return "%d|%d|%d|%d" % [a.actor.get_instance_id(), a.target_cell.x, a.target_cell.y, attack_id]


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
	var candidates := _standable_attack_cells(unit, goal, aiming, board)
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


# Every cell `unit` could both STAND on and hit `goal` from -- the firing positions around a target.
# Reach is unioned over all 4 facings, so "X can hit goal" iff "goal can hit X" for every pattern
# this game authors -- for the HORIZONTAL half only, since #258's up/down tolerance is asymmetric by
# design. The vertical clause is therefore judged in the TRUE direction (stand at `cell`, hit
# `goal`), never inverted. can_traverse then drops walls and is_standable_for drops occupied cells,
# which are the same two rules compute_move_range's own BFS enforces. Shared by the approach picker
# and by target selection so the two cannot disagree about where a fight can be had from (#127).
#
# Since #756 that clause reaches DIRECTIONAL attacks too, in its point form: the straight line from
# the firing cell to the goal, which for a line spread is exactly the lane the shot would run down.
# It is an APPROXIMATION for a wide spread's side lanes, where the true question is which facing's
# truncated footprint covers the goal — conservative, so the cost is a firing position declined
# rather than one wrongly offered, and the candidate builder's own footprint read is authoritative.
static func _standable_attack_cells(unit: Unit, goal: Vector2i, aiming: AttackData, board: BoardContext) -> Dictionary:
	var cells := {}
	for cell in Reach.get_all_attack_cells_from(unit, goal, aiming):
		if not Reach.vertical_aim_ok(aiming, cell, goal, board):
			continue   # a ledge above the weapon's tolerance is not a firing position (#258)
		if not RulesService.can_traverse(cell, unit, board):
			continue   # a wall/off-map neighbour of goal is not a firing position either
		if RulesService.is_standable_for(unit, board.unit_at_cell(cell)):
			cells[cell] = true
	return cells


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
	var best_can_attack: bool = prefer_attack and Reach.get_all_attack_cells_from(unit, here, aiming).has(goal) \
		and Reach.vertical_aim_ok(aiming, here, goal, board)
	var best_hops: int = route.get(here, RulesService.UNREACHABLE)
	var best_dist: int = GridUtils.manhattan_distance(here, goal)
	var best_cost := 0

	for cell in range.reachable.keys():
		if allowed != null and not allowed.has(cell):
			continue
		var can_attack: bool = prefer_attack and Reach.get_all_attack_cells_from(unit, cell, aiming).has(goal) \
			and Reach.vertical_aim_ok(aiming, cell, goal, board)
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
