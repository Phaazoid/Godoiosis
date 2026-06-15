extends AttackAction
class_name CounterAttackAction

var source_attack: AttackAction

const COUNTER_ATTACK_ICON := preload("res://Art/Icons/CounterAttackIcoon.png")


func init_counter(counter_unit: Unit, target_unit: Unit, attack_origin: Vector2i, source: AttackAction):
	var predicted_damage := counter_unit.get_base_stat("STR")
	if counter_unit.has_equipped_weapon():
		var weapon := counter_unit.get_equipped_weapon()
		predicted_damage = weapon.power + counter_unit.get_effective_stat(weapon.scaling_stat)

	init(counter_unit, attack_origin, target_unit, target_unit.get_projected_destination(), predicted_damage)
	
	action_type = ActionType.COUNTER_ATTACK
	source_attack = source
	is_reaction = true
	show_in_queue = true
	
func get_description() -> String:
	return "%s counters %s" % [actor.get_unit_name(), get_target_name()]

func get_action_icon() -> Texture2D:
	return COUNTER_ATTACK_ICON
