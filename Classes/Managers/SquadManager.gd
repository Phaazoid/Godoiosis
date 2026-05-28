extends Node2D
class_name SquadManager

var squads: Array[Squad] = []
var active_squad: Squad = null
@onready var overlay_manager: OverlayManager = $"../OverlayManager"

signal squad_created(squad: Squad)
signal squad_deleted(squad: Squad)
signal squad_action_cancelled(squad: Squad, unit: Unit, actiontype: BaseAction.ActionType)
signal squad_became_active(squad: Squad, action: BaseAction)
signal squad_became_empty(squad: Squad)
signal squad_action_queued(squad: Squad, action: BaseAction)


func is_active_squad(squad: Squad):
	return squad == active_squad

func is_another_squad_active(squad: Squad):
	if active_squad == null:
		return false
	return active_squad != squad

func reset_faction_actions(faction):
	for squad in squads:
		if squad.leader.get_faction() == faction:
			squad._reset_squad()

func create_squad(leader: Unit) -> Squad:
	var squad := Squad.new()
	add_child(squad)
	
	squad.set_leader(leader)
	
	squads.append(squad)
	_register_squad_signals(squad)
	
	squad_created.emit(squad)
	return squad
	
func join_squad(unit: Unit, target_squad: Squad):
	var old_squad = unit.squad
	old_squad._remove_member(unit)
	target_squad._add_member(unit)
	
	if old_squad.get_members().is_empty():
		delete_squad(old_squad)

func validate_squad_plan(squad: Squad) -> bool:
	return _validate_action_list(squad, squad.action_queue)
	
#We need to pass in an action list as well for the specific case of the hover preview, where we use a different action list than saved in the squad depending on cell hovered
func _get_projected_cell_for_unit(unit: Unit, actions: Array[BaseAction]) -> Vector2i:
	for action in actions:
		if action.actor == unit and action.action_type == BaseAction.ActionType.MOVE:
			return action.get_destination()
	return unit.movement.cell
	
#Note - only treats valid actions as projected moves
func get_projected_unit_from_cell(cell: Vector2i) -> Unit:
	if active_squad == null:
		return null
	for action in active_squad.get_actions():
		if action.action_type == BaseAction.ActionType.MOVE and action.get_destination() == cell and action.is_valid:
			return action.actor
			
	return null
	
func _validate_action_list(squad: Squad, actions: Array[BaseAction]) -> bool:
	var valid := true
	var move_actions := []
	var actions_by_destination = {} #{Vector2i : Array[MoveActions]}
	var current_member_locations = {} #{Vector2i : Unit}
	
	var projected_leader_cell := _get_projected_cell_for_unit(squad.leader, actions)
	var leader_range := squad.get_ldr_range_from_cell(projected_leader_cell)
	for action in actions:
		action.clear_validation_errors()
		
	for action in actions: 
		if action.action_type == BaseAction.ActionType.MOVE:
			move_actions.append(action)
	
	for member in squad.get_members() :#{Vector2i: Unit}
		current_member_locations[member.movement.cell] = member
	
	for action in move_actions:
		var destination = action.destination
			
		if not actions_by_destination.has(destination):
			actions_by_destination[destination] = []
		
		actions_by_destination[destination].append(action)
		
	for destination in actions_by_destination.keys():
		var actions_at_cell: Array = actions_by_destination[destination]

		#if destination is another squadmate with no move queued, move is invalid, remove from list to check
		if current_member_locations.has(destination):
			var occupying_unit: Unit = current_member_locations[destination]
			if not _unit_has_action_type_in_list(occupying_unit, BaseAction.ActionType.MOVE, actions):
				for action in actions_at_cell:
					action.add_validation_error("Destination occupied")
					valid = false
				continue

		if actions_at_cell.size() > 1:
			valid = false
			for action in actions_at_cell:
				action.add_validation_error("Multiple units attempting to move here")
				
		
	#Have to validate actions for the rest of the squad that can get canceled by the leader moving and shifting his range
	for action in move_actions:
		var moving_unit: Unit = action.actor
		
		if moving_unit == squad.leader or not moving_unit.has_squad():
			continue

		if not leader_range.has(action.get_destination()):
			action.add_validation_error("Squad leader range invalidates other movement")
			valid = false
	
	return valid

func _unit_has_action_type_in_list(unit: Unit, action_type: BaseAction.ActionType, actions: Array[BaseAction]) -> bool:
	for action in actions:
		if action.actor == unit and action.action_type == action_type:
			return true
			
	return false
	
	
func validate_squad_plan_preview(squad: Squad, preview_action: BaseAction) -> bool:
	var actions := squad.action_queue.duplicate()
	
	#Replace this unit's existing action of same type in hypothetical list
	for action in actions.duplicate():
		if action.actor == preview_action.actor and action.action_type == preview_action.action_type:
			actions.erase(action)
			
	actions.append(preview_action)
	
	return _validate_action_list(squad, actions)
	
func leave_squad(unit: Unit):
	var old_squad := unit.squad
	
	if unit.is_leader():
		old_squad._reassign_leader()
	else:
		old_squad._remove_member(unit)
		
	if old_squad.get_members().is_empty():
		delete_squad(old_squad)
		
	create_squad(unit)

func delete_squad(squad: Squad):
	if not squads.has(squad):
		return
	
	for member in squad.get_members().duplicate():
		squad._remove_member(member)
		
	squads.erase(squad)
	squad_deleted.emit(squad)
	squad.queue_free()

func queue_action(squad: Squad, action: BaseAction) -> bool:
	if active_squad != null and active_squad != squad:
		return false

	active_squad = squad
	squad._queue_action(action)
	validate_squad_plan(squad)
	overlay_manager.redraw_planned_paths()

	return true

func set_has_acted(squad: Squad, acted: bool):
	squad._set_has_acted(acted)
	
func remove_actions_for_unit(unit: Unit):
	unit.squad.remove_actions_for_unit(unit)
	if not unit.squad.has_any_queued_actions() and active_squad == unit.squad:
		active_squad = null
		return
	validate_squad_plan(unit.squad)
	overlay_manager.redraw_planned_paths()
	
func remove_action(squad: Squad, action: BaseAction):
	squad._remove_action(action)

	if not squad.has_any_queued_actions() and active_squad == squad:
		active_squad = null
		return
		
	validate_squad_plan(squad)
	overlay_manager.redraw_planned_paths()

func squad_has_invalid_actions(squad: Squad) -> bool:
	for action in squad.action_queue:
		if not action.is_valid:
			return true
	return false

func _register_squad_signals(squad: Squad):
	if not squad.action_cancelled.is_connected(_on_squad_action_cancelled):
		squad.action_cancelled.connect(_on_squad_action_cancelled)
	if not squad.actions_became_active.is_connected(_on_squad_became_active):
		squad.actions_became_active.connect(_on_squad_became_active)
	if not squad.actions_became_empty.is_connected(_on_squad_became_empty):
		squad.actions_became_empty.connect(_on_squad_became_empty)
	if not squad.action_queued.is_connected(_on_squad_action_queued):
		squad.action_queued.connect(_on_squad_action_queued)

func _on_squad_action_queued(squad: Squad, action: BaseAction):
	squad_action_queued.emit(squad, action)

func _on_squad_action_cancelled(squad: Squad, unit: Unit, actiontype: BaseAction.ActionType):
	squad_action_cancelled.emit(squad, unit, actiontype)

func _on_squad_became_active(squad: Squad, action: BaseAction):
	squad_became_active.emit(squad, action)

func _on_squad_became_empty(squad: Squad):
	squad_became_empty.emit(squad)
