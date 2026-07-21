extends BaseAction
class_name IntimidateAction

# Intimidation (Action, docs/design/jobs.md "The ability chassis"): a plannable main-action
# Will-drain. Mirrors RescueAction's shape — a targeted action outside PlanResolver's pass,
# not a weapon attack — with a known simplification: its preview shows the drain amount
# accurately, but doesn't thread into PlanResolver's same-pass maim-cliff prediction the way
# a queued attack does (that would mean threading this action into the resolver's _Hypo
# dictionary, a bigger change than this seed pass attempts).

const INTIMIDATE_ICON := preload("res://Art/Icons/IntimidateIcon.png")

var target: Unit   # the enemy being intimidated

func init(intimidator: Unit, victim: Unit) -> void:
	actor = intimidator
	target = victim
	action_type = BaseAction.ActionType.INTIMIDATE

func execute() -> void:
	begin_execution()
	if target != null and is_instance_valid(target):
		target.unit_instance.set_current_will(target.unit_instance.get_current_will() - Abilities.INTIMIDATION_WILL_DRAIN)
	finish_execution()

func actor_can_perform() -> bool:
	return actor.unit_instance.has_live_ability(Abilities.Id.INTIMIDATION)

func get_description() -> String:
	if target != null and is_instance_valid(target):
		return "%s intimidates %s" % [actor.get_unit_name(), target.get_unit_name()]
	return "%s intimidates" % actor.get_unit_name()

func get_target_texture() -> Texture2D:
	if target != null and is_instance_valid(target):
		return target.get_map_sprite_texture()
	return null
	
func get_action_icon() -> Texture2D:
	return INTIMIDATE_ICON
