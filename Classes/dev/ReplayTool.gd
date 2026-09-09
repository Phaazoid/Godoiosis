extends VBoxContainer
class_name ReplayTool

# THE REPLAY PAGE (#53 slice 4) -- Session > Replay. Pick a recorded run, put it back on the board,
# and step it. The panel owns nothing: ReplayRun reads the folder, ReplayDriver re-issues and diffs,
# and everything here is a button and a readout over those two.
#
# The run list is rebuilt on show rather than cached: the folder gains a run every time the dev
# plays a mission, and a list built once at _ready would never show the run they came here to look
# at. DevInfoTool's refresh_on_show idiom, for the same reason it has one.
#
# A REPLAY REPLACES WHAT IS ON THE BOARD, because seeding is apply_scenario. That is stated on the
# page rather than guarded against -- this is the dev tools, and refusing to load over a live battle
# would be the wrong trade for the one surface whose job is to load boards.

const COPY := "Copy"
const COPIED := "Copied"
const COPIED_SECONDS := 1.0

var _game
var _driver: ReplayDriver = null
var _run: ReplayRun = null

var _rows: VBoxContainer
var _list: OptionButton
var _status: Label
var _report: RichTextLabel
var _step_button: Button
var _play_button: Button


func init(game) -> void:
	_game = game
	_rows = DevWidgets.add_knob_scroll(self)
	_driver = ReplayDriver.new()
	_driver.game = game
	add_child(_driver)
	_build()
	refresh_on_show()


func refresh_on_show() -> void:
	if _list == null:
		return
	var selected := _list.get_item_text(_list.selected) if _list.selected >= 0 else ""
	_list.clear()
	_list.select(-1)   # add_item auto-selects the first entry, so a vanished run would silently point at another
	for run_id: String in ReplayRun.list_runs():
		_list.add_item(run_id)
		if run_id == selected:
			_list.select(_list.item_count - 1)
	if _list.item_count == 0:
		_status.text = "No recorded runs yet. Play a mission, then come back."
	elif _list.selected < 0:
		_list.select(0)
		_on_pick(0)


func _build() -> void:
	DevWidgets.add_heading(_rows, "Recorded runs")
	var pick_row := HBoxContainer.new()
	_rows.add_child(pick_row)
	_list = OptionButton.new()
	_list.custom_minimum_size.x = 320
	_list.item_selected.connect(_on_pick)
	pick_row.add_child(_list)
	var copy := Button.new()
	copy.text = COPY
	copy.tooltip_text = "Copy the telemetry folder's path. Never opens Explorer -- a second OS window stealing focus is how every dev key ends up going nowhere."
	copy.pressed.connect(func(): _copy(ProjectSettings.globalize_path(TelemetryStore.root), copy))
	pick_row.add_child(copy)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(_status)

	var buttons := HBoxContainer.new()
	_rows.add_child(buttons)
	var load_button := Button.new()
	load_button.text = "Load onto the board"
	load_button.tooltip_text = "Seeds the board from this run's board.tres and arms it. This REPLACES whatever is on the board now."
	load_button.pressed.connect(_on_load)
	buttons.add_child(load_button)
	_step_button = Button.new()
	_step_button.text = "Step"
	_step_button.tooltip_text = "Replay one recorded event -- a pass, a turn hand-over, a gear change."
	_step_button.pressed.connect(_on_step)
	buttons.add_child(_step_button)
	_play_button = Button.new()
	_play_button.text = "Play to end"
	_play_button.pressed.connect(_on_play)
	buttons.add_child(_play_button)

	DevWidgets.add_heading(_rows, "Report")
	_report = RichTextLabel.new()
	_report.fit_content = true
	_report.custom_minimum_size.y = 160
	_rows.add_child(_report)

	DevWidgets.add_heading(_rows, "The first-launch notice")
	var notice := Button.new()
	notice.text = "Show the notice again"
	notice.tooltip_text = "Forgets that this install has seen the playtest-data notice, so the next launch shows it. Leaves the anonymous install id alone, which deleting the file would not."
	notice.pressed.connect(_on_reset_notice)
	_rows.add_child(notice)
	_set_running(false)


func _on_pick(index: int) -> void:
	if index < 0 or index >= _list.item_count:
		return
	_run = ReplayRun.load_run(_list.get_item_text(index))
	var head := _run.headline()
	var flags: Array[String] = []
	if bool(head.get("sandbox", false)):
		flags.append("sandbox")
	if bool(head.get("dev_mode", false)):
		flags.append("dev mode")
	if bool(head.get("dev_touched", false)):
		flags.append("DEV-TOUCHED -- a replay of this cannot be trusted")
	_status.text = "%s -- %s, %d rounds%s" % [
		str(head.get("scenario")), str(head.get("outcome")), int(head.get("rounds", 0)),
		("  [%s]" % ", ".join(flags)) if not flags.is_empty() else ""]
	if not _run.problems.is_empty():
		_status.text += "\n" + "\n".join(_run.problems)
	_report.text = ""
	_set_running(false)


func _on_load() -> void:
	if _run == null:
		return
	if not _driver.seed(_run):
		_render()
		return
	_set_running(true)
	_render()


func _on_step() -> void:
	await _driver.step()
	_render()


func _on_play() -> void:
	await _driver.play()
	_render()


func _on_reset_notice() -> void:
	TelemetryStore.reset_notice()
	_status.text = "The notice is due again on the next launch."


func _set_running(on: bool) -> void:
	_step_button.disabled = not on
	_play_button.disabled = not on


# The report is the point of the page, so it leads with the verdict rather than burying it under a
# progress line: a run that replayed clean should say so in one word.
func _render() -> void:
	var r := _driver.report()
	var out: Array[String] = []
	if not bool(r.get("seeded", false)):
		out.append("[b]Not loaded.[/b]")
	else:
		var at := int(r.get("at", 0))
		var of := int(r.get("of", 0))
		var divs: Array = r.get("divergences", [])
		if bool(r.get("finished", false)):
			out.append("[b]Clean -- the replay matched the run.[/b]" if divs.is_empty()
				else "[b]%d divergences.[/b]" % divs.size())
		else:
			out.append("At event %d of %d." % [at, of])
		for line in divs:
			out.append("  - " + str(line))
	for line in (r.get("unbindable", []) as Array):
		out.append("[b]Could not bind:[/b] " + str(line))
	for line in (r.get("notes", []) as Array):
		out.append("Note: " + str(line))
	_report.text = "\n".join(out)
	_set_running(bool(r.get("seeded", false)) and not bool(r.get("finished", false)))


func _copy(text: String, button: Button) -> void:
	DisplayServer.clipboard_set(text)
	button.text = COPIED
	await get_tree().create_timer(COPIED_SECONDS).timeout
	if is_instance_valid(button):
		button.text = COPY
