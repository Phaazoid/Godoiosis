extends Control
class_name SquadActionQueueControl

@onready var action_list: VBoxContainer = $BackgroundPanel/MarginContainer/ScrollContainer/ActionListBox
@onready var scroll_container: ScrollContainer = $BackgroundPanel/MarginContainer/ScrollContainer

const ACTION_ROW_SCENE := preload("res://Scenes/ActionQueueRow.tscn")
var current_squad = null

func show_squad_actions(squad: Squad):
	current_squad = squad
	visible = true
	_rebuild()
	
func _rebuild():
	_clear_rows()
	
	if current_squad == null:
		visible = false
		return
	
	var actions = current_squad.get_actions()
	
	if actions.is_empty():
		visible = false
		return
	
	visible = true
	
	for action in actions:
		var row: ActionQueueRow = ACTION_ROW_SCENE.instantiate()
		action_list.add_child(row)
		row.setup(action)
		
	await get_tree().process_frame
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value


func clear():
	current_squad = null
	visible = false
	_clear_rows()
	
func _clear_rows():
	for child in action_list.get_children():
		child.queue_free()
