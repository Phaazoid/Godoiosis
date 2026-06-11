extends AttackAction
class_name CounterAttackAction

var source_attack: AttackAction

const COUNTER_ATTACK_ICON := preload("res://Art/Icons/CounterAttackIcoon.png")


func init_counter(counter_unit: Unit, target_unit: Unit, attack_origin: Vector2i, source: AttackAction):
	init(counter_unit, attack_origin, target_unit, target_unit.movement.cell, 5)
	action_type = ActionType.COUNTER_ATTACK
	source_attack = source
	is_reaction = true
	show_in_queue = true
	
func get_description() -> String:
	return "%s counters %s" % [actor.get_unit_name(), get_target_name()]

func get_action_icon() -> Texture2D:
	return COUNTER_ATTACK_ICON
