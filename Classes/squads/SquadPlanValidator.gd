extends Object
class_name SquadPlanValidator

# Decides which of a squad's queued orders are currently legal, by stamping is_valid +
# validation_errors onto each action. Split out of SquadManager 2026-07-26: it reads a plan and
# marks it, touching no squad lifecycle and no board state, so it is entirely static. Callers go
# through SquadManager.validate_squad_plan / validate_squad_plan_preview.
#
# Why it runs to a FIXED POINT rather than once (#16): the occupancy rule asks "did the unit
# standing here move away *validly*?", so one action's invalidation can invalidate another's.
# is_valid is reset ONCE up front and each pass only ever ADDS invalidations, which makes the
# loop monotonic and therefore terminating. Per-pass we clear only the MESSAGES
# (clear_validation_messages, which leaves is_valid alone) so text doesn't stack up across passes.
#
# Actions carrying their own queueing requirements (move-before-main, verb locks) enforce those in
# BaseAction.actor_can_perform at queue time. This is the separate, plan-CONTEXT layer: leader
# range, destination conflicts, and adjacency that a re-planned move can silently break.

static func validate(squad: Squad, actions: Array[BaseAction]) -> bool:
	for action in actions:
		action.reset_validation()

	# One pass per member plus one: each pass can invalidate at least one more action, so this
	# bounds the cascade. Breaks as soon as a pass changes nothing.
	var max_passes := squad.get_members().size() + 1
	for _i in range(max_passes):
		var before := actions.map(func(a): return a.is_valid)
		_run_pass(squad, actions)
		if actions.map(func(a): return a.is_valid) == before:
			break

	for action in actions:
		if not action.is_valid:
			return false
	return true

# The projected cell a unit will occupy under this action list. Takes the list explicitly rather
# than reading the squad's queue, because the hover preview validates a HYPOTHETICAL list.
static func projected_cell_for(unit: Unit, actions: Array[BaseAction]) -> Vector2i:
	for action in actions:
		if action.actor == unit and action.action_type == BaseAction.ActionType.MOVE:
			return action.get_destination()
	return unit.movement.cell

static func _run_pass(squad: Squad, actions: Array[BaseAction]) -> void:
	for action in actions:
		action.clear_validation_messages()

	# Typed as MoveAction, not BaseAction: get_destination() is declared on MoveAction only, so a
	# BaseAction-typed list would resolve it dynamically and lose every return type downstream.
	var move_actions: Array[MoveAction] = []
	for action in actions:
		if action.action_type == BaseAction.ActionType.MOVE:
			move_actions.append(action as MoveAction)

	# Leader-range validity must resolve BEFORE the occupancy check, which trusts is_valid.
	_check_leader_range(squad, actions, move_actions)
	_check_destination_conflicts(squad, actions, move_actions)
	_revalidate_rescues(actions)
	_revalidate_intimidates(actions)

# A non-leader squadmate may only land inside the leader's projected cohesion range.
static func _check_leader_range(squad: Squad, actions: Array[BaseAction], move_actions: Array[MoveAction]) -> void:
	var leader_range := squad.get_squad_range_from_cell(projected_cell_for(squad.leader, actions))
	for action in move_actions:
		var moving_unit: Unit = action.actor
		if moving_unit == squad.leader or not moving_unit.has_squad():
			continue
		if not leader_range.has(action.get_destination()):
			action.add_validation_error("Squad leader range invalidates other movement")

# Two members can't land on the same cell, and a cell only frees up if its current occupant has a
# VALID move away. An invalid move (out of leader range) or a hold means they stay put.
static func _check_destination_conflicts(squad: Squad, actions: Array[BaseAction], move_actions: Array[MoveAction]) -> void:
	var current_member_locations := {}   # {Vector2i : Unit}
	for member in squad.get_members():
		current_member_locations[member.movement.cell] = member

	var actions_by_destination := {}     # {Vector2i : Array[MoveAction]}
	for action in move_actions:
		var destination := action.get_destination()
		if not actions_by_destination.has(destination):
			actions_by_destination[destination] = []
		actions_by_destination[destination].append(action)

	for destination in actions_by_destination.keys():
		var actions_at_cell: Array = actions_by_destination[destination]

		if current_member_locations.has(destination):
			var occupying_unit: Unit = current_member_locations[destination]
			if not _unit_has_valid_move_away_from(occupying_unit, destination, actions):
				for action in actions_at_cell:
					if action.actor == occupying_unit:
						continue   # the occupant's own hold/stay on this cell isn't a self-collision
					action.add_validation_error("Destination occupied")
				continue

		if actions_at_cell.size() > 1:
			for action in actions_at_cell:
				action.add_validation_error("Multiple units attempting to move here")

static func _unit_has_valid_move_away_from(unit: Unit, cell: Vector2i, actions: Array[BaseAction]) -> bool:
	for action in actions:
		if action.actor == unit and action.action_type == BaseAction.ActionType.MOVE and action.is_valid and action.get_destination() != cell:
			return true
	return false

# The rescuer must still END its projected move adjacent to a still-downed ally. Mirrors the AoE
# re-derivation debt: a move re-planned away from the body invalidates the rescue, and a target
# someone else rescued first drops out too.
static func _revalidate_rescues(actions: Array[BaseAction]) -> void:
	for action in actions:
		if not (action is RescueAction):
			continue
		var rescue := action as RescueAction
		var target: Unit = rescue.target
		if target == null or not is_instance_valid(target) or not target.is_downed():
			rescue.add_validation_error("Rescue target is no longer down")
			continue
		if not _actor_ends_adjacent_to(rescue, target, actions):
			rescue.add_validation_error("Rescuer no longer adjacent to the downed ally")

# Same shape as rescue, but the target only has to still be ALIVE (active or downed).
static func _revalidate_intimidates(actions: Array[BaseAction]) -> void:
	for action in actions:
		if not (action is IntimidateAction):
			continue
		var intimidate := action as IntimidateAction
		var victim: Unit = intimidate.target
		if victim == null or not is_instance_valid(victim) or victim.is_dead():
			intimidate.add_validation_error("Intimidate target is gone")
			continue
		if not _actor_ends_adjacent_to(intimidate, victim, actions):
			intimidate.add_validation_error("No longer adjacent to the intimidate target")

static func _actor_ends_adjacent_to(action: BaseAction, target: Unit, actions: Array[BaseAction]) -> bool:
	var actor_cell := projected_cell_for(action.actor, actions)
	return GridUtils.cells_within_manhattan_range(actor_cell, 1).has(target.movement.cell)
