extends Node2D
class_name SquadManager

var squads: Array[Squad] = []
var active_squad: Squad = null

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
	return true

func set_has_acted(squad: Squad, acted: bool):
	squad._set_has_acted(acted)
	
func remove_actions_for_unit(unit: Unit):
	unit.squad.remove_actions_for_unit(unit)
	if not unit.squad.has_any_queued_actions() and active_squad == unit.squad:
		active_squad = null
	
func remove_action(squad: Squad, action: BaseAction):
	squad._remove_action(action)
	
	if not squad.has_any_queued_actions() and active_squad == squad:
		active_squad = null

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
