extends BaseAction
class_name TileHitAction

# What the tile a unit stands on does to it at the END OF ITS TURN (#419): its ground's damage (a
# burn), or since #508 the state the gas over it gives (a soak), or since #1260 the state the weather
# gives. Derived, never queued: the queue forecasts these from projected positions, the end-of-turn
# pass makes its own from live ones, and both build through make() / soaks() so what is previewed is
# what lands.

var state: Terrain.TileState = Terrain.TileState.NONE   # which tile state is charging
var gas := -1   # the Gas.Kind soaking, or -1
var weather := -1   # the Weather.Kind soaking, or -1
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
	var hit := _soak(unit, gained)
	hit.gas = kind
	return hit


# Everything that soaks this unit at its end of turn, in the order the pass plays it: the gas over
# its cell, then the weather over the board (#1260). The ONE composition both the forecast and the
# pass call, and the weather is asked with what the gas rows already add, so a unit in steam in the
# rain gets one Wet row rather than two.
static func soaks(unit: Unit, held: Array[Elemental.State], packed: int,
		sky: Weather.Kind) -> Array[TileHitAction]:
	var hits := gas_hits(unit, held, packed)
	var after: Array[Elemental.State] = held.duplicate()
	for hit in hits:
		after.append_array(hit.resolved.states_added)
	var rules := WeatherRules.for_kind(sky)
	if rules != null and rules.state != Elemental.State.NONE \
			and not after.has(rules.state) and not Elemental.is_blocked(after, rules.state):
		var hit := _soak(unit, rules.state)
		hit.weather = sky
		hits.append(hit)
	return hits


static func _soak(unit: Unit, gained: Elemental.State) -> TileHitAction:
	var hit := TileHitAction.new()
	hit.actor = unit
	hit.action_type = BaseAction.ActionType.TILE_HIT
	var outcome := ResolvedOutcome.new()
	outcome.reads_hp = false   # nobody is hit; the row must not print an HP arrow (#884)
	outcome.states_added.append(gained)
	hit.resolved = outcome
	return hit


# What soaked this unit, as the player reads it ("Steam", "Heavy Rain"); "" for a burn.
func soak_source_name() -> String:
	if gas >= 0:
		return Gas.display_name(gas as Gas.Kind)
	if weather >= 0:
		return Weather.display_name(weather as Weather.Kind)
	return ""


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
	if weather >= 0:
		return WeatherArt.icon()
	var lethal := AttackAction.lethality_icon(resolved)
	if lethal != null:
		return lethal
	var tex: Texture2D = OverlayManager.TERRAIN_STATE_ICONS.get(state, null)
	return tex


func get_description() -> String:
	var who := actor.get_unit_name() if actor != null and is_instance_valid(actor) else "?"
	var source := soak_source_name()
	if source != "":
		return "%s stands in %s" % [who, source]
	var amount := resolved.damage if resolved != null else 0
	return "%s takes %d from %s" % [who, amount, Terrain.tile_state_display_name(state)]
