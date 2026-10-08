extends BaseAction
class_name RevAction

# Rev (#84): the Chainsword's signature main action. Mirrors ReloadAction's shape exactly —
# self-only, no resolver pass, a plain state mutation on execute(). While the wielder's chainsword
# is revved, every attack it makes ignores the target's DEF (PlanResolver's mitigation stage).
# Named per-mechanic (unlike ReloadAction, which went generic once a second
# family wanted it); its body drives the generic Unit.can_rev_weapon()/rev_weapon() seam.

const REV_ICON := preload("res://Art/Icons/WeaponIcons/Chainsword.png")   # placeholder

func init(rever: Unit) -> void:
	actor = rever
	action_type = BaseAction.ActionType.REV

func execute() -> void:
	begin_execution()
	if actor != null and is_instance_valid(actor):
		actor.rev_weapon()
	finish_execution()

func actor_block_reason() -> String:
	if actor.can_rev_weapon():
		return ""
	return "%s has nothing equipped that can rev." % actor.get_unit_name()

func get_description() -> String:
	return "%s revs up" % actor.get_unit_name()

func get_action_icon() -> Texture2D:
	return REV_ICON

func get_target_texture() -> Texture2D:
	if actor != null and is_instance_valid(actor):
		return actor.get_map_sprite_texture()
	return null
