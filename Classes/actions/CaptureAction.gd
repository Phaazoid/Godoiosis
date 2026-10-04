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
# MissionState is stamped for the same reason AttackAction stamps fired_attack -- an action has no
# game ref, and the alternative is a per-type mirror in OrderExecutor, which is exactly what the
# action registry exists to avoid. The state rather than the game's MissionController because both
# hosts own one (#46); the game hears the claim off MissionState.zone_captured.

const CAPTURE_ICON := preload("res://Art/Icons/BoardIcons/SelectedIcon.png")   # placeholder

var cell: Vector2i
var zone_name: String
var mission: MissionState

func init(capturer: Unit, target_cell: Vector2i, mission_state: MissionState) -> void:
	actor = capturer
	action_type = BaseAction.ActionType.CAPTURE
	cell = target_cell
	mission = mission_state
	zone_name = mission_state.capturable_zone_at(target_cell)

func execute() -> void:
	begin_execution()
	if mission != null:
		mission.capture(zone_name)
	finish_execution()

func actor_block_reason() -> String:
	if mission == null:
		return "There is no mission to capture for."
	if zone_name == "":
		return "%s is not standing on a capture point." % actor.get_unit_name()
	if mission.is_zone_captured(zone_name):
		return "%s is already captured." % zone_name
	return ""

func get_description() -> String:
	return "%s captures %s" % [actor.get_unit_name(), zone_name]

func get_action_icon() -> Texture2D:
	return CAPTURE_ICON

func get_target_texture() -> Texture2D:
	if actor != null and is_instance_valid(actor):
		return actor.get_map_sprite_texture()
	return null
