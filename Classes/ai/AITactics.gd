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
# via PlanResolver.projected_lifecycle, which covers the same three rungs and cannot double-count
# a second hit on the same body. See _score_plan.)

# `within`: optional Dictionary set of cells -- only enemies standing in it count.
# NEAREST IS BY ROUTE, not raw distance: an enemy two cells away through a wall is further off than
# one eight cells down an open corridor, and picking the walled one commits the whole squad to
# walking at a wall. Distance survives only as the tie-break, which is what everything degrades to
# when no enemy is reachable at all (an island, a sealed room) -- the old answer, unchanged.
# Downed enemies are DEPRIORITIZED, not protected (#57, fork 3): any active enemy wins;
# a downed one is targeted only when nothing active matches (finishing off is legal).
static func nearest_enemy(from_unit: Unit, board: BoardContext, within = null) -> Unit:
	var route := _approach_distances(from_unit, board)
	var target := _nearest_enemy_matching(from_unit, board, within, false, route)
	if target == null:
		target = _nearest_enemy_matching(from_unit, board, within, true, route)
	return target

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
		# `within` still tests the enemy's OWN cell -- "is this enemy inside my zone" is a different
		# question from "how far is a firing position on it", and Sentry's leash means the first.
		if within != null and not within.has(unit.movement.cell):
			continue
		var hops: int = route.get(unit, RulesService.UNREACHABLE)
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
			BaseAction.ActionType.REV:
				queued = _try_rev(unit, squad_manager)
			_:
				push_error("No AI builder for ActionType %s" % BaseAction.ActionType.keys()[t])
		if queued:
			return true
	return false

# Attack choice (#78, rebuilt #117): probe every selectable+fireable attack, score each aim as its
# MARGINAL GAIN to the squad's own plan, queue the best. The per-unit door -- one member, deciding
# alone. The squad walks these jointly instead; see _queue_attacks_jointly.
static func _try_best_attack(unit: Unit, board: BoardContext, squad_manager: SquadManager) -> bool:
	if not unit.can_wield_equipped() or unit.squad == null:
		return false
	var reactions := ReactionCatalog.get_all()   # hoisted -- both catalogs dir-scan per call, and
	var terrain := TerrainReactionCatalog.get_all()   # a scoring pass resolves many times
	var squad := unit.squad
	var base := _score_plan(unit.get_faction(), squad_manager.resolve_plan(squad, board, reactions, terrain), false)
	var pick := _best_candidate_for(unit, squad, board, base, squad_manager, reactions, terrain, {}, true)
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


# Every attack `unit` could declare from `origin`: each selectable+fireable attack crossed with
# every enemy it can reach and legally aim at. Built as REAL declared orders through
# AttackAction.declare -- the one stamp factory (#78) -- so the thing scored and the thing queued
# are the same object rather than two descriptions of one.
static func _attack_candidates(unit: Unit, board: BoardContext, origin: Vector2i, include_downed: bool) -> Array[AttackAction]:
	var out: Array[AttackAction] = []
	var candidates: Array[AttackData] = unit.get_selectable_attacks()
	if candidates.is_empty():
		candidates = [null]   # unarmed (or aura-dry rune): null pick = bare-fist Manhattan-1, the resolver's STR fallback
	for attack in candidates:
		if not unit.is_attack_fireable(attack):
			continue
		# The candidate is passed straight to the geometry (#102) -- active_attack is written only
		# for declare()'s stamp, immediately before it, and cleared again below.
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
			# The player's vertical gate, mirrored (#258): a point aim above the attack's tolerance
			# is refused at the click, so the AI must not author one. Directional attacks pass, as
			# they do at the click. (Live cell, not projected -- the declared v1 approximation.)
			if not Reach.vertical_aim_ok(attack, origin, other.movement.cell, board):
				continue
			var affected := Reach.get_affected_cells_from(unit, origin, other.movement.cell, attack)
			if RulesService.gather_attack_victims(unit, affected, board, attack).is_empty():
				continue
			unit.active_attack = attack
			out.append(AttackAction.declare(unit, origin, other.movement.cell))
	unit.active_attack = null   # no probe left behind (#102)
	return out


# Score a whole RESOLVED PLAN -> Vector2i(x = net removals, y = net damage); removals outrank
# damage (lexicographic, _beats), and a candidate's MARGINAL must beat (0,0) to queue at all.
#
# The rule is #78's, widened from one throwaway volley to the squad's whole plan, and the widening
# is what buys squad play: the plan holds every squadmate's queued swing (so a finishing blow is
# visible as one), the threaded hypo (so a soak already in the plan is priced into the shock behind
# it), and the DERIVED counters and watch shots -- which is how "counters aren't scored" closes.
#
# ONE sign rule covers all three lists: a victim hostile to `faction` counts FOR, anyone else counts
# AGAINST. That is the net-damage doctrine (dev, 2026-07-22), and it lands the derived rows
# correctly with no second clause -- an enemy AoE counter splashing its own side adds. Heals
# contribute nothing: heal_amount is not damage, and scoring it would start AI healers healing,
# which is its own behaviour and its own ticket.
#
# BUT A REACTION'S DAMAGE IS NOT SCORED AT ALL -- ONLY ITS REMOVALS (dev ruling, 2026-09-02).
# Priced at par it cancels exactly: two units with the same weapon trade 3 for 3, every even
# exchange scores (0,0), and an AI facing mirror-statted enemies declines every attack and reloads
# instead. That is not caution, it is a parked squad, and it is the common matchup. Removals are
# the currency the AI plays for and damage is the tie-break (the ratified lexicographic order), so
# a counter that FELLS one of ours is a real loss and counts, while chip damage taken is the price
# of engaging and is free. This is what closes "counters aren't scored" for the case that matters:
# a candidate handing the enemy a lethal counter is refused, one handing them a scratch is not.
#
# CRISIS counts as nothing -- the target stands back up surged, so triggering it is neither prize
# nor penalty (revisit with smarter AI kinds). Downed enemies count only when count_downed (#57).
static func _score_plan(faction: Team.Faction, plan: ResolvedPlan, count_downed: bool) -> Vector2i:
	var dealt := {}   # Unit -> damage this plan lands on them, before the overkill clamp
	for a in plan.attacks:
		var victim: Unit = a.target
		if victim == null or a.resolved == null or not is_instance_valid(victim):
			continue
		if Team.is_enemy(faction, victim.get_faction()):
			if a.resolved.lethality == ResolvedOutcome.Lethality.CRISIS:
				continue
			if victim.is_downed() and not count_downed:
				continue   # already on the ground before this plan -- #57, pass 1
		dealt[victim] = int(dealt.get(victim, 0)) + a.resolved.damage

	# The REACTIONS this plan draws -- counters and any watch shots it sets off. Their victims join
	# the removal ledger and nothing else, per the ruling above.
	for a in _reaction_rows(plan):
		var victim: Unit = a.target
		if victim == null or a.resolved == null or not is_instance_valid(victim):
			continue
		if not dealt.has(victim):
			dealt[victim] = 0

	# OVERKILL IS WORTH NOTHING: a victim's damage is capped at the HP they had going in, so you
	# cannot get more value out of a person than taking them out of the fight. Without this the
	# removal ledger below fixes only half the double-spend -- a second member swinging at someone
	# the first already downed still banked full damage, which ties exactly with hitting an
	# untouched enemy for the same number, leaving focus-fire to be decided by board order. The cap
	# binds only on overkill, so chipping a healthy unit is unaffected. Live HP is plan-start HP.
	var net := 0
	for victim: Unit in dealt:
		var counted: int = mini(int(dealt[victim]), maxi(victim.get_current_hp(), 0))
		net += counted if Team.is_enemy(faction, victim.get_faction()) else -counted

	# A REMOVAL IS PER VICTIM, NOT PER HIT, and that is the whole of squad focus-fire. Counting the
	# lethality rung of each row instead double-pays: the ladder answers KILLED for any damaging hit
	# on an already-downed body (LethalityRules.predict), so a second member swinging at someone the
	# first already downed scored a fresh removal and the two happily overkilled one target while a
	# second enemy went untouched. Asked as a CHANGE OF STANDING -- on its feet before the plan,
	# off them after -- so it is the plan's effect on a person, which is what a removal means.
	var removals := 0
	for victim: Unit in dealt:
		if not _plan_removes(victim, plan):
			continue
		removals += 1 if Team.is_enemy(faction, victim.get_faction()) else -1
	return Vector2i(removals, net)


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
	return PlanResolver.projected_lifecycle(victim, plan.hypo) != Unit.LifecycleState.ACTIVE


static func _beats(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x > b.x
	return a.y > b.y

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
	# The AI has no tile pick, so it takes the FIRST landing -- which is exactly the answer the rule
	# gave everyone before the player was handed the choice (#116), NEIGHBOURS declaration order.
	# Non-empty by construction: adjacent_downed_allies already refuses a body with no landing.
	var landings := RulesService.rescue_landings(unit, target, board)
	var rescue := RescueAction.new()
	rescue.init(unit, target, landings[0])
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

static func _try_rev(unit: Unit, squad_manager: SquadManager) -> bool:
	if not unit.can_rev_weapon():
		return false
	var action := RevAction.new()
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


# Fights `target`: destination pick -> conditional group move -> every member tries a main
# action. The shared shape behind Rushdown's whole turn and Sentry's intruder branch -- was
# hand-duplicated in both files with no third caller (AI generalization sweep, finding #2).
static func engage(squad: Squad, target: Unit, board: BoardContext, squad_manager: SquadManager, allowed = null) -> void:
	var leader := squad.get_leader()
	var destination := best_attack_destination(leader, target, board, allowed)
	if destination != leader.movement.cell:
		squad_manager.queue_group_move(squad, destination, board, allowed)
	queue_main_actions_for_squad(squad, board, squad_manager)


# Every member takes a main action. The tail of engage() and the whole of HoldArchetype's turn --
# and, since finding #3, Rushdown's no-target branch too.
#
# TWO PASSES, and the split is the point (#117). ATTACK is decided for the squad JOINTLY, because
# an attack's worth depends on what the rest of the squad is already doing; the remaining verbs
# stay the ratified per-unit priority walk (dev, 2026-07-22 -- rescue/reload/rev/intimidate are a
# lexical order, not a score). The fallback list therefore has ATTACK REMOVED: leaving it in would
# let a member the joint pass deliberately declined re-decide alone and undo that judgement.
static func queue_main_actions_for_squad(squad: Squad, board: BoardContext, squad_manager: SquadManager) -> void:
	var priority: Array = AIArchetype.main_action_priority(squad.archetype)
	if priority.has(BaseAction.ActionType.ATTACK):
		_queue_attacks_jointly(squad, board, squad_manager)
	var fallback: Array = priority.duplicate()
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
	var faction := leader.get_faction()
	var reactions := ReactionCatalog.get_all()
	var terrain := TerrainReactionCatalog.get_all()
	var refused := {}   # candidate key -> true; queue_action turned this one down, don't re-pick it

	while true:
		var base := _score_plan(faction, squad_manager.resolve_plan(squad, board, reactions, terrain), false)
		var best: _Scored = null
		for member in squad.get_members():
			var pick := _best_candidate_for(member, squad, board, base, squad_manager, reactions, terrain, refused, true)
			if pick != null and (best == null or _beats(pick.score, best.score)):
				best = pick
		if best == null:
			break
		best.action.actor.active_attack = best.action.fired_attack
		# RESTORE BEFORE QUEUEING, not merely at the end. queue_action's whiff gate asks
		# SquadPlanValidator.aim_finds_a_target, the one reader of published knockback, and it is
		# correct there ONLY because that knockback is the already-queued aims' shoves. Scoring has
		# just published a LOSING candidate's shove, so without this the gate looks for the target
		# on the cell some rejected hypothetical would have thrown it to, finds nobody, and refuses
		# the winner as a whiff -- which made a shoving attack unqueueable by this pass entirely.
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
	var score: Vector2i


# One member's best candidate, or null when nothing it can do beats (0,0). Two passes preserve
# #57's downed deprioritization PER MEMBER: downed enemies neither aim nor score until nothing
# active produced a candidate for this unit.
static func _best_candidate_for(member: Unit, squad: Squad, board: BoardContext, base: Vector2i,
		squad_manager: SquadManager, reactions: Array[ElementalReaction],
		terrain: Array[TerrainReaction], refused: Dictionary, allow_lookahead: bool) -> _Scored:
	if not member.is_active() or member.has_main_action_queued() or not member.can_wield_equipped():
		return null
	var origin := member.get_projected_destination()
	for include_downed in [false, true]:
		var best: _Scored = null
		for candidate in _attack_candidates(member, board, origin, include_downed):
			if refused.has(_candidate_key(candidate)):
				continue
			var one: Array[BaseAction] = [candidate]
			var plan := squad_manager.resolve_hypothetical(squad, one, board, reactions, terrain)
			var score := _score_plan(member.get_faction(), plan, include_downed) - base
			# A SET-UP is worth nothing by itself and everything to the swing behind it: Splash
			# deals no damage, so soaking a target scores (0,0) and the old chooser refused it --
			# the AI was structurally unable to OPEN a combo. One step of lookahead prices it by
			# what a squadmate could then do (dev call, pairs in v1, 2026-09-02).
			if not _beats(score, Vector2i.ZERO) and allow_lookahead and _applies_state_to_an_enemy(member.get_faction(), plan):
				score = _lookahead(member, candidate, squad, board, base, squad_manager, reactions, terrain, refused)
			if not _beats(score, Vector2i.ZERO):
				continue
			if best == null or _beats(score, best.score):
				best = _Scored.new()
				best.action = candidate
				best.score = score
		if best != null:
			return best
	return null


# What the best squadmate follow-up makes this set-up worth. Scored as the PAIR against the same
# base, so a set-up is credited with the whole combo's gain; the follow-up is NOT committed -- the
# next round finds it on its own merits, against a plan that now really holds the set-up.
#
# Bounded by its trigger rather than by a depth counter: only a candidate that scores nothing alone
# AND applies a state to an enemy gets here, so a squad of plain weapons pays nothing at all.
static func _lookahead(setup_unit: Unit, setup: AttackAction, squad: Squad, board: BoardContext,
		base: Vector2i, squad_manager: SquadManager, reactions: Array[ElementalReaction],
		terrain: Array[TerrainReaction], refused: Dictionary) -> Vector2i:
	var best := Vector2i.ZERO
	for mate in squad.get_members():
		if mate == setup_unit or not mate.is_active() or mate.has_main_action_queued() or not mate.can_wield_equipped():
			continue
		var origin := mate.get_projected_destination()
		for follow in _attack_candidates(mate, board, origin, false):
			if refused.has(_candidate_key(follow)):
				continue
			var pair: Array[BaseAction] = [setup, follow]
			var plan := squad_manager.resolve_hypothetical(squad, pair, board, reactions, terrain)
			var score := _score_plan(setup_unit.get_faction(), plan, false) - base
			if _beats(score, best):
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
