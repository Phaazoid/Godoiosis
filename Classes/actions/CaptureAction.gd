extends BaseAction
class_name CaptureAction

# Claiming an objective zone by standing in it (#96 slice 3, docs/design/missions.md). Instant and
# uncontested in v1 (fork D): one main action, the zone is yours, nobody takes it back.
#
# A capture point is just a ZoneManager zone of kind CAPTURE -- there is no separate objective
# store. Standing anywhere inside claims the whole zone.
#
# Both the cell and the zone name are stamped at queue time rather than read at execute time: Law
# #2 says the queue previewed THIS cell. If a re-planned move walks the actor off the point,
# SquadPlanValidator invalidates the order instead of quietly capturing somewhere else. The
# MissionController ref is stamped for the same reason AttackAction stamps fired_attack -- an
# action has no game ref, and the alternative is a per-type mirror in OrderExecutor, which is
# exactly what the action registry exists to avoid.

const CAPTURE_ICON := preload("res://Art/Icons/BoardIcons/SelectedIcon.png")   # placeholder

var cell: Vector2i
var zone_name: String
var controller: MissionController

func init(capturer: Unit, target_cell: Vector2i, mission: MissionController) -> void:
	actor = capturer
	action_type = BaseAction.ActionType.CAPTURE
	cell = target_cell
	controller = mission
	zone_name = mission.capturable_zone_at(target_cell)

func execute() -> void:
	begin_execution()
	if controller != null and is_instance_valid(controller):
		controller.capture(zone_name)
	finish_execution()

func actor_can_perform() -> bool:
	return controller != null and zone_name != "" and not controller.is_zone_captured(zone_name)

func get_description() -> String:
	return "%s captures %s" % [actor.get_unit_name(), zone_name]

func get_action_icon() -> Texture2D:
	return CAPTURE_ICON

func get_target_texture() -> Texture2D:
	if actor != null and is_instance_valid(actor):
		return actor.get_map_sprite_texture()
	return null
