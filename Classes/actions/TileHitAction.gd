extends BaseAction
class_name TileHitAction

# What the tile a unit stands on does to it at the END OF ITS TURN (#419): its ground's damage (a
# burn), or since #508 the state the gas over it gives (a soak). Derived, never queued: the queue
# forecasts these from projected positions, the end-of-turn pass makes its own from live ones, and
# both build through make() / gas_hits() so what is previewed is what lands.

var state: Terrain.TileState = Terrain.TileState.NONE   # which tile state is charging
var gas := -1   # the Gas.Kind soaking, or -1 for a burn
var resolved: ResolvedOutcome = null


# `situation` is whose HP/lifecycle the rung is predicted against — the pass's threaded
# hypothetical at plan time, the live unit at execution.
static func make(unit: Unit, tile_state: Terrain.TileState, damage: int,
		situation: LethalityRules.Situation) -> TileHitAction:
	var hit := TileHitAction.new()
	hit.actor = unit
	hit.action_type = BaseAction.ActionType.TILE_HIT
	hit.state = tile_state
	var outcome := ResolvedOutcome.new()
	outcome.base_damage = damage
	outcome.damage = damage
	outcome.hp_before = situation.hp
	# The rung FIRST: what a burn leaves behind is the rung's answer, not a subtraction (#1002).
	# Spelling it here is how a burn that downed a unit previewed 3->0 where the attack path said 1,
	# and how one that triggered Crisis previewed 0 against an execution that stands them up at 5.
	outcome.lethality = LethalityRules.predict(situation, damage)
	outcome.target_hp_after = LethalityRules.hp_after(outcome.lethality, situation.hp, damage)
	hit.resolved = outcome
	return hit


# The gas over this unit's cell (`packed`, Gas.with_level's form): one row per kind whose rules name a
# state, from its authored level up -- unless `held` already has it or holds one that keeps it off.
# Idempotent like a wade's soak: a row says what CHANGED, so an already-wet unit grows none.
static func gas_hits(unit: Unit, held: Array[Elemental.State], packed: int) -> Array[TileHitAction]:
	var hits: Array[TileHitAction] = []
	for kind: Gas.Kind in Gas.kinds_in(packed):
		var rules := GasRules.for_kind(kind)
		if rules == null or rules.state == Elemental.State.NONE:
			continue
		if Gas.level_in(packed, kind) < rules.state_from:
			continue
		if held.has(rules.state) or Elemental.is_blocked(held, rules.state):
			continue
		hits.append(make_gas(unit, kind, rules.state))
	return hits


static func make_gas(unit: Unit, kind: Gas.Kind, gained: Elemental.State) -> TileHitAction:
	var hit := TileHitAction.new()
	hit.actor = unit
	hit.action_type = BaseAction.ActionType.TILE_HIT
	hit.gas = kind
	var outcome := ResolvedOutcome.new()
	outcome.reads_hp = false   # nobody is hit; the row must not print an HP arrow (#884)
	outcome.states_added.append(gained)
	hit.resolved = outcome
	return hit


func execute() -> void:
	begin_execution()
	if actor != null and is_instance_valid(actor) and resolved != null:
		if resolved.damage > 0:
			actor.take_damage(resolved.damage, resolved.damage)   # the ground is never a blow (#1174)
		for gained in resolved.states_added:
			actor.add_element_state(gained)
	finish_execution()


func resolved_outcome() -> ResolvedOutcome:
	return resolved


func is_reorderable() -> bool:
	return false   # derived, never queued — nobody ordered the fire


func get_action_icon() -> Texture2D:
	if gas >= 0:
		return GasPuffArt.icon(gas as Gas.Kind)
	var lethal := AttackAction.lethality_icon(resolved)
	if lethal != null:
		return lethal
	var tex: Texture2D = OverlayManager.TERRAIN_STATE_ICONS.get(state, null)
	return tex


func get_description() -> String:
	var who := actor.get_unit_name() if actor != null and is_instance_valid(actor) else "?"
	if gas >= 0:
		return "%s stands in %s" % [who, Gas.display_name(gas as Gas.Kind)]
	var amount := resolved.damage if resolved != null else 0
	return "%s takes %d from %s" % [who, amount, Terrain.tile_state_display_name(state)]
