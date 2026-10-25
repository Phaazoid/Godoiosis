extends AttackAction
class_name CounterAttackAction

# A REACTION — derived fresh from the attack plan each resolve pass, never stored as a player
# order (Law #2; see SquadManager.calculate_reactions_for_squad / create_counter_volley). Fires
# whatever the counter-er's body, as the pass has left it, decides (UnitState.counter_attack): a weapon
# ALWAYS counters with its main attack regardless of any live pick, while a rune counters with
# whatever it would currently fire (#30/#72).
#
# Always a STRIKE at the attacking party. It had a second kind, a reactive heal on the defender's own
# side (#148), until the dev repealed it (2026-09-28); a heal never counters now (AttackData.can_ever_counter).

var source_attack: AttackAction

const COUNTER_ATTACK_ICON := preload("res://Art/Icons/ActionIcons/CounterAttackIcon.png")


# A null target is a CELL counter aimed at its own origin -- only ever a payload with nobody in reach
# (#1058), which still goes off; a counter proper always has somebody to answer.
func init_counter(counter_unit: Unit, target_unit: Unit, attack_origin: Vector2i, source: AttackAction):
	var aim := attack_origin if target_unit == null else target_unit.get_projected_destination()
	init(counter_unit, attack_origin, target_unit, aim)

	action_type = ActionType.COUNTER_ATTACK
	source_attack = source

func is_reorderable() -> bool:
	return false   # derived, never queued — its section is inert (#412)

func get_description() -> String:
	if fired_attack != null and fired_attack.heals:
		return "%s heals %s" % [actor.get_unit_name(), get_target_name()]
	return "%s counters %s" % [actor.get_unit_name(), get_target_name()]

func get_action_icon() -> Texture2D:
	var lethal := lethality_icon(resolved)
	return lethal if lethal != null else COUNTER_ATTACK_ICON

# Every counter volley comes out of this one factory. `chosen` is the attack the volley fires, decided
# by the caller and HANDED IN (#1480 stage 4): a counter's is the counter-er's body as the pass left
# it (UnitState.counter_attack), a counter's PAYLOAD (#1058, PlanResolver.drop_payloads) is the payload
# itself. One `null` victim is a cell attack with nobody in reach: a payload always goes off.
static func create_counter_volley(counter_unit: Unit, chosen: AttackData, origin: Vector2i, victims: Array[Unit], source: AttackAction, footprint: Array[Vector2i], arc_links: Array[Conduction.Link] = []) -> Array[CounterAttackAction]:
	var counters: Array[CounterAttackAction] = []
	var volley: Array[AttackAction] = []
	for victim in victims:
		var counter := CounterAttackAction.new()
		counter.init_counter(counter_unit, victim, origin, source)
		counter.fired_attack = chosen
		counter.footprint = footprint
		counter.arc_links = arc_links   # a shock counter arcs, so it is drawn arcing (#887)
		counter.is_secondary_hit = not counters.is_empty()   # only the first lunges
		counters.append(counter)
		volley.append(counter)
	for counter in counters:
		counter.volley = volley
	return counters
