extends BaseAction
class_name RevAction

# Rev (#84): the Chainsword's signature main action. Mirrors SpringLoadAction's shape exactly —
# self-only, no resolver pass, a plain state mutation on execute(). While the wielder's chainsword
# is revved, every attack it makes ignores the target's DEF (PlanResolver's mitigation stage).
# Named per-mechanic like SpringLoad/Rally/Intimidate; its body drives the generic
# Unit.can_rev_weapon()/rev_weapon() seam.

const REV_ICON := preload("res://Art/Icons/WeaponIcons/Chainsword.png")   # placeholder

func init(rever: Unit) -> void:
	actor = rever
	action_type = BaseAction.ActionType.REV

func execute() -> void:
	begin_execution()
	if actor != null and is_instance_valid(actor):
		actor.rev_weapon()
	finish_execution()

func actor_can_perform() -> bool:
	return actor.can_rev_weapon()

func get_description() -> String:
	return "%s revs up" % actor.get_unit_name()

func get_action_icon() -> Texture2D:
	return REV_ICON

func get_target_texture() -> Texture2D:
	if actor != null and is_instance_valid(actor):
		return actor.get_map_sprite_texture()
	return null
