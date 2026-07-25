extends BaseAction
class_name BurrowAction

# Burrow (#84): the Drill's signature main action, queued via the Weapon Action submenu like Rev/
# Spring Load. Self-targeted, but its consequence is TERRAIN, not unit state — it lays a permanent
# COVER tile on the burrower's own cell (flat DEF to whoever stands there; PlanResolver's mitigation
# stage reads it, a revved Chainsword pierces it). The deposit is derived in SquadManager.resolve_plan
# as a COVER cell-effect (preview == execution, R3), so execute() is a pure no-op.

const BURROW_ICON := preload("res://Art/Icons/WeaponIcons/Drill.png")   # placeholder

func init(burrower: Unit) -> void:
	actor = burrower
	action_type = BaseAction.ActionType.BURROW

func execute() -> void:
	begin_execution()
	finish_execution()

func actor_can_perform() -> bool:
	return actor.can_burrow_weapon()

func get_description() -> String:
	return "%s burrows cover" % actor.get_unit_name()

func get_action_icon() -> Texture2D:
	return BURROW_ICON

func get_target_texture() -> Texture2D:
	if actor != null and is_instance_valid(actor):
		return actor.get_map_sprite_texture()
	return null
