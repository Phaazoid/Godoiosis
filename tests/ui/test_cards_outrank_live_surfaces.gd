# A card over a LIVE surface (#1034): the pause menu, the report card, every ModalCard -- over the
# action wheel and over a playing dialogue.
#
# THE ROOT CAUSE WAS TWO AXES READ AS ONE. Every card drew at z_index 200 inside UILayer, a CanvasLayer
# at 0; the wheel is a CanvasLayer at 20 and Dialogic's layout one at 1. A z_index never crosses a
# CanvasLayer, for the eye OR for the mouse (GUI picking sorts roots by layer first), so both smaller
# numbers won: a click on the pause menu advanced the dialogue, and an open wheel -- a full-rect catcher,
# frozen but still hit-tested -- swallowed every click on the card (a DISABLED Control is a wall, probed
# on 4.7.1: it takes the click and does nothing with it). Cards mount on game.card_layer now.
#
# EVERY CLICK AND KEY HERE IS REAL -- Input.parse_input_event into the window, through GameContainer and
# GameView's own stretch, so GUI picking is what is under test. Emitting a card's `chosen` directly is
# exactly the blindness #131's suite had: it cannot see which surface the mouse reaches.
#
# WHAT A MODAL OWES A SURFACE IT CANNOT FREEZE: the dialogue is mounted BESIDE Game (#687), outside the
# subtree ModalLock disables, so the lock pauses Dialogic from the same group state. The Enter case is
# the one that needs it -- no card takes keyboard focus, so Enter reaches Dialogic's _unhandled_input.
#
# The dialogue's advances are counted off Dialogic's own dialogic_action_priority, never off
# current_event_idx: a press during the text reveal only finishes the reveal, so an index compare would
# pass against a build whose dialogue took the click.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const SCRATCH := "user://__cards_outrank_1034.tres"
const ZONE_CELLS := 6

var _main: Node
var game: Node2D
var _advances := 0


func before_test() -> void:
	# Headless windows can be tiny, and a click has to land inside this one.
	get_tree().root.size = Vector2i(1280, 720)
	PlayerSettings.reset_for_test()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	await await_idle_frame()   # game._ready defers the title screen by a frame
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.scenario_director.disarm()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	_advances = 0
	Dialogic.Inputs.dialogic_action_priority.connect(_count_advance)
	# A headless window is never told the mouse entered it, and a viewport that thinks the pointer is
	# outside tracks nothing under it -- test_objective_rows' line.
	get_tree().root.notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
	await await_idle_frame()


func after_test() -> void:
	Dialogic.Inputs.dialogic_action_priority.disconnect(_count_advance)
	# Cards first: freeing them releases the lock, which is what lifts Dialogic's pause -- the dance
	# below ends a timeline and should not be asked to do it paused.
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		node.free()
	await await_idle_frame()
	await DialogFixtures.end_all_dialog(self)
	get_tree().root.remove_child(_main)
	_main.free()
	await await_idle_frame()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _count_advance() -> void:
	_advances += 1


# --- driving it for real ---------------------------------------------------------------------------

func _pump() -> void:
	Input.flush_buffered_events()
	await await_idle_frame()
	Input.flush_buffered_events()
	await await_idle_frame()
	await await_idle_frame()


# Where a Control inside GameView sits in the WINDOW: through the viewport's own stretch and out
# through GameContainer, the chain Viewport.push_input inverts on the way in (visual-clarity.md).
func _screen_point(control: Control) -> Vector2:
	var view := control.get_viewport()
	var in_view: Vector2 = (view.get_final_transform() * control.get_global_transform_with_canvas()) \
			* (control.size * 0.5)
	var container := _main.get_node("GameContainer") as Control
	return container.get_global_rect().position + in_view


func _click(control: Control) -> void:
	var at := _screen_point(control)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event)
	await _pump()


func _press(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _pump()


func _modal_of(script_class) -> Node:
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		if is_instance_of(node, script_class) and not node.is_queued_for_deletion():
			return node
	return null


func _button(root: Node, label: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == label:
			return button
	return null


func _ring() -> ActionMenuController:
	for child: Node in game.get_children():
		if child is ActionMenuController and not child.is_queued_for_deletion():
			return child as ActionMenuController
	return null


func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	return unit


# Opened the way a click opens it, so the selection goes through the one select door.
func _open_ring(unit: Unit) -> ActionMenuController:
	game._click_idle(unit.get_projected_destination())
	await await_idle_frame()
	var ring := _ring()
	assert_object(ring).override_failure_message("clicking the unit opened no ring").is_not_null()
	return ring


# A few lines, so there is always a next one to advance to. Played through the director's own door,
# which is what sets the layout's layer.
func _talk() -> void:
	var timeline := DialogicTimeline.new()
	timeline.from_text("The first line.\nThe second line.\nThe third line.\nThe fourth line.")
	assert_bool(game.scenario_director.preview(timeline)).override_failure_message(
		"the director refused to play -- something was already talking").is_true()
	await Dialogic.timeline_started
	# Past Dialogic's own input block (0.1s after a reveal starts), so that is never what keeps a
	# press from counting. A wall-clock wait is safe: nothing here pauses the TREE.
	await await_millis(250)


# ==============================================================================
#  The wheel
# ==============================================================================

# THE LAYER FIX, on the one card that still opens over a live wheel: F3's report card leaves the ring
# frozen underneath (dev ruling), so this is where "the card is what the mouse hits" is asked.
func test_a_click_on_the_report_card_reaches_it_over_an_open_wheel() -> void:
	var unit := _spawn(Vector2i(2, 0))
	var ring := await _open_ring(unit)

	await _press(KEY_F3)
	var card := _modal_of(ReportPanel)
	assert_object(card).override_failure_message("F3 over an open wheel opened no report card").is_not_null()
	var cancel := _button(card, "Cancel")
	assert_object(cancel).is_not_null()

	await _click(cancel)

	assert_object(_modal_of(ReportPanel)).override_failure_message(
		"a click on the report card's Cancel never reached it -- the wheel's full-rect catcher is "
		+ "still above the card and swallowed it").is_null()
	assert_bool(ModalLock.any_open(get_tree())).is_false()
	# The report card is a detour, so the ring is back exactly as it was.
	assert_object(_ring()).override_failure_message(
		"the report card took the wheel with it -- only the pause menu closes it").is_same(ring)
	assert_bool(ring.can_process()).is_true()


# RULING 1: Esc closes the wheel and the pause menu opens over the plain board. Resume is then a real
# click, and the board comes back. The ordering this depends on is that the ring closes BEFORE
# _open_pause_menu writes MENU: closing it clears the selection, which rests game_state, so a close
# landing after that write leaves a pause menu up over a board that reads as not locked.
func test_escape_over_an_open_wheel_closes_it_and_resume_hands_the_board_back() -> void:
	var unit := _spawn(Vector2i(2, 0))
	await _open_ring(unit)

	await _press(KEY_ESCAPE)

	assert_object(_ring()).override_failure_message(
		"the wheel survived Esc -- Restart, Load and Title would leave it over the next board, "
		+ "holding a unit that board has freed").is_null()
	var menu := _modal_of(PauseMenu)
	assert_object(menu).override_failure_message("Esc reached no pause menu").is_not_null()
	assert_bool(game.menu_is_up()).override_failure_message(
		"the pause menu is up but the board does not read as MENU -- the ring closed after the "
		+ "menu's own write and rested game_state under it").is_true()

	await _click(_button(menu, "Resume"))

	assert_object(_modal_of(PauseMenu)).override_failure_message(
		"a click on Resume never reached the pause menu").is_null()
	assert_bool(game.menu_is_up()).override_failure_message(
		"Resume left the board locked").is_false()
	assert_bool(game.can_process()).is_true()


# No ring outlives its board: F2, a restart and a load all tear the board down through reset().
func test_a_board_teardown_closes_an_open_wheel() -> void:
	var unit := _spawn(Vector2i(2, 0))
	await _open_ring(unit)

	game.scenario_manager.clear_board()
	await await_idle_frame()

	assert_object(_ring()).override_failure_message(
		"the ring outlived the board it was opened on").is_null()


# The Enter path the dev never hit: Enter opens "Begin Mission?" over an open ring, and now that the
# card is clickable, Begin ends the phase. The phase's one exit takes the ring with it.
func test_ending_the_pre_mission_phase_closes_an_open_wheel() -> void:
	if not await _enter_phase():
		push_warning("the phase did not open, so its exit cannot be exercised")
		return
	var placed: Unit = null
	for child: Node in game.units_root.get_children():
		var unit := child as Unit
		if unit != null and unit.drawn_from_roster:
			placed = unit
	assert_object(placed).override_failure_message(
		"the phase opened with nobody placed, so there is no ring to open").is_not_null()
	game.main_action_menu.show_main_menu(placed, Vector2i(400, 300))
	await await_idle_frame()
	assert_object(_ring()).is_not_null()

	assert_bool(game.mission_controller.commit_deployment()).is_true()
	await await_idle_frame()

	assert_object(_ring()).override_failure_message(
		"the ring survived the end of the phase, still offering its verbs to a battle that has begun"
	).is_null()


# ==============================================================================
#  The dialogue
# ==============================================================================

# THE REPORTED DEFECT: "clicking in the pause menu advances the dialogue". The click has to reach the
# CARD -- that is the layer fix -- and the dialogue must not hear it.
func test_a_click_on_the_pause_menu_reaches_it_over_a_playing_dialogue() -> void:
	await _talk()
	await _press(KEY_ESCAPE)
	var menu := _modal_of(PauseMenu)
	assert_object(menu).override_failure_message("Esc during dialogue reached no pause menu").is_not_null()
	var before := _advances

	await _click(_button(menu, "Resume"))

	assert_object(_modal_of(PauseMenu)).override_failure_message(
		"a click on Resume never reached the pause menu -- the dialogue's full-rect catcher is above "
		+ "the card and took it").is_null()
	assert_int(_advances).override_failure_message(
		"the click on the pause menu advanced the dialogue behind it").is_equal(before)


# RULING 2: the card pauses the dialogue. Enter is Dialogic's advance and no card takes focus, so
# without the pause it reaches Dialogic's _unhandled_input straight through the menu.
func test_enter_behind_a_card_does_not_advance_the_dialogue() -> void:
	await _talk()
	# The control: with no card up, Enter DOES advance. Without it, a press that never reached
	# Dialogic at all would make the assertion below pass vacuously.
	await _press(KEY_ENTER)
	assert_int(_advances).override_failure_message(
		"Enter did not reach the dialogue even with no card up, so this case proves nothing").is_equal(1)
	await await_millis(250)   # past the input block the advance just set

	await _press(KEY_ESCAPE)
	assert_object(_modal_of(PauseMenu)).is_not_null()
	assert_bool(Dialogic.paused).override_failure_message(
		"the pause menu is up and the dialogue is not paused").is_true()

	await _press(KEY_ENTER)

	assert_int(_advances).override_failure_message(
		"Enter advanced the dialogue behind the pause menu").is_equal(1)

	await _click(_button(_modal_of(PauseMenu), "Resume"))
	assert_bool(Dialogic.paused).override_failure_message(
		"the last card closed and the dialogue stayed paused").is_false()


# THE AUTOLOAD BLEED: Dialogic outlives every scene. If the release waited on a valid game_root, a card
# outliving its Game would leave the pause on for good, and every dialogue after it -- in the game or
# in the next suite -- would hang on dialogic_resumed. EXPECTED in the log: the engine's "Lambda capture
# at index 1 was freed", which is ModalLock's release being handed the freed game_root -- the path.
func test_the_dialogue_pause_lifts_even_when_the_game_is_freed_first() -> void:
	var fake_game := Node.new()
	get_tree().root.add_child(fake_game)
	var card := Control.new()
	get_tree().root.add_child(card)
	ModalLock.claim(card, fake_game)
	assert_bool(Dialogic.paused).is_true()

	fake_game.free()
	card.free()
	await await_idle_frame()

	assert_bool(Dialogic.paused).override_failure_message(
		"a card freed after its Game left the dialogue paused for good").is_false()


# THE RISKIEST ASSUMPTION of the pause: Restart from the pause menu starts the mission's intro while
# the menu is still in the tree, i.e. paused. Dialogic's handle_event waits for dialogic_resumed rather
# than dropping the event -- this says so on the real addon, not on a reading of it.
func test_a_timeline_started_under_a_card_plays_once_the_card_closes() -> void:
	var card := Control.new()
	get_tree().root.add_child(card)
	ModalLock.claim(card, game)
	assert_bool(Dialogic.paused).is_true()

	var timeline := DialogicTimeline.new()
	timeline.from_text("Said under a card.\nAnd after it.")
	assert_bool(game.scenario_director.preview(timeline)).is_true()
	await Dialogic.timeline_started
	await await_idle_frame()
	assert_int(Dialogic.current_event_idx).override_failure_message(
		"the first line ran while a card was up -- the pause did not hold it").is_less(0)

	card.free()
	await await_idle_frame()
	await await_idle_frame()

	assert_int(Dialogic.current_event_idx).override_failure_message(
		"the card closed and the timeline never started -- it was dropped, not held").is_equal(0)


# ==============================================================================
#  The stack, live
# ==============================================================================

# Every layer in the stack is SET from UiLayers, read here off the live nodes. The order is what the
# Prolog needs (its UNIT_SELECTED line plays while the wheel is open) and what #1034 needs (a card over
# everything). NB the dialogue's number equals Dialogic's own default of 1, so its line cannot tell
# "set from the table" from "left alone"; it can still catch a style that moves it.
func test_the_live_stack_is_the_declared_one() -> void:
	assert_int(UiLayers.LAYER_HUD).is_less(UiLayers.LAYER_DIALOGUE)
	assert_int(UiLayers.LAYER_DIALOGUE).is_less(UiLayers.LAYER_ACTION_MENU)
	assert_int(UiLayers.LAYER_ACTION_MENU).is_less(UiLayers.LAYER_CARDS)

	assert_int((game.ui_layer as CanvasLayer).layer).is_equal(UiLayers.LAYER_HUD)
	assert_int((game.card_layer as CanvasLayer).layer).is_equal(UiLayers.LAYER_CARDS)

	var ring := await _open_ring(_spawn(Vector2i(2, 0)))
	assert_int(ring._layer.layer).is_equal(UiLayers.LAYER_ACTION_MENU)
	ring.dismiss()
	await await_idle_frame()

	await _talk()
	# Through a plain Node: DialogicLayoutBase is a script class on Node, so it will not cast directly.
	var layout_node: Node = Dialogic.Styles.get_layout_node()
	var layout := layout_node as CanvasLayer
	assert_object(layout).override_failure_message("the dialogue layout is not a CanvasLayer").is_not_null()
	assert_int(layout.layer).is_equal(UiLayers.LAYER_DIALOGUE)

	await _press(KEY_ESCAPE)
	var menu := _modal_of(PauseMenu)
	assert_object(menu).is_not_null()
	assert_object(menu.get_parent()).override_failure_message(
		"the pause menu mounted somewhere other than the card layer").is_same(game.card_layer)


# --- the pre-mission fixture, test_escape_routing's shape ------------------------------------------

func _author(roster: String, cap: int) -> String:
	var sm: ScenarioManager = game.scenario_manager
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = roster
	sm.current_deployment_cap = cap
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	game.mission_controller.set_objectives(objectives)
	var scenario := sm.capture_scenario("cards_outrank_1034", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _enter_phase() -> bool:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the phase cannot be entered")
		return false
	game.mission_controller.begin_mission(_author(names[0], 2))
	await await_idle_frame()
	await await_idle_frame()
	return game.mission_controller.is_deploying()
