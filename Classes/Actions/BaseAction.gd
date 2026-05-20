extends RefCounted
class_name BaseAction

var actor: Unit
var priority
var action_type: ActionType

enum ActionType {
	MOVE,
	ATTACK,
	WAIT,
	SQUAD_MOVE
}

func get_action_name() -> String:
	return ActionType.keys()[action_type]

func execute():
	pass
