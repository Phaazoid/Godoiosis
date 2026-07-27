extends BaseAction
class_name ReloadAction

# Reload (#73 as Spring Load, generalized #84): a plannable main-action rearm. Mirrors
# RallyAction's shape exactly — self-only, no resolver pass, a plain state mutation on execute().
# Deliberately family-AGNOSTIC now that a second reload-style weapon exists: the body only calls
# the generic Unit.can_reload_weapon()/reload_weapon() seam, so a Springspear rearming its spring
# and a Carbine swapping a magazine are the same order. What the player SEES is per-family
# (WeaponInstance.reload_label() — "Spring Load" vs "Reload"); what the queue holds is one
# ActionType.RELOAD.

const RELOAD_ICON := preload("res://Art/Icons/WeaponIcons/Springspear.png")   # placeholder

func init(loader: Unit) -> void:
	actor = loader
	action_type = BaseAction.ActionType.RELOAD

func execute() -> void:
	begin_execution()
	if actor != null and is_instance_valid(actor):
		actor.reload_weapon()
	finish_execution()

func actor_can_perform() -> bool:
	return actor.can_reload_weapon()

func get_description() -> String:
	return "%s reloads" % actor.get_unit_name()

func get_action_icon() -> Texture2D:
	return RELOAD_ICON

func get_target_texture() -> Texture2D:
	if actor != null and is_instance_valid(actor):
		return actor.get_map_sprite_texture()
	return null
