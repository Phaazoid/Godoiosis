extends AttackAction
class_name CounterAttackAction

var source_attack: AttackAction

func init_counter(counter_unit: Unit, target_unit: Unit, attack_origin: Vector2i, source: AttackAction):
	init(counter_unit, attack_origin, target_unit, target.movement.cell, 5)
	action_type = ActionType.COUNTER_ATTACK
	source_attack = source
	is_reaction = true
	show_in_queue = true
	
