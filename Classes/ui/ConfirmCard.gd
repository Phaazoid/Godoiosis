extends ModalCard
class_name ConfirmCard

# A small yes/no question card (#144) -- the player-facing twin of DevWidgets.confirm_delete,
# which is a ConfirmationDialog and therefore a real OS Window: the wrong mechanism inside the
# game SubViewport (embed_subwindows is off; prefer Control-based menus). One-shot: builds,
# awaits the answer, frees. Stacks over another ModalCard cleanly -- ModalLock derives the
# freeze from group membership, so the handoff is gapless.

signal answered(yes: bool)

static func ask(game_node: Node, question: String, yes_label := "Yes", no_label := "No") -> bool:
	var card := ConfirmCard.new()
	game_node.ui_layer.add_child(card)
	card._build(question, yes_label, no_label, game_node)
	var yes: bool = await card.answered
	card.queue_free()
	return yes

func _build(question: String, yes_label: String, no_label: String, game_node: Node) -> void:
	var content := _build_chrome(game_node)
	_build_body(content, question)
	var row := _build_button_row(content, false, content_separation)
	_add_button(row, yes_label, func(): answered.emit(true))
	_add_button(row, no_label, func(): answered.emit(false))

# Esc is No. Taking the key is what stops the card underneath from also reading it as its own
# back-out -- see SaveLoadScreen._busy, which guards the same seam from the other side.
func _on_cancel() -> bool:
	answered.emit(false)
	return true
