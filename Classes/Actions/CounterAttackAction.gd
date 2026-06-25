extends AttackAction
class_name CounterAttackAction

var source_attack: AttackAction

const COUNTER_ATTACK_ICON := preload("res://Art/Icons/CounterAttackIcoon.png")


func init_counter(counter_unit: Unit, target_unit: Unit, attack_origin: Vector2i, source: AttackAction):
	init(counter_unit, attack_origin, target_unit, target_unit.get_projected_destination())

	action_type = ActionType.COUNTER_ATTACK
	source_attack = source
	is_reaction = true
	show_in_queue = true

func get_description() -> String:
	return "%s counters %s" % [actor.get_unit_name(), get_target_name()]

func get_action_icon() -> Texture2D:
	var lethal := _lethality_icon()
	return lethal if lethal != null else COUNTER_ATTACK_ICON

static func create_counter_volley(counter_unit: Unit, origin: Vector2i, victims: Array[Unit], source: AttackAction) -> Array[CounterAttackAction]:
	var counters: Array[CounterAttackAction] = []
	var volley: Array[AttackAction] = []
	for victim in victims:
		var counter := CounterAttackAction.new()
		counter.init_counter(counter_unit, victim, origin, source)
		counter.is_secondary_hit = not counters.is_empty()   # only the first lunges
		counters.append(counter)
		volley.append(counter)
	for counter in counters:
		counter.volley = volley
	return counters
