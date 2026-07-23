extends BaseAction
class_name SpringLoadAction

# Spring Load (#73): a plannable main-action rearm. Mirrors RallyAction's shape exactly —
# self-only, no resolver pass, a plain state mutation on execute(). Named for Springspear
# specifically (matches RallyAction/IntimidateAction's precedent of concrete-per-mechanic
# actions rather than one generic "use ability" type), but its body only calls the generic
# Unit.can_reload_weapon()/reload_weapon() — a second reload-style weapon later could either
# get its own sibling action or this one could be promoted to something generic.

const SPRING_LOAD_ICON := preload("res://Art/Icons/WeaponIcons/Springspear.png")   # placeholder

func init(loader: Unit) -> void:
	actor = loader
	action_type = BaseAction.ActionType.SPRING_LOAD

func execute() -> void:
	begin_execution()
	if actor != null and is_instance_valid(actor):
		actor.reload_weapon()
	finish_execution()

func actor_can_perform() -> bool:
	return actor.can_reload_weapon()

func get_description() -> String:
	return "%s spring-loads" % actor.get_unit_name()

func get_action_icon() -> Texture2D:
	return SPRING_LOAD_ICON

func get_target_texture() -> Texture2D:
	if actor != null and is_instance_valid(actor):
		return actor.get_map_sprite_texture()
	return null
