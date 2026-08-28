extends ModalCard
class_name ReportPanel

# The player-facing report card (#131) -- the only surface a stranger has for telling us anything
# at all. Built on ModalCard, the base shared with every other full-screen surface; it is the one
# that is a FORM rather than a choice, which is what retired the old ChoiceModal name.
#
# It is deliberately DUMB: it collects a Kind and a note, and it is TOLD the outcome. It never
# writes a file, never formats a message and never touches the transport, so "what is in a report"
# stays BugReporter's single answer. BugReporter.open_card drives the whole exchange.

# The chosen kind and the typed note are READ off the panel afterwards rather than carried on the
# signal: an enum crossing a signal boundary arrives as a bare int, and the round-trip back to a
# typed Kind is a cast with nothing to gain from it.
signal finished(submitted: bool)
signal dismissed

const NOTE_MIN_SIZE := Vector2(520, 180)
const ACTION_ROW_SEPARATION := 12

var _kind: BugReporter.Kind
var _note_edit: TextEdit
var _status: Label
var _actions: HBoxContainer
var _report_dir: String = ""

func _init() -> void:
	# BEGIN, not CENTER: this is a stacked form (toggles, note box, disclosure, status), and its
	# rows read top-down rather than as a centred card of choices.
	content_alignment = BoxContainer.ALIGNMENT_BEGIN
	button_size = Vector2(160, 40)

# Takes the Game node rather than a parent, for the reason PauseMenu.show_menu does.
static func open(game_node: Node, default_kind: BugReporter.Kind, has_board: bool,
		upload_enabled: bool) -> ReportPanel:
	var panel := ReportPanel.new()
	game_node.ui_layer.add_child(panel)
	panel._build(default_kind, has_board, upload_enabled, game_node)
	return panel

func _build(default_kind: BugReporter.Kind, has_board: bool, upload_enabled: bool,
		game_node: Node) -> void:
	_kind = default_kind

	# The chrome claims ModalLock, which is what stops WASD panning the camera while someone types
	# into the note box -- CameraController polls Input globally, so focus cannot save us.
	var content := _build_chrome(game_node)
	_build_title(content, "TELL US SOMETHING")

	content.add_child(_build_kind_row(default_kind))

	_note_edit = TextEdit.new()
	_note_edit.custom_minimum_size = NOTE_MIN_SIZE
	_note_edit.placeholder_text = "What happened, or what did you think?"
	_note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content.add_child(_note_edit)

	# The consent disclosure (#131 item 5). Pressing Submit IS the consent, which is only honest
	# while this line names everything that leaves the machine -- keep it in step with
	# ReportUploader.ATTACHMENTS.
	var disclosure := Label.new()
	disclosure.text = _disclosure_text(has_board, upload_enabled)
	disclosure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	disclosure.custom_minimum_size = Vector2(NOTE_MIN_SIZE.x, 0)
	disclosure.add_theme_font_size_override("font_size", 13)
	disclosure.modulate = Color(0.75, 0.75, 0.78)
	content.add_child(disclosure)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(NOTE_MIN_SIZE.x, 0)
	_status.visible = false
	content.add_child(_status)

	_actions = _build_button_row(content, false, ACTION_ROW_SEPARATION) as HBoxContainer
	_show_submit_actions()

	_note_edit.grab_focus()

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
	button.custom_minimum_size = Vector2(190, 36)
	button.pressed.connect(func() -> void: _kind = kind)
	row.add_child(button)

func _disclosure_text(has_board: bool, upload_enabled: bool) -> String:
	if not upload_enabled:
		return "Saving to this machine only -- no intake endpoint is configured in this build."
	var carried := "a screenshot and the last 80 lines of the game log"
	if has_board:
		carried = "a screenshot, a snapshot of the current board, and the last 80 lines of the game log"
	return "Submitting sends the developer your message plus %s. Nothing else is collected." % carried

# ==============================================================================
#  The three states: collecting, sending, done
# ==============================================================================

func selected_kind() -> BugReporter.Kind:
	return _kind

func note_text() -> String:
	return _note_edit.text

func _show_submit_actions() -> void:
	_clear_button_row(_actions)
	_add_button(_actions, "Submit", func() -> void: finished.emit(true))
	_add_button(_actions, "Cancel", func() -> void: finished.emit(false))

func show_sending() -> void:
	_note_edit.editable = false
	_clear_button_row(_actions)   # no cancel: the POST is already in flight and cannot be recalled
	_status.visible = true
	_status.modulate = Color(0.85, 0.85, 0.88)
	_status.text = "Sending..."

# A silent success reads as a broken feature and they stop using it (#131 item 2), so BOTH outcomes
# say something. A failure is not a dead end -- the report is on disk and the folder opens.
func show_outcome(report_dir: String, sent: bool) -> void:
	_report_dir = report_dir
	_status.visible = true
	_clear_button_row(_actions)

	if report_dir == "":
		_status.modulate = Color(0.95, 0.55, 0.55)
		_status.text = "Could not write the report to disk. Nothing was sent."
		_add_button(_actions, "Close", func() -> void: dismissed.emit())
		return

	if sent:
		_status.modulate = Color(0.6, 0.9, 0.6)
		_status.text = "Sent. Thanks!."
	else:
		_status.modulate = Color(0.95, 0.8, 0.5)
		_status.text = "Could not reach the developer, but the report was saved on this machine. You can send the folder along any other way."
		_add_button(_actions, "Open Folder", func() -> void:
			OS.shell_open(ProjectSettings.globalize_path(_report_dir)))

	_add_button(_actions, "Close", func() -> void: dismissed.emit())

# Esc backs out of the card, through ModalCard's one handler. Note the mid-send arm returns TRUE
# while doing nothing: the key is TAKEN rather than acted on, so it cannot fall through to whatever
# is underneath while an upload is in flight.
func _on_cancel() -> bool:
	if _actions.get_child_count() == 0:
		return true   # mid-send: nothing to back out to, and nobody else may have it either
	if _status.visible:
		dismissed.emit()
	else:
		finished.emit(false)
	return true
