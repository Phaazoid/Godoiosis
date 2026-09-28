extends ModalCard
class_name ReportPanel

# The player-facing report card (#131) -- the only surface a stranger has for telling us anything
# at all. Built on ModalCard, the base shared with every other full-screen surface; it is the one
# that is a FORM rather than a choice, which is what retired the old ChoiceModal name.
#
# The form itself is ReportForm since #1052, because the mission-end banner hosts one too; this card
# is the chrome and the title around it. BugReporter.open_card opens it and drives its form, and the
# card, like the form, never writes a file or touches the transport.

var form: ReportForm

func _init() -> void:
	# BEGIN, not CENTER: this is a stacked form (toggles, note box, status), and its rows read
	# top-down rather than as a centred card of choices.
	content_alignment = BoxContainer.ALIGNMENT_BEGIN
	button_size = Vector2(160, 40)

# Takes the Game node rather than a parent, for the reason PauseMenu.show_menu does.
static func open(game_node: Node, default_kind: BugReporter.Kind) -> ReportPanel:
	var panel := ReportPanel.new()
	game_node.card_layer.add_child(panel)
	panel._build(default_kind, game_node)
	return panel

func _build(default_kind: BugReporter.Kind, game_node: Node) -> void:
	# The chrome claims ModalLock, which is what stops WASD panning the camera while someone types
	# into the note box -- CameraController polls Input globally, so focus cannot save us.
	var content := _build_chrome(game_node)
	_build_title(content, "TELL US SOMETHING")

	form = ReportForm.new(self, default_kind, true)
	content.add_child(form)
	form.focus_note()

# Esc backs out of the card, through ModalCard's one handler; what backing out means mid-exchange is
# the form's answer.
func _on_cancel() -> bool:
	return form.handle_cancel()
