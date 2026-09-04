extends Control
class_name SquadActionQueueControl

# The action-queue panel: renders a squad's plan as sectioned rows (via ActionQueueDisplayEntry)
# with drag-reorder and the Execute button. A section IS an action type and a drag never leaves its
# own section, so the sections are the pass's phase order and the rows inside one are its clock
# (#412). Which rows may be dragged is the ORDER's answer, not this panel's -- see
# ActionQueueRow.is_reorderable_row. Layout invariant (#160): the scene ROOT
# is full-rect with mouse_filter IGNORE — never STOP, or it eats every board click — and
# BackgroundPanel is anchored to the RIGHT edge so the dock follows a window resize; don't let
# an editor resave quietly restore absolute offsets.
#
# The chain under BackgroundPanel is FULL-RECT and must stay so (#685). It used to be a
# MarginContainer at absolute offsets (~64x32) inside a 145x465 panel, so every child overflowed
# its own box -- which is what clipped the section headers at any resolution. The panel is 216
# design-px wide now; only offset_left moved, so the dock's 7px edge gap is unchanged.
#
# Its LOOK lives in QueueStyle, not here: sections and rows are code-built, so their chrome cannot
# be a .tscn sub-resource, and one file answering "what colour is the queue" is what keeps this
# panel from drifting off the inspect panel it was matched to. That file answers it for TWO palettes
# since round 5 -- the player picks, this panel only re-applies.

@onready var sections_box: VBoxContainer = $BackgroundPanel/MarginContainer/VBox/OuterScroll/SectionsBox
@onready var execute_button: Button = $BackgroundPanel/MarginContainer/VBox/ExecuteButton
@onready var title_label: Label = $BackgroundPanel/MarginContainer/VBox/Title
@onready var background_panel: Panel = $BackgroundPanel

const ACTION_ROW_SCENE := preload("res://Scenes/ActionQueueRow.tscn")

enum ExecuteState { DISABLED, READY, ALL_COMMITTED }

const EXECUTE_DULL := Color(0.5, 0.5, 0.5, 1.0)
const EXECUTE_BRIGHT := Color(1, 1, 1, 1)
const EXECUTE_FLASH := Color(0.5, 1.0, 0.5, 1.0)

var current_squad = null
var _flash_tween: Tween = null
var _drag_row: ActionQueueRow = null
var _drag_section: VBoxContainer = null
var _drag_dirty := false
var _expanded_actors: Dictionary = {}                  # actor instance_id -> bool (volley expanded?)
var _last_entries: Array[ActionQueueDisplayEntry] = []  # cached so a toggle re-renders without the backend
# Hidden while a cinematic pass owns the frame (#722), and what the CONTENT rule last decided.
# Two fields because the playback edge must re-apply the gate WITHOUT re-deriving the content half:
# game.refresh_action_queue refuses to run at all while a pass is executing (#361), and the release
# edge fires before `executing_plan` is cleared -- so routing the re-apply through it would leave
# this panel hidden for the rest of the mission. Storing what _render decided is what makes the
# gate re-applicable on its own.
var _hidden_for_playback := false
var _content_shown := false


signal execute_requested
signal cancel_requested(action: BaseAction)
signal row_hover_changed(action: BaseAction, hovering: bool)
signal reorder_requested(action_type: BaseAction.ActionType, ordered_actors: Array)

func _ready() -> void:
	execute_button.text = "Execute Orders"
	execute_button.focus_mode = Control.FOCUS_NONE
	execute_button.pressed.connect(_execute)
	_apply_chrome()
	set_process(false)

# The PANEL's own chrome, as against the rows' -- the frame, the title and Execute. Its own function
# only so restyle() can re-apply it; see there for why that matters.
func _apply_chrome() -> void:
	background_panel.add_theme_stylebox_override("panel", QueueStyle.panel_box())
	title_label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.TITLE_TEXT))
	# The engine's default button chrome is grey on a grey panel, so Execute vanished into the dock
	# (dev, 2026-09-03). Its DISABLED look is still set_execute_state's EXECUTE_DULL modulate over
	# this, rather than a second stylebox nobody would keep in sync.
	execute_button.add_theme_stylebox_override("normal", QueueStyle.execute_box())
	execute_button.add_theme_stylebox_override("hover", QueueStyle.execute_hover_box())
	execute_button.add_theme_stylebox_override("pressed", QueueStyle.execute_hover_box())
	execute_button.add_theme_stylebox_override("disabled", QueueStyle.execute_box())
	var execute_text := QueueStyle.ink(QueueStyle.Role.EXECUTE_TEXT)
	execute_button.add_theme_color_override("font_color", execute_text)
	execute_button.add_theme_color_override("font_hover_color", execute_text)
	execute_button.add_theme_color_override("font_disabled_color", execute_text)

# Repaint what is already on screen, with no trip through the backend (#685). The dev's element
# colours are knobs, so a slider drag needs the rows to re-read them -- and a resolve per tick is
# what the mission-HUD's own re-apply door would have cost. `_render` re-reads _last_entries, which
# the volley toggle already relied on; the Execute button's visibility is preserved across it
# because a restyle is not a plan change and must not un-hide a button a running pass hid.
#
# THE CHROME IS RE-APPLIED FIRST AND UNCONDITIONALLY (round 5). It used to be set once in _ready,
# which is invisible while a palette is fixed and wrong the moment one is not: a swap re-rendered
# every row and left the frame, the title and Execute wearing the palette the game booted in. Above
# the early return on purpose -- an empty queue has no rows to re-render, and its panel still has to
# be right before the next order shows it.
func restyle() -> void:
	_apply_chrome()
	if _last_entries.is_empty():
		return
	var was_showing := execute_button.visible
	_render()
	execute_button.visible = was_showing

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
		_content_shown = false
		_apply_visibility()
		return

	_content_shown = true
	_apply_visibility()
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
				# An INDENTED entry is a DERIVED row (#592): a watch shot hanging off the walk that
				# took it. Asked FIRST, because a watch shot is an AttackAction and would otherwise
				# be volley-grouped and made draggable -- it is nobody's order to sequence.
				if entry.indent_level > 0:
					_make_row(current_list, entry.action, entry.indent_level, false)
					i += 1
				elif _is_attack_action(entry.action):
					var group := _collect_volley_group(i)
					if group.size() > 1:
						_add_volley_group(current_list, group)
					else:
						_make_row(current_list, entry.action, 0, true)   # single attack: draggable
					i += group.size()
				else:
					# Moves and the side-channel verbs drag too (#412) -- the order decides.
					_make_row(current_list, entry.action, entry.indent_level, entry.action.is_reorderable())
					i += 1
			_:
				i += 1


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
	_flash_tween = Pulse.start(self, execute_button, &"modulate", EXECUTE_BRIGHT, EXECUTE_FLASH)

func _stop_flash() -> void:
	Pulse.stop(_flash_tween, execute_button, &"modulate", EXECUTE_BRIGHT)
	_flash_tween = null

# A section is a bordered CARD with its own header strip (#685) -- the delineation the dev asked
# for. ONE SCROLL IN THE PANEL, THE OUTER ONE: each section used to own a ScrollContainer capped at
# 160px, so a section began scrolling while the dock still had empty space below it -- "if there is
# space available, we shouldn't be using scrollbars, we should be stretching to fit it until there's
# none left" (dev, 2026-09-03). Sections take their natural height now and OuterScroll handles the
# overflow, which deleted the cap, the scroll list and the measure-after-a-frame pass with it.
#
# The row list is still a plain VBox whose children are the per-row indent wrappers, so the drag's
# row -> wrapper -> list walk is unchanged.
func _start_section(title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", QueueStyle.section_box())
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sections_box.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)

	if title != "":
		var header_box := PanelContainer.new()
		header_box.add_theme_stylebox_override("panel", QueueStyle.header_box())
		header_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(header_box)

		var header := Label.new()
		header.text = title
		header.add_theme_font_size_override("font_size", QueueStyle.HEADER_FONT_SIZE)
		header.add_theme_color_override("font_color", QueueStyle.HEADER_TEXT)
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_box.add_child(header)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 0)   # each row wrapper carries its own gap
	col.add_child(inner)
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

# The wrapper carries the indent AND the row's clearance from its section card's edges -- the row
# must stay its SOLE direct child, because both the drag's section lookup
# (row -> wrapper -> inner VBox) and _row_in's get_child(0) are counted in hops.
func _new_row(list: VBoxContainer, indent_level: int) -> ActionQueueRow:
	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_left", indent_level * 18 + QueueStyle.ROW_INSET)
	wrapper.add_theme_constant_override("margin_right", QueueStyle.ROW_INSET)
	wrapper.add_theme_constant_override("margin_top", QueueStyle.ROW_GAP)
	wrapper.add_theme_constant_override("margin_bottom", QueueStyle.ROW_GAP)
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
	_content_shown = false
	_apply_visibility()
	_clear_sections()
	_expanded_actors.clear()

# #722's one input, and the gate both halves write through. Deliberately NOT `_render()` -- that
# rebuilds every section, and a playback edge has not changed a single row.
func set_hidden_for_playback(hidden: bool) -> void:
	_hidden_for_playback = hidden
	_apply_visibility()

func _apply_visibility() -> void:
	visible = _content_shown and not _hidden_for_playback

func _clear_sections():
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

	if dirty and is_instance_valid(section) and is_instance_valid(row) and row.action != null:
		# A section holds ONE action type, so the dragged row names the type being resequenced.
		var reordered_type: BaseAction.ActionType = row.action.action_type
		var ordered_actors: Array = []
		for sib in section.get_children():
			var r := _row_in(sib)
			if r != null and r.is_reorderable_row() and r.action.actor != null and not ordered_actors.has(r.action.actor):
				ordered_actors.append(r.action.actor)
		reorder_requested.emit(reordered_type, ordered_actors)
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
