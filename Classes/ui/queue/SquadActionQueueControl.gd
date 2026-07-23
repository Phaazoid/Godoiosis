extends Control
class_name SquadActionQueueControl

@onready var sections_box: VBoxContainer = $BackgroundPanel/MarginContainer/VBox/OuterScroll/SectionsBox
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
var _drag_row: ActionQueueRow = null
var _drag_section: VBoxContainer = null
var _drag_dirty := false
var _expanded_actors: Dictionary = {}                  # actor instance_id -> bool (volley expanded?)
var _last_entries: Array[ActionQueueDisplayEntry] = []  # cached so a toggle re-renders without the backend


signal execute_requested
signal cancel_requested(action: BaseAction)
signal row_hover_changed(action: BaseAction, hovering: bool)
signal reorder_attacks_requested(ordered_actors: Array)

func _ready() -> void:
	execute_button.text = "Execute Orders"
	execute_button.focus_mode = Control.FOCUS_NONE
	execute_button.pressed.connect(_execute)
	set_process(false)

func _execute():
	execute_requested.emit()
	execute_button.hide()

func show_display_entries(entries: Array[ActionQueueDisplayEntry]):
	if entries == null:
		_last_entries = []
	else:
		_last_entries = entries.duplicate()
	_render()

func _render() -> void:
	_clear_sections()

	if _last_entries.is_empty():
		visible = false
		return

	visible = true
	execute_button.show()

	var current_list: VBoxContainer = null
	var i := 0
	while i < _last_entries.size():
		var entry: ActionQueueDisplayEntry = _last_entries[i]
		if entry == null:
			i += 1
			continue
		match entry.entry_type:
			ActionQueueDisplayEntry.EntryType.HEADER:
				current_list = _start_section(entry.label)
				i += 1
			ActionQueueDisplayEntry.EntryType.DIVIDER:
				i += 1
			ActionQueueDisplayEntry.EntryType.ACTION:
				if current_list == null:
					current_list = _start_section("")
				if _is_attack_action(entry.action):
					var group := _collect_volley_group(i)
					if group.size() > 1:
						_add_volley_group(current_list, group)
					else:
						_make_row(current_list, entry.action, 0, true)   # single attack: draggable
					i += group.size()
				else:
					_make_row(current_list, entry.action, entry.indent_level, false)
					i += 1
			_:
				i += 1

	# Cap each section's height once rows have a measured min size (snapshot: a re-render can
	# rebuild _section_scrolls while we await).
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

func _is_attack_action(a: BaseAction) -> bool:
	return a is AttackAction and not a is CounterAttackAction

# A volley = the run of consecutive attack entries sharing one actor (members come out of
# resolve_plan together). One actor per aim, so this also yields singletons for normal attacks.
func _collect_volley_group(start: int) -> Array[BaseAction]:
	var actor: Unit = _last_entries[start].action.actor
	var group: Array[BaseAction] = []
	var j := start
	while j < _last_entries.size():
		var e: ActionQueueDisplayEntry = _last_entries[j]
		if e == null or e.entry_type != ActionQueueDisplayEntry.EntryType.ACTION:
			break
		if not _is_attack_action(e.action) or e.action.actor != actor:
			break
		group.append(e.action)
		j += 1
	return group

func _add_volley_group(list: VBoxContainer, group: Array[BaseAction]) -> void:
	var actor: Unit = group[0].actor
	var expanded: bool = _expanded_actors.get(actor.get_instance_id(), false)
	# Header is one token. Draggable only when collapsed ("minimized to drag").
	var header := _new_row(list, 0)
	header.setup_volley_summary(group[0] as AttackAction, group.size(), expanded)
	header.draggable = not expanded
	_wire_row(header)
	if expanded:
		# Header is a pure designator — ALL hits spread into the folder beneath it (incl. the first).
		for k in range(group.size()):
			_make_row(list, group[k], 1, false)

func _make_row(list: VBoxContainer, action: BaseAction, indent_level: int, draggable: bool) -> ActionQueueRow:
	var row := _new_row(list, indent_level)
	row.setup(action)
	row.draggable = draggable
	_wire_row(row)
	return row

func _new_row(list: VBoxContainer, indent_level: int) -> ActionQueueRow:
	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_left", indent_level * 18)
	list.add_child(wrapper)
	var row: ActionQueueRow = ACTION_ROW_SCENE.instantiate()
	wrapper.add_child(row)
	return row

func _wire_row(row: ActionQueueRow) -> void:
	row.cancel_requested.connect(func(a): cancel_requested.emit(a))
	row.hover_changed.connect(func(a, h): row_hover_changed.emit(a, h))
	row.drag_requested.connect(_on_row_drag_requested)

func clear():
	current_squad = null
	visible = false
	_clear_sections()
	_expanded_actors.clear()

func _clear_sections():
	_section_scrolls.clear()
	for child in sections_box.get_children():
		child.queue_free()

func _on_row_drag_requested(row: ActionQueueRow) -> void:
	if not is_instance_valid(row):
		return
	_drag_row = row
	_drag_section = row.get_parent().get_parent() as VBoxContainer   # row -> MarginContainer wrapper -> section VBox
	_drag_dirty = false
	row.modulate = Color(1, 1, 1, 0.6)                               # lift cue
	set_process(true)

func _process(_delta: float) -> void:
	if _drag_row == null:
		return
	if not is_instance_valid(_drag_row) or not is_instance_valid(_drag_section):
		_cancel_drag()                                              # a refresh freed our rows mid-drag
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_drag()
		return
	_update_drag()

func _update_drag() -> void:
	if not _drag_row.draggable:
		return
	var wrapper: Control = _drag_row.get_parent()
	if wrapper == null:
		return
	var mouse_y := wrapper.get_global_mouse_position().y
	# New index = how many OTHER rows the cursor has dropped past (below their vertical center).
	var target_index := 0
	for sib in _drag_section.get_children():
		if sib == wrapper:
			continue
		var r := (sib as Control).get_global_rect()
		if mouse_y > r.position.y + r.size.y * 0.5:
			target_index += 1
	if target_index != wrapper.get_index():
		_drag_section.move_child(wrapper, target_index)
		_drag_dirty = true

func _end_drag() -> void:
	var section := _drag_section
	var row := _drag_row
	var dirty := _drag_dirty
	if is_instance_valid(row):
		row.modulate = Color(1, 1, 1, 1)
	_drag_row = null
	_drag_section = null
	_drag_dirty = false
	set_process(false)

	if dirty and is_instance_valid(section):
		var ordered_actors: Array = []
		for sib in section.get_children():
			var r := _row_in(sib)
			if r != null and r.is_attack_row() and r.action.actor != null and not ordered_actors.has(r.action.actor):
				ordered_actors.append(r.action.actor)
		reorder_attacks_requested.emit(ordered_actors)
		return

	# No movement = a click. On a volley header, that toggles expand/collapse (UI-only re-render).
	if is_instance_valid(row) and row.is_volley_header and row.action != null and is_instance_valid(row.action.actor):
		var id := row.action.actor.get_instance_id()
		_expanded_actors[id] = not _expanded_actors.get(id, false)
		_render()

func _cancel_drag() -> void:
	if is_instance_valid(_drag_row):
		_drag_row.modulate = Color(1, 1, 1, 1)
	_drag_row = null
	_drag_section = null
	_drag_dirty = false
	set_process(false)

func _row_in(wrapper: Node) -> ActionQueueRow:
	if wrapper == null or wrapper.get_child_count() == 0:
		return null
	return wrapper.get_child(0) as ActionQueueRow
