extends Node
class_name ActionMenuController

var local_unit: Unit
var local_menu: PopupMenu
signal action_selected(action_id, local_unit)
signal cancelled(me)

func setup(unit: Unit):
	local_unit = unit
	local_menu = PopupMenu.new()
	add_child(local_menu)
	
	local_menu.id_pressed.connect(_on_option_selected)
	local_menu.popup_hide.connect(_on_popup_closed)
	
func setpos(pos: Vector2i):
	local_menu.position = pos

func _on_option_selected(action_id: int):
	action_selected.emit(action_id, local_unit)
	cleanup()
	
func cleanup():
	queue_free()
	
func _on_popup_closed():
	cleanup()
	cancelled.emit(self)
