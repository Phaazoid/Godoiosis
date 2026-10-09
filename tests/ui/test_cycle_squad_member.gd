# F / Shift+F cycle the selected squad member (#1038), on the real game scene.
#
# The key is pressed the way project.godot binds it -- an InputEventKey on its physical keycode into
# game._input -- so a bound-and-dead action reds here rather than passing a suite that calls the
# cycle directly (test_pre_mission_bar.gd's Tab case is the precedent). Selecting is a queue-row
# click's sequence: the ring opens on the unit and the camera is asked to look at it.
#
# Fixture is tests/ui/test_queue_row_click.gd's, minus the real clicks.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	await await_idle_frame()
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.scenario_director.disarm()
	game.turn_manager.set_active_faction(Team.Faction.PLAYER)
	game.game_state = game.GameState.IDLE
	for x in range(10):
		for y in range(4):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# --- fixture -------------------------------------------------------------------------------------

func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	return unit


# A leader and two followers on row `y`, joined in order, so the squad's member order is the order
# returned.
func _squad_of_three(y: int) -> Array[Unit]:
	var leader := _spawn(Vector2i(1, y))
	var second := _spawn(Vector2i(2, y))
	var third := _spawn(Vector2i(3, y))
	game.squad_manager.join_squad(second, leader.squad)
	game.squad_manager.join_squad(third, leader.squad)
	var members: Array[Unit] = []
	members.assign(leader.squad.get_members())
	assert_array(members).override_failure_message("fixture: the squad did not form").has_size(3)
	return members


func _press_f(shift := false) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.shift_pressed = shift
	key.pressed = true
	game._input(key)


func _open(unit: Unit) -> void:
	game.open_unit_ring(unit, unit.movement.cell, Vector2i(640, 360))


func _open_rings() -> Array[ActionMenuController]:
	var out: Array[ActionMenuController] = []
	for child in game.get_children():
		if child is ActionMenuController and not child.is_queued_for_deletion():
			out.append(child as ActionMenuController)
	return out


func _focused_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	game.view_focus_requested.connect(func(cell: Vector2i) -> void: cells.append(cell))
	return cells


# --- cases ---------------------------------------------------------------------------------------

func test_f_selects_the_next_squadmate_with_its_ring_up_and_the_camera_on_it() -> void:
	var members := _squad_of_three(1)
	_open(members[0])
	var cells := _focused_cells()
	_press_f()
	assert_object(game.selected_unit).is_same(members[1])
	assert_int(game.game_state).override_failure_message(
		"the next squadmate is selected but its ring is not up").is_equal(game.GameState.TILE_SELECTED)
	assert_int(_open_rings().size()).override_failure_message(
		"the old ring was not closed, or the new one did not open").is_equal(1)
	assert_array(cells).override_failure_message(
		"the camera was not asked to look at the unit the cycle landed on").contains([members[1].movement.cell])


func test_the_cycle_wraps_both_ways() -> void:
	var members := _squad_of_three(1)
	_open(members[0])
	for i in 3:
		_press_f()
	assert_object(game.selected_unit).override_failure_message(
		"three presses in a squad of three did not come back round").is_same(members[0])
	_press_f(true)
	assert_object(game.selected_unit).override_failure_message(
		"Shift+F from the first member did not wrap to the last").is_same(members[2])


# The exact-match check: a Shift+F press also matches the plain-F binding unless the handler asks
# for an exact match, and then it would cycle FORWARD.
func test_shift_f_goes_back_and_never_forward() -> void:
	var members := _squad_of_three(1)
	_open(members[1])
	_press_f(true)
	assert_object(game.selected_unit).override_failure_message(
		"Shift+F did not go back one -- if it landed on the third, it fired plain F too").is_same(members[0])


func test_with_nobody_selected_f_starts_on_the_first_squad_that_can_act() -> void:
	var spent := _squad_of_three(1)
	var ready := _squad_of_three(2)
	game.squad_manager.set_has_acted(spent[0].squad, true)
	assert_object(game.selected_unit).is_null()
	_press_f()
	assert_object(game.selected_unit).override_failure_message(
		"with nothing selected, F did not start on the leader of the first squad still able to act"
	).is_same(ready[0].squad.leader)


func test_a_downed_member_is_skipped() -> void:
	var members := _squad_of_three(1)
	members[2].force_down()
	assert_bool(members[2].is_active()).override_failure_message("fixture: the unit is still up").is_false()
	_open(members[1])
	_press_f()
	assert_object(game.selected_unit).override_failure_message(
		"the cycle landed on a downed member").is_same(members[0])


# A half-made gesture belongs to the unit that started it: a move being planned, an aim, a pick.
func test_mid_aim_the_key_does_nothing() -> void:
	var members := _squad_of_three(1)
	_open(members[0])
	game.game_state = game.GameState.ATTACK_TARGETING
	_press_f()
	assert_object(game.selected_unit).is_same(members[0])
	assert_int(game.game_state).is_equal(game.GameState.ATTACK_TARGETING)


func test_a_locked_board_ignores_the_key() -> void:
	var members := _squad_of_three(1)
	_open(members[0])
	game.camera_controller.set_playback_locked(true)
	_press_f()
	game.camera_controller.set_playback_locked(false)
	assert_object(game.selected_unit).override_failure_message(
		"the cycle ran while playback owned the board").is_same(members[0])
