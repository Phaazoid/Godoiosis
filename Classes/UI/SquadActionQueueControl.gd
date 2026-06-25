extends Control
class_name SquadActionQueueControl

@onready var sections_box: VBoxContainer = $BackgroundPanel/MarginContainer/VBox/SectionsBox
@onready var execute_button: Button = $BackgroundPanel/MarginContainer/VBox/ExecuteButton

const ACTION_ROW_SCENE := preload("res://Scenes/ActionQueueRow.tscn")

# A section shows up to this many pixels of rows before it scrolls internally. Tune to taste.
const SECTION_MAX_HEIGHT := 160

enum ExecuteState { DISABLED, READY, ALL_COMMITTED }

const EXECUTE_DULL := Color(0.5, 0.5, 0.5, 1.0)
const EXECUTE_BRIGHT := Color(1, 1, 1, 1)
const EXECUTE_FLASH := Color(0.5, 1.0, 0.5, 1.0)

var current_squad = null
var _section_scrolls: Array[ScrollContainer] = []
var _flash_tween: Tween = null

signal execute_requested
signal cancel_requested(action: BaseAction)
signal row_hover_changed(action: BaseAction, hovering: bool)

func _ready() -> void:
	execute_button.text = "Execute Orders"
	execute_button.focus_mode = Control.FOCUS_NONE
	execute_button.pressed.connect(_execute)
	
func _execute():
	execute_requested.emit()
	execute_button.hide()

func show_display_entries(entries: Array[ActionQueueDisplayEntry]):
	_clear_sections()

	if entries == null or not entries is Array or entries.is_empty():
		visible = false
		return

	visible = true
	execute_button.show()

	var current_list: VBoxContainer = null
	for entry in entries:
		if entry == null:
			continue
		match entry.entry_type:
			ActionQueueDisplayEntry.EntryType.HEADER:
				current_list = _start_section(entry.label)
			ActionQueueDisplayEntry.EntryType.DIVIDER:
				pass   # each section is already its own visually-separate box
			ActionQueueDisplayEntry.EntryType.ACTION:
				if current_list == null:
					current_list = _start_section("")
				_add_action_row(current_list, entry.action, entry.indent_level)

	# Cap each section's height once the rows have a measured min size. Snapshot first: another
	# refresh can re-enter and rebuild _section_scrolls while we're awaiting.
	var scrolls := _section_scrolls.duplicate()
	await get_tree().process_frame
	for scroll in scrolls:
		if not is_instance_valid(scroll) or scroll.get_child_count() == 0:
			continue
		var inner: Control = scroll.get_child(0)
		var content_h := inner.get_combined_minimum_size().y
		scroll.custom_minimum_size.y = min(content_h, SECTION_MAX_HEIGHT)

func set_execute_state(state: ExecuteState) -> void:
	_stop_flash()
	match state:
		ExecuteState.DISABLED:
			execute_button.disabled = true
			execute_button.modulate = EXECUTE_DULL
		ExecuteState.READY:
			execute_button.disabled = false
			execute_button.modulate = EXECUTE_BRIGHT
		ExecuteState.ALL_COMMITTED:
			execute_button.disabled = false
			execute_button.modulate = EXECUTE_BRIGHT
			_start_flash()

func _start_flash() -> void:
	_flash_tween = create_tween().set_loops()
	_flash_tween.tween_property(execute_button, "modulate", EXECUTE_FLASH, 0.5)
	_flash_tween.tween_property(execute_button, "modulate", EXECUTE_BRIGHT, 0.5)

func _stop_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null

func _start_section(title: String) -> VBoxContainer:
	if title != "":
		var header := Label.new()
		header.text = title
		sections_box.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(128, 0)
	scroll.size_flags_vertical = Control.SIZE_FILL
	sections_box.add_child(scroll)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	_section_scrolls.append(scroll)
	return inner

func _add_action_row(list: VBoxContainer, action: BaseAction, indent_level: int = 0) -> void:
	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_left", indent_level * 18)
	list.add_child(wrapper)

	var row: ActionQueueRow = ACTION_ROW_SCENE.instantiate()
	wrapper.add_child(row)
	row.setup(action)
	row.cancel_requested.connect(func(a): cancel_requested.emit(a))
	row.hover_changed.connect(func(a, h): row_hover_changed.emit(a, h))

func clear():
	current_squad = null
	visible = false
	_clear_sections()

func _clear_sections():
	_section_scrolls.clear()
	for child in sections_box.get_children():
		child.queue_free()
