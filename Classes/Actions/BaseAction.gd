extends RefCounted
class_name BaseAction

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
	RALLY
}

func is_main_action() -> bool:
	# Main actions are the mutually-exclusive headline orders — a unit gets at most ONE per
	# turn (attack, rescue, and future contenders share the slot). MOVE stays separate.
	# Add new main action types here.
	return action_type == ActionType.ATTACK or action_type == ActionType.RESCUE or action_type == ActionType.RALLY

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
