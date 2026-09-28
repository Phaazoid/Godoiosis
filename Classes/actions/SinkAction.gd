extends BaseAction
class_name SinkAction

# One unit going under because the ground left it (#922): ice melted beneath it, so it stands on water
# it cannot stand on. Derived, never queued -- PlanResolver.settle_sinks makes these, the queue hangs
# each one under the attack whose deposit took the floor away, and both execution twins play them back.
#
# #116's drowning from the other side: there the unit arrives in the water, here the floor leaves. So
# the water does what it does to a shove -- takes everything left, through the ordinary ladder (Will,
# maim, Crisis, and a body already down is finished) -- and the answer is a rescue from the bank.

# WHEN it goes under. The ice melts when the pass's deposits land, straight after the attack volley
# (OrderExecutor._apply_cell_effects); a melt only a COUNTER or a tail shot makes is not known until
# those resolve, so its stander goes under once the pass has settled (dev ruling, 2026-09-27).
enum Moment { DEPOSITS_LAND, PASS_END }

var moment: Moment = Moment.DEPOSITS_LAND
var cell: Vector2i
# The attack whose deposit took the floor away -- read by the queue panel, which hangs this row under it.
var cause: AttackAction = null
var resolved: ResolvedOutcome = null


# `situation` is the unit as the pass has it at `moment`. `wets` is RulesService.wets_in on the ground
# the deposits leave, asked by the caller because only it holds that board.
static func make(unit: Unit, situation: LethalityRules.Situation, at: Vector2i, melted_by: AttackAction,
		when: Moment, wets: bool) -> SinkAction:
	var sink := SinkAction.new()
	sink.actor = unit
	sink.action_type = BaseAction.ActionType.SINK
	sink.moment = when
	sink.cell = at
	sink.cause = melted_by
	var outcome := ResolvedOutcome.new()
	outcome.hp_before = situation.hp
	# The water takes everything (PlanResolver._resolve_one's drowning, #116). drown_damage is what the
	# queue row's Drowned badge reads, so the two doors into the water wear one badge.
	outcome.drown_damage = maxi(0, situation.hp)
	outcome.damage = outcome.drown_damage
	outcome.lethality = LethalityRules.predict(situation, outcome.damage)
	outcome.target_hp_after = LethalityRules.hp_after(outcome.lethality, situation.hp, outcome.damage)
	outcome.popups.append(PlanResolver.DROWNING_POPUP)
	if wets:
		outcome.states_added.append(Elemental.State.WET)
	sink.resolved = outcome
	return sink


# Pure playback (R3): the damage, then the soak -- AttackAction.execute's order.
func execute() -> void:
	begin_execution()
	if actor != null and is_instance_valid(actor) and resolved != null:
		actor.take_damage(resolved.damage)
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
