extends Node
class_name Squad

var leader: Unit
var members: Array[Unit] = []
var action_queue: Array[BaseAction] = []
var has_acted: bool = false
signal actions_became_active(squad: Squad, action: BaseAction)
signal actions_became_empty(squad: Squad)
signal action_cancelled(squad: Squad, unit: Unit, actiontype: BaseAction.ActionType)
signal action_queued(squad: Squad, action: BaseAction)

func set_leader(unit: Unit):
	leader = unit
	_add_member(unit)
	
func get_leader() -> Unit:
	return leader

func get_members() -> Array:
	return members
	
func contains_unit(unit: Unit) -> bool:
	if members.has(unit):
		return true
	else:
		return false
	
func _add_member(unit: Unit):
	if not members.has(unit):
		members.append(unit)
		unit.squad = self

func has_any_queued_actions() -> bool:
	if action_queue.is_empty():
		return false
	return true

func _remove_member(unit: Unit): 
	members.erase(unit)
	unit.reset_squad()
	
func _reassign_leader():
	members.erase(leader)
	leader.reset_squad()
	var newLeader: Unit = members[0]
	for member in members:
		if member.get_base_stat("LDR") > newLeader.get_base_stat("LDR"):
			newLeader = member
	leader = newLeader 

	for member in members:
		if not validate_member_distance(member):
			_remove_member(member)

func validate_member_distance(unit: Unit) -> bool:
	var dist = unit.movement.cell.distance_to(leader.movement.cell)
	if dist > get_max_range():
		return false
	else:
		return true
	
func get_max_range() -> int:
	return leader.get_base_stat("LDR") #This is a placeholder value for now
	
func get_planned_movement_destinations() -> Array:
	var cells = []
	for action in action_queue:
		if action.action_type == BaseAction.ActionType.MOVE:
			cells.append(action.destination)
		
	return cells
	
func get_ldr_range_from_cell(cell: Vector2i) -> Array[Vector2i]:
	return GridUtils.cells_within_manhattan_range(cell, get_max_range())
	
func get_actions() -> Array[BaseAction]:
	return action_queue.duplicate()
	
func get_actions_of_type(type: BaseAction.ActionType) -> Array:
	var actions = []
	for action in action_queue:
		if action.action_type == type:
			actions.append(action)
			
	return actions
			
func _queue_action(action: BaseAction):
	var was_empty = action_queue.is_empty()
		
	#For now, enforce only one of each kind of action per unit in the queue.
	for existing_action in action_queue.duplicate():
		if existing_action.actor == action.actor and existing_action.action_type == action.action_type:
			_remove_action(existing_action)
			
	action_queue.append(action)
	action_queued.emit(self, action)

	if was_empty:
		actions_became_active.emit(self, action)

func _remove_action(action: BaseAction):
	action_queue.erase(action)
	action_cancelled.emit(self, action.actor, action.action_type)
	
	if action_queue.is_empty():
		actions_became_empty.emit(self)

func _clear_all_actions():
	for action in action_queue.duplicate():
		action_queue.erase(action)
		action_cancelled.emit(self, action.actor, action.action_type)
	actions_became_empty.emit(self)
		
func _set_has_acted(acted: bool):
	has_acted = acted
	if acted:
		_clear_all_actions()

func _reset_squad():
	has_acted = false
	action_queue.clear() #TODO later if giving units status negative actions or whatnot, don't want to fully clear this. Can easily filter if that becomes a thing
