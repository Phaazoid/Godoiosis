extends Object
class_name PlanResolver

# The one place consequences are derived (docs/design/resolution-pipeline.md, R1-R8).
# ONE pure pass over the ordered plan — attacks, then counters (R7) — threading a
# hypothetical {position, element states, HP, Will-slot} per unit forward (R4). Per hit:
# base damage -> elemental (-> Will in Phase 3). Writes one ResolvedOutcome per action
# (R8). Reads a snapshot, mutates no live state, contains no RNG (R2).

static func resolve(plan: ResolvedPlan, reactions: Array[ElementalReaction] = ReactionCatalog.get_all()) -> void:
	var hypo: Dictionary = {}   # Unit -> _Hypo (the threaded working copy)
	for atk in plan.attacks:
		_resolve_one(atk, reactions, hypo)
	for ctr in plan.counters:
		if not _counter_actor_live(ctr, hypo):
			var no_op := ResolvedOutcome.new()
			no_op.skipped = true
			ctr.resolved = no_op                    # counter-er is down/dead this pass -> no counter
			continue
		_resolve_one(ctr, reactions, hypo)

static func _resolve_one(action: AttackAction, reactions: Array[ElementalReaction], hypo: Dictionary) -> void:
	var outcome := ResolvedOutcome.new()
	var attacker := action.actor
	var target := action.target
	if attacker == null or target == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		action.resolved = outcome
		return

	# --- base damage stage (E1: the calc that used to live in AttackAction.create) ---
	var base := _base_damage(attacker)
	outcome.base_damage = base

	# --- elemental stage: collect EVERY reaction matching the PRE-HIT snapshot (E8) ---
	var target_hypo: _Hypo = _hypo_for(target, hypo)
	var elements := _elements_of(attacker)
	var mult := 1.0
	var bonus := 0
	var adds: Array[Elemental.State] = []
	var removes: Array[Elemental.State] = []
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

	# final damage (E8): round(base * Pi(mult) + Sum(bonus)), never negative
	outcome.damage = max(0, int(round(base * mult + bonus)))

	# --- thread the hypothetical forward (R4) ---
	for s in outcome.states_removed:
		target_hypo.states.erase(s)
	for s in outcome.states_added:
		if not target_hypo.states.has(s):
			target_hypo.states.append(s)

	# Will/death stage (R7): pick the rung from the now-final damage so the queue previews
	# it (Law #2). Reads pre-hit HP + Will, so it runs BEFORE the subtraction below.
	outcome.lethality = _predict_lethality(target_hypo.lifecycle, target_hypo.hp, target_hypo.will, outcome.damage, target_hypo.in_crisis, target_hypo.start_hp)
	if outcome.lethality == ResolvedOutcome.Lethality.DOWNED:
		target_hypo.lifecycle = Unit.LifecycleState.DOWNED
		target_hypo.will -= UnitInstance.DOWN_WILL_COST
	elif outcome.lethality == ResolvedOutcome.Lethality.MAIMED:
		target_hypo.lifecycle = Unit.LifecycleState.DOWNED   # a maim IS a down — same lifecycle
		target_hypo.will = 0
	elif outcome.lethality == ResolvedOutcome.Lethality.KILLED:
		target_hypo.lifecycle = Unit.LifecycleState.DEAD

	target_hypo.hp -= outcome.damage
	outcome.target_hp_after = target_hypo.hp

	action.resolved = outcome

static func _base_damage(attacker: Unit) -> int:
	var weapon := attacker.get_equipped_weapon()
	if weapon != null:
		return weapon.base_damage(attacker)
	return attacker.get_effective_stat(Stats.Stat.STR)
	
static func _elements_of(attacker: Unit) -> Array[Elemental.Element]:
	var result: Array[Elemental.Element] = []
	var weapon := attacker.get_equipped_weapon()
	if weapon != null and weapon.elemental_damage_type != Elemental.Element.NONE:
		result.append(weapon.elemental_damage_type)
	return result

static func _counter_actor_live(action: AttackAction, hypo: Dictionary) -> bool:
	# R7 liveness: a counter-er downed/killed earlier in the pass can't counter. The threaded
	# HP carries every attack's (and prior counter's) damage; <= 0 means a fatal hit landed on
	# this unit — downed or dead, either way no counter. The counter-er (action.actor) is only
	# in `hypo` if it was personally hit this pass; an untouched squadmate isn't -> still live.
	var counterer := action.actor
	if counterer == null or not hypo.has(counterer):
		return true
	return hypo[counterer].hp > 0

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
		hypo[unit] = h
	return hypo[unit]

static func _predict_lethality(lifecycle: Unit.LifecycleState, hp_before: int, will_before: int, damage: int, in_crisis: bool, start_hp: int) -> ResolvedOutcome.Lethality:
	# Mirror of Unit.take_damage + _go_downed (Law #2 — preview must equal execution):
	#   already DEAD        -> no-op (NONE)
	#   already DOWNED      -> any hit kills (Fork 3: downed-attack = kill)
	#   damage < hp         -> survivable (NONE)
	#   overkill > ceiling  -> KILLED
	#   otherwise           -> a down; MAIMED if Will can't pay the flat cost, else DOWNED
	#
	# Crisis is special (dev call 2026-06-26): it never downs/maims (a would-be-down is death),
	# and EVERY independently-lethal hit stays flagged KILLED even after the unit "dies" earlier
	# in the pass — the player must see that dodging one fatal counter won't save them; the others
	# kill too. "Independently lethal" = the hit alone would fell the unit at its pass-start HP.
	# (Execution still only kills once; the extra skulls telegraph stakes, not damage.)
	if in_crisis:
		if lifecycle == Unit.LifecycleState.DEAD:
			return ResolvedOutcome.Lethality.KILLED if damage >= start_hp else ResolvedOutcome.Lethality.NONE
		if damage >= hp_before:
			return ResolvedOutcome.Lethality.KILLED
		return ResolvedOutcome.Lethality.NONE
	if lifecycle == Unit.LifecycleState.DEAD:
		return ResolvedOutcome.Lethality.NONE
	if lifecycle == Unit.LifecycleState.DOWNED:
		return ResolvedOutcome.Lethality.KILLED
	if damage < hp_before:
		return ResolvedOutcome.Lethality.NONE
	if damage - hp_before > Unit.OVERKILL_CEILING:
		return ResolvedOutcome.Lethality.KILLED
	if will_before < UnitInstance.DOWN_WILL_COST:
		return ResolvedOutcome.Lethality.MAIMED
	return ResolvedOutcome.Lethality.DOWNED

# Per-unit threaded hypothetical (R4). Will-ready: HP is threaded now; `will` is the
# reserved Phase-3 slot.
class _Hypo:
	var position: Vector2i
	var states: Array[Elemental.State] = []
	var hp: int = 0
	var lifecycle: Unit.LifecycleState = Unit.LifecycleState.ACTIVE
	var will: int = 0   # threaded so a multi-hit pass previews maim correctly (Law #2)
	var in_crisis: bool = false   # crisis units die instead of downing — mirror take_damage's short-circuit
	var start_hp: int = 0   # HP at pass start — a crisis hit is "independently lethal" if damage >= this
