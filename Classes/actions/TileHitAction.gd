extends BaseAction
class_name TileHitAction

# One unit's END OF TURN damage from the tile it is standing on (#419). Derived, never queued:
# the queue forecasts these from projected positions, the end-of-turn pass makes its own from live
# ones, and both build through make() so the number previewed is the number dealt.

var state: Terrain.TileState = Terrain.TileState.NONE   # which tile state is charging
var resolved: ResolvedOutcome = null


# `situation` is whose HP/Will/lifecycle the rung is predicted against — the pass's threaded
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


func execute() -> void:
	begin_execution()
	if actor != null and is_instance_valid(actor) and resolved != null:
		actor.take_damage(resolved.damage)
	finish_execution()


func resolved_outcome() -> ResolvedOutcome:
	return resolved


func is_reorderable() -> bool:
	return false   # derived, never queued — nobody ordered the fire


func get_action_icon() -> Texture2D:
	var lethal := AttackAction.lethality_icon(resolved)
	if lethal != null:
		return lethal
	var tex: Texture2D = OverlayManager.TERRAIN_STATE_ICONS.get(state, null)
	return tex


func get_description() -> String:
	var who := actor.get_unit_name() if actor != null and is_instance_valid(actor) else "?"
	var amount := resolved.damage if resolved != null else 0
	return "%s takes %d from %s" % [who, amount, Terrain.tile_state_display_name(state)]
