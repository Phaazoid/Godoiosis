extends ModalCard
class_name SaveLoadScreen

# The player's save-slot card (#144), one surface with two modes. SAVE writes the slot itself
# (safe under the modal freeze -- a freeze stops callbacks, not method calls) and reports a
# failed write in its own status line (#168's lesson: a silent dev-tool failure was bad, a
# silent player one is worse). LOAD only RETURNS the chosen slot -- board mutation stays at the
# caller, the "card is told the outcome" doctrine. Empty and unreadable slots grey with the
# reason in their tooltip (#166: a menu can only grey what it can explain).

enum Mode { SAVE, LOAD }

signal finished(slot: int)   # -1 = backed out

var _busy := false   # a ConfirmCard is stacked on top; Esc belongs to it, not to this screen

func _init() -> void:
	button_size = Vector2(420, 44)

# confirm_load: the pause menu passes true -- loading there discards live progress; the title
# screen passes false -- there is nothing in progress to lose.
static func show_screen(game_node: Node, mode: Mode, confirm_load := false) -> int:
	var screen := SaveLoadScreen.new()
	game_node.ui_layer.add_child(screen)
	screen._build(mode, confirm_load, game_node)
	var slot: int = await screen.finished
	screen.queue_free()
	return slot

func _build(mode: Mode, confirm_load: bool, game_node: Node) -> void:
	var content := _build_chrome(game_node)
	_build_title(content, "SAVE GAME" if mode == Mode.SAVE else "LOAD GAME")

	if mode == Mode.SAVE:
		# #87 deliberately excludes the queued plan, and a save screen is where a player would
		# otherwise learn that the hard way.
		var note := _build_body(content, "Queued orders are not saved — re-issue them after loading.")
		note.modulate = Color(0.7, 0.7, 0.75)

	var status := _build_body(content, "")
	status.visible = false
	status.modulate = Color(0.9, 0.55, 0.55)

	var manager: ScenarioManager = game_node.scenario_manager
	var row := _build_button_row(content, true, content_separation)
	for slot in range(1, ScenarioManager.SLOT_COUNT + 1):
		_add_slot_button(row, slot, mode, confirm_load, manager, game_node, status)

	_add_button(row, "Back", func(): finished.emit(-1))

func _add_slot_button(row: Container, slot: int, mode: Mode, confirm_load: bool,
		manager: ScenarioManager, game_node: Node, status: Label) -> void:
	var save: SaveGame = manager.load_slot(slot)
	var on_disk := ScenarioManager.slot_exists(slot)
	var button := _add_button(row, _slot_label(slot, save, on_disk),
		func(): _on_slot_pressed(slot, save != null, mode, confirm_load, manager, game_node, status))

	if mode == Mode.LOAD and save == null:
		button.disabled = true
		button.tooltip_text = UiText.wrap("Unreadable save" if on_disk else "Empty slot")

func _slot_label(slot: int, save: SaveGame, on_disk: bool) -> String:
	if save == null:
		return "Slot %d — %s" % [slot, "unreadable save" if on_disk else "Empty"]
	var mission := ScenarioManager.display_name(save.mission_path).trim_prefix("missions/")
	return "Slot %d — %s — %s" % [slot, mission, _timestamp(save.saved_at)]

# Unix seconds -> local wall-clock, via the system timezone bias (the string helper is UTC-only).
static func _timestamp(unix: int) -> String:
	var bias_minutes: int = Time.get_time_zone_from_system().bias
	return Time.get_datetime_string_from_unix_time(unix + bias_minutes * 60, true)

func _on_slot_pressed(slot: int, filled: bool, mode: Mode, confirm_load: bool,
		manager: ScenarioManager, game_node: Node, status: Label) -> void:
	if mode == Mode.SAVE:
		if filled:
			_busy = true
			var overwrite: bool = await ConfirmCard.ask(game_node, "Overwrite the save in Slot %d?" % slot)
			_busy = false
			if not overwrite:
				return
		if manager.save_to_slot(slot):
			finished.emit(slot)
		else:
			status.text = "Save failed — the game log has the details."
			status.visible = true
		return

	if confirm_load:
		_busy = true
		var proceed: bool = await ConfirmCard.ask(game_node, "Load this save? Current battle progress will be lost.")
		_busy = false
		if not proceed:
			return
	finished.emit(slot)

# Esc backs out, the ReportPanel shape -- safe because game._input ignores ui_cancel while
# anything is in the modal group. The _busy guard is belt-and-braces beside ConfirmCard's own
# accept_event: backing out while a confirm is up would strand the child card mid-await.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _busy:
		accept_event()
		finished.emit(-1)
