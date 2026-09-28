extends VBoxContainer
class_name ReportForm

# The report FORM (#131, split out of ReportPanel by #1052): the kind toggle, the note, the status
# line and the form's own buttons. Two surfaces host it -- ReportPanel, the card every report door
# opens, and MissionEndBanner, which carries one under its verdict so the end of a mission asks by
# default. One component, so the two cannot drift apart.
#
# It is deliberately DUMB: it collects a Kind and a note, and it is TOLD the outcome. It never
# writes a file, never formats a message and never touches the transport, so "what is in a report"
# stays BugReporter's single answer. BugReporter.serve drives it, whoever hosts it.
#
# CANCELLABLE is the one fork between the hosts. The card's form backs out (Cancel, then Close after
# the outcome) because the card is a detour; the banner's does not, because the banner's own buttons
# are the only ways off it and a Close there would close nothing.

# The chosen kind and the typed note are READ off the form afterwards rather than carried on the
# signal: an enum crossing a signal boundary arrives as a bare int, and the round-trip back to a
# typed Kind is a cast with nothing to gain from it.
signal finished(submitted: bool)
signal dismissed

const NOTE_MIN_SIZE := Vector2(520, 180)
const ACTION_ROW_SEPARATION := 12
const KIND_BUTTON_SIZE := Vector2(190, 36)

var cancellable: bool

var _kind: BugReporter.Kind
var _button_size: Vector2
var _kind_buttons: Array[Button] = []
var _note_edit: TextEdit
var _status: Label
var _actions: HBoxContainer
var _report_dir: String = ""

# Styled by its HOST: the buttons take the host card's size and the rows its spacing, so a form on
# the banner and one on the card each match the card around them.
func _init(host: ModalCard, default_kind: BugReporter.Kind, can_cancel: bool) -> void:
	_kind = default_kind
	cancellable = can_cancel
	_button_size = host.button_size
	add_theme_constant_override("separation", host.content_separation)

	add_child(_build_kind_row(default_kind))

	_note_edit = TextEdit.new()
	_note_edit.custom_minimum_size = NOTE_MIN_SIZE
	_note_edit.placeholder_text = "What happened, or what did you think?"
	_note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(_note_edit)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(NOTE_MIN_SIZE.x, 0)
	_status.visible = false
	add_child(_status)

	_actions = HBoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("separation", ACTION_ROW_SEPARATION)
	add_child(_actions)
	_show_submit_actions()

func _build_kind_row(default_kind: BugReporter.Kind) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)

	# Two toggles rather than a dropdown: the choice is visible without a click, and which one is
	# selected is visible without one either.
	var group := ButtonGroup.new()
	_add_kind_button(row, group, BugReporter.Kind.BUG, "Something broke", default_kind)
	_add_kind_button(row, group, BugReporter.Kind.FEEDBACK, "Just feedback", default_kind)
	return row

func _add_kind_button(row: HBoxContainer, group: ButtonGroup, kind: BugReporter.Kind,
		label: String, default_kind: BugReporter.Kind) -> void:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = kind == default_kind
	button.custom_minimum_size = KIND_BUTTON_SIZE
	button.pressed.connect(func() -> void: _kind = kind)
	row.add_child(button)
	_kind_buttons.append(button)

# The host decides, because the banner's form is optional and a focused note box would swallow the
# first keypress a player meant for the banner.
func focus_note() -> void:
	_note_edit.grab_focus()

# ==============================================================================
#  The three states: collecting, sending, done
# ==============================================================================

func selected_kind() -> BugReporter.Kind:
	return _kind

func note_text() -> String:
	return _note_edit.text

func _show_submit_actions() -> void:
	ModalCard.clear_button_row(_actions)
	_add_action("Submit", func() -> void: finished.emit(true))
	if cancellable:
		_add_action("Cancel", func() -> void: finished.emit(false))

func show_sending() -> void:
	_note_edit.editable = false
	for button in _kind_buttons:
		button.disabled = true
	ModalCard.clear_button_row(_actions)   # no cancel: the POST is already in flight and cannot be recalled
	_status.visible = true
	_status.modulate = Color(0.85, 0.85, 0.88)
	_status.text = "Sending..."

# A silent success reads as a broken feature and they stop using it (#131 item 2), so BOTH outcomes
# say something. A failure is not a dead end -- the report is on disk and the folder opens.
func show_outcome(report_dir: String, sent: bool) -> void:
	_report_dir = report_dir
	_status.visible = true
	ModalCard.clear_button_row(_actions)

	if report_dir == "":
		_status.modulate = Color(0.95, 0.55, 0.55)
		_status.text = "Could not write the report to disk. Nothing was sent."
		_add_close()
		return

	if sent:
		_status.modulate = Color(0.6, 0.9, 0.6)
		_status.text = "Sent. Thanks!."
	else:
		_status.modulate = Color(0.95, 0.8, 0.5)
		_status.text = "Could not reach the developer, but the report was saved on this machine. You can send the folder along any other way."
		_add_action("Open Folder", func() -> void:
			OS.shell_open(ProjectSettings.globalize_path(_report_dir)))

	_add_close()

func _add_close() -> void:
	if cancellable:
		_add_action("Close", func() -> void: dismissed.emit())

func _add_action(text: String, on_pressed: Callable) -> void:
	_actions.add_child(ModalCard.make_button(text, _button_size, on_pressed))

# The card's Esc, which ReportPanel._on_cancel hands here. The mid-send arm returns TRUE while doing
# nothing: the key is TAKEN rather than acted on, so it cannot fall through to whatever is
# underneath while an upload is in flight. A form that cannot back out takes nothing.
func handle_cancel() -> bool:
	if not cancellable:
		return false
	if _actions.get_child_count() == 0:
		return true   # mid-send: nothing to back out to, and nobody else may have it either
	if _status.visible:
		dismissed.emit()
	else:
		finished.emit(false)
	return true
