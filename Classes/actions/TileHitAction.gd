extends BaseAction
class_name TileHitAction

# What the tile a unit stands on does to it at the END OF ITS TURN (#419): its ground's damage (a
# burn), or since #508 what the gas over it does (a soak, and since #1331 steam's scald, on one row),
# or since #1260 the state the weather gives. Derived, never queued: the queue forecasts these from
# projected positions, the end-of-turn pass makes its own from live ones, and both build through
# end_of_turn() so what is previewed is what lands.

var state: Terrain.TileState = Terrain.TileState.NONE   # which tile state is charging
var gas := -1   # the Gas.Kind soaking or scalding, or -1
var weather := -1   # the Weather.Kind soaking, or -1
var resolved: ResolvedOutcome = null


# `body` is what the rung is predicted against (end_of_turn hands it the copy its rows thread). It is
# not written; the actor is its unit.
static func make(body: UnitState, tile_state: Terrain.TileState, damage: int) -> TileHitAction:
	var hit := TileHitAction.new()
	hit.actor = body.unit
	hit.action_type = BaseAction.ActionType.TILE_HIT
	hit.state = tile_state
	var outcome := ResolvedOutcome.new()
	outcome.base_damage = damage
	outcome.damage = damage
	outcome.hp_before = body.get_current_hp()
	# The rung FIRST: what a burn leaves behind is the rung's answer, not a subtraction (#1002).
	# Spelling it here is how a burn that downed a unit previewed 3->0 where the attack path said 1,
	# and how one that triggered Crisis previewed 0 against an execution that stands them up at 5.
	outcome.lethality = LethalityRules.predict(body, damage)
	outcome.target_hp_after = LethalityRules.hp_after(outcome.lethality, outcome.hp_before, damage)
	hit.resolved = outcome
	return hit


# The gas over this unit's cell (`packed`, Gas.with_level's form): one row per kind that hurts it or
# gives it a state. The damage is RulesService.gas_damage_for (steam's scald, #1331); the state is the
# rules' own from its authored level up, unless the body already has it or holds one that keeps it off.
# Idempotent like a wade's soak: a row says what CHANGED, so an already-wet unit grows a row only for
# the damage. A gas whose state is held only WHILE STANDING in it (smoke, #1335) gives nothing to keep.
# A row with damage is predicted against `body`, which is advanced past it, so whatever comes next is
# predicted against the HP this one leaves. Its states are not written: a row says what it adds.
static func gas_hits(body: UnitState, packed: int) -> Array[TileHitAction]:
	var held := body.element_states
	var hits: Array[TileHitAction] = []
	for kind: Gas.Kind in Gas.kinds_in(packed):
		var rules := GasRules.for_kind(kind)
		if rules == null:
			continue
		var level := Gas.level_in(packed, kind)
		var damage := RulesService.gas_damage_for(body, kind, level)
		var gains := rules.state != Elemental.State.NONE and not rules.while_standing \
				and level >= rules.state_from and not held.has(rules.state) \
				and not Elemental.is_blocked(held, rules.state)
		if damage <= 0 and not gains:
			continue
		var hit := make_gas(body, kind, rules.state if gains else Elemental.State.NONE, damage)
		hits.append(hit)
		if damage > 0:
			LethalityRules.land_rung(body, hit.resolved.lethality, damage)
	return hits


# A gas row: the scald through make() when there is one, so it reads HP and names its rung, and the
# state it gives. A body the scald kills gains nothing.
static func make_gas(body: UnitState, kind: Gas.Kind, gained: Elemental.State, damage: int) -> TileHitAction:
	var hit := make(body, Terrain.TileState.NONE, damage) if damage > 0 else _soak(body.unit, gained)
	if damage > 0 and gained != Elemental.State.NONE \
			and hit.resolved.lethality != ResolvedOutcome.Lethality.KILLED:
		hit.resolved.states_added.append(gained)
	hit.gas = kind
	return hit


# Everything the END OF THIS UNIT'S TURN does to it, in the order the pass plays it: the gas over its
# cell, the weather over the board, then the burn of the ground under it. The ONE composition the
# forecast (PlanResolver.resolve_tile_hits) and the pass (TurnBoundary.tile_hits) both call (#1331):
# a scald and a burn are two damage rows on one unit, and the burn must be predicted against the HP
# the scald leaves, so the threading lives here rather than in each caller. A body a row kills takes
# nothing more. `body` is not written: the rows thread a copy of it, made only when a row can land
# damage, because the health bars ask this every frame (TurnBoundary.forecast).
static func end_of_turn(body: UnitState, packed: int, sky: Weather.Kind,
		ground: Array[Terrain.TileState]) -> Array[TileHitAction]:
	var burn := RulesService.occupant_damage_for(body, ground)
	var now := body.copy() if packed != 0 or burn > 0 else body
	var hits := soaks(now, packed, sky)
	if now.lifecycle_state == Unit.LifecycleState.DEAD:
		return hits
	if burn > 0:
		hits.append(make(now, Terrain.burning_state(ground), burn))
	return hits


# Everything that soaks or scalds this unit at its end of turn, in the order the pass plays it: the
# gas over its cell, then the weather over the board (#1260). The weather is asked with what the gas
# rows already add, so a unit in steam in the rain gets one Wet row rather than two. `body` is
# advanced past every scald.
static func soaks(body: UnitState, packed: int, sky: Weather.Kind) -> Array[TileHitAction]:
	var hits := gas_hits(body, packed)
	if body.lifecycle_state == Unit.LifecycleState.DEAD:
		return hits   # the scald killed it: the rain soaks no body
	var after: Array[Elemental.State] = body.element_states.duplicate()
	for hit in hits:
		after.append_array(hit.resolved.states_added)
	var rules := WeatherRules.for_kind(sky)
	if rules != null and rules.state != Elemental.State.NONE \
			and not after.has(rules.state) and not Elemental.is_blocked(after, rules.state):
		var hit := _soak(body.unit, rules.state)
		hit.weather = sky
		hits.append(hit)
	return hits


# What ONE unit's end-of-turn rows leave its HP at, as a preview shows it (#1428): the last row that
# reads HP, whose threaded number already carries every row before it. -1 when no row touches HP: a
# soak alone moves no number. The board's health bar reads this rather than adding the rows up.
static func shown_hp_after(rows: Array[TileHitAction]) -> int:
	for i in range(rows.size() - 1, -1, -1):
		var outcome := rows[i].resolved
		if outcome != null and outcome.reads_hp:
			return outcome.displayed_hp_after()
	return -1


# ...and whether any of them names a rung, the bar's alarm. Every row is asked, not the last: a scald
# that drops a unit into Crisis leaves a burn behind it that names nothing.
static func names_a_rung(rows: Array[TileHitAction]) -> bool:
	for hit in rows:
		if hit.resolved != null and hit.resolved.lethality != ResolvedOutcome.Lethality.NONE:
			return true
	return false


static func _soak(unit: Unit, gained: Elemental.State) -> TileHitAction:
	var hit := TileHitAction.new()
	hit.actor = unit
	hit.action_type = BaseAction.ActionType.TILE_HIT
	var outcome := ResolvedOutcome.new()
	outcome.reads_hp = false   # nobody is hit; the row must not print an HP arrow (#884)
	outcome.states_added.append(gained)
	hit.resolved = outcome
	return hit


# What soaked or scalded this unit, as the player reads it ("Steam", "Heavy Rain"); "" for a burn.
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


# The rung first on every row, so a scald that kills wears the skull rather than its puff.
func get_action_icon() -> Texture2D:
	var lethal := AttackAction.lethality_icon(resolved)
	if lethal != null:
		return lethal
	if gas >= 0:
		return GasPuffArt.icon(gas as Gas.Kind)
	if weather >= 0:
		return WeatherArt.icon()
	var tex: Texture2D = OverlayManager.TERRAIN_STATE_ICONS.get(state, null)
	return tex


func get_description() -> String:
	var who := actor.get_unit_name() if actor != null and is_instance_valid(actor) else "?"
	var source := soak_source_name()
	var amount := resolved.damage if resolved != null else 0
	if source != "" and amount <= 0:
		return "%s stands in %s" % [who, source]
	if source == "":
		source = Terrain.tile_state_display_name(state)
	return "%s takes %d from %s" % [who, amount, source]
