extends BaseAction
class_name MoveAction

var path: Array[Vector2i]
var destination: Vector2i

func init(unit: Unit, move_path: Array[Vector2i]):
	actor = unit
	path = move_path
	destination = path.back()
	action_type = ActionType.MOVE
	
func execute():
	actor.movement.move_along_path(path)
