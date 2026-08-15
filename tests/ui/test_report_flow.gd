# The report card's WIRE (#131) -- Esc through to a file on disk, fired as the real sequence.
#
# Why a game-scene suite and not unit tests on BugReporter: every bug this found lived in the
# ORDERING, not at either end. test_reporting_from_the_pause_menu_leaves_the_board_playable is the
# one that matters -- _open_pause_menu stashes the pre-pause GameState in a local, and reopening
# itself after the card restashed MENU as that local, so Resume left the board locked forever with
# every individual piece behaving correctly. Setting game_state directly cannot see it.
#
# The uploader is inert here, and NOT because it is unconfigured -- ENDPOINT is a live Worker. The
# suite runs headless and ReportUploader.is_configured() refuses a headless run outright, so these
# tests never open a socket and `sent` is false throughout by construction rather than by mocking.
# test_a_headless_run_never_uploads pins that, because the failure mode is silent: a suite that
# quietly POSTs 975 times into the intake channel still reports green.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D
var _written: Array[String] = []


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	# A test that fails mid-modal would otherwise leave the freeze on for everything after it.
	get_tree().paused = false
	if is_instance_valid(game):
		game.process_mode = Node.PROCESS_MODE_INHERIT
	for dir: String in _written:
		_delete_recursive(dir)
	_written.clear()
	remove_child(_main)
	_main.free()


func _delete_recursive(dir: String) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	for file: String in access.get_files():
		access.remove(file)
	DirAccess.remove_absolute(dir)


# Frame counting rather than await_millis, and it stays that way deliberately. gdUnit4 implements
# await_millis with a Timer NODE parented under root; a Timer is pausable, so the moment anything
# calls get_tree().paused it stops firing and the whole RUN hangs with no failure and no timeout.
# ModalLock no longer pauses the tree, so await_millis would work again today -- but the next
# person to reach for a tree pause should not also have to rediscover that. process_frame is
# emitted regardless of pause.
func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _modals() -> Array[Node]:
	return get_tree().get_nodes_in_group("modal")


func _first_modal_of(script_class) -> Node:
	for node: Node in _modals():
		if is_instance_of(node, script_class):
			return node
	return null


# ==============================================================================
#  The ordering
# ==============================================================================

func test_reporting_from_the_pause_menu_leaves_the_board_playable() -> void:
	# THE regression. Esc -> Report -> back out -> Resume must land on the state Esc interrupted,
	# not on MENU. A board stuck in MENU is _board_locked_for_player() forever: no clicks, no
	# orders, and no second Esc either, because MENU routes Esc to the report card instead.
	game.game_state = game.GameState.IDLE
	game._open_pause_menu()
	await _frames(4)

	var menu: Node = _first_modal_of(PauseMenu)
	assert_object(menu).is_not_null()
	menu.chosen.emit(PauseMenu.Choice.REPORT)
	await _frames(4)

	var card: Node = _first_modal_of(ReportPanel)
	assert_object(card).is_not_null()
	card.finished.emit(false)          # Cancel
	await _frames(4)

	# The pause menu comes back rather than dumping them into the board mid-thought.
	var reopened: Node = _first_modal_of(PauseMenu)
	assert_object(reopened).is_not_null()
	reopened.chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)

	assert_int(game.game_state).is_equal(game.GameState.IDLE)
	assert_bool(game._board_locked_for_player()).is_false()


func test_a_second_escape_does_not_stack_a_second_card() -> void:
	game.game_state = game.GameState.AI_TURN   # locked, so Esc routes straight to the card
	game.open_report_card(BugReporter.Kind.BUG)
	await _frames(4)
	assert_int(_modals().size()).is_equal(1)

	game.open_report_card(BugReporter.Kind.BUG)
	await _frames(4)
	assert_int(_modals().size()).is_equal(1)

	var card: Node = _first_modal_of(ReportPanel)
	card.finished.emit(false)
	await _frames(4)


func test_a_locked_board_can_still_be_reported_on() -> void:
	# AI_TURN and MISSION_OVER are exactly when a stranger wants to complain, and exactly when the
	# pause menu refuses to open. Both must still reach a card.
	for state: int in [game.GameState.AI_TURN, game.GameState.MISSION_OVER]:
		game.game_state = state
		assert_bool(game._board_locked_for_player()).is_true()
		game.open_report_card(BugReporter.Kind.BUG)
		await _frames(4)
		var card: Node = _first_modal_of(ReportPanel)
		assert_object(card).is_not_null()
		card.finished.emit(false)
		await _frames(4)
		assert_int(_modals().size()).is_equal(0)


# ==============================================================================
#  What lands on disk
# ==============================================================================

func test_a_submitted_report_writes_the_note_and_the_board() -> void:
	game.spawn_sandbox()
	await await_idle_frame()
	assert_int(game.units_root.get_child_count()).is_greater(0)

	var result: Dictionary = await game.bug_reporter.report(
		"ATTACK_TARGETING", BugReporter.Kind.BUG, "the shove went the wrong way", null)
	_written.append(result["dir"])

	assert_str(result["dir"]).is_not_equal("")
	assert_bool(result["sent"]).is_false()   # headless: see the header

	var text := FileAccess.get_file_as_string(result["dir"] + "report.md")
	assert_str(text).contains("the shove went the wrong way")
	assert_str(text).contains("ATTACK_TARGETING")
	assert_str(text).contains("# Bug report")
	assert_bool(FileAccess.file_exists(result["dir"] + "board.tres")).is_true()


func test_the_screenshot_comes_from_the_window_and_not_the_hidden_subviewport() -> void:
	# #240. game.get_viewport() is the SubViewport the 2D game lives in, and since #222 that
	# viewport is transparent with the board visuals hidden -- so a frame grabbed there is 2D UI
	# on nothing, with the diorama, and therefore every visual bug in it, missing.
	#
	# The IMAGE cannot be the subject: capture_frame() returns null headless by design, because
	# RenderingServer.frame_post_draw never fires without a draw. So pin the CHOICE, which is the
	# whole of the fix. Falsify by pointing capture_viewport() back at game.get_viewport().
	#
	# Both halves are load-bearing. A case asserting only "it returns a Viewport" passes against
	# the bug; the is_not_same is what actually reds.
	var chosen: Viewport = game.bug_reporter.capture_viewport()
	assert_object(chosen).is_same(get_tree().root)
	assert_object(chosen).is_not_same(game.get_viewport())


func test_a_menu_side_report_has_no_board_and_says_so() -> void:
	# Feedback sent from mission select. Claiming "board.tres is the authoritative snapshot" beside
	# a folder with no board.tres is the kind of small lie that wastes a triage session.
	game.scenario_manager.clear_board()
	await await_idle_frame()
	assert_int(game.units_root.get_child_count()).is_equal(0)

	var result: Dictionary = await game.bug_reporter.report(
		"MENU", BugReporter.Kind.FEEDBACK, "I had no idea what to do", null)
	_written.append(result["dir"])

	var text := FileAccess.get_file_as_string(result["dir"] + "report.md")
	assert_str(text).contains("# Feedback report")
	assert_str(text).contains("I had no idea what to do")
	assert_str(text).contains("sent from a menu")
	assert_bool(FileAccess.file_exists(result["dir"] + "board.tres")).is_false()


# ==============================================================================
#  The modal lock (the "game moved while I was typing" bug)
# ==============================================================================

func test_a_card_freezes_the_game_and_closing_it_thaws() -> void:
	assert_bool(game.can_process()).is_true()
	game.game_state = game.GameState.AI_TURN
	game.open_report_card(BugReporter.Kind.BUG)
	await _frames(4)
	assert_bool(game.can_process()).is_false()
	assert_bool(game.camera_controller.can_process()).is_false()
	assert_bool(game.hover_presenter.can_process()).is_false()

	var card: Node = _first_modal_of(ReportPanel)
	card.finished.emit(false)
	await _frames(4)
	assert_bool(game.can_process()).is_true()
	assert_bool(game.camera_controller.can_process()).is_true()


func test_a_modal_leaves_the_click_path_into_the_subviewport_alive() -> void:
	# THE case this suite was missing, and its absence shipped a broken build. Every other test
	# emits `chosen`/`finished` directly, so no modal button was ever exercised -- and the first
	# fix froze the game with get_tree().paused, which left the modal itself processable while
	# killing GameContainer. GameContainer is the SubViewportContainer that forwards mouse input
	# INTO the viewport the modal lives in, so the pause menu drew, ate the board, and had no
	# working way out: the game was unrecoverable from its own pause screen.
	#
	# Assert the WHOLE path, not the endpoint. Falsify by swapping ModalLock._apply back to
	# `tree.paused = true`: the modal and its button stay green and the three links above go red.
	game.game_state = game.GameState.IDLE
	game._open_pause_menu()
	await _frames(4)

	var menu: Node = _first_modal_of(PauseMenu)
	assert_object(menu).is_not_null()

	var button: Button = null
	for node: Node in menu.find_children("*", "Button", true, false):
		button = node
		break
	assert_object(button).is_not_null()

	# Every link from the OS to the button has to survive the freeze, or the click never lands.
	assert_bool(_main.can_process()).is_true()
	assert_bool(_main.get_node("GameContainer").can_process()).is_true()
	assert_bool(_main.get_node("GameContainer/GameView").can_process()).is_true()
	assert_bool(menu.can_process()).is_true()
	assert_bool(button.can_process()).is_true()

	menu.chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)


func test_the_camera_does_not_move_while_a_card_is_up() -> void:
	# THE reported bug, driven through the real action rather than asserted on the mechanism.
	# cam_right is bound to D, so typing "and" or "sword" into the note box panned the board.
	# CameraController._process reads Input.is_action_pressed, a GLOBAL poll -- the focused
	# TextEdit consumes the key event and the poll never hears about it.
	var camera: CameraController = game.camera_controller
	# Isolate the pause as the only thing that could stop the poll -- the camera has two other
	# locks of its own (a scripted pan, and an AI turn) and neither is what this test is about.
	camera.lock_manual_input = false
	camera.ai_locked = false

	game.game_state = game.GameState.IDLE
	game.open_report_card(BugReporter.Kind.BUG)
	await _frames(4)

	var before: Vector2 = camera.target_position
	Input.action_press("cam_right")
	await _frames(10)
	# keyboard_direction is the poll's own output, recomputed every _process. Asserting on it as
	# well as on the position is what makes this immune to the camera being clamped to a boundary,
	# which would otherwise let a broken pause pass by simply having nowhere to move.
	assert_vector(camera.keyboard_direction).is_equal(Vector2.ZERO)
	assert_vector(camera.target_position).is_equal(before)

	# Not vacuous: the same held key MUST reach the camera once the card is gone, or this test
	# would pass just as well against a camera that never panned at all.
	_first_modal_of(ReportPanel).finished.emit(false)
	await _frames(10)
	assert_vector(camera.keyboard_direction).is_not_equal(Vector2.ZERO)
	Input.action_release("cam_right")


func test_the_freeze_survives_the_handoff_back_to_the_pause_menu() -> void:
	# The card frees and the pause menu is rebuilt in its place. If the lock were released on a
	# modal's own departure rather than derived from what is still open, the board would go live
	# for the frames in between -- which is exactly long enough for a held key to move it.
	game.game_state = game.GameState.IDLE
	game._open_pause_menu()
	await _frames(4)
	assert_bool(game.can_process()).is_false()

	_first_modal_of(PauseMenu).chosen.emit(PauseMenu.Choice.REPORT)
	await _frames(4)
	assert_bool(game.can_process()).is_false()

	_first_modal_of(ReportPanel).finished.emit(false)
	await _frames(4)
	assert_bool(game.can_process()).is_false()   # the pause menu is back

	_first_modal_of(PauseMenu).chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)
	assert_bool(game.can_process()).is_true()


func test_the_uploader_outlives_the_pause_it_runs_behind() -> void:
	# An upload is in flight while the card is up, i.e. while the Game subtree it lives under is
	# DISABLED. HTTPRequest polls its own internal process to emit request_completed, so a
	# freezable uploader never finishes and the card sticks on "Sending..." with no button to press.
	assert_int(game.bug_reporter.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	var uploader: Node = null
	for child: Node in game.bug_reporter.get_children():
		if child is ReportUploader:
			uploader = child
	assert_object(uploader).is_not_null()
	assert_int(uploader.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)


func test_dev_controls_outlive_the_modal_lock() -> void:
	# Dev controls are a layer ABOVE the lock. The boundary was drawn before dev affordances were
	# in scope, so every dev key sat under the freeze. can_process() is the delivery precondition
	# for _input, so assert it in the same breath as the loops that MUST stay frozen.
	# Falsify by deleting DevController's _ready: this goes red, every other freeze case stays green.
	var dev: DevController = game.dev_controller
	assert_int(dev.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)

	game.open_report_card(BugReporter.Kind.BUG)
	await _frames(4)
	assert_bool(game.can_process()).is_false()
	assert_bool(game.camera_controller.can_process()).is_false()
	assert_bool(dev.can_process()).is_true()

	var card: Node = _first_modal_of(ReportPanel)
	card.finished.emit(false)
	await _frames(4)


func test_the_report_hotkey_fires_behind_a_modal() -> void:
	# The reported symptom itself: F3 did nothing while a menu was up. Real InputEvents are never
	# delivered headless, so the event goes to _input directly -- that is the handler either way,
	# and can_process above is what pins the delivery half.
	assert_bool(DevTools.enabled()).is_true()   # the gate; without this the case passes vacuously
	var before: int = _report_dirs().size()

	game._open_pause_menu()
	await _frames(4)
	assert_object(_first_modal_of(PauseMenu)).is_not_null()   # the board really is locked

	var press := InputEventAction.new()
	press.action = "dev_report_bug"
	press.pressed = true
	game.dev_controller._input(press)
	await _frames(4)

	var after: Array[String] = _report_dirs()
	assert_int(after.size()).is_equal(before + 1)
	for dir: String in after:
		_written.append("user://reports/".path_join(dir))


func _report_dirs() -> Array[String]:
	var access := DirAccess.open("user://reports")
	if access == null:
		return []
	var dirs: Array[String] = []
	dirs.assign(access.get_directories())
	return dirs


func test_a_headless_run_never_uploads() -> void:
	# Falsify by deleting the headless check in ReportUploader.is_configured(): this goes red, and
	# in the version that ships it would instead post a report to Discord for every test that
	# reaches report(). The premise assertion is what stops this going vacuous if ENDPOINT is
	# ever blanked -- an empty endpoint would make it pass while proving nothing.
	assert_str(ReportUploader.ENDPOINT).is_not_equal("")
	assert_bool(game.bug_reporter.upload_configured()).is_false()


func test_reports_are_written_outside_the_scenario_tree() -> void:
	# Mission Select and #9's folder scan both walk Scenarios/. A report landing in there would
	# show up as a playable mission, and board.tres is a real scenario file, so it would load.
	assert_str(BugReporter.REPORT_DIR).starts_with("user://")
	assert_bool(BugReporter.REPORT_DIR.contains("Scenarios")).is_false()


# ==============================================================================
#  The message that reaches the channel
# ==============================================================================

func test_the_summary_names_the_kind_and_state_and_carries_the_note() -> void:
	var summary := BugReporter.build_summary(
		"2026-08-05_10-00-00", "AI_TURN", BugReporter.Kind.FEEDBACK, "the shove was the best part")
	assert_str(summary).contains("FEEDBACK")
	assert_str(summary).contains("AI_TURN")
	assert_str(summary).contains("the shove was the best part")


func test_a_long_note_is_truncated_in_the_message_but_not_in_the_report() -> void:
	# Discord drops a message over 2000 characters entirely -- the failure is silence, not an error,
	# so the truncation is what keeps a wordy playtester's report from vanishing.
	var long_note := "x".repeat(BugReporter.NOTE_IN_MESSAGE * 3)
	var summary := BugReporter.build_summary("stamp", "IDLE", BugReporter.Kind.BUG, long_note)
	assert_int(summary.length()).is_less(2000)
	assert_str(summary).contains("full text in report.md")

	var full := BugReporter.build_report_text(
		"stamp", "IDLE", BugReporter.Kind.BUG, long_note, null, null, [] as Array[Unit], "")
	assert_str(full).contains(long_note)


func test_an_empty_note_is_stated_rather_than_left_blank() -> void:
	# F3 files with no note at all. "(nothing typed)" beats an empty section that reads as a bug
	# in the reporter itself.
	var summary := BugReporter.build_summary("stamp", "IDLE", BugReporter.Kind.BUG, "   ")
	assert_str(summary).contains("(nothing typed)")
