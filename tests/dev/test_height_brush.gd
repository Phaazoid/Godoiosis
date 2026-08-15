# The Tile Brush ELEVATION mode (#260): the scroll wheel sets the level the brush places at, a
# button resets it to flat, and one click writes both the level and the ramp rise.
#
# Cases drive real InputEvents through DevController.handle_tile_brush -- and one drives
# game._unhandled_input -- because the ROUTING is what a controller-level test cannot see: a wheel
# notch that never reaches the brush, or one that lands in the drag flags and ends a stroke, both
# leave every individual piece correct. The board cell is the fixed headless hover cell, since
# _mouse_cell() cannot be steered without a real window.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const NONE := Terrain.RampRise.NONE
const NORTH := Terrain.RampRise.NORTH
const EAST := Terrain.RampRise.EAST
const WEST := Terrain.RampRise.WEST

var _main: Node
var game: Node2D
var _brush: TileBrushTool
var _dc: DevController


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.DEV_MODE
	_brush = game.dev_overlay.tile_brush
	_dc = game.dev_controller
	_brush.brush_active = true
	_brush._set_paint_mode(TileBrushTool.PaintMode.ELEVATION)
	# Elevation refuses a groundless cell, so the hover cell has to have a tile under it.
	_give_ground(_hover_cell())


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _hover_cell() -> Vector2i:
	return _dc._mouse_cell()


func _give_ground(cell: Vector2i) -> void:
	game.grid.set_cell(cell, _brush.selected_source, _brush.selected_tile)


func _press(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


# A notch is a press AND a release, the way Godot emits it.
func _wheel(button: MouseButton) -> void:
	_dc.handle_tile_brush(_press(button, true))
	_dc.handle_tile_brush(_press(button, false))


func _motion() -> InputEventMouseMotion:
	return InputEventMouseMotion.new()


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


# ---- the wheel sets the level ----

func test_the_wheel_moves_the_brush_level_both_ways() -> void:
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	assert_int(_brush.selected_elevation()).is_equal(2)

	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	# NEGATIVE is reachable on purpose (dev, 2026-08-15): authoring a dip must not require lifting
	# the whole map. A clamp at 0 goes red here.
	assert_int(_brush.selected_elevation()).is_equal(-1)


func test_the_wheel_writes_through_the_spinbox_too() -> void:
	# One writer: the widget and the value the brush paints with cannot drift.
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	assert_int(int(_brush._elevation_spin.value)).is_equal(1)


func test_the_wheel_is_inert_in_the_other_paint_modes() -> void:
	_brush._set_paint_mode(TileBrushTool.PaintMode.TERRAIN)
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	assert_int(_brush.selected_elevation()).is_equal(0)


func test_reset_returns_the_brush_to_flat_ground() -> void:
	_brush.set_elevation(4)
	_brush._rise_option.item_selected.emit(TileBrushTool.RISE_CYCLE.find(EAST))
	assert_int(_brush.selected_rise()).is_equal(EAST)

	_brush.reset_elevation()

	assert_int(_brush.selected_elevation()).is_equal(0)
	assert_int(_brush.selected_rise()).is_equal(NONE)


# ---- Z / C turn the rise ----

func test_z_and_c_turn_the_rise_like_a_compass() -> void:
	# Turning must READ as turning, which enum order (N, S, E, W) does not: C from North lands East.
	_dc._input(_key(KEY_C))
	assert_int(_brush.selected_rise()).is_equal(NORTH)
	_dc._input(_key(KEY_C))
	assert_int(_brush.selected_rise()).is_equal(EAST)

	_dc._input(_key(KEY_Z))
	assert_int(_brush.selected_rise()).is_equal(NORTH)
	_dc._input(_key(KEY_Z))
	assert_int(_brush.selected_rise()).is_equal(NONE)


func test_the_cycle_wraps_so_the_keys_alone_reach_every_value() -> void:
	# Z from flat wraps backwards to the last direction; a full C lap comes home to flat. Without
	# the wrap the keys would strand the brush at an end and force the menu trip back.
	_dc._input(_key(KEY_Z))
	assert_int(_brush.selected_rise()).is_equal(WEST)

	for i in TileBrushTool.RISE_CYCLE.size():
		_dc._input(_key(KEY_C))
	assert_int(_brush.selected_rise()).is_equal(WEST)


func test_turning_moves_the_picker_too() -> void:
	# One writer: the dropdown must always show what the next click will paint.
	_dc._input(_key(KEY_C))
	assert_int(TileBrushTool.RISE_CYCLE[_brush._rise_option.selected]).is_equal(NORTH)


func test_a_held_key_does_not_spin_the_rise() -> void:
	var repeat := _key(KEY_C)
	repeat.echo = true

	_dc._input(repeat)

	assert_int(_brush.selected_rise()).is_equal(NONE)


func test_the_rise_keys_are_inert_outside_elevation_mode() -> void:
	_brush._set_paint_mode(TileBrushTool.PaintMode.TERRAIN)
	_dc._input(_key(KEY_C))
	assert_int(_brush.selected_rise()).is_equal(NONE)


func test_the_rise_keys_are_inert_when_the_brush_is_down() -> void:
	_brush.brush_active = false
	_dc._input(_key(KEY_C))
	assert_int(_brush.selected_rise()).is_equal(NONE)


func test_every_rise_direction_is_reachable_from_the_picker() -> void:
	# The cycle list is hand-declared (compass order), so a new Terrain.RampRise member would
	# silently miss the picker AND the keys. This is the pin that refuses that.
	assert_int(TileBrushTool.RISE_CYCLE.size()).is_equal(Terrain.RampRise.size())
	for i in Terrain.RampRise.size():
		var rise: Terrain.RampRise = Terrain.RampRise.values()[i]
		assert_bool(TileBrushTool.RISE_CYCLE.has(rise)).is_true()


# ---- painting ----

func test_painting_writes_the_level_and_the_rise_together() -> void:
	var cell := _hover_cell()
	_brush.set_elevation(2)
	_brush._rise_option.item_selected.emit(TileBrushTool.RISE_CYCLE.find(NORTH))

	_dc.handle_tile_brush(_press(MOUSE_BUTTON_LEFT, true))

	assert_int(game.board_heights.elevation_at(cell)).is_equal(2)
	assert_int(game.board_heights.ramp_rise_at(cell)).is_equal(NORTH)


func test_a_wheel_notch_mid_drag_does_not_end_the_drag() -> void:
	# The ordering case: the wheel is read before the drag flags and returns, so scrolling to a new
	# level part way through a stroke keeps painting -- at the NEW level.
	var cell := _hover_cell()
	_dc.handle_tile_brush(_press(MOUSE_BUTTON_LEFT, true))
	assert_int(game.board_heights.elevation_at(cell)).is_equal(0)

	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_dc.handle_tile_brush(_motion())

	assert_int(game.board_heights.elevation_at(cell)).is_equal(2)


func test_erase_returns_the_cell_to_flat() -> void:
	var cell := _hover_cell()
	game.board_heights.set_cell(cell, 3, EAST)

	_dc.handle_tile_brush(_press(MOUSE_BUTTON_RIGHT, true))

	assert_int(game.board_heights.elevation_at(cell)).is_equal(0)
	assert_int(game.board_heights.ramp_rise_at(cell)).is_equal(NONE)


# ---- elevation goes with the ground (#245's rule, #260's store) ----

func test_a_groundless_cell_takes_no_elevation() -> void:
	var cell := Vector2i(80, 80)
	game.grid.erase_cell(cell)
	_brush.set_elevation(3)

	_dc._paint_elevation(cell)

	assert_int(game.board_heights.elevation_at(cell)).is_equal(0)


func test_erasing_the_ground_takes_the_elevation_with_it() -> void:
	var cell := _hover_cell()
	game.board_heights.set_cell(cell, 3, EAST)
	_brush._set_paint_mode(TileBrushTool.PaintMode.TERRAIN)

	_dc.handle_tile_brush(_press(MOUSE_BUTTON_RIGHT, true))   # the real terrain erase

	assert_int(game.board_heights.elevation_at(cell)).is_equal(0)
	assert_int(game.board_heights.ramp_rise_at(cell)).is_equal(NONE)


func test_shrinking_the_map_prunes_stranded_elevation() -> void:
	var inside := Vector2i(1, 1)
	var outside := Vector2i(15, 10)
	game.board_heights.set_cell(inside, 2, NONE)
	game.board_heights.set_cell(outside, 4, EAST)

	_dc.resize_map(5, 5, _brush.selected_source, _brush.selected_tile)

	assert_int(game.board_heights.elevation_at(outside)).is_equal(0)
	assert_int(game.board_heights.ramp_rise_at(outside)).is_equal(NONE)
	assert_int(game.board_heights.elevation_at(inside)).is_equal(2)   # still has ground


# ---- the readout ----

func test_the_height_readout_lights_with_the_elevation_brush() -> void:
	var readout: HeightDebugOverlay = game.height_debug_overlay
	assert_object(readout).is_not_null()
	assert_bool(readout.visible).is_true()   # before_test entered ELEVATION mode

	_brush._set_paint_mode(TileBrushTool.PaintMode.TERRAIN)
	assert_bool(readout.visible).is_false()


func test_an_f5_readout_survives_leaving_elevation_mode() -> void:
	# Visibility is DERIVED from both reasons, not assigned by either: a brush that switched off a
	# readout F5 asked for is the second-authority bug this shape exists to prevent.
	var readout: HeightDebugOverlay = game.height_debug_overlay
	readout.toggle()                                           # F5 on, on top of the brush's own
	_brush._set_paint_mode(TileBrushTool.PaintMode.TERRAIN)

	assert_bool(readout.visible).is_true()


# ---- the wire ----

func test_a_wheel_notch_reaches_the_brush_through_the_games_own_input() -> void:
	# handle_tile_brush being right is worth nothing if nothing calls it. This drives game.gd's
	# actual arm, so the DEV_MODE + brush-armed gate and the forwarding path are asserted, not
	# assumed -- a wheel event is an InputEventMouseButton and must ride the same branch a click does.
	game._unhandled_input(_press(MOUSE_BUTTON_WHEEL_UP, true))

	assert_int(_brush.selected_elevation()).is_equal(1)


func test_the_games_input_arm_ignores_the_wheel_when_the_brush_is_down() -> void:
	_brush.brush_active = false

	game._unhandled_input(_press(MOUSE_BUTTON_WHEEL_UP, true))

	assert_int(_brush.selected_elevation()).is_equal(0)
