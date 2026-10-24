# Both OS windows reach the dev keys through ONE entry, DevController.handle_dev_key (#1446), and each
# hands over its own viewport so the entry can ask what only a window knows: is someone typing there,
# and where to spend a key that must reach nothing else.
#
# Every press is PUSHED into its window (Viewport.push_input), never handed to _input, because the bug
# lived in Godot's order: _input runs BEFORE the GUI, so a focused text field shields nothing unless the
# entry asks. A direct _input call skips the GUI pass, so it could not see Space's other half either: a
# focused Button taking the press as ui_accept.
#
# "The game window" is the GameView SubViewport, the viewport DevController hears; its container
# forwards a key there from the root window.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const TARGET := Vector2i(3, 0)

var _scene: Node3D
var game: Node2D
var _overlay: DevOverlay


func before_test() -> void:
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	game = _scene.get_node("Main/GameContainer/GameView/Game")
	_overlay = _scene.get_node("Main/DevOverlay") as DevOverlay
	_overlay.show()
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func _game_window() -> Viewport:
	return game.get_viewport()


# A press AND its release, the way a keyboard sends them, with the text a plain press types.
func _press(window: Viewport, code: Key, shift := false) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = code
		key.physical_keycode = code
		key.shift_pressed = shift
		if code >= KEY_A and code <= KEY_Z:
			key.unicode = code + 32
		elif code == KEY_SPACE:
			key.unicode = 32
		key.pressed = pressed
		window.push_input(key)


func _selector_depth() -> BoardOverlays.SelectorDepth:
	return (_scene.get_node("BoardOverlays") as BoardOverlays).selector_depth


func _focus_a_field(parent: Node, window: Viewport) -> LineEdit:
	var field := LineEdit.new()
	parent.add_child(field)
	field.grab_focus()
	await await_idle_frame()
	assert_object(window.gui_get_focus_owner()).override_failure_message(
			"fixture: the field never took focus, so the guard case would pass vacuously").is_same(field)
	return field


# H is the selector depth: a dev key live in ordinary play, so nothing else has to be armed for it.
func _assert_the_field_holds_the_keys(parent: Node, window: Viewport, which: String) -> void:
	var field: LineEdit = await _focus_a_field(parent, window)
	var before := _selector_depth()

	_press(window, KEY_H)

	assert_int(_selector_depth()).override_failure_message(
			"typing H in a %s text field moved the selector depth" % which).is_equal(before)
	# The guard's twin, so the case cannot pass because the press never arrived at all.
	field.release_focus()
	_press(window, KEY_H)
	assert_int(_selector_depth()).override_failure_message(
			"H pressed in the %s with no field focused never reached the selector" % which) \
		.is_not_equal(before)
	field.free()


func test_typing_in_a_game_window_field_fires_no_dev_key() -> void:
	await _assert_the_field_holds_the_keys(game, _game_window(), "game window")


func test_typing_in_a_dev_window_field_fires_no_dev_key() -> void:
	await _assert_the_field_holds_the_keys(_overlay, _overlay, "dev-tools window")


# --- F4, F5 and Space reach the game from the dev window ----------------------------------------

func test_f4_swaps_the_view_from_either_window() -> void:
	for window: Viewport in [_overlay as Viewport, _game_window()]:
		_press(window, KEY_F4)
		assert_int(_scene.view).override_failure_message(
				"F4 in %s did not swap to the flat 2D game" % window.name).is_equal(_scene.View.FLAT_2D)
		_press(window, KEY_F4)
		assert_int(_scene.view).override_failure_message(
				"F4 in %s did not swap back" % window.name).is_equal(_scene.View.HD_2D)
		_press(window, KEY_F4, true)
		assert_int(_scene.view).override_failure_message(
				"Shift+F4 in %s did not open the corner view" % window.name).is_equal(_scene.View.CORNER)
		_press(window, KEY_F4, true)
		assert_int(_scene.view).override_failure_message(
				"Shift+F4 in %s did not close the corner view" % window.name).is_equal(_scene.View.HD_2D)


func test_f5_toggles_the_readout_from_the_dev_window_with_a_card_up() -> void:
	var readout: HeightDebugOverlay = game.height_debug_overlay
	assert_object(readout).override_failure_message("fixture: no readout in this build").is_not_null()
	_press(_overlay, KEY_F5)
	assert_bool(readout.visible).override_failure_message(
			"F5 lit the readout in the 3D view, where the flat board it draws on is hidden").is_false()

	_press(_overlay, KEY_F4)
	# A readout edits nothing, so it sits above ModalLock like F4 (#1446's ruling).
	var card := Control.new()
	game.add_child(card)
	ModalLock.claim(card, game)
	_press(_overlay, KEY_F5)
	assert_bool(readout.visible).override_failure_message(
			"F5 in the dev-tools window did not light the readout over the flat board").is_true()
	_press(_overlay, KEY_F5)
	assert_bool(readout.visible).override_failure_message(
			"a second F5 did not put the readout out").is_false()
	card.free()


# The Spawn page armed, a board to spawn on, and the cell the pointer is over. cell_source is the
# 3D host's own injection seam, so this aims the press without a mouse.
func _arm_the_spawn() -> void:
	game.scenario_manager.clear_board()
	for x in range(6):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	game.set_dev_mode(true)
	_overlay.show_leaf(_overlay.spawn)
	game.dev_controller.cell_source = func() -> Vector2i: return TARGET
	await await_idle_frame()
	assert_bool(game.dev_controller.spawn_armed()).override_failure_message(
			"fixture: the Spawn page is up but the gate is not armed").is_true()


func test_space_spawns_from_the_dev_window_and_clicks_nothing_there() -> void:
	await _arm_the_spawn()
	# The focus a click on the page leaves behind, which Space used to press instead of spawning.
	var button := Button.new()
	_overlay.add_child(button)
	button.grab_focus()
	await await_idle_frame()
	assert_object(_overlay.gui_get_focus_owner()).override_failure_message(
			"fixture: the button never took focus").is_same(button)
	var clicks := [0]
	button.pressed.connect(func() -> void: clicks[0] += 1)

	_press(_overlay, KEY_SPACE)

	assert_object(game.get_unit_at_cell(TARGET)).override_failure_message(
			"SPACE in the dev-tools window spawned nothing at %s" % TARGET).is_not_null()
	assert_int(clicks[0]).override_failure_message(
			"one SPACE spawned AND clicked the dev window's focused button").is_equal(0)
	button.free()


func test_space_spawns_from_the_game_window() -> void:
	await _arm_the_spawn()
	_press(_game_window(), KEY_SPACE)
	assert_object(game.get_unit_at_cell(TARGET)).override_failure_message(
			"SPACE in the game window spawned nothing at %s" % TARGET).is_not_null()


# The gate the hosts' freeze used to give for free: a spawn is a board edit, and a card is up.
func test_space_spawns_nothing_under_a_card() -> void:
	await _arm_the_spawn()
	var card := Control.new()
	game.add_child(card)
	ModalLock.claim(card, game)

	_press(_overlay, KEY_SPACE)
	_press(_game_window(), KEY_SPACE)

	assert_object(game.get_unit_at_cell(TARGET)).override_failure_message(
			"SPACE spawned a unit behind a card").is_null()
	card.free()
