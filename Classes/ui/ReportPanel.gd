extends Control
class_name ReportPanel

# The player-facing report card (#131). PauseMenu's shape -- Control-based, code-built, awaited --
# and the only surface a stranger has for telling us anything at all.
#
# It is deliberately DUMB: it collects a Kind and a note, and it is TOLD the outcome. It never
# writes a file, never formats a message and never touches the transport, so "what is in a report"
# stays BugReporter's single answer. BugReporter.open_card drives the whole exchange.
#
# SIZING: set_anchors_and_offsets_preset, never set_anchors_preset (CLAUDE.md sharp edge -- a
# code-built Control under a CanvasLayer stays 0x0 with anchors alone).
# Z_INDEX: this can open on top of MissionSelectScreen, so it has to out-rank that screen's MENU_Z.

# The chosen kind and the typed note are READ off the panel afterwards rather than carried on the
# signal: an enum crossing a signal boundary arrives as a bare int, and the round-trip back to a
# typed Kind is a cast with nothing to gain from it.
signal finished(submitted: bool)
signal dismissed

const PANEL_Z := 200
const NOTE_MIN_SIZE := Vector2(520, 180)
const BUTTON_SIZE := Vector2(160, 40)

var _kind: BugReporter.Kind
var _note_edit: TextEdit
var _status: Label
var _actions: HBoxContainer
var _report_dir: String = ""

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

	# Freezes the game subtree and marks this as the open modal. That freeze is what stops WASD
	# panning the camera while someone types into the note box -- CameraController polls Input
	# globally, so focus cannot save us. See ModalLock.
	ModalLock.claim(self, game_node)

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # eat stray clicks meant for the board behind
	z_index = PANEL_Z

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "TELL US SOMETHING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	vbox.add_child(_build_kind_row(default_kind))

	_note_edit = TextEdit.new()
	_note_edit.custom_minimum_size = NOTE_MIN_SIZE
	_note_edit.placeholder_text = "What happened, or what did you think?"
	_note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(_note_edit)

	# The consent disclosure (#131 item 5). Pressing Submit IS the consent, which is only honest
	# while this line names everything that leaves the machine -- keep it in step with
	# ReportUploader.ATTACHMENTS.
	var disclosure := Label.new()
	disclosure.text = _disclosure_text(has_board, upload_enabled)
	disclosure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	disclosure.custom_minimum_size = Vector2(NOTE_MIN_SIZE.x, 0)
	disclosure.add_theme_font_size_override("font_size", 13)
	disclosure.modulate = Color(0.75, 0.75, 0.78)
	vbox.add_child(disclosure)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(NOTE_MIN_SIZE.x, 0)
	_status.visible = false
	vbox.add_child(_status)

	_actions = HBoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("separation", 12)
	vbox.add_child(_actions)
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
	_clear_actions()
	_add_action("Submit", func() -> void: finished.emit(true))
	_add_action("Cancel", func() -> void: finished.emit(false))

func show_sending() -> void:
	_note_edit.editable = false
	_clear_actions()   # no cancel: the POST is already in flight and cannot be recalled
	_status.visible = true
	_status.modulate = Color(0.85, 0.85, 0.88)
	_status.text = "Sending..."

# A silent success reads as a broken feature and they stop using it (#131 item 2), so BOTH outcomes
# say something. A failure is not a dead end -- the report is on disk and the folder opens.
func show_outcome(report_dir: String, sent: bool) -> void:
	_report_dir = report_dir
	_status.visible = true
	_clear_actions()

	if report_dir == "":
		_status.modulate = Color(0.95, 0.55, 0.55)
		_status.text = "Could not write the report to disk. Nothing was sent."
		_add_action("Close", func() -> void: dismissed.emit())
		return

	if sent:
		_status.modulate = Color(0.6, 0.9, 0.6)
		_status.text = "Sent. Thanks!."
	else:
		_status.modulate = Color(0.95, 0.8, 0.5)
		_status.text = "Could not reach the developer, but the report was saved on this machine. You can send the folder along any other way."
		_add_action("Open Folder", func() -> void:
			OS.shell_open(ProjectSettings.globalize_path(_report_dir)))

	_add_action("Close", func() -> void: dismissed.emit())

func _clear_actions() -> void:
	for child in _actions.get_children():
		child.queue_free()
		_actions.remove_child(child)

func _add_action(label: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = BUTTON_SIZE
	button.pressed.connect(on_pressed)
	_actions.add_child(button)

# Esc backs out of the card. game._input ignores ui_cancel while anything is in the "modal" group,
# so this is the only handler that sees it and there is no ordering question between the two.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _actions.get_child_count() == 0:
		return   # mid-send: nothing to back out to
	if _status.visible:
		dismissed.emit()
	else:
		finished.emit(false)
