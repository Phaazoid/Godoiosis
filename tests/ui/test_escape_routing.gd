# Where does Esc go (#723)?
#
# It used to fork on _board_locked_for_player() and open a BUG-defaulted report card on the far
# side. That predicate covers FOUR situations, not the one its comment described -- the title
# screen, the pre-mission screen, a finished board being inspected, and an AI turn -- so the card
# was the answer in all of them. The rule now: **Esc opens the pause menu whenever a board exists,
# and at the title screen it does nothing.**
#
# EVERY CASE FIRES A REAL KEY through Input.parse_input_event, the way test_modal_card_scaffold's
# _press_escape does. Calling _open_pause_menu() or _on_cancel() directly would skip the branch
# under test, which is the whole of what changed.
#
# The predicates are deliberately asserted UNNARROWED: the fix is to the one wrong READER, and
# menu_is_up()/_board_locked_for_player() are right about the nine others (#740's board lock among
# them). A case that let them relax would hide the regression this ticket most easily causes.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH := "user://__escape_routing_723.tres"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10
const ZONE_CELLS := 6

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController

# Set by _drive_beat once Pacing.beat has actually returned. A member rather than a local, because
# the point is to read it from OUTSIDE the coroutine while it is still suspended.
var _beat_landed := false


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	mc = game.mission_controller
	sm = game.scenario_manager
	# game._ready DEFERS open_mission_select, so the boot title screen lands a frame or two in.
	# Cases that want it gone dismiss it themselves -- it is the subject of the first case.
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# ModalLock freezes the game subtree, so a pausable Timer is not a safe wait here -- the same reason
# test_modal_card_scaffold.gd and test_report_flow.gd count frames.
func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _press_escape() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_ESCAPE
	down.physical_keycode = KEY_ESCAPE
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.physical_keycode = KEY_ESCAPE
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(4)


func _modal_of(script_class) -> Node:
	for node: Node in get_tree().get_nodes_in_group("modal"):
		if is_instance_of(node, script_class):
			return node
	return null


func _button(root: Node, label: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == label:
			return button
	return null


# --- the pre-mission fixture, the shape test_pre_mission_screen.gd uses -----------------------

func _author(roster: String, cap: int) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = roster
	sm.current_deployment_cap = cap
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(objectives)
	var scenario := sm.capture_scenario("escape_routing_723", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _enter_phase() -> bool:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the phase cannot be entered")
		return false
	mc._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()
	mc.begin_mission(_author(names[0], 2))
	await _frames(2)
	return mc.is_deploying()


func _screen() -> PreMissionScreen:
	for child: Node in game.ui_layer.get_children():
		if child is PreMissionScreen:
			return child as PreMissionScreen
	return null


# --- the title screen: the one place Esc does nothing ----------------------------------------

func test_escape_at_the_title_screen_does_nothing() -> void:
	assert_bool(mc.mission_select_is_up()).override_failure_message(
		"the fixture never landed on the title screen, so this case proves nothing").is_true()

	await _press_escape()

	assert_object(_modal_of(ReportPanel)).override_failure_message(
		"Esc at the title screen opened a bug report card -- the defect #723 was filed for"
	).is_null()
	assert_object(_modal_of(PauseMenu)).override_failure_message(
		"Esc opened a pause menu over the title screen. The title screen IS that menu; its Load, "
		+ "Glossary, Settings, Feedback and Quit rows are already on display behind the card."
	).is_null()


# --- the pre-mission screen: the dev's second sighting ----------------------------------------

func test_escape_in_the_pre_mission_phase_opens_the_pause_menu() -> void:
	if not await _enter_phase():
		push_warning("the phase did not open, so the routing under it cannot be exercised")
		return

	assert_bool(game.menu_is_up()).override_failure_message(
		"the phase is up but the board is not locked -- the fixture is not in the state under test"
	).is_true()

	await _press_escape()

	assert_object(_modal_of(ReportPanel)).override_failure_message(
		"Esc in the pre-mission phase still opens a bug report card").is_null()
	assert_object(_modal_of(PauseMenu)).override_failure_message(
		"Esc in the pre-mission phase reached no pause menu").is_not_null()


# The stack, which is what a card-first rule buys. The screen answers ui_cancel only with something
# in hand, so the FIRST press must drop it and leave the menu alone.
func test_escape_with_gear_in_hand_drops_it_before_it_reaches_the_menu() -> void:
	if not await _enter_phase():
		push_warning("the phase did not open, so the stack cannot be exercised")
		return

	var screen: PreMissionScreen = _screen()
	assert_object(screen).is_not_null()
	# Straight onto the selection, because what is under test is who ANSWERS the key, not how a
	# player fills their hand. Any non-null item puts the screen in the state that claims Esc.
	screen._selected_item = Item.new()

	await _press_escape()

	assert_object(screen._selected_item).override_failure_message(
		"the first Esc did not let go of what was in hand").is_null()
	assert_object(_modal_of(PauseMenu)).override_failure_message(
		"the first Esc dropped the item AND opened the pause menu -- the screen no longer gets "
		+ "first claim on the key, so one press did two things").is_null()

	await _press_escape()

	assert_object(_modal_of(PauseMenu)).override_failure_message(
		"the second Esc, with empty hands, still did not reach the pause menu").is_not_null()


# --- a finished board being inspected ---------------------------------------------------------

# MISSION_OVER is set directly: it is the INPUT to the predicate under test, and driving a real
# mission to its end here would be a second copy of tests/flow/test_mission_controller.gd. What is
# NOT faked is the key or the branch it travels.
func test_escape_on_a_finished_board_opens_the_pause_menu() -> void:
	mc._close_mission_select()
	game.game_state = game.GameState.MISSION_OVER
	await await_idle_frame()

	await _press_escape()

	assert_object(_modal_of(ReportPanel)).override_failure_message(
		"Esc on a finished board still opens a bug report card").is_null()
	assert_object(_modal_of(PauseMenu)).override_failure_message(
		"Esc on a finished board reached no pause menu").is_not_null()


# --- an AI turn: the case the dev accepted the risk on ----------------------------------------

func test_escape_during_a_pass_opens_a_menu_that_greys_what_it_cannot_serve() -> void:
	mc._close_mission_select()
	game.game_state = game.GameState.AI_TURN
	await await_idle_frame()
	assert_bool(game.playback_owns_board()).is_true()

	await _press_escape()

	var menu: Node = _modal_of(PauseMenu)
	assert_object(menu).override_failure_message(
		"Esc during a pass reached no pause menu").is_not_null()

	# Resume is what a pause menu is FOR; refusing it mid-pass would be a card with no way out.
	var resume: Button = _button(menu, "Resume")
	assert_object(resume).is_not_null()
	assert_bool(resume.disabled).override_failure_message(
		"Resume is greyed during a pass -- the card cannot be left").is_false()

	# Everything that tears the board down while a parked coroutine still holds references into it.
	# Load Game rides can_load, so it is greyed either way here; the ROW that must carry a reason is
	# Return to Title, which is always offered and always destructive.
	for label: String in ["Return to Title"]:
		var button: Button = _button(menu, label)
		assert_object(button).override_failure_message(
			"the pause menu has no %s row at all" % label).is_not_null()
		assert_bool(button.disabled).override_failure_message(
			"%s is live during a pass -- it would free the Unit nodes the parked pass resumes into"
			% label).is_true()
		# #166: a menu may only grey what it can explain.
		assert_str(button.tooltip_text).override_failure_message(
			"%s is greyed with no reason on it" % label).is_not_empty()


# --- the seam that makes the AI case honest ---------------------------------------------------

func _drive_beat() -> void:
	await Pacing.beat(self, 0.0)
	_beat_landed = true


# THE WIRE. ModalLock disables the GAME NODE and every wait in Pacing is a SceneTreeTimer owned by
# the tree with process_always -- so the freeze alone does not stop a coroutine, and the pass would
# play on behind a card calling itself PAUSED. The park in Pacing.beat is what actually stops it.
#
# Driven through the REAL pause menu rather than a bare "modal" group member: the group is the
# mechanism, but the claim worth pinning is that the card a player opens is one.
func test_a_pass_parks_on_the_pause_menu_and_resumes_when_it_closes() -> void:
	mc._close_mission_select()
	game.game_state = game.GameState.AI_TURN
	await await_idle_frame()

	await _press_escape()
	var menu: Node = _modal_of(PauseMenu)
	assert_object(menu).is_not_null()

	_beat_landed = false
	_drive_beat()
	await _frames(6)
	assert_bool(_beat_landed).override_failure_message(
		"a Pacing beat ran to completion while the pause menu was up -- playback does not park, "
		+ "so the battle plays on behind the card").is_false()

	menu.chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(6)
	assert_bool(_beat_landed).override_failure_message(
		"the beat never resumed after the card closed -- the park does not let go").is_true()


# --- the restore, which the park makes racy for the first time --------------------------------

# A pass that FINISHES under the card writes its own state, and putting the stashed one back over
# that is the "leaves the board locked for good" failure the GLOSSARY and REPORT arms already carry
# warnings about -- arriving by a new road, because until #723 Esc could not reach a running board.
#
# The finish is simulated by writing the state while the card is up: driving a real pass to its end
# behind a modal is not something a headless run can stage (Pacing collapses every beat to zero),
# and what is under test is the RESTORE, not the pass. The close is real.
func test_a_state_written_while_the_card_is_up_survives_the_close() -> void:
	mc._close_mission_select()
	game.game_state = game.GameState.AI_TURN
	await await_idle_frame()

	await _press_escape()
	var menu: Node = _modal_of(PauseMenu)
	assert_object(menu).is_not_null()
	assert_int(game.game_state).override_failure_message(
		"the card did not lock the board, so there is no stashed state to clobber"
	).is_equal(game.GameState.MENU)

	# The pass ends underneath the card and hands the board back.
	game.game_state = game.GameState.IDLE
	menu.chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)

	assert_int(game.game_state).override_failure_message(
		"Resume put the stale AI_TURN back over the state the finished pass wrote -- the board is "
		+ "locked with nothing running to unlock it").is_equal(game.GameState.IDLE)


# ...and the ordinary case the guard must not have broken: with nobody else writing, Resume still
# hands the board back exactly as it did.
func test_resume_still_restores_the_state_escape_interrupted() -> void:
	mc._close_mission_select()
	game.game_state = game.GameState.MISSION_OVER
	await await_idle_frame()

	await _press_escape()
	var menu: Node = _modal_of(PauseMenu)
	assert_object(menu).is_not_null()

	menu.chosen.emit(PauseMenu.Choice.RESUME)
	await _frames(4)

	assert_int(game.game_state).override_failure_message(
		"Resume did not put the pre-pause state back -- the guard swallowed the ordinary restore"
	).is_equal(game.GameState.MISSION_OVER)


# --- the predicate the fix must NOT have narrowed ---------------------------------------------

func test_the_board_lock_still_covers_every_situation_it_did() -> void:
	# The title screen, which the fixture boots onto.
	assert_bool(game.menu_is_up()).override_failure_message(
		"menu_is_up() stopped covering the title screen -- the predicate was narrowed instead of "
		+ "the one reader that was wrong").is_true()
	assert_bool(game._board_locked_for_player()).is_true()

	mc._close_mission_select()
	game.game_state = game.GameState.MISSION_OVER
	await await_idle_frame()
	assert_bool(game.menu_is_up()).override_failure_message(
		"menu_is_up() stopped covering a finished mission").is_true()

	game.game_state = game.GameState.AI_TURN
	await await_idle_frame()
	assert_bool(game.playback_owns_board()).override_failure_message(
		"playback_owns_board() stopped covering an AI turn").is_true()
	assert_bool(game._board_locked_for_player()).is_true()
