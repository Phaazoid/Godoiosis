extends VBoxContainer
class_name ReplayTool

# THE REPLAY PAGE (#53 slice 4) -- Session > Replay. Pick a recorded run, put it back on the board,
# and step it. The panel owns nothing: ReplayRun reads the folder, ReplayDriver re-issues and diffs,
# and everything here is a button and a readout over those two.
#
# The run list is rebuilt on show rather than cached: the folder gains a run every time the dev
# plays a mission, and a list built once at _ready would never show the run they came here to look
# at. DevInfoTool's refresh_on_show idiom, for the same reason it has one. It is also where the
# one-turn filter is applied, since the filter is a property of the LIST rather than of a run.
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
# SESSION-ONLY, and not a `PlayerSettings` row: this is a dev-tools list filter, not a preference a
# player keeps. It defaults to hiding because most of what the folder holds is board swaps -- but a
# CRASHED run is usually one turn long too, so the box is what gets one back rather than a rebuild.
var _hide_one_turn := true
var _hidden_count := 0
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
	_hidden_count = 0
	for run_id: String in ReplayRun.list_runs():
		# load_events, never load_run: the board is the expensive half and a filter has no use for it
		# (#53 slice 5 split them for exactly this). A run the filter keeps is parsed twice, which is
		# the cost of not caching a list that gains a run every time the dev plays.
		if _hide_one_turn and ReplayRun.load_events(run_id).is_one_turn():
			_hidden_count += 1
			continue
		_list.add_item(run_id)
		if run_id == selected:
			_list.select(_list.item_count - 1)
	if _list.item_count == 0:
		# TWO DIFFERENT EMPTINESSES. "No recorded runs yet" in front of thirty hidden ones sends the
		# dev looking for a recorder that is working perfectly.
		_status.text = ("Every recorded run is one turn long (%d hidden). Untick the box to see them."
			% _hidden_count) if _hidden_count > 0 else "No recorded runs yet. Play a mission, then come back."
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

	DevWidgets.add_checkbox(_rows, "Hide one-turn runs", _hide_one_turn, func(on: bool):
		_hide_one_turn = on
		refresh_on_show(),
		"A run that never reached round 2 -- a board swap, an F2, a mission opened and left. There is nothing in one to replay. Untick to see them; a crashed run is often one of them.")

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
	# THREE-VALUED (see ReplayRun.headline). Null is a swept run: nobody was there to clear the flag,
	# so it says so rather than reporting the clean answer it does not have. ReplayDriver's
	# `unbindable` is the real guard for a run in that state.
	var touched: Variant = head.get("dev_touched", false)
	if touched == null:
		flags.append("swept -- whether a dev tool touched this is unknown")
	elif bool(touched):
		flags.append("DEV-TOUCHED -- a replay of this cannot be trusted")
	_status.text = "%s -- %s, %d rounds%s" % [
		str(head.get("scenario")), str(head.get("outcome")), int(head.get("rounds", 0)),
		("  [%s]" % ", ".join(flags)) if not flags.is_empty() else ""]
	# Both lists: `problems` is why it cannot replay, `degraded` is why replaying it proves less than
	# it looks like (#871). Neither is worth hiding behind the other.
	var said: Array[String] = _run.problems.duplicate()
	said.append_array(_run.degraded)
	if not said.is_empty():
		_status.text += "\n" + "\n".join(said)
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
	var divs: Array = r.get("divergences", [])
	if not bool(r.get("seeded", false)):
		out.append("[b]Not loaded.[/b]")
	elif bool(r.get("finished", false)):
		out.append("[b]Clean -- the replay matched the run.[/b]" if divs.is_empty()
			else "[b]%d divergences.[/b]" % divs.size())
	else:
		out.append("At event %d of %d." % [int(r.get("at", 0)), int(r.get("of", 0))])
	# DIRECTLY UNDER THE VERDICT, AND BOLD (#871). A degraded board makes the verdict itself unsafe --
	# "Clean" over a board that lost a weapon is the same silence this ticket removed, arriving one
	# click later -- so it cannot sit below the divergences as a footnote the way `notes` does.
	for line in (r.get("degraded", []) as Array):
		out.append("[b]Degraded board:[/b] " + str(line))
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
