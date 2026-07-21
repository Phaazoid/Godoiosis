extends BaseAction
class_name RallyAction

const RALLY_ICON := preload("res://Art/Icons/RallyIcon.png")

func init(rallier: Unit) -> void:
	actor = rallier
	action_type = BaseAction.ActionType.RALLY

func execute() -> void:
	begin_execution()
	if actor != null and is_instance_valid(actor):
		actor.rally()
	finish_execution()

func actor_can_perform() -> bool:
	return actor.can_rally()

func get_description() -> String:
	return "%s rallies" % actor.get_unit_name()

func get_action_icon() -> Texture2D:
	return RALLY_ICON

func get_target_texture() -> Texture2D:
	# Self-rally: the actor's own sprite sits on both sides (left uses the standard actor texture —
	# a crown if it's a squad leader). Future squad-rally would put the leader on the left here.
	if actor != null and is_instance_valid(actor):
		return actor.get_map_sprite_texture()
	return null
