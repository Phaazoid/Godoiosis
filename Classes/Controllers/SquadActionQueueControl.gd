extends Control
class_name SquadActionQueueControl

@onready var action_list: VBoxContainer = $BackgroundPanel/MarginContainer/ScrollContainer/ActionListBox
@onready var scroll_container: ScrollContainer = $BackgroundPanel/MarginContainer/ScrollContainer

const ACTION_ROW_SCENE := preload("res://Scenes/ActionQueueRow.tscn")
var current_squad = null

func show_display_entries(entries: Array[ActionQueueDisplayEntry]):
	_clear_rows()

	if entries == null:
		visible = false
		return

	if not entries is Array:
		visible = false
		return

	if entries.is_empty():
		visible = false
		return

	visible = true

	for entry in entries:
		if entry == null:
			continue

		match entry.entry_type:
			ActionQueueDisplayEntry.EntryType.HEADER:
				_add_header(entry.label)
			ActionQueueDisplayEntry.EntryType.DIVIDER:
				_add_divider()
			ActionQueueDisplayEntry.EntryType.ACTION:
				_add_action_row(entry.action, entry.indent_level)

	await get_tree().process_frame
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value

func _add_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	action_list.add_child(label)

func _add_divider() -> void:
	var separator := HSeparator.new()
	action_list.add_child(separator)
	
func _add_action_row(action: BaseAction, indent_level: int = 0) -> void:
	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_left", indent_level * 18)
	action_list.add_child(wrapper)

	var row: ActionQueueRow = ACTION_ROW_SCENE.instantiate()
	wrapper.add_child(row)
	row.setup(action)

func clear():
	current_squad = null
	visible = false
	_clear_rows()
	
func _clear_rows():
	for child in action_list.get_children():
		child.queue_free()
