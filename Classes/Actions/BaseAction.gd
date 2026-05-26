extends RefCounted
class_name BaseAction

var actor: Unit
var priority
var action_type: ActionType

var is_valid := true
var validation_errors: Array[String] = []

enum ActionType {
	MOVE,
	ATTACK,
	WAIT,
	SQUAD_MOVE
}

func get_actor_texture() -> Texture2D:
	if actor == null:
		return null
	
	if actor.is_leader() and actor.has_squad():
		return preload("res://Art/Icons/CrownIcon.png")	
	
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

func execute():
	pass
