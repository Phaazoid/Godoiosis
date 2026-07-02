extends Node
class_name Squad


const NO_HOME := Vector2i(-999999, -999999)

var leader: Unit
var members: Array[Unit] = []
var action_queue: Array[BaseAction] = []
var has_acted: bool = false
var squad_name := ""
var archetype: AIArchetype.Type = AIArchetype.Type.FACTION_DEFAULT
var zone_name := ""   # painted zone this squad is bound to (Sentry); "" = none
var home_cell := NO_HOME   # sentry post: set at scenario load; first sentry turn fixes it otherwise

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
	
func _add_member(unit: Unit):
	if not members.has(unit):
		members.append(unit)
		unit.squad = self

func _erase_member(unit: Unit):
	members.erase(unit)

func has_any_queued_actions() -> bool:
	if action_queue.is_empty():
		return false
	return true
		
func get_max_range() -> int:
	return leader.get_base_stat(Stats.Stat.LDR) #This is a placeholder value for now

func get_ldr_range_from_cell(cell: Vector2i) -> Array[Vector2i]:
	return GridUtils.cells_within_manhattan_range(cell, get_max_range())
	
func get_actions() -> Array[BaseAction]:
	return action_queue.duplicate()
	
func _queue_action(action: BaseAction):
	var was_empty = action_queue.is_empty()

	#Enforce one order of each type per unit. A volley is one order
	#spread across multiple actions, so volley siblings don't replace each other.
	for existing_action in action_queue.duplicate():
		if existing_action.actor != action.actor:
			continue
		# Replace a same-type order, AND enforce one main action per unit — attack, rescue,
		# etc. contend for one slot. A volley is one order across siblings, so exempt those.
		var same_type = existing_action.action_type == action.action_type
		var main_conflict = action.is_main_action() and existing_action.is_main_action()
		if not same_type and not main_conflict:
			continue
		if _is_volley_sibling(existing_action, action):
			continue
		_remove_action(existing_action)

	action_queue.append(action)
	action_queued.emit(self, action)

	if was_empty:
		actions_became_active.emit(self, action)

func _is_volley_sibling(a: BaseAction, b: BaseAction) -> bool:
	if not (a is AttackAction and b is AttackAction):
		return false
	if b.volley.is_empty():
		return false
	return a in b.volley

func _remove_action(action: BaseAction):
	action_queue.erase(action)
	action_cancelled.emit(self, action.actor, action.action_type)
	
	if action_queue.is_empty():
		actions_became_empty.emit(self)

func _clear_all_actions():
	for action in action_queue.duplicate():
		action_queue.erase(action)
		action_cancelled.emit(self, action.actor, action.action_type)
		_break_volley_cycle(action)
	actions_became_empty.emit(self)

func _set_has_acted(acted: bool):
	has_acted = acted
	if acted:
		_clear_all_actions()

#Death-path removal: no signals. Death cleanup is not an order cancellation,
#and the cancel handlers restore squad badges for units that must not get them.
func _remove_actions_for_actor_silent(unit: Unit):
	for action in action_queue.duplicate():
		if action.actor == unit:
			action_queue.erase(action)
			_break_volley_cycle(action)

# Cancel a whole volley given any one of its members (an AoE is one order).
func _remove_volley(member: AttackAction) -> void:
	if member.volley.is_empty():
		_remove_action(member)
		return
	for sib in member.volley.duplicate():   # duplicate: removal mutates the queue, not this array
		_remove_action(sib)
	member.volley.clear()                    # break the RefCounted cycle (see #35)

# Reorder the stored ATTACK aims to follow the given actor order (one aim per unit — the AoE
# volley is re-derived at resolve, so each row maps to its aim by actor). resolve_plan iterates
# action_queue in order, so queue order IS combo order: this re-times the elemental combo
# deterministically — a planned reorder, Law #2 intact. Non-attack orders keep their place.
func reorder_attacks_by_actor(ordered_actors: Array) -> void:
	var attack_aims: Array[BaseAction] = []
	for action in action_queue:
		if action.action_type == BaseAction.ActionType.ATTACK:
			attack_aims.append(action)
	if attack_aims.size() <= 1:
		return
	attack_aims.sort_custom(func(a, b): return ordered_actors.find(a.actor) < ordered_actors.find(b.actor))

	var rebuilt: Array[BaseAction] = []
	var inserted := false
	for action in action_queue:
		if action.action_type == BaseAction.ActionType.ATTACK:
			if not inserted:
				rebuilt.append_array(attack_aims)   # drop the reordered block at the first attack slot
				inserted = true
		else:
			rebuilt.append(action)
	action_queue = rebuilt

func _reset_squad():
	has_acted = false
	for action in action_queue:
		_break_volley_cycle(action)
	action_queue.clear() #TODO later if giving units status negative actions or whatnot, don't want to fully clear this. Can easily filter if that becomes a thing

# Break the volley RefCounted cycle when actions leave the queue for good.
# create_volley() shares one Array[AttackAction] across all siblings, so each
# sibling strong-refs the array that strong-refs it -> the island never frees.
func _break_volley_cycle(action: BaseAction) -> void:
	if action is AttackAction and not action.volley.is_empty():
		action.volley.clear()
