extends AttackAction
class_name CounterAttackAction

# A counter-attack — derived fresh from the attack plan each resolve pass, never stored as a
# player order (Law #2; see SquadManager.calculate_counterattacks_for_squad / create_counter_
# volley). Fires whatever Unit.get_counter_attack() decides: a weapon ALWAYS counters with its
# main attack regardless of any live pick, while a rune counters with whatever it would currently
# fire (#30/#72).

var source_attack: AttackAction

const COUNTER_ATTACK_ICON := preload("res://Art/Icons/CounterAttackIcoon.png")


func init_counter(counter_unit: Unit, target_unit: Unit, attack_origin: Vector2i, source: AttackAction):
	init(counter_unit, attack_origin, target_unit, target_unit.get_projected_destination())

	action_type = ActionType.COUNTER_ATTACK
	source_attack = source

func get_description() -> String:
	return "%s counters %s" % [actor.get_unit_name(), get_target_name()]

func get_action_icon() -> Texture2D:
	var lethal := _lethality_icon()
	return lethal if lethal != null else COUNTER_ATTACK_ICON

static func create_counter_volley(counter_unit: Unit, origin: Vector2i, victims: Array[Unit], source: AttackAction) -> Array[CounterAttackAction]:
	var counters: Array[CounterAttackAction] = []
	var volley: Array[AttackAction] = []
	# The attack this unit fires reactively: a rune counters with whatever it would currently
	# fire (unchanged #30 quirk); a weapon ALWAYS counters with its main attack (#72 ruling —
	# overwatch-style alt-attack countering is out of scope, #73). Derived here, not stored, so
	# the counter's damage/elements/pattern match what get_counter_attack() decided.
	var chosen := counter_unit.get_counter_attack()
	for victim in victims:
		var counter := CounterAttackAction.new()
		counter.init_counter(counter_unit, victim, origin, source)
		counter.fired_attack = chosen
		counter.is_secondary_hit = not counters.is_empty()   # only the first lunges
		counters.append(counter)
		volley.append(counter)
	for counter in counters:
		counter.volley = volley
	return counters
