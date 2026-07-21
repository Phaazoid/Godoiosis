extends RefCounted
class_name BaseAction

# Base of every player order: actor + ActionType + validation state + the execute()
# lifecycle, plus the display hooks (icon/description/textures) the queue panel reads.

var actor: Unit
var action_type: ActionType

var execution_complete := false
var is_valid := true
var validation_errors: Array[String] = []

enum ActionType {
	MOVE,
	ATTACK,
	COUNTER_ATTACK,
	RESCUE,
	RALLY,
	INTIMIDATE
}

# The action registry: a new action type is added to the enum + whichever lists apply.
# Menu gating, execution phases, queue-panel sections, and the Play API all key off
# these lists instead of keeping their own.

# Main actions are the mutually-exclusive headline orders — a unit gets at most ONE per
# turn, and it must come after any move. MOVE stays separate.
const MAIN_ACTION_TYPES: Array[ActionType] = [
	ActionType.ATTACK,
	ActionType.RESCUE,
	ActionType.RALLY,
	ActionType.INTIMIDATE,
]

# Execution order of the side-channel tail — stored orders that bypass PlanResolver
# (resolver-backed attacks/counters run between MOVE and these). execute_orders, the
# queue panel's sections, and the Play API iterate THIS list.
const SIDE_CHANNEL_ORDER: Array[ActionType] = [
	ActionType.RESCUE,
	ActionType.RALLY,
	ActionType.INTIMIDATE,
]

func is_main_action() -> bool:
	return MAIN_ACTION_TYPES.has(action_type)

# Actor-intrinsic requirement for queueing this action; subclasses override (move ordering,
# verb locks, ability gates). SquadManager.queue_action is the sole enforcement point
# (Law #3). Plan-context checks (adjacency, occupancy) belong to plan validation instead.
func actor_can_perform() -> bool:
	return true

func get_actor_texture() -> Texture2D:
	if actor == null or not is_instance_valid(actor):
		return null
	return actor.get_map_sprite_texture()

func get_action_icon() -> Texture2D:
	return null
	
func get_target_texture() -> Texture2D:
	return null
	
func get_description() -> String:
	return "Action"

func clear_validation_errors():
	is_valid = true
	validation_errors.clear()
	
func add_validation_error(message: String):
	is_valid = false
	validation_errors.append(message)

func get_action_name() -> String:
	return ActionType.keys()[action_type]

func get_actor_modulate() -> Color:
	if actor == null:
		return Color.WHITE
		
	return actor.modulate
	
func get_ui_modulate() -> Color:
	if is_valid:
		return Color.WHITE
		
	return Color(1, .25, .25, 1)
	
func begin_execution():
	execution_complete = false
	
func finish_execution():
	execution_complete = true

func execute():
	finish_execution()
	
func clear_validation_messages():
	validation_errors.clear()
