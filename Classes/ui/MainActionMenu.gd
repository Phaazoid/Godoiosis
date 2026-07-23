extends Node
class_name MainActionMenu

# Player action-menu system, pulled out of game.gd: menu item ids/display data, which
# options a unit can take right now, and dispatch when one is picked. Holds a back-ref
# to the Game coordinator (mirrors DevController/AIController) for everything it reads
# from or calls back into.

var game   # the Game coordinator (Node2D); set by game._ready()

const MOVE := 0
const ATTACK := 1
const OTHER := 2
const CANCEL := 3
const WAIT := 4
const ENDTURN := 5
const SQUADUP := 6
const JOINSQUAD := 7
const LEAVESQUAD := 8
const DISBAND_SQUAD := 9
const INSPECT := 10
const EXECUTE_ORDERS := 11
const RESCUE := 12
const RALLY := 13
const GROUP_MOVE := 14
const INTIMIDATE := 15
const SPRING_LOAD := 16

# Display data AND print order: declaration order here IS the menu's order (Godot
# dicts iterate in insertion order). One entry per item — nothing else to keep in sync.
const ACTION_DATA := {
	EXECUTE_ORDERS: {"name": "Execute Orders"},
	MOVE: {"name": "Move"},
	GROUP_MOVE: {"name": "Group Move"},
	ATTACK: {"name": "Attack"},
	RESCUE: {"name": "Rescue"},
	RALLY: {"name": "Rally"},
	INTIMIDATE: {"name": "Intimidate"},
	SQUADUP: {"name": "Squad Up"},
	JOINSQUAD: {"name": "Join Squad"},
	LEAVESQUAD: {"name": "Leave Squad"},
	DISBAND_SQUAD: {"name": "Disband Squad"},
	WAIT: {"name": "Wait"},
	CANCEL: {"name": "Cancel Actions"},
	INSPECT: {"name": "Inspect"},
	ENDTURN: {"name": "End Turn"},
	SPRING_LOAD: {"name": "Spring Load"},
}

func on_pressed(action_id: int, unit: Unit) -> void:
	match action_id:
		MOVE:
			game.enter_move_mode(unit)
		ATTACK:
			game._begin_attack(unit)
		CANCEL:
			game.cancel_orders(unit)
			game.clear_selection()
		WAIT:
			game.squad_manager.set_has_acted(unit.squad, true)
			game.clear_selection()
		ENDTURN:
			game.end_turn()
		SQUADUP:
			game.create_squad(unit)
		JOINSQUAD:
			game.join_squad_mode(unit)
		DISBAND_SQUAD:
			game.disband_squad(unit)
		LEAVESQUAD:
			game.squad_manager.leave_squad(unit)
		INSPECT:
			game.unit_info_panel.set_unit(unit, game.can_control(unit))
		EXECUTE_ORDERS:
			game.execute_orders(unit)
		RESCUE:
			game.enter_target_pick_mode(RulesService.adjacent_downed_allies(unit, game._board()), func(target: Unit): game.queue_rescue(unit, target))
		RALLY:
			game.queue_rally(unit)
		INTIMIDATE:
			game.enter_target_pick_mode(RulesService.adjacent_enemies(unit, game._board()), func(target: Unit): game.queue_intimidate(unit, target))
		GROUP_MOVE:
			game.enter_group_move_mode(unit)
		SPRING_LOAD:
			game.queue_spring_load(unit)

# Shared gate for every main-action menu entry: one main action per unit per turn, squad
# not spent, no other squad mid-activation. Per-action requirements chain onto this.
func _can_take_main_action(unit: Unit) -> bool:
	return not unit.has_main_action_queued() and not unit.squad.has_acted and not game.squad_manager.is_another_squad_active(unit.squad)

func populate(unit: Unit) -> Array:
	var options = []

	if not game.can_control(unit):
		options.append(INSPECT)
		if not game.squad_manager.any_squad_active():
			options.append(ENDTURN)
		return options

	if unit.squad.has_any_queued_actions() and unit.is_leader():
		options.append(EXECUTE_ORDERS)

	if not unit.has_action_type_queued(BaseAction.ActionType.MOVE) and not unit.has_main_action_queued() and not unit.squad.has_acted and not game.squad_manager.is_another_squad_active(unit.squad):
		options.append(MOVE)

	if unit.is_leader() and unit.has_squad() \
		and not unit.has_action_type_queued(BaseAction.ActionType.MOVE) \
		and not unit.squad.has_acted \
		and not game.squad_manager.is_another_squad_active(unit.squad):
		options.append(GROUP_MOVE)

	if _can_take_main_action(unit) and unit.has_equipped_weapon() and unit.can_wield_equipped():
		options.append(ATTACK)

	if _can_take_main_action(unit) and not RulesService.adjacent_downed_allies(unit, game._board()).is_empty() and unit.can_rescue_carry():
		options.append(RESCUE)

	if _can_take_main_action(unit) and unit.can_rally():
		options.append(RALLY)

	if _can_take_main_action(unit) and unit.unit_instance.has_live_ability(Abilities.Id.INTIMIDATION) and not RulesService.adjacent_enemies(unit, game._board()).is_empty():
		options.append(INTIMIDATE)

	if _can_take_main_action(unit) and unit.can_reload_weapon():
		options.append(SPRING_LOAD)

		#Once Squad is active, squad state cannot change through actions
	if not unit.squad.has_any_queued_actions() and not unit.squad.has_acted and not game.squad_manager.any_squad_active():
		if game.squad_manager.can_create_any_squad(unit):
			options.append(SQUADUP)
		if game.squad_manager.can_join_any_squad(unit):
			options.append(JOINSQUAD)
		if unit.has_squad():
			options.append(LEAVESQUAD)
			if unit.squad.get_leader() == unit:
				options.append(DISBAND_SQUAD)

	if unit != null:
		options.append(INSPECT)

	if game.squad_manager.active_squad == null:
		options.append(WAIT)
		options.append(ENDTURN)

	if unit != null and unit.has_any_actions(): #TODO separate general cancel and cancel queued plans
		options.append(CANCEL)

	var ordered := []
	for id in ACTION_DATA:
		if options.has(id):
			ordered.append(id)
	return ordered
