# WHAT THE REPLAY TAB'S RUN LIST OFFERS (#925). The folder gains a run every time the dev opens a
# mission and leaves it, so most of what accumulates there is board swaps and F2s -- 34 of the 41
# runs on the dev's machine the day this was filed never reached round 2. There is nothing in one
# to replay, and they crowd out the handful worth looking at.
#
# THE RUNS ARE HAND-STAGED, which is a narrower fixture than test_replay_driver.gd's played mission
# and is the right one here: the filter reads the `round` stamped on each event line, so a file
# holding those lines exercises the whole wire this suite is about (refresh -> list_runs ->
# load_events -> is_one_turn -> add_item). That MissionLog stamps the round correctly is a different
# question, pinned where the recorder is.
#
# Persistence is aimed at a scratch folder for the ordinary reason -- the dev's own recorded runs
# are on this machine, and a suite that read them would pass or fail by how he last played.
#
# EVERY STAGED RUN IS SEALED. game.gd's boot calls MissionLog.sweep_unsealed(), so an unsealed
# fixture would be rewritten out from under the case that staged it.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH_ROOT := "user://__replay_picker_test/"
const SHORT_RUN := "2026-09-12_01-00-00_oneturn0"
const LONG_RUN := "2026-09-12_02-00-00_played00"
const NEWER_RUN := "2026-09-12_03-00-00_played01"
const NEWEST_RUN := "2026-09-12_04-00-00_played02"
const HIDE_BOX := "Hide one-turn runs"
const LOAD_BUTTON := "Load onto the board"

var _main: Node
var game: Node2D
var overlay: DevOverlay


func before_test() -> void:
	TelemetryStore.reset_for_test()
	TelemetryStore.root = SCRATCH_ROOT
	TelemetryStore.persistence_enabled = true
	_wipe(SCRATCH_ROOT)
	await _boot()


# The folder is wiped BEFORE the game boots, so every case here starts from a boot that saw no runs.
# The one case that needs runs already on disk at boot re-boots through this after staging them.
func _boot() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	overlay = game.dev_overlay
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	_wipe(SCRATCH_ROOT)
	TelemetryStore.reset_for_test()


# ==============================================================================
#  The filter
# ==============================================================================

func test_a_one_turn_run_is_kept_out_of_the_picker() -> void:
	_stage_run(SHORT_RUN, 1)
	_stage_run(LONG_RUN, 3)
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	# Non-vacuity: if the staged pair did not actually differ in rounds there is nothing to filter.
	assert_int(ReplayRun.load_events(LONG_RUN).rounds()).override_failure_message(
		"fixture: the long run never reached round 2, so this case cannot see the filter"
		).is_greater(1)
	assert_array(_listed(tool)).override_failure_message(
		"the one-turn run is still in the picker").is_equal([LONG_RUN])


func test_unticking_the_box_brings_the_one_turn_runs_back() -> void:
	_stage_run(SHORT_RUN, 1)
	_stage_run(LONG_RUN, 3)
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	assert_int(_listed(tool).size()).override_failure_message(
		"fixture: the filter never hid anything, so unticking cannot be seen").is_equal(1)

	# DRIVEN THROUGH THE REAL CHECKBOX, never by writing the flag: a box wired to nothing looks
	# exactly like a box wired correctly from the flag's side.
	_hide_box(tool).button_pressed = false

	assert_array(_listed(tool)).override_failure_message(
		"unticking the box did not put the one-turn run back -- it is bound to nothing"
		).is_equal([LONG_RUN, SHORT_RUN])


func test_a_run_that_reached_round_two_is_never_hidden() -> void:
	_stage_run(LONG_RUN, 2)
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	assert_array(_listed(tool)).override_failure_message(
		"round 2 is the first round that counts as more than one turn").is_equal([LONG_RUN])


# The box defaults to hiding, so this is the state the dev meets on opening the tab -- and the one
# where a stale "nothing recorded yet" would send him looking for a broken recorder.
func test_the_empty_list_says_runs_are_hidden_rather_than_absent() -> void:
	_stage_run(SHORT_RUN, 1)
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	assert_array(_listed(tool)).override_failure_message(
		"fixture: something was listed, so the message under test is not the empty one").is_empty()
	var said := _status_text(tool)
	assert_str(said).override_failure_message(
		"the tab claims nothing has been recorded while a run sits in the folder").contains("hidden")
	assert_str(said).contains("1")


func test_an_actually_empty_folder_still_says_so() -> void:
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	assert_array(_listed(tool)).is_empty()
	assert_str(_status_text(tool)).override_failure_message(
		"an empty folder reported hidden runs it does not have").contains("No recorded runs yet")


# ==============================================================================
#  The row (#939)
# ==============================================================================
#
# A row is a LABEL and the run id rides the item's metadata. These cases assert the FACTS a row
# carries, never the words around them.

func test_a_row_names_its_mission_and_ending_not_its_id() -> void:
	_stage_run(LONG_RUN, 3)
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	var labels := _labels(tool)
	assert_int(labels.size()).is_equal(1)
	assert_str(labels[0]).override_failure_message(
		"the row does not name its board: '%s'" % labels[0]).contains("Fixture")
	assert_str(labels[0]).override_failure_message(
		"the row does not say how the run ended: '%s'" % labels[0]).contains("ABANDONED")
	assert_str(labels[0]).override_failure_message(
		"the row is still the raw run id: '%s'" % labels[0]).not_contains(LONG_RUN.right(8))


# THE TRAP THE TICKET NAMED: a relabelled row that is still read back as the id loads nothing.
# Driven through the dropdown's own signal, so the wire is what is asserted.
func test_picking_a_row_loads_that_run() -> void:
	_stage_run(LONG_RUN, 3)
	_stage_run(NEWER_RUN, 3)
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	var list := _list(tool)
	assert_array(_listed(tool)).override_failure_message(
		"fixture: newest first, so index 1 is the older run").is_equal([NEWER_RUN, LONG_RUN])

	list.select(1)
	list.item_selected.emit(1)

	assert_object(tool._run).override_failure_message("picking a row loaded nothing").is_not_null()
	assert_str(tool._run.run_id).override_failure_message(
		"picking the second row loaded a different run").is_equal(LONG_RUN)


# A newer run arriving shifts every index down one, so a selection kept by INDEX -- or by a label
# compared against an id -- lands on the wrong run or falls back to the top.
func test_the_selection_survives_a_refresh_that_shifts_every_row() -> void:
	_stage_run(LONG_RUN, 3)
	_stage_run(NEWER_RUN, 3)
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	var list := _list(tool)
	list.select(1)
	list.item_selected.emit(1)   # a HAND pick: only those survive a refresh (#1156)

	_stage_run(NEWEST_RUN, 3)
	tool.refresh_on_show()

	assert_array(_listed(tool)).override_failure_message(
		"fixture: the newer run did not arrive at the top").is_equal([NEWEST_RUN, NEWER_RUN, LONG_RUN])
	assert_str(str(list.get_item_metadata(list.selected))).override_failure_message(
		"a refresh moved the selection off the run that was picked").is_equal(LONG_RUN)


# `dev_touched` is THREE-valued and the sweep writes null; `bool(null)` is a hard script error, which
# would drop the row from the list rather than fail loudly.
func test_a_swept_run_lists_and_carries_its_mark() -> void:
	_stage_run(LONG_RUN, 3, null)
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	var labels := _labels(tool)
	assert_int(labels.size()).override_failure_message(
		"a swept run vanished from the list -- its null flag was coerced").is_equal(1)
	assert_str(labels[0]).override_failure_message(
		"a swept run's row does not say so: '%s'" % labels[0]).contains("swept")


# The folder is the run's state (#852), so three runs identical but for where they sit must read
# differently -- which is all this asserts, not what each one says.
func test_where_a_run_sits_reaches_its_row() -> void:
	var owed := "2026-09-12_05-00-00_owedrun0"
	var sent := "2026-09-12_05-00-00_sentrun0"
	var held := "2026-09-12_05-00-00_heldrun0"
	for run_id: String in [owed, sent, held]:
		_stage_run(run_id, 3)
	assert_bool(TelemetryStore.mark_sent(sent)).is_true()
	assert_bool(TelemetryStore.mark_held(held)).is_true()
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	var labels := _labels(tool)
	assert_int(labels.size()).is_equal(3)
	assert_bool(labels[0] != labels[1] and labels[1] != labels[2] and labels[0] != labels[2]
		).override_failure_message(
			"runs in pending/, sent/ and held/ read the same: %s" % str(labels)).is_true()


# The stamp in a run id is UTC; the row shows it on the machine's clock. -240 is a UTC-4 offset,
# so 02:00 UTC reads as 22:00 the previous day.
func test_a_row_shows_the_time_on_the_local_clock() -> void:
	var head := {"run_id": "2026-09-12_02-00-00_played00", "scenario": "Fixture",
		"outcome": "ABANDONED", "rounds": 3, "sent": true}
	assert_str(ReplayTool.row_label(head, -240, "")).override_failure_message(
		"the row did not move the UTC stamp onto the local clock").contains("09-11 22:00")


# ==============================================================================
#  Who played it (#1155)
# ==============================================================================
#
# THE NAME LEADS THE ROW -- the dev's ruling, so it is the one shape pinned here. Everything else is
# a fact the row must carry, never the words around it.

const OTHER_INSTALL := "feedc0de12345678"
const PLAYER := "Fixture Player"


func test_someone_elses_named_run_leads_with_their_name() -> void:
	_stage_run(LONG_RUN, 3, false, {"install_id": OTHER_INSTALL, "player_name": PLAYER})
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	var labels := _labels(tool)
	assert_int(labels.size()).is_equal(1)
	assert_bool(labels[0].begins_with(PLAYER)).override_failure_message(
		"a stranger's run does not lead with their name: '%s'" % labels[0]).is_true()


func test_an_unnamed_player_is_named_by_their_install() -> void:
	_stage_run(LONG_RUN, 3, false, {"install_id": OTHER_INSTALL})
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	var labels := _labels(tool)
	var short := OTHER_INSTALL.left(ReplayTool.SHORT_INSTALL)
	assert_bool(labels[0].begins_with(short)).override_failure_message(
		"a run from a player with no name does not lead with their install: '%s'" % labels[0]).is_true()


# The same name on two installs: only the one that is THIS install is not named by it. Asserts the
# fact, not the word -- your own row carries neither the name nor the id.
func test_your_own_run_is_not_named_like_a_strangers() -> void:
	var me := TelemetryStore.install_id()
	_stage_run(LONG_RUN, 3, false, {"install_id": me, "player_name": PLAYER})
	_stage_run(NEWER_RUN, 3, false, {"install_id": OTHER_INSTALL, "player_name": PLAYER})
	var tool := overlay.replay_tool

	tool.refresh_on_show()

	var labels := _labels(tool)
	assert_array(_listed(tool)).override_failure_message(
		"fixture: newest first, so the stranger's run is on top").is_equal([NEWER_RUN, LONG_RUN])
	var mine := labels[1]
	assert_str(mine).override_failure_message(
		"your own run is named by your player name: '%s'" % mine).not_contains(PLAYER)
	assert_str(mine).override_failure_message(
		"your own run is named by your install: '%s'" % mine).not_contains(me.left(ReplayTool.SHORT_INSTALL))
	assert_bool(labels[0].begins_with(PLAYER)).override_failure_message(
		"fixture: the stranger's row does not lead with their name, so this case sees nothing").is_true()


# Two players can pick the same name, so the status line carries the install beside it. Picked
# through the dropdown's own signal: a rebuild does not fill the status line by itself (#1156).
func test_the_status_line_names_a_stranger_with_their_install() -> void:
	_stage_run(LONG_RUN, 3, false, {"install_id": OTHER_INSTALL, "player_name": PLAYER})
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	var list := _list(tool)

	list.select(0)
	list.item_selected.emit(0)

	var said := _status_text(tool)
	assert_str(said).override_failure_message("the status line does not name the player").contains(PLAYER)
	assert_str(said).override_failure_message(
		"the status line does not carry the player's install").contains(OTHER_INSTALL.left(ReplayTool.SHORT_INSTALL))


# ==============================================================================
#  Which pick sticks (#1156)
# ==============================================================================
#
# Dev ruling: only a pick the dev MADE survives a rebuild -- a dropdown pick, or a run he pressed Load
# on. The page's own pick follows the newest run. The first build of this ticket made the automatic
# pick sticky too, and nothing here saw it: every case below the boot one starts from a boot that saw
# an EMPTY folder, which is the one ordering in which a boot-time pick cannot exist.

func test_the_page_follows_the_newest_run_nobody_picked() -> void:
	_stage_run(LONG_RUN, 3)
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	assert_object(tool._run).override_failure_message(
		"fixture: the first show picked nothing, so Load would do nothing").is_not_null()
	if tool._run == null:
		return

	_stage_run(NEWER_RUN, 3)   # a mission played since the page was last shown
	tool.refresh_on_show()

	assert_str(tool._run.run_id).override_failure_message(
		"the page kept its own earlier pick, so Load would seed the older run").is_equal(NEWER_RUN)
	assert_str(str(_list(tool).get_item_metadata(_list(tool).selected))).is_equal(NEWER_RUN)


func test_a_hand_pick_survives_a_newer_run() -> void:
	_stage_run(LONG_RUN, 3)
	_stage_run(NEWER_RUN, 3)
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	var list := _list(tool)
	list.select(1)
	list.item_selected.emit(1)

	_stage_run(NEWEST_RUN, 3)
	tool.refresh_on_show()

	assert_object(tool._run).is_not_null()
	if tool._run == null:
		return
	assert_str(tool._run.run_id).override_failure_message(
		"a newer run took the page off the run the dev chose").is_equal(LONG_RUN)
	assert_str(str(list.get_item_metadata(list.selected))).is_equal(LONG_RUN)


# The pick ENDS with its run: once it is gone the page follows the newest again, and keeps following.
func test_a_hand_pick_that_vanished_falls_back_to_following() -> void:
	_stage_run(LONG_RUN, 3)
	_stage_run(NEWER_RUN, 3)
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	var list := _list(tool)
	list.select(1)
	list.item_selected.emit(1)

	_wipe(TelemetryStore.run_dir(LONG_RUN))
	tool.refresh_on_show()
	assert_object(tool._run).is_not_null()
	if tool._run == null:
		return
	assert_str(tool._run.run_id).override_failure_message(
		"the page still holds a run that is no longer listed").is_equal(NEWER_RUN)

	_stage_run(NEWEST_RUN, 3)
	tool.refresh_on_show()
	assert_str(tool._run.run_id).override_failure_message(
		"the vanished pick left the page stuck instead of following").is_equal(NEWEST_RUN)


func test_pressing_load_makes_the_run_yours() -> void:
	_stage_run(LONG_RUN, 3)
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	_load_button(tool).pressed.emit()   # a staged run has no board, so the seed refuses; the pick is what is asserted

	_stage_run(NEWER_RUN, 3)
	tool.refresh_on_show()

	assert_object(tool._run).is_not_null()
	if tool._run == null:
		return
	assert_str(tool._run.run_id).override_failure_message(
		"the run the dev pressed Load on was swapped for a newer one").is_equal(LONG_RUN)


# The page left open while a mission is played is never shown again, so nothing rebuilds it: Load
# is the last chance to notice the newer run.
func test_load_with_nothing_picked_seeds_the_newest_run() -> void:
	_stage_run(LONG_RUN, 3)
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	_stage_run(NEWER_RUN, 3)   # no refresh: the page stayed up through the mission

	_load_button(tool).pressed.emit()

	assert_object(tool._run).is_not_null()
	if tool._run == null:
		return
	assert_str(tool._run.run_id).override_failure_message(
		"Load acted on the run the page picked before the mission").is_equal(NEWER_RUN)


# The X only hides the window; the page stays current, so reopening it is no tab change.
func test_reopening_the_window_on_the_page_rebuilds_it() -> void:
	_stage_run(LONG_RUN, 3)
	var tool := overlay.replay_tool
	overlay.show_leaf(tool)
	assert_object(tool._run).override_failure_message("fixture: showing the page picked nothing").is_not_null()
	if tool._run == null:
		return
	overlay._on_close_requested()

	_stage_run(NEWER_RUN, 3)
	overlay.show_beside()

	assert_str(tool._run.run_id).override_failure_message(
		"the window came back on the page without rebuilding it").is_equal(NEWER_RUN)


func test_emptying_the_list_drops_the_run() -> void:
	_stage_run(SHORT_RUN, 1)
	var tool := overlay.replay_tool
	var box := _hide_box(tool)
	box.button_pressed = false
	assert_object(tool._run).override_failure_message(
		"fixture: unticking the box did not list and pick the one-turn run").is_not_null()

	box.button_pressed = true

	assert_object(tool._run).override_failure_message(
		"the list is empty but Load would still seed the run it dropped").is_null()


func test_a_refresh_that_changes_nothing_does_not_re_pick() -> void:
	_stage_run(LONG_RUN, 3)
	var tool := overlay.replay_tool
	tool.refresh_on_show()
	var first: ReplayRun = tool._run

	tool.refresh_on_show()

	assert_bool(is_same(tool._run, first)).override_failure_message(
		"an unchanged list re-picked its run, which stops a replay in progress").is_true()


# The ordering none of the cases above can reach: runs already on disk when the game boots.
func test_booting_with_runs_on_disk_loads_no_board() -> void:
	_stage_run(LONG_RUN, 3)
	get_tree().root.remove_child(_main)
	_main.free()

	await _boot()

	assert_object(overlay.replay_tool._run).override_failure_message(
		"the dev tools loaded a run at boot, for a tab nobody has opened").is_null()


# ==============================================================================
#  Fixture
# ==============================================================================

# A sealed run whose events reach `rounds`. One line per round plus the ending, which is the
# shape MissionLog leaves: every line carries the round it happened in.
func _stage_run(run_id: String, rounds: int, dev_touched: Variant = false,
		start_extra: Dictionary = {}) -> void:
	var dir := TelemetryStore.run_dir(run_id)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + ReplayRun.EVENTS_FILE, FileAccess.WRITE)
	var start := {"seq": 0, "t_ms": 0, "round": 1, "event": "mission_start",
		"scenario_name": "Fixture", "roster": []}
	start.merge(start_extra, true)
	f.store_line(JSON.stringify(start))
	var seq := 1
	for r in range(1, rounds + 1):
		f.store_line(JSON.stringify({
			"seq": seq, "t_ms": seq * 10, "round": r, "event": "turn_start", "units": []}))
		seq += 1
	f.store_line(JSON.stringify({
		"seq": seq, "t_ms": seq * 10, "round": rounds, "event": "mission_end",
		"outcome": "ABANDONED", "dev_touched": dev_touched, "units": []}))
	f.close()


# The run ids the picker offers, in order -- read off the METADATA, since a row's text is a label
# for a person (#939). Every filter case above asserts through this.
func _listed(tool: ReplayTool) -> Array[String]:
	var out: Array[String] = []
	var list := _list(tool)
	for i in range(list.item_count):
		out.append(str(list.get_item_metadata(i)))
	return out


func _labels(tool: ReplayTool) -> Array[String]:
	var out: Array[String] = []
	var list := _list(tool)
	for i in range(list.item_count):
		out.append(list.get_item_text(i))
	return out


func _list(tool: ReplayTool) -> OptionButton:
	var list := _first_of(tool, "OptionButton") as OptionButton
	assert_object(list).override_failure_message("the picker has no dropdown").is_not_null()
	return list


func _status_text(tool: ReplayTool) -> String:
	for node in _descendants(tool):
		var label := node as Label
		if label != null and label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART:
			return label.text
	return ""


func _hide_box(tool: ReplayTool) -> CheckBox:
	for node in _descendants(tool):
		var box := node as CheckBox
		if box != null and box.text == HIDE_BOX:
			return box
	fail("the Replay tab has no '%s' checkbox" % HIDE_BOX)
	return null


func _load_button(tool: ReplayTool) -> Button:
	for node in _descendants(tool):
		var button := node as Button
		if button != null and button.text == LOAD_BUTTON:
			return button
	fail("the Replay tab has no '%s' button" % LOAD_BUTTON)
	return null


func _first_of(root: Node, klass: String) -> Node:
	for node in _descendants(root):
		if node.is_class(klass):
			return node
	return null


func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir + sub + "/")
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + file)
	DirAccess.remove_absolute(dir)
