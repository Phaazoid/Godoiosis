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
# a scored one, because scoring an attack from a cell nobody has moved to is structurally
# impossible today (SquadManager._resolve_actions reads positions off the LIVE queue, so a
# hypothetical move moves nobody). That is why this layer and the ATTACK pick judge an exchange
# differently: this one cannot resolve, _score_plan can and would be throwing information away.
# Declared in ai-tactics.md rather than left to be discovered.
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
# OPTIMISTIC for a leader with squadmates, and declared rather than fixed: this is the leader's own
# unclamped move range, but cohesion (V3) can refuse the group move to a cell the leader alone
# could stand on, in which case the squad stays put. best_attack_destination has carried the
# identical optimism since #29, so nothing new is introduced here.
class _Engagement:
	var from: Vector2i   # the cell we would attack from -- the same one the approach will route to
	var hops: int        # route to it, the tie-break


static func _engageable_enemies(leader: Unit, board: BoardContext, within, allowed) -> Dictionary:
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
# ACTIVE_ONLY is the caller's to state (#750), the path_hops(block_on_occupancy) shape: one question
# -- which enemy is nearest -- with the lifecycle admission passed in rather than a second walk.
# PURSUIT wants a body (it is an ordinary target, #720); a WATCH cannot use one, because a corpse
# never enters anything and _watch_triggered_by refuses a non-ACTIVE entrant outright. Left false so
# every existing caller is unchanged.
static func nearest_enemy(from_unit: Unit, board: BoardContext, within = null, active_only := false) -> Unit:
	var route := _approach_distances(from_unit, board)
	var nearest: Unit = null
	var best_hops := 0
	var best_standing := false
	var best_dist := 0
	for unit in board.units:
		if not is_instance_valid(unit):
			continue
		if not (unit.is_active() or (unit.is_downed() and not active_only)):
			continue
		if not Team.is_enemy(from_unit.get_faction(), unit.get_faction()):
			continue
		# `within` still tests the enemy's OWN cell -- "is this enemy inside my zone" is a different
		# question from "how far is a firing position on it", and Sentry's leash means the first.
		if within != null and not within.has(unit.movement.cell):
			continue
		var hops: int = route.get(unit, RulesService.UNREACHABLE)
		var standing := unit.is_active()
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
		# rescue/intimidate/rally are not a weapon's to veto.
		if AIWeaponRoutine.WEAPON_VERBS.has(verb) and not routine.allows_preparation(unit, verb, board):
			continue
		var queued := false
		match verb:
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
	var reactions := ReactionCatalog.get_all()   # hoisted -- both catalogs dir-scan per call, and
	var terrain := TerrainReactionCatalog.get_all()   # a scoring pass resolves many times
	var squad := unit.squad
	var base_plan := squad_manager.resolve_plan(squad, board, reactions, terrain)
	var alone: Array[Unit] = [unit]
	var pick := _best_candidate_for(unit, squad, board, base_plan, squad_manager, reactions, terrain, {}, true,
			_candidates_by_member(alone, board, base_plan))
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
static func _candidates_by_member(members: Array[Unit], board: BoardContext, base_plan: ResolvedPlan) -> Dictionary:
	var out := {}
	for member in members:
		if not member.is_active() or member.has_main_action_queued() or not member.can_wield_equipped():
			continue
		out[member] = _attack_candidates(member, board, member.get_projected_destination(), base_plan.hypo)
	return out


# Every attack `unit` could declare from `origin`: each selectable+fireable attack crossed with
# every enemy it can reach and legally aim at. Built as REAL declared orders through
# AttackAction.declare -- the one stamp factory (#78) -- so the thing scored and the thing queued
# are the same object rather than two descriptions of one.
#
# ONE LIST, standing and downed alike (#720, dev 2026-09-03). It was two passes, a body offered only
# once nothing upright had produced a candidate -- #57's precedence as a hard gate. The score already
# says everything that rule was protecting: a downed unit clings at 1 HP (Unit._go_downed), so the
# overkill clamp prices finishing one at exactly +1, which loses to any real swing and wins only when
# nothing else is there. The gate on top of that was what made a body an ABSOLUTE last resort.
#
# WHAT THE PLAN HAS ALREADY KILLED IS NOT A TARGET (#719). Planning does not execute, so a unit a
# squadmate felled THIS round is still standing on the live board -- the base plan's hypo is the only
# honest answer, and the pass-2 filter never asked it. That is how a leader queued her 6-long line
# through her own party at a corpse: it was the one candidate she had left, and with no bar (#711)
# the one candidate is taken however bad it is. DOWNED in the hypo is still a target (finishing is
# intended); DEAD is not, because there is nobody there to finish.
static func _attack_candidates(unit: Unit, board: BoardContext, origin: Vector2i,
		base_hypo: Dictionary) -> Array[AttackAction]:
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
			if not (other.is_active() or other.is_downed()):
				continue
			if PlanResolver.projected_lifecycle(other, base_hypo) == Unit.LifecycleState.DEAD:
				continue   # a squadmate already finished them this pass -- see the header
			# WHERE THE PLAN PUTS THEM, not where they stand (#709). Sibling of the lifecycle read
			# directly above, answered off the same dict: a squadmate's queued shove has already
			# moved this target, and gather_attack_victims below has resolved occupants through
			# PROJECTED cells since #105 -- so a live aim did not merely mis-point, it built a
			# footprint holding nobody and the candidate was dropped at that guard. The direction
			# that was invisible is the other one: a shove that pulls a target INTO reach.
			var at := PlanResolver.projected_position(other, base_hypo)
			if not reach.has(at):
				continue
			# The player's vertical gate, mirrored (#258): a point aim above the attack's tolerance
			# is refused at the click, so the AI must not author one. Directional attacks pass, as
			# they do at the click.
			if not Reach.vertical_aim_ok(attack, origin, at, board):
				continue
			var affected := Reach.get_affected_cells_from(unit, origin, at, attack)
			if RulesService.gather_attack_victims(unit, affected, board, attack).is_empty():
				continue
			unit.active_attack = attack
			out.append(AttackAction.declare(unit, origin, at))
	unit.active_attack = null   # no probe left behind (#102)
	return out


# Score a whole RESOLVED PLAN -> Vector3i(x = net removals, y = net damage dealt, z = -damage taken
# from reactions); compared lexicographically (_beats). The MARGINAL a candidate adds is what ranks
# it, and since #711 there is no bar it has to clear -- the score orders, it never gates.
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
# A REACTION'S DAMAGE NEVER JOINS y -- ONLY ITS REMOVALS (dev ruling, 2026-09-02). Priced at par
# it cancels exactly: two units with the same weapon trade 3 for 3, every even exchange scores
# (0,0), and an AI facing mirror-statted enemies declines every attack and reloads instead. That is
# not caution, it is a parked squad, and it is the common matchup. So a counter that FELLS one of
# ours is a real loss and lands in x, while chip damage taken is the price of engaging.
#
# ...BUT IT IS THE TIE-BREAK z (dev, 2026-09-02, from playtest): "when all else is even, they
# should go for optimal exchanges." Sitting strictly BELOW damage dealt is what keeps it from
# reviving the parked squad -- a mirror matchup still scores (0, 8, -8) and beats (0,0,0), because
# z only ever speaks when both higher terms tie exactly. It is also what stops the ATTACK pick
# undoing the TARGET pick: once the squad has walked to the harmless target, the dangerous one may
# still be in reach from the settled cell, and without z that choice ties on damage and falls to
# board order. See choose_engagement_target for the other half.
#
# THE AI IS BLIND TO CRISIS (dev ruling, 2026-09-04, explicitly provisional): a hit the ladder
# sentences to CRISIS is priced at the damage AND the removal it would have earned if the gambit did
# not exist. His words: "the ai simply won't see crisis mode until they have to react to a unit
# currently in it." It counted as NOTHING before -- the damage was skipped here and CRISIS threads
# ACTIVE so no removal followed -- which under #711's no-bar rule is not a refusal but a LOSING
# candidate, so a full-Will Berserker was the last thing an AI would swing at. (#708, whose own
# "a neutral verdict means never" reading died with the bar.)
#
# Neither half needs new arithmetic. The damage is the raw pre-Crisis number (the resolver fixes
# outcome.damage before the rung is named and the Crisis branch rewrites only hp/will/in_crisis),
# and the overkill clamp below caps it at the HP they had going in -- which a would-be-down met by
# definition. The removal comes from _plan_removes asking PlanResolver.plan_fells.
#
# BLIND TO THE GAMBIT, SIGHTED TO WHAT IT DRAWS (dev, same day). A Crisis'd defender is still ACTIVE
# and so COUNTERS where a downed one cannot, and that counter's damage still lands in z -- so
# between two otherwise identical targets the AI prefers the one that cannot answer. Declared rather
# than accidental: blinding z too is a different edit in the reaction loop, and "it takes the
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
# outranking somebody upright is the arithmetic below rather than a gate above it. A downed unit
# clings at 1 HP (Unit._go_downed), so the overkill clamp values finishing one at exactly +1 damage
# -- enough to break a tie, never enough to outrank a real swing -- and _plan_removes answers false
# for a body, so it cannot earn a removal either.
static func _score_plan(faction: Team.Faction, plan: ResolvedPlan) -> Vector3i:
	var dealt := {}   # Unit -> damage this plan lands on them, before the overkill clamp
	for a in plan.attacks:
		var victim: Unit = a.target
		if victim == null or a.resolved == null or not is_instance_valid(victim):
			continue
		dealt[victim] = int(dealt.get(victim, 0)) + a.resolved.damage

	# The REACTIONS this plan draws -- counters and any watch shots it sets off. Their victims join
	# the removal ledger, and what they land on OUR side accumulates as the z tie-break. Damage a
	# reaction deals to an ENEMY (an AoE counter splashing its own party) is deliberately outside
	# the term rather than counted as a bonus, so z means exactly one thing: what engaging costs us.
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
	return Vector3i(removals, net, -taken)


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


# Lexicographic, and the ORDER is the design: removals are the currency, damage dealt is the
# tie-break, and damage taken from reactions only speaks when both of those tie exactly -- which is
# what "when all else is even, go for optimal exchanges" means, and what keeps a counter from ever
# talking the AI out of a trade.
static func _beats(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x > b.x
	if a.y != b.y:
		return a.y > b.y
	return a.z > b.z

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

# Burrow (#726): the rev pair's shape once more. WHETHER it is worth digging here is the Drill's
# own call (DrillWeaponRoutine), asked by queue_main_action before this builder runs.
static func _try_burrow(unit: Unit, squad_manager: SquadManager) -> bool:
	if not unit.can_burrow_weapon():
		return false
	var action := BurrowAction.new()
	action.init(unit)
	return squad_manager.queue_action(unit.squad, action)

# Overwatch (#750): AIM the attack instead of firing it, down the way an enemy would come.
#
# A PREPARATION, so it is a RULE and never a score term -- the shot lands on somebody else's turn,
# which `_score_plan` structurally cannot reach (#726's doctrine, second application). It sits below
# ATTACK for the same reason REV does: no preemption.
#
# THE AIM MUST BE ACTIVE-ONLY, and this is #720's pathology one door over. `nearest_enemy` ranks a
# BODY as an ordinary target, but `PlanResolver._watch_triggered_by` refuses a non-ACTIVE entrant and
# a corpse never moves -- so a watcher beside a downed enemy would aim at its "approach" every quiet
# turn for the rest of the battle, watching something that can never arrive.
static func _try_overwatch(unit: Unit, board: BoardContext, squad_manager: SquadManager) -> bool:
	var watchable := unit.overwatch_attacks()
	if watchable.is_empty():
		return false
	var attack: AttackData = watchable[0]   # one watch per weapon (dev, 2026-08-26); first is the deterministic pick
	if unit.attack_block_reason(attack) != "":
		return false   # the menu's own gate -- a dry Carbine cannot watch either, Overwatch requires readiness
	var enemy := nearest_enemy(unit, board, null, true)
	if enemy == null:
		return false
	var origin := unit.get_projected_destination()   # the fallback walk runs AFTER the group move is queued
	var aim := _watch_aim(unit, origin, attack, enemy, board)
	if aim == origin:
		return false   # no facing produces a footprint -- see _watch_aim
	var action := OverwatchAction.new()
	action.init(unit, aim, attack)
	return squad_manager.queue_action(unit.squad, action)


# Which cell to aim the watch at -- a FACING for a directional attack (Overwatch.tres is a
# ForwardLinePattern), the cell itself for a point one. Ranked by how few hops the enemy needs to
# reach it, walking from THE ENEMY'S side with its own traversal and occupancy on: that is what makes
# "the way you'll come" true around a wall rather than along a straight line.
#
# A DUD AIM MUST NEVER BE QUEUED. `ForwardLinePattern.get_selectable_cells` answers empty for a hint
# that yields no cardinal direction, and from there the failure is entirely silent -- the resolver
# arms nothing, `Unit.arm_watch` refuses on an empty footprint, and no queue gate looks at an
# OverwatchAction at all, so the unit would spend its main action on air behind a legal-looking row.
# Returning `origin` is this function's way of saying "no facing works", and the caller refuses.
#
# Ties keep CARDINAL_DIRECTIONS order (Law #1). A sealed board -- no route to any facing -- falls back
# to simply facing the enemy, reusing GridUtils' own diagonal tie-break rather than inventing a second.
static func _watch_aim(unit: Unit, origin: Vector2i, attack: AttackData, enemy: Unit, board: BoardContext) -> Vector2i:
	var best := origin
	var best_hops := -1
	for dir in AttackPattern.CARDINAL_DIRECTIONS:
		var aim: Vector2i = origin + dir
		if Reach.get_affected_cells_from(unit, origin, aim, attack).is_empty():
			continue
		var field := RulesService.path_hops(enemy.movement.cell, board, enemy, -1, {aim: true}, true)
		if not field.has(aim):
			continue
		var hops: int = field[aim]
		if best_hops < 0 or hops < best_hops:
			best = aim
			best_hops = hops
	if best_hops >= 0:
		return best
	var facing := GridUtils.cardinal_direction_i_between(origin, enemy.movement.cell)
	if facing != Vector2i.ZERO and not Reach.get_affected_cells_from(unit, origin, origin + facing, attack).is_empty():
		return origin + facing
	return origin


# Guard (#750): ward the ally the most enemies can reach. The other preparation whose payoff lands on
# somebody else's turn, so it is a rule for the same reason Overwatch is.
#
# ZERO EXPOSURE REFUSES. "Shields whoever is most exposed" presumes exposure above zero -- without
# the refusal a Guard would pre-empt INTIMIDATE with a purposeless ward whenever any ally happened to
# be standing beside it, and menacing somebody is the better use of that action.
#
# A DOWNED ally is in `guard_candidates` by design, but RESCUE sits above GUARD in the walk and
# rescue adjacency IS the guard range, so a body is normally carried before this is asked.
#
# Ties keep guard_candidates' own order (Law #1), which walks cells_within_manhattan_range.
static func _try_guard(unit: Unit, board: BoardContext, squad_manager: SquadManager) -> bool:
	var candidates := RulesService.guard_candidates(unit, board)
	if candidates.is_empty():
		return false
	var exposure := _exposure_counts(candidates, board, unit.get_faction())
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
# DECLARED APPROXIMATIONS, both inherited from the seams this composes: the search reads LIVE
# occupancy (a squadmate about to move still blocks it) and honours the enemy's own cohesion leash,
# so an enemy that could only reach the ally by breaking formation does not count. The cost is one
# search per ACTIVE enemy, paid only once a unit has reached GUARD in the walk -- second to last, so
# after every other verb has declined.
static func _exposure_counts(allies: Array[Unit], board: BoardContext, faction: Team.Faction) -> Dictionary:
	var counts := {}
	for other in board.units:
		if not is_instance_valid(other) or not other.is_active():
			continue
		if not Team.is_enemy(faction, other.get_faction()):
			continue
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
		var by_member := _candidates_by_member(squad.get_members(), board, base_plan)
		var best: _Scored = null
		for member in squad.get_members():
			var pick := _best_candidate_for(member, squad, board, base_plan, squad_manager, reactions, terrain, refused, true, by_member)
			if pick != null and (best == null or _beats(pick.score, best.score)):
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
	var score: Vector3i


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
# same thing more precisely: a body clings at 1 HP, so finishing one is worth +1 and earns no
# removal, and any swing at somebody on their feet outranks it. (This SUPERSEDES "felling someone
# standing always beats finishing a body", dev 2026-09-02 -- kept as a ranking, dropped as a gate.)
#
# The one corner where the two rulings disagree is a body in reach beside a standing target whose
# counter would FELL the attacker, and the score decides it (dev, 2026-09-03): a free finish at
# (0,+1,0) beats a suicidal swing at (-1,d,-x). That is the only comparison a body wins.
#
# THE SCORE ORDERS, IT NEVER GATES (#711, dev ruling 2026-09-02): "the AI should ALWAYS attack if
# there is an option to, and if all the options are weighed bad, it has to pick its least bad
# option." So there is no bar to beat and the argmax wins at any sign -- a squad frozen by a
# counter bill it could not net positive against is the shape that deleted the bar.
#
# REFUSAL still removes a candidate before it can count: one `queue_action` turned down is skipped,
# so it was never a real option. That is the surviving half of "pass 2 needs an empty pass 1".
static func _best_candidate_for(member: Unit, squad: Squad, board: BoardContext, base_plan: ResolvedPlan,
		squad_manager: SquadManager, reactions: Array[ElementalReaction],
		terrain: Array[TerrainReaction], refused: Dictionary, allow_lookahead: bool,
		by_member: Dictionary) -> _Scored:
	if not by_member.has(member):
		return null   # the eligibility gate ran when the table was built -- _candidates_by_member
	var base := _score_plan(member.get_faction(), base_plan)
	var routine := AIWeaponRoutine.for_unit(member)
	var best: _Scored = null
	var last_resort: _Scored = null   # the best of what the family DEFERRED -- see below
	var candidates: Array[AttackAction] = by_member[member]
	for candidate in candidates:
		if refused.has(_candidate_key(candidate)):
			continue
		var one: Array[BaseAction] = [candidate]
		var plan := squad_manager.resolve_hypothetical(squad, one, board, reactions, terrain)
		var score := _score_plan(member.get_faction(), plan) - base
		# A SET-UP is worth nothing by itself and everything to the swing behind it: Splash deals
		# no damage, so soaking a target scores (0,0) and a greedy chooser could never OPEN a
		# combo. One step of lookahead prices it by what a squadmate could then do (dev call,
		# pairs in v1, 2026-09-02), FLOORED AT ITS OWN SOLO SCORE -- see _lookahead for why
		# inventing a zero there inverts the ranking now that a negative score can still win.
		if not _beats(score, Vector3i.ZERO) and allow_lookahead and _applies_state_to_an_enemy(member.get_faction(), plan):
			score = _lookahead(member, candidate, score, squad, board, base_plan, squad_manager, reactions, terrain, refused, by_member)
		# A DEFERRED candidate is the family's own last resort (#726): it loses to every candidate
		# this member has NOT deferred and is still taken when it has nothing else, so #711 stays
		# literal -- the AI always attacks. MEMBER-LOCAL on purpose: decided here, never carried on
		# _Scored into the joint loop, where it would become a precedence across members (the
		# two-tier shape #720 deleted) and let one family's routine reorder another family's swing.
		if routine.defers_candidate(member, candidate, plan, score):
			if last_resort == null or _beats(score, last_resort.score):
				last_resort = _scored(candidate, score)
			continue
		if best == null or _beats(score, best.score):
			best = _scored(candidate, score)
	if best != null:
		return best
	return last_resort


static func _scored(action: AttackAction, score: Vector3i) -> _Scored:
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
# THE ACCUMULATOR STARTS AT THE SET-UP'S OWN SOLO SCORE, never at Vector3i.ZERO (#711). A zero floor
# was invisible while a candidate had to BEAT zero to queue -- it only ever turned a refusal into a
# refusal. With no bar it LAUNDERS: a set-up really worth (-1, 0, -5) came back (0,0,0) and then
# outranked an honest plain swing at (-1, 8, -4) on the first term, so a member facing a lethal
# counter soaked instead of hitting and died dealing nothing. A set-up is worth the better of what
# it does alone and what it enables; zero is not one of those two and must not be invented here.
static func _lookahead(setup_unit: Unit, setup: AttackAction, solo: Vector3i, squad: Squad, board: BoardContext,
		base_plan: ResolvedPlan, squad_manager: SquadManager, reactions: Array[ElementalReaction],
		terrain: Array[TerrainReaction], refused: Dictionary, by_member: Dictionary) -> Vector3i:
	var base := _score_plan(setup_unit.get_faction(), base_plan)
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
			var score := _score_plan(setup_unit.get_faction(), plan) - base
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
