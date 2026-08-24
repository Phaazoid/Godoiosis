extends Object
class_name PlanResolver

const INSULATED_POPUP := "Insulated!"

# The one place consequences are derived (docs/design/resolution-pipeline.md, R1-R8).
# ONE pure pass over the ordered plan — attacks, then counters (R7) — threading a
# hypothetical {position, element states, HP, Will-slot} per unit forward (R4). Per hit:
# base damage -> elemental (-> Will in Phase 3). Writes one ResolvedOutcome per action
# (R8). Reads a snapshot, mutates no live state, contains no RNG (R2).

static func resolve(plan: ResolvedPlan, reactions: Array[ElementalReaction] = ReactionCatalog.get_all(), board: BoardContext = null, terrain_reactions: Array[TerrainReaction] = []) -> void:
	# plan.hypo (Unit -> _Hypo) is shared across both phases so counter liveness sees the attacks,
	# and lives on the plan so end-of-pass state stays readable after the pass (#124).
	resolve_attacks(plan, plan.hypo, reactions, board, terrain_reactions)
	resolve_counters(plan, plan.hypo, reactions, board, terrain_reactions)

# Phase 1: the ordered attacks. Split out so SquadManager.resolve_plan can reflect knockback shoves
# into projected positions BEFORE deriving counters (#84 approach B) — a counter is judged from
# where a shoved unit LANDS, not where it stood.
static func resolve_attacks(plan: ResolvedPlan, hypo: Dictionary, reactions: Array[ElementalReaction], board: BoardContext, terrain_reactions: Array[TerrainReaction]) -> void:
	resolve_attack_group(plan.attacks, plan, hypo, reactions, board, terrain_reactions)

# One volley (or a lone cell attack), resolved against the SHARED hypo and appending its cell
# effects to the plan. Split out of resolve_attacks 2026-07-28 (#105) so SquadManager can interleave
# resolution with volley EXPANSION: a shove only becomes a projected position once its own attack
# has resolved, so expanding every volley up front put all victim-gathering strictly before all
# shoves — and no aim could ever see one.
static func resolve_attack_group(group: Array[AttackAction], plan: ResolvedPlan, hypo: Dictionary, reactions: Array[ElementalReaction], board: BoardContext, terrain_reactions: Array[TerrainReaction]) -> void:
	_apply_guards(group, plan, hypo)
	for atk in group:
		_resolve_one(atk, reactions, hypo, board)
		if board != null and not atk.is_secondary_hit:
			for cell_effect in _resolve_cell_effects(atk, board, terrain_reactions):
				plan.cell_effects.append(cell_effect)

# Phase 2: counters, threaded off the SAME hypo so a counter-er downed by an attack this pass can't counter (R7).
static func resolve_counters(plan: ResolvedPlan, hypo: Dictionary, reactions: Array[ElementalReaction], board: BoardContext, terrain_reactions: Array[TerrainReaction]) -> void:
	for ctr in plan.counters:
		# A counter is an attack with a volley like any other, so it gets the same one-blast-one-
		# moment read. plan.counters is FLAT (create_counter_volley's members are appended in
		# order), so the volley's lead member is where its snapshot is taken.
		if not ctr.is_secondary_hit:
			var volley: Array[AttackAction] = []
			if ctr.volley.is_empty():
				volley.append(ctr)      # hand-built counter (test fixtures); a real one always has one
			else:
				volley.assign(ctr.volley)
			_apply_guards(volley, plan, hypo)
		if not _counter_actor_live(ctr, hypo):
			var no_op := ResolvedOutcome.new()
			no_op.skipped = true
			ctr.resolved = no_op                    # counter-er is down/dead this pass -> no counter
			continue
		_resolve_one(ctr, reactions, hypo, board)
		if board != null and not ctr.is_secondary_hit:
			for cell_effect in _resolve_cell_effects(ctr, board, terrain_reactions):
				plan.cell_effects.append(cell_effect)

# --- Guard substitution (#414, docs/design/standing-reactions.md) ---------------------------
#
# ONE BLAST, ONE MOMENT: this runs once per volley, BEFORE any member resolves, so standing-reaction
# liveness (spent + lifecycle + range) is read at the volley's start and the outcome can never hinge
# on gather order — the order the player neither authors nor sees. Between volleys the answer moves
# freely: a shove earlier in the pass has already threaded new positions into the hypo.
#
# The substitution itself is a VICTIM REWRITE on the DERIVED action (resolve_plan expands every
# stored aim fresh each pass, #15), which is what makes "the entire payload, from the blocker's own
# cell" fall out with no second copy of anything: mitigation, elemental immunity, Iron Will, the
# knockback direction and landing, the elevation stamp, the lethality rung, execution's playback and
# the queue row all just run with a different victim. The player's stored aim is untouched.
static func _apply_guards(group: Array[AttackAction], plan: ResolvedPlan, hypo: Dictionary) -> void:
	if plan.guards.is_empty():
		return
	for action in group:
		# A substituted hit is never Guard-bait — no chains (ON HOLD, not buried: the doc leaves
		# the door open for a wanted tank conga). Walking the group once already guarantees it;
		# this says so out loud.
		if action.blocked_for != null:
			continue
		var guard := _guard_for(action, plan, hypo)
		if guard == null:
			continue
		action.blocked_for = action.target
		action.target = guard.blocker
		guard.spent = true              # a COPY (ResolvedPlan.guards); the live ward is spent by execution

# The Guard that catches this hit, or null. Order is arm order, so stacked Guards absorb
# earliest-first with no precedence rule of its own.
static func _guard_for(action: AttackAction, plan: ResolvedPlan, hypo: Dictionary) -> GuardWard:
	var victim := action.target
	if victim == null or not is_instance_valid(victim):
		return null                     # a cell-targeted attack (#47) has nobody to guard
	var attack := action.fired_attack
	if attack != null and (attack.heals or attack.deals_no_damage or attack.pierces_guard):
		return null                     # heals and pure utility pass through; pierce is the authored counter
	for guard in plan.guards:
		if guard.spent or not guard.is_intact() or guard.ward != victim:
			continue
		# A Guard cannot shield someone from its OWN swing. Only reachable through an AoE counter
		# (a unit gets one main action, so it can never both Guard and attack in one turn), and
		# absorbing your own attack for someone is incoherent rather than funny.
		if guard.blocker == action.actor:
			continue
		if projected_lifecycle(guard.blocker, hypo) != Unit.LifecycleState.ACTIVE:
			continue
		if not guard.pair_in_range(projected_position(guard.blocker, hypo), projected_position(victim, hypo)):
			continue
		return guard
	return null

static func _resolve_one(action: AttackAction, reactions: Array[ElementalReaction], hypo: Dictionary, board: BoardContext = null) -> void:
	var outcome := ResolvedOutcome.new()
	var attacker := action.actor
	var target := action.target
	if attacker == null or target == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		action.resolved = outcome
		return

	# Elevation stamp (#258): frozen origin (Law #2, same as fired_attack) against the THREADED
	# position — a shove earlier in the pass moves the target's level, and the delta must describe
	# the hit as previewed. Hoisted above the heal branch so heals carry it too; _hypo_for is
	# idempotent, so the heal branch re-fetching the same object costs nothing.
	var target_hypo: _Hypo = _hypo_for(target, hypo)
	if board != null:
		outcome.elevation_delta = board.elevation_at(target_hypo.position) - board.elevation_at(action.origin_cell)

	# --- base damage stage (E1: the calc that used to live in AttackAction.create) ---
	var base := _source_base_damage(action)
	outcome.base_damage = base

	# A heal short-circuits here: reinterprets `base` as HP restored, skips every hurt-only stage below.
	if action.fired_attack != null and action.fired_attack.heals:
		var heal_hypo: _Hypo = _hypo_for(target, hypo)
		var heal_amount := maxi(0, base)
		outcome.hp_before = heal_hypo.hp   # BEFORE the clamp below eats the overheal
		heal_hypo.hp = mini(heal_hypo.hp + heal_amount, target.get_max_hp())
		outcome.heal_amount = heal_amount
		outcome.target_hp_after = heal_hypo.hp
		action.resolved = outcome
		return

	# --- elemental stage: collect EVERY reaction matching the PRE-HIT snapshot (E8) ---
	outcome.hp_before = target_hypo.hp   # threaded pre-hit HP (R4), not the live board value
	var incoming := _source_elements(action)
	var elements := _surviving_elements(incoming, target)
	var fully_insulated := not incoming.is_empty() and elements.is_empty()
	if elements.size() < incoming.size():
		outcome.popups.append(INSULATED_POPUP)
	var mult := 1.0
	var bonus := 0
	var adds: Array[Elemental.State] = []
	var removes: Array[Elemental.State] = []
	var add_turns: Dictionary[Elemental.State, int] = {}
	for reaction in reactions:
		if not elements.has(reaction.incoming_element):
			continue
		if reaction.required_state != Elemental.State.NONE and not target_hypo.states.has(reaction.required_state):
			continue
		mult *= reaction.damage_mult
		bonus += reaction.damage_bonus
		for s in reaction.add_states:
			if not adds.has(s):
				adds.append(s)
			# Longest authored clock wins across fired reactions (max is commutative -> E8-safe).
			if reaction.add_state_turns.get(s, 0) > add_turns.get(s, 0):
				add_turns[s] = reaction.add_state_turns[s]
		for s in reaction.remove_states:
			if not removes.has(s):
				removes.append(s)
		if reaction.popup != "":
			outcome.popups.append(reaction.popup)
		if reaction.icon != null:
			outcome.reaction_icons.append(reaction.icon)

	# remove-wins on conflict -> net-disjoint delta sets
	var net_added: Array[Elemental.State] = []
	for s in adds:
		if not removes.has(s):
			net_added.append(s)
	outcome.states_added = net_added
	outcome.states_removed = removes
	for s in net_added:
		if add_turns.get(s, 0) > 0:
			outcome.state_turns[s] = add_turns[s]

	# final damage (E8): round(base * mult + bonus), then flat DEF mitigation (#84), never negative.
	# DEF subtracts AFTER elemental scaling and BEFORE the 0-floor; a revved Chainsword attacker
	# pierces it entirely. Iron Will (below) stays the last clamp — an absolute cap on damage taken.
	var mitigation := _mitigation_for(action, target, target_hypo, board, outcome)
	outcome.damage = max(0, int(round(base * mult + bonus)) - mitigation)

	# Insulation (a granted PASSIVE ability, #90 — from gear today, from any source the kit knows
	# tomorrow): an attack whose damage IS elemental -- a rune carving,
	# which scales off the wielder's AURA rather than their body -- is TURNED ASIDE ENTIRELY when
	# the armor blocks every element it carries. Deliberately NOT modelled as a 0-damage hit: a
	# 0-damage hit still ARRIVES (states, deposits, on-hit effects, and since #126 a shove -- the
	# early return below is what keeps this one from displacing anybody). The bolt never arrived,
	# so it does none of that. A weapon merely TAGGED with a blocked element skips this branch and
	# still lands its swing: insulation, not a shield.
	if fully_insulated and action.fired_attack is TransmutationData:
		outcome.damage = 0
		outcome.lethality = ResolvedOutcome.Lethality.NONE
		outcome.target_hp_after = target_hypo.hp
		action.resolved = outcome
		return

	# Falls (#259): the landing must be known BEFORE the rung is named, because fall damage can
	# change it -- so the landing computes here, off a PROVISIONAL rung (a hit that alone kills
	# leaves nothing to shove, the pre-#259 rule preserved), and only the FINAL predict below
	# feeds the Will-spend stage. predict is pure; the second call is the one that counts.
	var landing: _Landing = null
	if LethalityRules.predict(target_hypo, outcome.damage) != ResolvedOutcome.Lethality.KILLED:
		landing = _knockback_landing(action, target_hypo, board)
	if landing != null:
		# The landing measures in height UNITS; the outcome reports LEVELS, since that is what the
		# readout and the popup have always meant (#427). A half-level drop reports zero and costs
		# nothing -- dev, 2026-08-23.
		outcome.fall_levels = Terrain.level_of(landing.fall_units)
		if outcome.fall_levels > 0:
			# Falls bypass DEF (dev, 2026-08-20: armor does not stop gravity) -- added after
			# mitigation, before the Iron Will clamp so the cap stays absolute.
			outcome.fall_damage = FallRules.damage_for(landing.fall_units, target)
			outcome.damage += outcome.fall_damage
			outcome.popups.append("Fell %d!" % outcome.fall_levels)

	# Iron Will (Passive, docs/design/jobs.md "The ability chassis"): a deterministic per-hit
	# damage cap on the holder. Composes with the floor above as an ordinary clamp — order is
	# a non-issue since cap >= 0 makes max(0,min(cap,x)) == min(cap,max(0,x)) always.
	if target.has_live_ability(Abilities.Id.IRON_WILL):
		outcome.damage = mini(outcome.damage, Abilities.IRON_WILL_DAMAGE_CAP)

	# --- thread the hypothetical forward (R4) ---
	for s in outcome.states_removed:
		target_hypo.states.erase(s)
	for s in outcome.states_added:
		if not target_hypo.states.has(s):
			target_hypo.states.append(s)

	# Will/death stage (R7): pick the rung from the now-final damage (fall included) so the queue
	# previews it (Law #2). Reads pre-hit HP + Will, so it runs BEFORE the subtraction below. Same
	# call Unit.take_damage makes at execution time — one ladder, two callers.
	outcome.lethality = LethalityRules.predict(target_hypo, outcome.damage)
	if landing != null and landing.removed:
		# A void removal (#259) outranks the ladder: gone regardless of HP or Will. KILLED so
		# every reader threads DEAD; the flag is execution's own die() door.
		outcome.lethality = ResolvedOutcome.Lethality.KILLED
		outcome.removed = true
		outcome.popups.append("Into the void!")
	# The lifecycle a rung leaves behind is ONE map (#313) — a preview holding only an outcome reads
	# the same one. What a rung SPENDS stays here: it differs per rung and it is spent from the hypo.
	target_hypo.lifecycle = LethalityRules.lifecycle_for(outcome.lethality, target_hypo.lifecycle)
	if outcome.lethality == ResolvedOutcome.Lethality.DOWNED:
		target_hypo.will -= UnitInstance.DOWN_WILL_COST
	elif outcome.lethality == ResolvedOutcome.Lethality.MAIMED:
		target_hypo.will = 0
	elif outcome.lethality == ResolvedOutcome.Lethality.CRISIS:
		target_hypo.in_crisis = true                          # the gambit: no safety net from here on
		target_hypo.will = 0

	target_hypo.hp -= outcome.damage
	if outcome.lethality == ResolvedOutcome.Lethality.CRISIS:
		target_hypo.hp = Abilities.CRISIS_REVIVE_HP           # stood back up mid-pass (enter_crisis)
	outcome.target_hp_after = target_hypo.hp

	# Displacement stage (#84/#259): apply the landing computed above -- position threaded into
	# the hypo so a later hit this pass sees the moved cell (R4). The path is the trail's one
	# source (a landing tumble can bend it); from/to stay the endpoints execute reads.
	if landing != null and landing.path.size() > 1:
		outcome.knockback_applied = true
		outcome.knockback_from = landing.path[0]
		outcome.knockback_to = landing.cell
		outcome.knockback_path = landing.path
		outcome.knockback_landing_index = landing.landing_index
		target_hypo.position = landing.cell

	action.resolved = outcome

# Elements that survive the target's gear. A blocked element is erased from the hit entirely, so
# no reaction keyed on it can fire -- canon calls this shape "immune to SHOCK reactions"
# (elemental-interactions.md's GROUNDED state, the designed shock counter).
static func _surviving_elements(elements: Array[Elemental.Element], target: Unit) -> Array[Elemental.Element]:
	var kept: Array[Elemental.Element] = []
	for e in elements:
		if not target.is_immune_to(e):
			kept.append(e)
	return kept

# DEF mitigation (#84): the flat, gear-and-terrain damage reduction the target brings to THIS hit,
# read from RulesService's shared breakdown so the inspect panel's DEF readout is the same number.
# DEF is gear-and-terrain only (stats.md — no base DEF), so "ignore DEF bonuses" means ignore all
# of it: a revved Chainsword attacker (WeaponInstance.ignores_def()) returns 0, armor AND cover.
static func _mitigation_for(action: AttackAction, target: Unit, target_hypo: _Hypo, board: BoardContext, outcome: ResolvedOutcome) -> int:
	var weapon := action.actor.get_equipped_weapon() as WeaponInstance
	if weapon != null and weapon.ignores_def():
		return 0   # brace_bonus stays 0: a Chainsword pierces it with the rest of DEF
	var def := RulesService.def_breakdown(target, target_hypo.position, board)
	# The brace bonus (#414): extra DEF the blocker brings to a hit it ABSORBED, on top of its own
	# armour and cover, and only ever on a substituted instance -- which is why it is added here and
	# not inside def_breakdown, whose sum is also the inspect panel's standing DEF readout. Stamped
	# on the outcome in the same breath it is applied, so the queue row can never name a different
	# number than the one subtracted.
	if action.blocked_for != null:
		outcome.brace_bonus = target.get_brace_bonus()
	return def["total"] + outcome.brace_bonus

# The attack's source surface: the order's stamped fired_attack — a carving OR a specific weapon
# attack. A NULL stamp means this unit fired NO attack at all (bare fists, an aura-dry rune, a
# weapon with no authored main), and every question below answers accordingly.
#
# These used to fall back to the equipped weapon's MAIN when the stamp was null, which left `null`
# meaning "no attack" to the geometry layer (Reach) and "main" here — one value, two meanings, i.e.
# design law #4 one level down from #102 itself. Only hand-built actions ever hit it, because
# declare() and create_counter_volley always stamp, but several test suites were doing exactly that.
# Resolved 2026-07-28 (dev): null means no attack; a caller wanting main says so. Bare fists is
# now the same answer on both sides — STR damage here, adjacency-1 in Reach.
# A rune fails the WeaponAttackData check -> contributes nothing in melee (its attack rides on
# fired_attack instead). #30/#72.
static func _source_base_damage(action: AttackAction) -> int:
	var attacker := action.actor
	if action.fired_attack is TransmutationData:
		return (action.fired_attack as TransmutationData).base_damage(attacker)
	if action.fired_attack is WeaponAttackData:
		var weapon := attacker.get_equipped_weapon() as WeaponInstance
		if weapon != null:
			return weapon.base_damage(attacker, action.fired_attack as WeaponAttackData)
	return attacker.get_effective_stat(Stats.Stat.STR)

static func _source_elements(action: AttackAction) -> Array[Elemental.Element]:
	if action.fired_attack is TransmutationData:
		return (action.fired_attack as TransmutationData).get_elements()
	if action.fired_attack is WeaponAttackData:
		var weapon := action.actor.get_equipped_weapon() as WeaponInstance
		if weapon != null:
			return weapon.get_elements(action.actor, action.fired_attack as WeaponAttackData)
	var none: Array[Elemental.Element] = []
	return none

# hits_map() lives on the shared AttackData base, so both kinds answer it directly — and with the
# fallback gone, WeaponInstance.hits_map()'s only remaining job was that fallback, so it's deleted.
static func _source_hits_map(action: AttackAction) -> bool:
	return action.fired_attack != null and action.fired_attack.hits_map()

static func _source_knockback(action: AttackAction) -> int:
	if action.fired_attack != null:
		return action.fired_attack.knockback   # on the shared AttackData base — no cast needed
	return 0   # counters fire main (no stamped attack) — no shove

# One shove's full result (#259): where it ends, every cell it crosses, and what the landing does.
class _Landing:
	var cell: Vector2i
	var path: Array[Vector2i] = []   # start + every cell entered, flight then tumble
	var landing_index := 0           # path index where flight ends -- the drop cell; tumble follows
	var fall_units := 0              # in height units (#427); the outcome converts to whole levels
	var removed := false


# The AIRBORNE shove (#259, dev: "the drop occurs where the shove would move the unit to" -- so
# you can blow an ally over a hole to safety). The unit flies its knockback distance at its
# STARTING elevation; the landing resolves wherever the horizontal travel ends, whether the
# distance ran out or a blocker halted it early. Pure -- reads the hypo position, mutates nothing;
# _resolve_one applies the result after the rung is named.
static func _knockback_landing(action: AttackAction, target_hypo: _Hypo, board: BoardContext) -> _Landing:
	var distance := _source_knockback(action)
	if distance <= 0 or board == null:
		return null
	var dir := GridUtils.cardinal_direction_i_between(action.origin_cell, target_hypo.position)
	if dir == Vector2i.ZERO:
		return null

	var start := target_hypo.position
	var flight_height := board.elevation_at(start)
	var pos := start
	var path: Array[Vector2i] = [start]
	for _i in range(distance):
		var next: Vector2i = pos + dir
		if board.elevation_at(next) > flight_height:
			break   # you cannot be pushed uphill -- high ground braces you (#259)
		if board.terrain_kind_at(next) == Terrain.Kind.VOID:
			pos = next
			path.append(pos)
			continue   # airborne: a hole cannot catch you mid-flight
		# DECLARED, not an oversight (#115): a shove asks the CELL-level question
		# (BoardContext.is_walkable), never the per-unit one (RulesService.can_traverse) that
		# movement and GroupMoveSolver ask. So a Waterwalker is NOT shoved onto water — the
		# ability lets you walk there under your own power, and being thrown is not walking.
		# Water therefore still stops a shove at the shoreline: what a shove INTO water should
		# DO is #116's deliberately open fork (#259 resolved the cliff and the void, not this).
		if not board.is_walkable(next) or board.unit_at_cell(next) != null:
			break   # wall / water / off-board / occupied: today's rule, unchanged
		pos = next
		path.append(pos)
	if pos == start:
		return null

	var landing := _Landing.new()
	landing.path = path
	landing.cell = pos
	landing.landing_index = path.size() - 1   # flight ends here; _tumble appends beyond it
	if board.terrain_kind_at(pos) == Terrain.Kind.VOID:
		landing.removed = true   # halted over (or blown exactly onto) the hole -- gone
		return landing

	var corners := board.corners_at(pos)
	var drop := flight_height - board.elevation_at(pos)
	# The doc's original tumble entry: a connected descending slope -- the edge the flight ARRIVES
	# over meets the flight level, so sliding on is not a fall ("slopes never deal fall damage").
	#
	# ONE edge comparison since #427 slice 3, where it was three clauses (a rise, its climb, and the
	# direction it faced). The entry edge sitting level with the flight is exactly what those three
	# said together for a cardinal ramp, and it keeps meaning the same thing for a form they could
	# not describe. A corner slope whose arrival edge is level catches the flight; one that arrives
	# at a sloped edge does not, which is the honest answer rather than a special case.
	if Terrain.edge_of_corners(corners, -dir) == Vector2i(flight_height, flight_height):
		drop = 0
	landing.fall_units = drop
	# "When a unit lands, if they land on a slope, they tumble down that too" (dev, 2026-08-20).
	if Terrain.climb_of_corners(corners) > 0:
		_tumble(landing, board, dir)
	return landing


# The tumble (#259): from a slope, slide its downhill -- continuing down slopes that keep descending
# the same way -- until the first walkable, unoccupied cell level with the current one catches it.
# A wall, a rise, an occupied cell, water or a hole stops it where it stands: no launch, no fall
# damage on those. A sheer DROP below the slope's base (the deferred tumble-then-plummet) does NOT
# stop it any more: the unit falls the remaining height -- fall damage, folded into fall_units --
# and keeps whatever descent waits below (another slope tumbles again, a flat cell catches it).
# Terminates by construction -- every continuation strictly descends.
#
# WHICH WAY IS DOWNHILL is a cardinal question and a corner form's answer is diagonal, which the step
# vocabulary cannot express. The dev's ruling (2026-08-23): "For now, keep the tumble in the
# direction the unit was shoved. We can eyeball it from there." So a cardinal ramp keeps sliding down
# its OWN slope exactly as before, and a form that has no cardinal downhill carries on the way the
# shove was already going -- provisional, and the one thing in this slice meant to be judged by eye.
static func _tumble(landing: _Landing, board: BoardContext, shove_dir: Vector2i) -> void:
	var cell := landing.cell
	while true:
		var rise := board.ramp_rise_at(cell)
		var down := shove_dir if rise == Terrain.RampRise.NONE else -Terrain.rise_direction(rise)
		var next: Vector2i = cell + down
		if board.unit_at_cell(next) != null or board.terrain_kind_at(next) == Terrain.Kind.VOID \
				or not board.is_walkable(next):
			break
		var here_elev := board.elevation_at(cell)
		var next_elev := board.elevation_at(next)
		# Another CARDINAL ramp continuing down the same slope: continuity is its HIGH edge meeting
		# this cell's base (#427 slice 2), so a chain of gentle slopes flows exactly like a chain of
		# steep ones and a mixed chain still only joins where the surfaces actually touch.
		#
		# `rise != NONE` is what keeps this branch from swallowing the others (#427 slice 3), and it
		# is load-bearing rather than tidy: a corner form reads NONE, and without the guard a FLAT
		# next cell at the same height would satisfy "same rise, climbs match" and chain forever
		# instead of catching. The loop terminates because every continuation strictly descends, and
		# that is only true while a continuation requires a climb.
		if rise != Terrain.RampRise.NONE and board.ramp_rise_at(next) == rise \
				and next_elev + board.ramp_climb_at(next) == here_elev:
			cell = next
			landing.path.append(cell)
			continue
		if next_elev == here_elev:
			cell = next
			landing.path.append(cell)
			break   # the first flat or level cell it can legally enter -- the landing catches it
		if next_elev < here_elev:
			# Tumble-then-plummet: the slope bottoms out at a sheer drop, so the unit falls the
			# remaining levels and keeps whatever descent waits below.
			landing.fall_units += here_elev - next_elev
			cell = next
			landing.path.append(cell)
			# ANY slope tumbles again, corner forms included -- "if they land on a slope, they tumble
			# down that too" is about the ground being sloped, not about it having a cardinal name.
			if Terrain.climb_of_corners(board.corners_at(next)) > 0:
				continue
			break   # lands on a flat cell at the lower level -- the landing catches it
		break   # a rise: stop where it stands
	landing.cell = cell

static func _counter_actor_live(action: AttackAction, hypo: Dictionary) -> bool:
	# R7 liveness: a counter-er downed/killed earlier in the pass can't counter. The threaded
	# HP carries every attack's (and prior counter's) damage; <= 0 means a fatal hit landed on
	# this unit — downed or dead, either way no counter. A VOID removal is the one kill that
	# leaves HP untouched (the drop deals no HP), so the lifecycle term below catches it: KILLED
	# threads DEAD while hp stays > 0. The counter-er (action.actor) is only in `hypo` if it was
	# personally hit this pass; an untouched squadmate isn't -> still live.
	var counterer := action.actor
	if counterer == null or not hypo.has(counterer):
		return true
	return hypo[counterer].hp > 0 and hypo[counterer].lifecycle == Unit.LifecycleState.ACTIVE

# --- Reading the threaded hypothetical from outside the pass (R4) ---
# A derivation that runs MID-pass -- SquadManager's reaction targeting, after the attacks have
# resolved -- must judge a unit by what this pass has already done to it, not by the live board:
# damage lives only in the hypo until execution. A unit nothing has touched yet has no hypo entry
# at all, and its live value IS its projected one. Read-only on purpose: unlike _hypo_for, these
# never seed an entry, so asking a question cannot alter the pass.
static func projected_hp(unit: Unit, hypo: Dictionary) -> int:
	if unit == null or not is_instance_valid(unit):
		return 0
	if not hypo.has(unit):
		return unit.get_current_hp()
	return (hypo[unit] as _Hypo).hp

static func projected_lifecycle(unit: Unit, hypo: Dictionary) -> Unit.LifecycleState:
	if unit == null or not is_instance_valid(unit):
		return Unit.LifecycleState.DEAD
	if not hypo.has(unit):
		return unit.lifecycle_state
	return (hypo[unit] as _Hypo).lifecycle

# Where the pass has put the unit so far — a shove earlier in this plan has already threaded its
# landing here (#414's range check reads it, so a mid-pass displacement really does move who is
# still covered). Same read-only contract as the two above: a unit the pass has not touched has no
# entry, and its live projection IS its answer.
static func projected_position(unit: Unit, hypo: Dictionary) -> Vector2i:
	if unit == null or not is_instance_valid(unit):
		return Vector2i.ZERO
	if not hypo.has(unit):
		return unit.get_projected_destination()
	return (hypo[unit] as _Hypo).position

# Does this pass MOVE the unit's rung -- the alarm's question (#313), re-asked against the hypo's own
# baseline rather than the live unit (#354). DOWNED and MAIMED move the lifecycle, KILLED moves it
# further, and CRISIS moves neither (it is never DOWNED, #158), which is why crisis is asked
# separately. A unit already down, or already in Crisis, stays put and does not alarm.
static func plan_fells(unit: Unit, hypo: Dictionary) -> bool:
	if unit == null or not is_instance_valid(unit) or not hypo.has(unit):
		return false
	var h := hypo[unit] as _Hypo
	return h.lifecycle != h.start_lifecycle or (h.in_crisis and not h.start_in_crisis)

# Does this pass change the unit at all -- WHO the readout is for (#354). Wholly internal to the
# hypo, so the answer is settled when the plan is and cannot go false as execution applies the very
# damage it predicted. That is the whole bug: asked against live HP, each bar switched off at the
# instant its own hit landed.
#
# Asking the RAW threaded number rather than the displayed one also fixes the boundary the display
# clamp hides: a unit at 1 HP felled by this pass threads to zero-or-below and shows as 1, so the
# two displayed numbers collide and "differs from current" reported no change at all. Same shape at
# CRISIS_REVIVE_HP, where the hypo's hp lands back on the number it started from and only the crisis
# flag moves -- which is what plan_fells is doing in this expression.
static func plan_changes(unit: Unit, hypo: Dictionary) -> bool:
	if unit == null or not is_instance_valid(unit) or not hypo.has(unit):
		return false
	var h := hypo[unit] as _Hypo
	return h.hp != h.start_hp or plan_fells(unit, hypo)

static func _hypo_for(unit: Unit, hypo: Dictionary) -> _Hypo:
	if not hypo.has(unit):
		var h := _Hypo.new()
		h.position = unit.get_projected_destination()
		h.states = unit.element_states.duplicate()
		h.hp = unit.get_current_hp()
		h.start_hp = unit.get_current_hp()
		h.lifecycle = unit.lifecycle_state
		h.start_lifecycle = unit.lifecycle_state
		h.will = unit.unit_instance.get_current_will()
		h.in_crisis = unit.in_crisis
		h.start_in_crisis = unit.in_crisis
		h.can_maim = unit.unit_instance.next_maim_slot() != -1
		h.crisis_armed = LethalityRules.crisis_armed_for(unit)
		hypo[unit] = h
	return hypo[unit]

# Per-unit threaded hypothetical (R4). Everything the lethality ladder reads lives on the
# LethalityRules.Situation base, so a hypo IS a situation and _predict_lethality is just
# LethalityRules.predict — no second copy of the ladder to keep in sync (Law #2). This class
# adds only what the rest of the pass threads: the projected cell and the element states.
#
# STAT MODIFIERS ARE DELIBERATELY NOT THREADED (#112, verified 2026-07-29). It looks like the
# obvious next field beside `states`, and it isn't — yet:
#
#   * Every stat-derived number (base damage, DEF mitigation) is computed ONCE here at plan time
#     and frozen onto the ResolvedOutcome; AttackAction.execute is pure playback (R3).
#   * The one thing execution DOES recompute — LethalityRules.predict, via Unit.take_damage — reads
#     hp/will/lifecycle/limbs and no effective stat at all.
#
# So a stat change landing mid-pass (today only a maim's forced unequip, Unit._settle_stat_change)
# cannot make preview and execution disagree. It is un-modelled identically by both halves — a
# fidelity gap, not a Law #2 break. Both bullets are pinned by tests/law/test_resolution_laws.gd.
#
# Threading becomes OWED the moment a QUEUED ACTION applies an effect — a transmutation buffing an
# ally, a tonic — because then one order's stat change has to reach a later order's damage in the
# same plan. That is issue #113, and this comment is the first item on its checklist.
class _Hypo extends LethalityRules.Situation:
	var position: Vector2i
	var states: Array[Elemental.State] = []
	# The rung the unit stood at when this hypo was seeded, beside the base's start_hp (#354). The
	# threaded lifecycle/in_crisis above are mutated as the pass resolves, so without these the
	# question "did this pass MOVE the unit" can only be asked against the live board — which drifts
	# the moment execution starts applying what the plan predicted.
	var start_lifecycle: Unit.LifecycleState = Unit.LifecycleState.ACTIVE
	var start_in_crisis := false

# Cell-effect stage (#50 / the #47 cell-effect channel). A map-hitting attack deposits its
# element(s) across EVERY cell of its blast footprint — AoE parity with damage, which already
# hits every affected cell. Terrain reactions turn each into tile-state changes (FIRE on a tree ->
# BURNING). Pure like the rest of the pass — reads the board snapshot, returns one ResolvedCellEffect
# per reacting cell. Empty when nothing fires: a unit-only attack, no element, or no cell reacts.
static func _resolve_cell_effects(action: AttackAction, board: BoardContext, terrain_reactions: Array[TerrainReaction]) -> Array[ResolvedCellEffect]:
	var effects: Array[ResolvedCellEffect] = []
	var attacker := action.actor
	if attacker == null or not is_instance_valid(attacker):
		return effects
	if not _source_hits_map(action):
		return effects                                  # unit-only attack -> deposits nothing
	var elements := _source_elements(action)
	if elements.is_empty():
		return effects
	# The footprint is the SAME geometry the volley fired over, because both are derived from this
	# order's own stamped attack (#102) — not, as before, from whatever the attacker happens to
	# have picked right now. The deposit lands exactly where the blast did — every cell, occupied
	# or not.
	for cell in Reach.get_affected_cells_from(attacker, action.origin_cell, action.target_cell, action.fired_attack):
		var effect := _resolve_cell_effect_at(cell, elements, board, terrain_reactions)
		if effect != null:
			effects.append(effect)
	return effects

# One cell's terrain reaction: match the incoming elements against the tile's kind and return the
# resolved deposit, or null when no reaction fires there.
static func _resolve_cell_effect_at(cell: Vector2i, elements: Array[Elemental.Element], board: BoardContext, terrain_reactions: Array[TerrainReaction]) -> ResolvedCellEffect:
	var kind := board.terrain_kind_at(cell)
	var held: Array[Terrain.TileState] = []
	if board.terrain_states != null:
		held = board.terrain_states.states_at(cell)
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	var fired := false
	for reaction in terrain_reactions:
		if not elements.has(reaction.incoming_element):
			continue
		# The kind/state gate is the reaction's own predicate — shared with the tile hover card's
		# interaction list (#135), so the card can never promise a deposit this filter refuses.
		if not reaction.applies_to_tile(kind, held):
			continue
		for s in reaction.add_tile_states:
			if not effect.states_added.has(s):
				effect.states_added.append(s)
		for s in reaction.remove_tile_states:
			if not effect.states_removed.has(s):
				effect.states_removed.append(s)
		if reaction.popup != "":
			effect.popups.append(reaction.popup)
		if reaction.icon != null:
			effect.icons.append(reaction.icon)
		fired = true
	return effect if fired else null
