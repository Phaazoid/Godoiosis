extends Object
class_name PlanResolver

# The one place consequences are derived (docs/design/resolution-pipeline.md, R1-R8).
# ONE pure pass over the ordered plan — attacks, then counters (R7) — threading a
# hypothetical {position, element states, HP, Will-slot} per unit forward (R4). Per hit:
# base damage -> elemental (-> Will in Phase 3). Writes one ResolvedOutcome per action
# (R8). Reads a snapshot, mutates no live state, contains no RNG (R2).

static func resolve(plan: ResolvedPlan, reactions: Array[ElementalReaction] = ReactionCatalog.get_all(), board: BoardContext = null, terrain_reactions: Array[TerrainReaction] = []) -> void:
	var hypo: Dictionary = {}   # Unit -> _Hypo (the threaded working copy)
	for atk in plan.attacks:
		_resolve_one(atk, reactions, hypo)
		# Cell-effect stage (#50): a map-hitting attack deposits terrain effects across its WHOLE
		# blast footprint, not just the aimed cell — parity with how AoE damage hits every cell.
		# Derived once per aim: a volley's secondaries share the footprint, so only its lead member
		# (is_secondary_hit == false) deposits. Runs only with a board (unit-only callers pass none);
		# counters still skip the stage (a later slice).
		if board != null and not atk.is_secondary_hit:
			for cell_effect in _resolve_cell_effects(atk, board, terrain_reactions):
				plan.cell_effects.append(cell_effect)
	for ctr in plan.counters:
		if not _counter_actor_live(ctr, hypo):
			var no_op := ResolvedOutcome.new()
			no_op.skipped = true
			ctr.resolved = no_op                    # counter-er is down/dead this pass -> no counter
			continue
		_resolve_one(ctr, reactions, hypo)
		# A live, map-hitting counter ignites its own footprint too (#50) — same channel as an
		# attack. Sits after the liveness `continue`, so a skipped counter never deposits; gated
		# identically (lead volley member only, board only).
		if board != null and not ctr.is_secondary_hit:
			for cell_effect in _resolve_cell_effects(ctr, board, terrain_reactions):
				plan.cell_effects.append(cell_effect)

static func _resolve_one(action: AttackAction, reactions: Array[ElementalReaction], hypo: Dictionary) -> void:
	var outcome := ResolvedOutcome.new()
	var attacker := action.actor
	var target := action.target
	if attacker == null or target == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		action.resolved = outcome
		return

	# --- base damage stage (E1: the calc that used to live in AttackAction.create) ---
	var base := _source_base_damage(action)
	outcome.base_damage = base

	# --- elemental stage: collect EVERY reaction matching the PRE-HIT snapshot (E8) ---
	var target_hypo: _Hypo = _hypo_for(target, hypo)
	var elements := _source_elements(action)
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
	outcome.lethality = _predict_lethality(target_hypo, outcome.damage)
	if outcome.lethality == ResolvedOutcome.Lethality.DOWNED:
		target_hypo.lifecycle = Unit.LifecycleState.DOWNED
		target_hypo.will -= UnitInstance.DOWN_WILL_COST
	elif outcome.lethality == ResolvedOutcome.Lethality.MAIMED:
		target_hypo.lifecycle = Unit.LifecycleState.DOWNED   # a maim IS a down — same lifecycle
		target_hypo.will = 0
	elif outcome.lethality == ResolvedOutcome.Lethality.CRISIS:
		target_hypo.in_crisis = true                          # the gambit: no safety net from here on
		target_hypo.will = 0
	elif outcome.lethality == ResolvedOutcome.Lethality.KILLED:
		target_hypo.lifecycle = Unit.LifecycleState.DEAD

	target_hypo.hp -= outcome.damage
	if outcome.lethality == ResolvedOutcome.Lethality.CRISIS:
		target_hypo.hp = Unit.CRISIS_REVIVE_HP                # stood back up mid-pass (enter_crisis)
	outcome.target_hp_after = target_hypo.hp

	action.resolved = outcome

# The attack's source surface: a fired transmutation (rune) if the order carries one, else the
# attacker's equipped weapon. A rune casts to null here -> it contributes nothing in melee (its
# attack rides on the transmutation instead). Both real sources expose base_damage(wielder) /
# get_elements() / hits_map(), so the resolver reads them uniformly and stays fully typed. #30.
static func _source_base_damage(action: AttackAction) -> int:
	var attacker := action.actor
	if action.transmutation != null:
		return action.transmutation.base_damage(attacker)
	var weapon := attacker.get_equipped_weapon() as WeaponData
	if weapon != null:
		return weapon.base_damage(attacker)
	return attacker.get_effective_stat(Stats.Stat.STR)

static func _source_elements(action: AttackAction) -> Array[Elemental.Element]:
	if action.transmutation != null:
		return action.transmutation.get_elements()
	var weapon := action.actor.get_equipped_weapon() as WeaponData
	if weapon != null:
		return weapon.get_elements()
	var none: Array[Elemental.Element] = []
	return none

static func _source_hits_map(action: AttackAction) -> bool:
	if action.transmutation != null:
		return action.transmutation.hits_map()
	var weapon := action.actor.get_equipped_weapon() as WeaponData
	return weapon != null and weapon.hits_map()

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
		h.can_maim = unit.unit_instance.next_maim_slot() != -1
		h.crisis_stance_accepts = unit.get_faction() != Team.Faction.PLAYER and AIArchetype.accepts_crisis(unit.squad.archetype)
		hypo[unit] = h
	return hypo[unit]

static func _predict_lethality(h: _Hypo, damage: int) -> ResolvedOutcome.Lethality:
	# Mirror of Unit.take_damage + _go_downed + the Crisis offer (Law #2 — preview must equal
	# execution). Takes the threaded hypo whole — eight loose params was a call-site hazard.
	#   already DEAD        -> no-op (NONE)
	#   already DOWNED      -> any hit kills (Fork 3: downed-attack = kill)
	#   damage < hp         -> survivable (NONE)
	#   overkill > ceiling  -> KILLED
	#   would-be-down       -> CRISIS if full-Will + stance accepts (deterministic, R9),
	#                          else MAIMED if Will can't pay and a limb remains, else DOWNED
	#
	# Crisis-in-progress is special (dev call 2026-06-26): it never downs/maims (a would-be-down
	# is death), and EVERY independently-lethal hit stays flagged KILLED even after the unit
	# "dies" earlier in the pass — the player must see that dodging one fatal counter won't
	# save them. "Independently lethal" = the hit alone would fell the unit at pass-start HP.
	if h.in_crisis:
		if h.lifecycle == Unit.LifecycleState.DEAD:
			return ResolvedOutcome.Lethality.KILLED if damage >= h.start_hp else ResolvedOutcome.Lethality.NONE
		if damage >= h.hp:
			return ResolvedOutcome.Lethality.KILLED
		return ResolvedOutcome.Lethality.NONE
	if h.lifecycle == Unit.LifecycleState.DEAD:
		return ResolvedOutcome.Lethality.NONE
	if h.lifecycle == Unit.LifecycleState.DOWNED:
		return ResolvedOutcome.Lethality.KILLED
	if damage < h.hp:
		return ResolvedOutcome.Lethality.NONE
	if damage - h.hp > Unit.OVERKILL_CEILING:
		return ResolvedOutcome.Lethality.KILLED
	if h.will >= Unit.CRISIS_WILL_GATE and h.crisis_stance_accepts:
		return ResolvedOutcome.Lethality.CRISIS   # stands back up surged — stances are deterministic
	if h.will < UnitInstance.DOWN_WILL_COST:
		return ResolvedOutcome.Lethality.MAIMED if h.can_maim else ResolvedOutcome.Lethality.DOWNED
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
	var can_maim: bool = true   # false = fully maimed at pass start; a down can't cost a limb
	var crisis_stance_accepts: bool = false   # non-player + stance ALWAYS -> a would-be-down previews CRISIS
	
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
	# The footprint is the SAME geometry the volley fired over (get_affected_cells_from), so the
	# deposit lands exactly where the blast did — every cell, occupied or not.
	for cell in attacker.combat.get_affected_cells_from(action.origin_cell, action.target_cell):
		var effect := _resolve_cell_effect_at(cell, elements, board, terrain_reactions)
		if effect != null:
			effects.append(effect)
	return effects

# One cell's terrain reaction: match the incoming elements against the tile's kind and return the
# resolved deposit, or null when no reaction fires there.
static func _resolve_cell_effect_at(cell: Vector2i, elements: Array[Elemental.Element], board: BoardContext, terrain_reactions: Array[TerrainReaction]) -> ResolvedCellEffect:
	var kind := board.terrain_kind_at(cell)
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	var fired := false
	for reaction in terrain_reactions:
		if not elements.has(reaction.incoming_element):
			continue
		if reaction.required_kind != Terrain.Kind.NONE and reaction.required_kind != kind:
			continue
		if reaction.required_tile_state != Terrain.TileState.NONE:
			if board.terrain_states == null or not board.terrain_states.has_state(cell, reaction.required_tile_state):
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
