extends Node2D
class_name SquadManager

var squads: Array[Squad] = []
var active_squad: Squad = null
@onready var overlay_manager: OverlayManager = $"../OverlayManager"
@onready var grid: TileMapLayer = $"../Grid"

signal squad_created(squad: Squad)
signal squad_deleted(squad: Squad)
signal squad_action_cancelled(squad: Squad, unit: Unit, actiontype: BaseAction.ActionType)
signal squad_became_active(squad: Squad, action: BaseAction)
signal squad_became_empty(squad: Squad)
signal squad_action_queued(squad: Squad, action: BaseAction)


func is_active_squad(squad: Squad):
	return squad == active_squad
	
func any_squad_active() -> bool:
	for squad in squads:
		if not squad.get_actions().is_empty():
			return true
			
	return false

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
	
func _detach_from_current_squad(unit: Unit): #This should be the only place that ever erases a unit from a squad
	var old_squad := unit.squad
	if old_squad == null:
		return

	old_squad._erase_member(unit)
	check_reassign_leader(old_squad, unit)

	if old_squad.get_members().is_empty():
		destroy_empty_squad(old_squad)
		
func join_squad(unit: Unit, target_squad: Squad):
	if unit.squad == target_squad:
		return

	_detach_from_current_squad(unit)
	target_squad._add_member(unit)
		
func leave_squad(unit: Unit):
	_detach_from_current_squad(unit)
	create_squad(unit)

func check_reassign_leader(squad: Squad, unit: Unit):
	if squad.members.is_empty():
		return
		
	if squad.leader != unit:
		return
	
	var newLeader: Unit = squad.members[0]
	for member in squad.members.duplicate():
		if member.get_base_stat(Stats.Stat.LDR) > newLeader.get_base_stat(Stats.Stat.LDR):
			newLeader = member
	squad.leader = newLeader 

	for member in squad.members.duplicate():
		if not GridUtils.validate_member_distance(member):
			leave_squad(member)

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
	var max_passes := squad.get_members().size() + 1
	var valid := true
	for _i in range(max_passes):
		var before := actions.map(func(a): return a.is_valid)
		valid = _validate_action_list_once(squad, actions)   # current body, factored out
		var after := actions.map(func(a): return a.is_valid)
		if before == after:
			break   # fixpoint reached
	return valid

func _validate_action_list_once(squad: Squad, actions: Array[BaseAction]) -> bool:
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
	
	#Leader-range validity must be resolved BEFORE the occupancy check below,
	#so that check can trust each move's is_valid flag.
	for action in move_actions:
		var moving_unit: Unit = action.actor
		
		if moving_unit == squad.leader or not moving_unit.has_squad():
			continue

		if not leader_range.has(action.get_destination()):
			action.add_validation_error("Squad leader range invalidates other movement")
			valid = false
	
	for action in move_actions:
		var destination = action.destination
			
		if not actions_by_destination.has(destination):
			actions_by_destination[destination] = []
		
		actions_by_destination[destination].append(action)
		
	for destination in actions_by_destination.keys():
		var actions_at_cell: Array = actions_by_destination[destination]

		#A squadmate's cell only frees up if that squadmate has a VALID move AWAY from it.
		#An invalid move (out of leader range) or a hold means they stay put — cell stays occupied.
		if current_member_locations.has(destination):
			var occupying_unit: Unit = current_member_locations[destination]
			if not _unit_has_valid_move_away_from(occupying_unit, destination, actions):
				for action in actions_at_cell:
					if action.actor == occupying_unit:
						continue  # the occupant's own hold/stay on this cell is not a self-collision
					action.add_validation_error("Destination occupied")
					valid = false
				continue

		if actions_at_cell.size() > 1:
			valid = false
			for action in actions_at_cell:
				action.add_validation_error("Multiple units attempting to move here")
		
	return valid

func _unit_has_valid_move_away_from(unit: Unit, cell: Vector2i, actions: Array[BaseAction]) -> bool:
	for action in actions:
		if action.actor == unit and action.action_type == BaseAction.ActionType.MOVE and action.is_valid and action.get_destination() != cell:
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

func setup_hold_move_actions(squad: Squad):
	for member in squad.get_members():
		if not member.has_action_type_queued(BaseAction.ActionType.MOVE):
			var hold_move := MoveAction.new()
			hold_move.init_hold_position(member, GridUtils.get_terrain_icon_at_cell(grid, member.movement.cell))
			squad._queue_action(hold_move)

func disband_squad(squad: Squad):
	if not squads.has(squad):
		return
	
	for member in squad.get_members().duplicate():
		squad._erase_member(member)
		create_squad(member)
		
	destroy_empty_squad(squad)
		
func destroy_empty_squad(squad: Squad):
	if squad == null:
		return
	if not squad.get_members().is_empty():
		return

	if active_squad == squad:
		active_squad = null

	squads.erase(squad)
	squad_deleted.emit(squad)
	squad.queue_free()
	
func clear_all_squads():
	active_squad = null
	for squad in squads.duplicate():
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
	var squad = unit.squad
	for action in squad.action_queue.duplicate():
		if action.actor == unit:
			if action.action_type == BaseAction.ActionType.MOVE:
				cancel_move_for_unit(action.actor)
			else:
				squad._remove_action(action)

	if only_hold_actions():
		active_squad._clear_all_actions()
		active_squad = null
		return

	if not squad.has_any_queued_actions() and active_squad == squad:
		active_squad = null
		return

	validate_squad_plan(squad)
	overlay_manager.redraw_planned_paths()
	
func cancel_move_for_unit(unit: Unit):
	var squad = unit.squad
	
	for action in squad.action_queue.duplicate():
		if action.actor == unit and action.action_type == BaseAction.ActionType.MOVE:
			squad._remove_action(action)
			
	var hold_move = MoveAction.new()
	hold_move.init_hold_position(unit,GridUtils.get_terrain_icon_at_cell(grid, unit.movement.cell))
	squad._queue_action(hold_move)
	
	validate_squad_plan(squad)
	overlay_manager.redraw_planned_paths()
			
func only_hold_actions() -> bool: #checking if the only actions a squad has are the 'not move' action
	if active_squad == null:
		return false
		
	for action in active_squad.action_queue:
		if not action.action_type == BaseAction.ActionType.MOVE:
			return false
		if action.action_type == BaseAction.ActionType.MOVE and action.is_hold_position == false:
			return false
			
	return true
	
func remove_action(squad: Squad, action: BaseAction):
	if action is AttackAction and not (action as AttackAction).volley.is_empty():
		squad._remove_volley(action)
	else:
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
	
func can_counter(countering_unit: Unit, target_unit: Unit) -> bool: 
	if countering_unit == null or target_unit == null:
		return false
	if not is_instance_valid(countering_unit) or not is_instance_valid(target_unit):
		return false
	if not countering_unit.combat.can_counter:
		return false
	if not countering_unit.combat.can_attack(countering_unit, target_unit):
		return false
	if not countering_unit.has_equipped_weapon():
		return false
	if not countering_unit.get_equipped_weapon().can_counter:
		return false

	var counter_cell := countering_unit.get_projected_destination()
	var target_cell := target_unit.get_projected_destination()

	return countering_unit.combat.can_hit_cell_from(counter_cell, target_cell)

func choose_counter_target(countering_unit: Unit, attacking_party: Array[Unit]) -> Unit:
	#This is where logic will need to live later, in order to determine who counter attacks who and why.  For now just pulls first member from list. 
	for member in attacking_party:
		if can_counter(countering_unit, member):
			return member
	return null

func calculate_counterattacks_for_squad(attacking_squad: Squad) -> Array[CounterAttackAction]:
	var counters: Array[CounterAttackAction] = []
	var defender_groups_that_countered := {} # {Squad : bool} 
	var attacking_units = attacking_squad.get_members()

	for action in attacking_squad.action_queue:
		if action.action_type != BaseAction.ActionType.ATTACK:
			continue

		var attack := action as AttackAction
		var defender := attack.target

		if defender == null or not is_instance_valid(defender):
			continue

		var defender_squad = defender.squad

		if defender_groups_that_countered.has(defender_squad):
			continue

		for countering_unit in defender.squad.get_members():
			var counter_target := choose_counter_target(countering_unit, attacking_units)
			if counter_target == null:
				continue
				
			var counter := CounterAttackAction.new()
			counter.init_counter(countering_unit, counter_target, countering_unit.get_projected_destination(), attack)
			counters.append(counter)

		defender_groups_that_countered[defender_squad] = true

	return counters
	
func resolve_plan(squad: Squad) -> ResolvedPlan:
	var plan := ResolvedPlan.new()
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.ATTACK:
			plan.attacks.append(action as AttackAction)
	plan.counters = calculate_counterattacks_for_squad(squad)
	PlanResolver.resolve(plan)
	return plan

func get_display_entries_for_squad(squad: Squad) -> Array[ActionQueueDisplayEntry]:
	var entries: Array[ActionQueueDisplayEntry] = []

	var move_actions: Array[BaseAction] = []
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.MOVE:
			move_actions.append(action)

	# One pass derives counters AND resolves every outcome; rows read .resolved (R3/R8).
	var plan := resolve_plan(squad)

	if not move_actions.is_empty():
		entries.append(ActionQueueDisplayEntry.header("MOVE"))
		for action in move_actions:
			entries.append(ActionQueueDisplayEntry.action_row(action, 0))

	if not plan.attacks.is_empty():
		if not entries.is_empty():
			entries.append(ActionQueueDisplayEntry.divider())

		entries.append(ActionQueueDisplayEntry.header("ATTACK"))
		for attack in plan.attacks:
			entries.append(ActionQueueDisplayEntry.action_row(attack, 0))

			for counter in plan.counters:
				if counter.source_attack == attack:
					entries.append(ActionQueueDisplayEntry.action_row(counter, 1))

	return entries

func handle_unit_death(unit: Unit):
	var squad := unit.squad
	if squad == null or not is_instance_valid(squad):
		return

	squad._remove_actions_for_actor_silent(unit)

	_detach_from_current_squad(unit)

	if is_instance_valid(squad) and not squad.get_members().is_empty():
		validate_squad_plan(squad)
		overlay_manager.redraw_planned_paths()

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
