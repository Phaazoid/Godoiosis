extends BaseAction
class_name RescueAction

const RESCUE_ICON := preload("res://Art/Icons/Rescue.png")

var target: Unit   # the downed ally being picked up

func init(rescuer: Unit, downed_ally: Unit) -> void:
	actor = rescuer
	target = downed_ally
	action_type = BaseAction.ActionType.RESCUE

func execute() -> void:
	begin_execution()
	if target != null and is_instance_valid(target) and target.is_downed():
		target.revive()
		target.squad.has_acted = true   # spent the turn it's rescued — no actions; resets next turn.
										 # (Future: Will could buy back movement/attack here.)
	finish_execution()

func actor_can_perform() -> bool:
	return actor.can_rescue_carry()   # verb lock (will-and-death.md limb model)

func get_description() -> String:
	if target != null and is_instance_valid(target):
		return "%s rescues %s" % [actor.get_unit_name(), target.get_unit_name()]
	return "%s rescues" % actor.get_unit_name()

func get_target_texture() -> Texture2D:
	if target != null and is_instance_valid(target):
		return target.get_map_sprite_texture()
	return null

func get_action_icon() -> Texture2D:
	return RESCUE_ICON
