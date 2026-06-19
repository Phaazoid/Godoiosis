extends Object
class_name PlanResolver

# The one place consequences are derived (docs/design/resolution-pipeline.md, R1-R8).
# ONE pure pass over the ordered plan — attacks, then counters (R7) — threading a
# hypothetical {position, element states, HP, Will-slot} per unit forward (R4). Per hit:
# base damage -> elemental (-> Will in Phase 3). Writes one ResolvedOutcome per action
# (R8). Reads a snapshot, mutates no live state, contains no RNG (R2).

static func resolve(plan: ResolvedPlan, reactions: Array[ElementReaction] = ReactionCatalog.get_all()) -> void:
	var hypo: Dictionary = {}   # Unit -> _Hypo (the threaded working copy)
	for atk in plan.attacks:
		_resolve_one(atk, reactions, hypo)
	for ctr in plan.counters:
		if not _counter_actor_live(ctr, hypo):
			ctr.resolved = ResolvedOutcome.new()   # skipped — no-op playback (Phase 3)
			continue
		_resolve_one(ctr, reactions, hypo)

static func _resolve_one(action: AttackAction, reactions: Array[ElementReaction], hypo: Dictionary) -> void:
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
	target_hypo.hp -= outcome.damage
	outcome.target_hp_after = target_hypo.hp
	# (Will stage, Phase 3: read outcome.damage + target_hypo.hp here -> lifecycle.)

	action.resolved = outcome

static func _base_damage(attacker: Unit) -> int:
	var weapon := attacker.get_equipped_weapon()
	if weapon != null:
		return weapon.power + attacker.get_effective_stat(weapon.scaling_stat)
	return attacker.get_effective_stat("STR")

static func _elements_of(attacker: Unit) -> Array[Elemental.Element]:
	var result: Array[Elemental.Element] = []
	var weapon := attacker.get_equipped_weapon()
	if weapon != null and weapon.elemental_damage_type != Elemental.Element.NONE:
		result.append(weapon.elemental_damage_type)
	return result

static func _counter_actor_live(action: AttackAction, hypo: Dictionary) -> bool:
	# R7 liveness flag — always true in Phase 2. Phase 3's Will stage flips this on:
	# a counter-er downed/killed earlier in the pass cannot counter. The threaded HP
	# is already in `hypo` for that check.
	return true

static func _hypo_for(unit: Unit, hypo: Dictionary) -> _Hypo:
	if not hypo.has(unit):
		var h := _Hypo.new()
		h.position = unit.get_projected_destination()
		h.states = unit.element_states.duplicate()
		h.hp = unit.get_current_hp()
		hypo[unit] = h
	return hypo[unit]

# Per-unit threaded hypothetical (R4). Will-ready: HP is threaded now; `will` is the
# reserved Phase-3 slot.
class _Hypo:
	var position: Vector2i
	var states: Array[Elemental.State] = []
	var hp: int = 0
	# var will: int = 0   # Phase 3
