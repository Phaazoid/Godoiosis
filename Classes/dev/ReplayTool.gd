extends VBoxContainer
class_name ReplayTool

# THE REPLAY PAGE (#53 slice 4) -- Session > Replay. Pick a recorded run, put it back on the board,
# and step it. The panel owns nothing: ReplayRun reads the folder, ReplayDriver re-issues and diffs,
# and everything here is a button and a readout over those two.
#
# The run list is rebuilt on show rather than cached: the folder gains a run every time the dev
# plays a mission, and a list built once at _ready would never show the run they came here to look
# at. DevInfoTool's refresh_on_show idiom, for the same reason it has one. It is also where the
# one-turn filter is applied, since the filter is a property of the LIST rather than of a run. A row
# reads as the run it is (row_label, #939); the run id travels as the item's metadata.
#
# ONLY A HAND PICK STICKS (#1156, dev ruling). A run the dev chose from the dropdown, or pressed Load
# on, survives a rebuild while it is still listed; otherwise the page follows the newest run. The
# page's own pick must never stick: the list is rebuilt after a mission records a new run, and a
# sticky automatic pick is how Load came to seed the run that was newest an hour ago.
#
# A REPLAY REPLACES WHAT IS ON THE BOARD, because seeding is apply_scenario. That is stated on the
# page rather than guarded against -- this is the dev tools, and refusing to load over a live battle
# would be the wrong trade for the one surface whose job is to load boards.

const COPY := "Copy"
const COPIED := "Copied"
const PLAY := "Play"
const PAUSE := "Pause"
const COPIED_SECONDS := 1.0
const NO_FILE := "(no file)"   # a board that was never saved records an empty scenario name
const YOU := "You"
const UNKNOWN_PLAYER := "(unknown)"   # a run that recorded no install at all
const SHORT_INSTALL := 8

var _game
var _driver: ReplayDriver = null
var _run: ReplayRun = null
var _hand_picked := ""   # the run id the dev chose; "" = the page follows the newest run

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
var _next_divergence_button: Button


func init(game) -> void:
	_game = game
	_rows = DevWidgets.add_knob_scroll(self)
	_driver = ReplayDriver.new()
	_driver.game = game
	add_child(_driver)
	_build()
	_driver.progressed.connect(func(_finished: bool) -> void: _render())
	# No refresh here: DevOverlay rebuilds this page whenever it is SHOWN (a tree pick, or the window
	# coming back), and a build at boot would load a board for a tab that may never open (#1156).


func refresh_on_show() -> void:
	if _list == null:
		return
	_list.clear()
	_hidden_count = 0
	var kept := false
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var me := TelemetryStore.install_id()
	for run_id: String in ReplayRun.list_runs():
		# load_events, never load_run: the board is the expensive half, and neither the filter nor the
		# label has a use for it (#53 slice 5 split them for exactly this). ONE parse serves both; a run
		# the filter keeps is parsed again only if it is picked.
		var run := ReplayRun.load_events(run_id)
		if _hide_one_turn and run.is_one_turn():
			_hidden_count += 1
			continue
		_list.add_item(row_label(run.headline(), bias, me))
		# THE ID RIDES THE METADATA, never the text (#939): the text is a label for a person, and reading
		# it back as the id is how a relabel silently breaks the pick and the selection both.
		_list.set_item_metadata(_list.item_count - 1, run_id)
		if _hand_picked != "" and run_id == _hand_picked:
			_list.select(_list.item_count - 1)
			kept = true
	if _list.item_count == 0:
		_hand_picked = ""
		_run = null   # or Load seeds a run the list no longer offers
		_report.text = ""
		_set_running(false)
		# TWO DIFFERENT EMPTINESSES. "No recorded runs yet" in front of thirty hidden ones sends the
		# dev looking for a recorder that is working perfectly.
		_status.text = ("Every recorded run is one turn long (%d hidden). Untick the box to see them."
			% _hidden_count) if _hidden_count > 0 else "No recorded runs yet. Play a mission, then come back."
		return
	if kept:
		return
	# Follow the newest. add_item already SHOWS row 0 as selected (CLAUDE.md's OptionButton edge), so the
	# select is not what matters -- the pick is. Only when the top row changed: re-picking an unchanged
	# run would stop a replay in progress for nothing.
	_hand_picked = ""
	_list.select(0)
	if _run == null or _run.run_id != str(_list.get_item_metadata(0)):
		_on_pick(0)


func _build() -> void:
	DevWidgets.add_heading(_rows, "Recorded runs")
	var pick_row := HBoxContainer.new()
	_rows.add_child(pick_row)
	_list = OptionButton.new()
	_list.custom_minimum_size.x = 320
	_list.item_selected.connect(_on_hand_pick)
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
	_play_button.text = PLAY
	_play_button.tooltip_text = "Replay the remaining events. While playing, pauses at the next event -- a pass in flight finishes first."
	_play_button.pressed.connect(_on_play)
	buttons.add_child(_play_button)
	_next_divergence_button = Button.new()
	_next_divergence_button.text = "Run to next divergence"
	_next_divergence_button.tooltip_text = "Step until the replay disagrees with the run, or the run ends."
	_next_divergence_button.pressed.connect(_on_next_divergence)
	buttons.add_child(_next_divergence_button)

	DevWidgets.add_heading(_rows, "Report")
	_report = RichTextLabel.new()
	_report.fit_content = true
	_report.custom_minimum_size.y = 160
	_rows.add_child(_report)

	DevWidgets.add_heading(_rows, "The launch notice")
	var notice := Button.new()
	notice.text = "Show the notice again"
	notice.tooltip_text = "Forgets which version of the playtest-data notice this install has acknowledged, so the next launch shows it. Leaves the install id and the name alone, which deleting the file would not."
	notice.pressed.connect(_on_reset_notice)
	_rows.add_child(notice)
	_set_running(false)


# The dropdown's own signal is the only way a pick becomes the dev's (#1156).
func _on_hand_pick(index: int) -> void:
	if index < 0 or index >= _list.item_count:
		return
	_hand_picked = str(_list.get_item_metadata(index))
	_on_pick(index)


func _on_pick(index: int) -> void:
	if index < 0 or index >= _list.item_count:
		return
	_run = ReplayRun.load_run(str(_list.get_item_metadata(index)))
	var head := _run.headline()
	var marks := flags(head, true)
	_status.text = "%s -- %s -- %s, %d rounds%s" % [
		who(head, TelemetryStore.install_id(), true),
		str(head.get("scenario")), str(head.get("outcome")), int(head.get("rounds", 0)),
		("  [%s]" % ", ".join(marks)) if not marks.is_empty() else ""]
	# Both lists: `problems` is why it cannot replay, `degraded` is why replaying it proves less than
	# it looks like (#871). Neither is worth hiding behind the other.
	var said: Array[String] = _run.problems.duplicate()
	said.append_array(_run.degraded)
	if not said.is_empty():
		_status.text += "\n" + "\n".join(said)
	_report.text = ""
	_set_running(false)


# WHAT ONE ROW SAYS (#939): who, when, which board, how it ended, how long, and its marks. WHO LEADS
# (#1155, dev ruling). The time is the run id's UTC stamp moved by `bias_minutes`, and this install
# is `my_install` -- both parameters so a case can state them. The page passes the machine's CURRENT
# offset, so a run recorded across a daylight-saving change reads an hour off.
static func row_label(head: Dictionary, bias_minutes: int, my_install: String) -> String:
	var run_id := str(head.get("run_id", ""))
	var when := run_id
	var unix := MissionLog.stamp_unix(run_id)
	if unix >= 0:
		var t := Time.get_datetime_dict_from_unix_time(unix + bias_minutes * 60)
		when = "%02d-%02d %02d:%02d" % [t["month"], t["day"], t["hour"], t["minute"]]
	var scenario := str(head.get("scenario", ""))
	var rounds := int(head.get("rounds", 0))
	var marks := flags(head)
	return "%s  %s  %s -- %s, %d %s%s" % [who(head, my_install), when,
		scenario if scenario != "" else NO_FILE,
		str(head.get("outcome", "")), rounds, "round" if rounds == 1 else "rounds",
		("  [%s]" % ", ".join(marks)) if not marks.is_empty() else ""]


# WHO PLAYED A RUN (#1155) -- the one answer, leading every row. This install is You; anyone else is
# their opt-in name, or their install id's first eight characters when they never set one. The name
# was typed on SOMEONE ELSE's machine and reached the intake unchecked, so it goes through the
# store's own rule for what a name may hold. `explain` puts the install beside a name, so two players
# who picked the same one stay apart on the status line.
static func who(head: Dictionary, my_install: String, explain := false) -> String:
	var install := str(head.get("install_id", ""))
	if install == "":
		return UNKNOWN_PLAYER
	if install == my_install:
		return YOU
	var short := install.left(SHORT_INSTALL)
	var player := PlayerSettings._clean_text(str(head.get("player_name", "")),
		PlayerSettings.max_length_of(PlayerSettings.Setting.PLAYER_NAME))
	if player == "":
		return ("install " + short) if explain else short
	return ("%s (install %s)" % [player, short]) if explain else player


# WHICH MARKS A RUN CARRIES (#939) -- one decision, rendered short on a row and explained on the status
# line. Marks are EXCEPTIONS: a sent run nobody touched with a dev tool carries none.
static func flags(head: Dictionary, explain := false) -> Array[String]:
	var out: Array[String] = []
	if bool(head.get("sandbox", false)):
		out.append("sandbox")
	if bool(head.get("dev_mode", false)):
		out.append("dev mode")
	# THREE-VALUED (see ReplayRun.headline). Null is a swept run: nobody was there to clear the flag,
	# so it says so rather than reporting the clean answer it does not have. ReplayDriver's
	# `unbindable` is the real guard for a run in that state.
	var touched: Variant = head.get("dev_touched", false)
	if touched == null:
		out.append("swept -- whether a dev tool touched this is unknown" if explain else "swept")
	elif bool(touched):
		out.append("DEV-TOUCHED -- a replay of this cannot be trusted" if explain else "DEV-TOUCHED")
	# Where the folder is (#852), in the Info page's words. Sent is the ordinary state.
	if bool(head.get("held", false)):
		out.append("held back -- never sent: empty, or recorded before runs had an id" if explain else "held back")
	elif not bool(head.get("sent", false)):
		out.append("owed -- not uploaded yet" if explain else "owed")
	return out


# With nothing hand-picked, Load re-checks first so it seeds the NEWEST run: a page left open while a
# mission was played has never been shown again, so nothing else would have rebuilt it (#1156). Load
# then makes the run the dev's -- a replay in progress must not be swapped out by the next rebuild.
func _on_load() -> void:
	if _hand_picked == "":
		refresh_on_show()
	if _run == null:
		return
	_hand_picked = _run.run_id
	if not _driver.seed(_run):
		_render()
		return
	_set_running(true)
	_render()


func _on_step() -> void:
	_set_running(true, true)
	await _driver.step_once()
	_render()


# One button, two verbs: Pause while anything is playing -- a single Step or a run to the next
# divergence included.
func _on_play() -> void:
	if _driver.is_playing():
		_driver.pause()
		_play_button.disabled = true   # until the event in flight lands
		return
	_set_running(true, true)
	await _driver.play()
	_render()


func _on_next_divergence() -> void:
	_set_running(true, true)
	await _driver.run_to_next_divergence()
	_render()


func _on_reset_notice() -> void:
	TelemetryStore.reset_notice()
	_status.text = "The notice is due again on the next launch."


# A transport button passes `playing` before its first step lands: _render runs only when one does,
# so a long first pass would otherwise still read Play.
func _set_running(on: bool, playing := _driver.is_playing()) -> void:
	_step_button.disabled = not on or playing
	_next_divergence_button.disabled = not on or playing
	_play_button.disabled = not on
	_play_button.text = PAUSE if playing else PLAY


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
		var next: Dictionary = r.get("next", {})
		out.append("At event %d of %d -- next: %s (round %d)." % [int(r.get("at", 0)), int(r.get("of", 0)),
			str(next.get("event", "?")), int(next.get("round", 0))])
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
