# An open aim ends with the board or the turn it was opened on (#1572).
#
# The aim's teardown in exit_current_mode used to run only while game_state still said
# ATTACK_TARGETING. Three exits move the state first -- the pause menu writes MENU, and its Restart
# and Load rows write IDLE before clear_board; Return to Title runs abandon_mission under MENU -- and
# End Turn never called exit_current_mode at all. Each left the aim strip standing (a click-eating
# box), the watch palette on both aim layers, and, after End Turn, the pick and the stored selection.
#
# Every exit is taken through its real door: the pause card's `chosen`, the save screen's slot button
# and its confirm, the End Turn button's signal and its confirm card. The aim is opened through the
# ring's own watch pick, so the palette it leaves is the watch one and its reset is observable.
#
# The mission is authored in memory and saved to user://, never into Scenarios/, with save_dir
# redirected off the dev's own slots (test_pre_mission_restart.gd's fixture).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const SCRATCH := "user://__aim_ends_1572.tres"
const TEST_SAVE_DIR := "user://__test_saves_1572/"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10

var _main: Node
var game: Node2D


func before_test() -> void:
	ScenarioManager.save_dir = TEST_SAVE_DIR
	_wipe_saves()
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
	await await_idle_frame()


func after_test() -> void:
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		node.free()
	await _frames(1)
	await DialogFixtures.end_all_dialog(self)
	game.scenario_manager.clear_board()
	await _frames(1)
	get_tree().root.remove_child(_main)
	_main.free()
	_wipe_saves()
	ScenarioManager.save_dir = ScenarioManager.DEFAULT_SAVE_DIR
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


static func _wipe_saves() -> void:
	if not DirAccess.dir_exists_absolute(TEST_SAVE_DIR):
		return
	for file in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute(TEST_SAVE_DIR.path_join(file))
	DirAccess.remove_absolute(TEST_SAVE_DIR)


# ModalLock freezes the game subtree, so count frames rather than wait on a pausable timer.
func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


# --- the board ----------------------------------------------------------------------------------

# One walkable row, a player at one end and a hotseat enemy at the other, begun as a mission so
# Restart has a file to reload and a slot can be saved.
func _begin() -> Unit:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	assert_object(game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 0))).is_not_null()
	assert_object(game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(ROW_WIDTH - 1, 0))) \
		.is_not_null()
	var scenario: ScenarioData = game.scenario_manager.capture_scenario("aim_ends_1572", true)
	scenario.ai_factions.clear()   # hotseat: the enemy's turn waits rather than playing out
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	game.mission_controller.begin_mission(SCRATCH)
	await _frames(2)
	return _player()


func _player() -> Unit:
	for unit: Unit in game._all_units():
		if unit.get_faction() == Team.Faction.PLAYER:
			return unit
	return null


# A watch aim opened through the ring's own pick, with the preconditions that give every later
# assertion its teeth: the strip is up and both layers wear the WATCH palette, not the rest one.
func _aim_watch(unit: Unit) -> void:
	assert_object(unit).override_failure_message("fixture: no player unit on the board").is_not_null()
	var weapon := H.make_weapon(1)
	P.point(weapon.template.main_attack, 1)
	weapon.template.main_attack.can_overwatch = true
	assert_bool(unit.add_item(weapon)).override_failure_message("fixture: could not carry").is_true()
	assert_bool(unit.set_equipped_weapon(weapon)).override_failure_message("fixture: could not equip").is_true()
	game.select_unit(unit, unit.movement.cell)
	game.main_action_menu._pick_watch(unit, unit.get_default_attack())
	await _frames(1)
	assert_int(game.game_state).override_failure_message("fixture: the pick opened no aim") \
		.is_equal(game.GameState.ATTACK_TARGETING)
	assert_bool(game.aim_strip.visible).override_failure_message("fixture: the aim drew no strip").is_true()
	assert_int(game.aim_intent).is_equal(game.AimIntent.WATCH)
	assert_bool(game.overlay_manager.hover_overlay.modulate == OverlayManager.aim_fill_color(false)) \
		.override_failure_message("fixture: the watch palette is indistinguishable from the rest one").is_false()


func _assert_aim_gone(after: String) -> void:
	assert_bool(game.aim_strip.visible) \
		.override_failure_message("the aim strip outlived the aim, after %s" % after).is_false()
	assert_that(game.overlay_manager.attack_overlay.modulate) \
		.override_failure_message("the reach layer kept the aim's palette, after %s" % after) \
		.is_equal(OverlayManager.attack_reach_color(null, false))
	assert_that(game.overlay_manager.hover_overlay.modulate) \
		.override_failure_message("the footprint layer kept the aim's palette, after %s" % after) \
		.is_equal(OverlayManager.aim_fill_color(false))
	assert_int(game.aim_intent).override_failure_message("the watch verb outlived the aim, after %s" % after) \
		.is_equal(game.AimIntent.FIRE)
	assert_object(game.aim_source).is_null()
	assert_object(game.aim_forecast).is_null()


# --- the doors ----------------------------------------------------------------------------------

func _menu() -> PauseMenu:
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		if node is PauseMenu:
			return node
	return null


func _modal(type: Variant) -> Node:
	for node: Node in get_tree().get_nodes_in_group(ModalLock.GROUP):
		if is_instance_of(node, type):
			return node
	return null


func _button_with_prefix(host: Node, prefix: String) -> Button:
	for node: Node in host.find_children("*", "Button", true, false):
		if (node as Button).text.begins_with(prefix):
			return node
	return null


func _pause_and_pick(choice: PauseMenu.Choice) -> void:
	game._open_pause_menu()
	await _frames(4)
	assert_object(_menu()).override_failure_message("Esc opened no pause card").is_not_null()
	_menu().chosen.emit(choice)
	await _frames(6)


# ------------------------------------------------------------------------------
#  The cases
# ------------------------------------------------------------------------------

func test_restart_mid_aim_ends_the_aim() -> void:
	await _aim_watch(await _begin())
	await _pause_and_pick(PauseMenu.Choice.RESTART)
	assert_object(_player()).override_failure_message("the restart put no board back").is_not_null()
	_assert_aim_gone("Restart")


func test_loading_a_slot_mid_aim_ends_the_aim() -> void:
	var unit := await _begin()
	assert_bool(game.scenario_manager.save_to_slot(1)).override_failure_message("fixture: no slot saved").is_true()
	await _aim_watch(unit)
	await _pause_and_pick(PauseMenu.Choice.LOAD_GAME)
	var screen := _modal(SaveLoadScreen)
	assert_object(screen).override_failure_message("Load opened no save screen").is_not_null()
	_button_with_prefix(screen, "Slot 1").pressed.emit()
	await _frames(4)
	var confirm := _modal(ConfirmCard)
	assert_object(confirm).override_failure_message("no lost-progress confirm").is_not_null()
	_button_with_prefix(confirm, "Yes").pressed.emit()
	await _frames(6)
	assert_object(_player()).override_failure_message("the load put no board back").is_not_null()
	_assert_aim_gone("Load")


func test_return_to_title_mid_aim_ends_the_aim() -> void:
	await _aim_watch(await _begin())
	await _pause_and_pick(PauseMenu.Choice.TITLE)
	assert_bool(game.mission_controller.mission_select_is_up()) \
		.override_failure_message("Return to Title opened no title screen").is_true()
	_assert_aim_gone("Return to Title")


func test_end_turn_mid_aim_ends_the_aim_the_pick_and_the_selection() -> void:
	var unit := await _begin()
	await _aim_watch(unit)
	assert_bool(game.end_turn_button.visible) \
		.override_failure_message("fixture: End Turn is not offered mid-aim, so no player reaches this path") \
		.is_true()
	game.end_turn_button.end_turn_requested.emit()   # the real .connect() site
	await _frames(2)
	var confirm: ConfirmCard = null
	for child: Node in game.card_layer.get_children():
		if child is ConfirmCard and not child.is_queued_for_deletion():
			confirm = child
	assert_object(confirm).override_failure_message("an early End Turn asked nothing").is_not_null()
	_button_with_prefix(confirm, "End Turn").pressed.emit()
	await _frames(6)
	assert_int(game.turn_manager.active_faction()) \
		.override_failure_message("the turn never handed off").is_equal(Team.Faction.ENEMY)

	_assert_aim_gone("End Turn")
	assert_object(unit.active_attack) \
		.override_failure_message("the abandoned watch pick outlived the turn -- it would counter with it") \
		.is_null()
	var held: Unit = game.selected_unit   # typed: a freed ref compares == null as true (#149)
	assert_object(held).override_failure_message("the aimer stayed selected into the enemy's turn").is_null()
