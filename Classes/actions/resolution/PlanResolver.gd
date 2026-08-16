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
	for atk in group:
		_resolve_one(atk, reactions, hypo, board)
		if board != null and not atk.is_secondary_hit:
			for cell_effect in _resolve_cell_effects(atk, board, terrain_reactions):
				plan.cell_effects.append(cell_effect)

# Phase 2: counters, threaded off the SAME hypo so a counter-er downed by an attack this pass can't counter (R7).
static func resolve_counters(plan: ResolvedPlan, hypo: Dictionary, reactions: Array[ElementalReaction], board: BoardContext, terrain_reactions: Array[TerrainReaction]) -> void:
	for ctr in plan.counters:
		if not _counter_actor_live(ctr, hypo):
			var no_op := ResolvedOutcome.new()
			no_op.skipped = true
			ctr.resolved = no_op                    # counter-er is down/dead this pass -> no counter
			continue
		_resolve_one(ctr, reactions, hypo, board)
		if board != null and not ctr.is_secondary_hit:
			for cell_effect in _resolve_cell_effects(ctr, board, terrain_reactions):
				plan.cell_effects.append(cell_effect)

static func _resolve_one(action: AttackAction, reactions: Array[ElementalReaction], hypo: Dictionary, board: BoardContext = null) -> void:
	var outcome := ResolvedOutcome.new()
	var attacker := action.actor
	var target := action.target
	if attacker == null or target == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		action.resolved = outcome
		return

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
	var target_hypo: _Hypo = _hypo_for(target, hypo)
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
	var mitigation := _mitigation_for(action, target, target_hypo, board)
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

	# Will/death stage (R7): pick the rung from the now-final damage so the queue previews
	# it (Law #2). Reads pre-hit HP + Will, so it runs BEFORE the subtraction below. Same call
	# Unit.take_damage makes at execution time — one ladder, two callers.
	outcome.lethality = LethalityRules.predict(target_hypo, outcome.damage)
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

	# Displacement stage (#84): a knockback attack shoves the target directly away from the
	# attacker, stopping at the first wall/unit/edge, threaded into the hypo so a later hit this
	# pass sees the moved cell (R4). Needs a board to test cells; unit-only callers skip it.
	_resolve_knockback(action, outcome, target_hypo, board)

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
static func _mitigation_for(action: AttackAction, target: Unit, target_hypo: _Hypo, board: BoardContext) -> int:
	var weapon := action.actor.get_equipped_weapon() as WeaponInstance
	if weapon != null and weapon.ignores_def():
		return 0
	var def := RulesService.def_breakdown(target, target_hypo.position, board)
	return def["total"]

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

static func _resolve_knockback(action: AttackAction, outcome: ResolvedOutcome, target_hypo: _Hypo, board: BoardContext) -> void:
	var distance := _source_knockback(action)
	if distance <= 0 or board == null or outcome.lethality == ResolvedOutcome.Lethality.KILLED:
		return   # no shove: no knockback, no board to test cells, or the target is dead (leaving)
	var dir := GridUtils.cardinal_direction_i_between(action.origin_cell, target_hypo.position)
	if dir == Vector2i.ZERO:
		return
	var landing := target_hypo.position
	for _i in range(distance):
		var next: Vector2i = landing + dir
		# DECLARED, not an oversight (#115): a shove asks the CELL-level question
		# (BoardContext.is_walkable), never the per-unit one (RulesService.can_traverse) that
		# movement and GroupMoveSolver ask. So a Waterwalker is NOT shoved onto water — the
		# ability lets you walk there under your own power, and being thrown is not walking.
		# This is parked rather than settled: what a shove into a hazard should DO is #116
		# (off a cliff = a kill; into water = deliberately still an open question). Resolve it
		# there, not by quietly swapping the predicate here.
		if not board.is_walkable(next) or board.unit_at_cell(next) != null:
			break   # stop at the first wall / off-board / occupied cell
		landing = next
	if landing != target_hypo.position:
		outcome.knockback_applied = true
		outcome.knockback_from = target_hypo.position   # where THIS shove started (may be a prior shove's landing)
		outcome.knockback_to = landing
		target_hypo.position = landing   # thread it forward (R4)

static func _counter_actor_live(action: AttackAction, hypo: Dictionary) -> bool:
	# R7 liveness: a counter-er downed/killed earlier in the pass can't counter. The threaded
	# HP carries every attack's (and prior counter's) damage; <= 0 means a fatal hit landed on
	# this unit — downed or dead, either way no counter. The counter-er (action.actor) is only
	# in `hypo` if it was personally hit this pass; an untouched squadmate isn't -> still live.
	var counterer := action.actor
	if counterer == null or not hypo.has(counterer):
		return true
	return hypo[counterer].hp > 0

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

# The gambit's own rung, which lifecycle cannot report: a CRISIS target is never DOWNED (#158), so
# a readout asking "does this plan change where the unit stands" has to ask here too (#313).
static func projected_in_crisis(unit: Unit, hypo: Dictionary) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if not hypo.has(unit):
		return unit.in_crisis
	return (hypo[unit] as _Hypo).in_crisis

static func _hypo_for(unit: Unit, hypo: Dictionary) -> _Hypo:
	if not hypo.has(unit):
		var h := _Hypo.new()
		h.position = unit.get_projected_destination()
		h.states = unit.element_states.duplicate()
		h.hp = unit.get_current_hp()
		h.start_hp = unit.get_current_hp()
		h.lifecycle = unit.lifecycle_state
		h.will = unit.unit_instance.get_current_will()
		h.in_crisis = unit.in_crisis
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
