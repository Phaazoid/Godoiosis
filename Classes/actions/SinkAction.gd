extends BaseAction
class_name SinkAction

# One unit going under because the ground left it (#922): ice melted beneath it, so it stands on water
# it cannot stand on. Derived, never queued -- PlanResolver.settle_landing and resolve_move make these,
# the queue hangs each one under its cause, and both execution twins play it right after that cause.
#
# #116's drowning from the other side: there the unit arrives in the water, here the floor leaves. So
# the water does what it does to a shove (#1657): no health, no rung, never Crisis -- a standing body
# goes DROWNING, a downed one stays down on the water's clock -- and the answer is a rescue from the bank.

var cell: Vector2i
# What it goes under after (#1498): the action whose landing melted the ice -- a volley's last member,
# a counter, a shot (ruling 4) -- or the walk that stepped onto water a walk shot melted (ruling 5).
var cause: BaseAction = null
var resolved: ResolvedOutcome = null


# `body` is the unit's body as the pass has it when it goes under, read and not written; the actor is
# its unit. `wets` is RulesService.wets_in on the ground it goes under on, less #1092's Chilled
# exclusion -- asked by the caller, which holds that board.
static func make(body: UnitState, at: Vector2i, after: BaseAction, wets: bool) -> SinkAction:
	var sink := SinkAction.new()
	sink.actor = body.unit
	sink.action_type = BaseAction.ActionType.SINK
	sink.cell = at
	sink.cause = after
	var outcome := ResolvedOutcome.new()
	outcome.hp_before = body.get_current_hp()
	outcome.target_hp_after = outcome.hp_before   # the water takes nothing (#1657)
	# `drowned` is what the queue row's Drowned badge reads, so the two doors into the water wear one
	# badge, and what lifecycle_after folds in.
	outcome.drowned = true
	outcome.popups.append(PlanResolver.DROWNING_POPUP)
	if wets:
		outcome.states_added.append(Elemental.State.WET)
	sink.resolved = outcome
	return sink


# Pure playback (R3): the water, then the soak -- AttackAction.land's order.
func execute() -> void:
	begin_execution()
	if actor != null and is_instance_valid(actor) and resolved != null:
		actor.go_under()
		for s in resolved.states_added:
			actor.add_element_state(s, resolved.state_turns.get(s, 0))
	finish_execution()


func resolved_outcome() -> ResolvedOutcome:
	return resolved


func is_reorderable() -> bool:
	return false   # derived, never queued -- nobody ordered the thaw


func get_action_icon() -> Texture2D:
	return AttackAction.lethality_icon(resolved)


func get_description() -> String:
	var who := actor.get_unit_name() if actor != null and is_instance_valid(actor) else "?"
	return "%s goes under at %s" % [who, str(cell)]
