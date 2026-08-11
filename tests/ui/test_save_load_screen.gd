# SaveLoadScreen + ConfirmCard + the title door (#144), driven through REAL buttons wherever a
# flow is asserted -- the #131 lesson: a suite that only emits signals ships a clickless dialog
# green. Chrome/lock pins live in test_modal_card_scaffold.gd; this file owns the flows.
#
# Same redirected-save_dir discipline as tests/flow/test_save_slots.gd: never the real slots.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const TEST_SAVE_DIR := "user://__test_saves_144_ui/"
const MISSION_A := "res://Scenarios/missions/__ui_fixture_a.tres"   # paths, never files
const MISSION_B := "res://Scenarios/missions/__ui_fixture_b.tres"

var _main: Node
var game: Node2D


func before_test() -> void:
	ScenarioManager.save_dir = TEST_SAVE_DIR
	_wipe_test_saves()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	await await_idle_frame()
	game.mission_controller._close_mission_select()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	_wipe_test_saves()
	ScenarioManager.save_dir = ScenarioManager.DEFAULT_SAVE_DIR
	if is_instance_valid(game):
		game.process_mode = Node.PROCESS_MODE_INHERIT
	remove_child(_main)
	_main.free()


static func _wipe_test_saves() -> void:
	if not DirAccess.dir_exists_absolute(TEST_SAVE_DIR):
		return
	for file in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute(TEST_SAVE_DIR.path_join(file))
	DirAccess.remove_absolute(TEST_SAVE_DIR)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _modal_of(type: Variant) -> Node:
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		if is_instance_of(node, type):
			return node
	return null


func _button_with_prefix(host: Node, prefix: String) -> Button:
	for node: Node in host.find_children("*", "Button", true, false):
		if (node as Button).text.begins_with(prefix):
			return node
	return null


# A saved slot 1: one PLAYER unit, origin mission `mission`.
func _fill_slot_one(mission: String) -> void:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 1))
	assert_object(unit).is_not_null()
	game.scenario_manager.last_loaded_path = mission
	assert_bool(game.scenario_manager.save_to_slot(1)).is_true()


func test_the_screen_leaves_the_click_path_into_the_subviewport_alive() -> void:
	# The report-flow:199 shape for the new card: assert the WHOLE chain, then leave through the
	# real Back button rather than an emitted signal.
	var result := [-2]
	var run := func() -> void:
		result[0] = await SaveLoadScreen.show_screen(game, SaveLoadScreen.Mode.LOAD)
	run.call()
	await _frames(4)

	var screen: Node = _modal_of(SaveLoadScreen)
	assert_object(screen).is_not_null()
	var back: Button = _button_with_prefix(screen, "Back")
	assert_object(back).is_not_null()

	assert_bool(_main.can_process()).is_true()
	assert_bool(_main.get_node("GameContainer").can_process()).is_true()
	assert_bool(_main.get_node("GameContainer/GameView").can_process()).is_true()
	assert_bool(screen.can_process()).is_true()
	assert_bool(back.can_process()).is_true()

	back.pressed.emit()
	await _frames(4)
	assert_int(result[0]).is_equal(-1)
	assert_object(_modal_of(SaveLoadScreen)).is_null()


func test_overwriting_a_slot_asks_first_and_no_declines() -> void:
	_fill_slot_one(MISSION_A)
	# A second mission is now "in progress": the overwrite question is whether B may replace A.
	game.scenario_manager.last_loaded_path = MISSION_B

	var result := [-2]
	var run := func() -> void:
		result[0] = await SaveLoadScreen.show_screen(game, SaveLoadScreen.Mode.SAVE)
	run.call()
	await _frames(4)
	var screen: Node = _modal_of(SaveLoadScreen)
	assert_object(screen).is_not_null()

	# Press the filled slot: a ConfirmCard must appear, and No must change NOTHING.
	_button_with_prefix(screen, "Slot 1").pressed.emit()
	await _frames(4)
	var confirm: Node = _modal_of(ConfirmCard)
	assert_object(confirm).is_not_null()
	_button_with_prefix(confirm, "No").pressed.emit()
	await _frames(4)

	assert_object(_modal_of(ConfirmCard)).is_null()
	assert_object(_modal_of(SaveLoadScreen)).is_not_null()   # still open
	assert_int(result[0]).is_equal(-2)                        # nothing finished
	var save_after_no: SaveGame = game.scenario_manager.load_slot(1)
	assert_str(save_after_no.mission_path).is_equal(MISSION_A)

	# Same press, Yes this time: the slot is rewritten and the screen closes on it.
	_button_with_prefix(screen, "Slot 1").pressed.emit()
	await _frames(4)
	_button_with_prefix(_modal_of(ConfirmCard), "Yes").pressed.emit()
	await _frames(4)

	assert_int(result[0]).is_equal(1)
	var save_after_yes: SaveGame = game.scenario_manager.load_slot(1)
	assert_str(save_after_yes.mission_path).is_equal(MISSION_B)


func test_empty_slots_grey_with_the_reason_in_load_mode() -> void:
	_fill_slot_one(MISSION_A)

	var run := func() -> void:
		var _slot: int = await SaveLoadScreen.show_screen(game, SaveLoadScreen.Mode.LOAD)
	run.call()
	await _frames(4)
	var screen: Node = _modal_of(SaveLoadScreen)

	var filled: Button = _button_with_prefix(screen, "Slot 1")
	var empty: Button = _button_with_prefix(screen, "Slot 2")
	assert_bool(filled.disabled).is_false()
	assert_bool(empty.disabled).is_true()
	assert_bool(empty.tooltip_text.is_empty()).is_false()   # a menu can only grey what it can explain (#166)

	screen.finished.emit(-1)
	await _frames(2)


func test_the_title_offers_load_game_only_when_a_save_exists() -> void:
	var bare := MissionSelectScreen.open(game, [] as Array[String], [] as Array[String])
	await _frames(2)
	assert_object(_button_with_prefix(bare, "Load Game")).is_null()
	bare.queue_free()
	await _frames(2)

	_fill_slot_one(MISSION_A)
	var stocked := MissionSelectScreen.open(game, [] as Array[String], [] as Array[String])
	await _frames(2)
	assert_object(_button_with_prefix(stocked, "Load Game")).is_not_null()
	stocked.queue_free()
	await _frames(2)


func test_the_title_door_resumes_and_closes_the_select_screen() -> void:
	# The full title wire, every step a real button: Load Game row -> slot row -> the board is
	# back, the select screen is gone, and Restart aims at the origin mission.
	_fill_slot_one(MISSION_A)
	game.scenario_manager.clear_board()
	await await_idle_frame()

	game.mission_controller.open_mission_select()
	await _frames(2)
	var title: Node = game.mission_controller._select_screen
	assert_object(title).is_not_null()

	_button_with_prefix(title, "Load Game").pressed.emit()
	await _frames(4)
	var screen: Node = _modal_of(SaveLoadScreen)
	assert_object(screen).is_not_null()

	_button_with_prefix(screen, "Slot 1").pressed.emit()   # no lost-progress confirm on the title
	await _frames(6)

	assert_object(_modal_of(SaveLoadScreen)).is_null()
	assert_object(game.mission_controller._select_screen).is_null()
	assert_int((game._all_units() as Array).size()).is_equal(1)
	assert_str(game.scenario_manager.last_loaded_path).is_equal(MISSION_A)
	assert_bool(game.can_process()).is_true()   # the lock lifted with the card
