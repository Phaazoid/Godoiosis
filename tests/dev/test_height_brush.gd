# The Tile Brush's LEVEL and RISE (#260, merged into the terrain brush by #340): the scroll wheel
# sets the level the brush places at, Z/C turn the rise, a button resets both to flat, and one click
# writes the tile, the level and the rise together.
#
# These used to pin a mode of their own, so several cases here read "inert in the other modes" with
# TERRAIN as the example of an other mode. TERRAIN is now the mode that OWNS the level, so those
# cases were re-aimed at ZONE/STATE rather than deleted -- the rule they guard (a key that retunes a
# brush you cannot see is worse than a dead key) is unchanged, only which modes can see it.
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
	_brush._set_paint_mode(TileBrushTool.PaintMode.TERRAIN)
	# Most cases here read a height back off a cell that already exists, so the hover cell starts
	# with ground. Painting one no longer REQUIRES it -- a paint creates the ground it raises.
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
	# Both of them, not one: the level rows are hidden in each, so a notch that moved the level there
	# would retune a brush the dev cannot see.
	for mode in [TileBrushTool.PaintMode.ZONE, TileBrushTool.PaintMode.STATE]:
		_brush.set_elevation(0)
		_brush._set_paint_mode(mode)
		_wheel(MOUSE_BUTTON_WHEEL_UP)
		assert_int(_brush.selected_elevation()).override_failure_message(
				"the wheel moved the level in mode %d, where the level row is hidden" % mode
				).is_equal(0)


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


func test_the_rise_keys_are_inert_outside_the_terrain_brush() -> void:
	for mode in [TileBrushTool.PaintMode.ZONE, TileBrushTool.PaintMode.STATE]:
		_brush.set_rise(NONE)
		_brush._set_paint_mode(mode)
		_dc._input(_key(KEY_C))
		assert_int(_brush.selected_rise()).override_failure_message(
				"Z/C turned the rise in mode %d, where the rise row is hidden" % mode
				).is_equal(NONE)


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

func test_painting_writes_the_tile_the_level_and_the_rise_together() -> void:
	# The whole point of #340: ONE click, all three. The tile assertion is the half that reds if the
	# height write is bolted onto a path that stopped painting, and the height half reds if the merge
	# only moved the UI rows.
	var cell := _hover_cell()
	game.grid.erase_cell(cell)
	_brush.set_elevation(2)
	_brush._rise_option.item_selected.emit(TileBrushTool.RISE_CYCLE.find(NORTH))

	_dc.handle_tile_brush(_press(MOUSE_BUTTON_LEFT, true))

	assert_int(game.grid.get_cell_source_id(cell)).override_failure_message(
			"the merged brush stopped painting the tile").is_equal(_brush.selected_source)
	assert_int(game.board_heights.elevation_at(cell)).override_failure_message(
			"the tile landed but its level did not").is_equal(2)
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


# NB there is no separate "erase returns the cell to flat" case any more. Erase has ONE meaning in
# the merged brush -- take the tile away, and the height goes with it (#245's rule) -- which is
# exactly what test_erasing_the_ground_takes_the_elevation_with_it below drives.


# ---- painting from the 3D view (#285) ----
#
# The 3D host paints by INJECTING the picked column as cell_source (#231); handle_tile_brush is
# routed on brush_armed() alone and _paint() is not mode-aware, so elevation should already land on
# the picked cell. These two pin that, because the ghost work built on top of it assumes it.

func test_the_injected_cell_is_where_elevation_lands() -> void:
	var picked := Vector2i(12, 9)
	var by_mouse := _hover_cell()
	assert_that(picked).override_failure_message(
			"fixture broken: the picked cell must differ from the headless hover cell"
			).is_not_equal(by_mouse)
	_give_ground(picked)
	_dc.cell_source = func() -> Vector2i: return picked
	_brush.set_elevation(3)
	_brush._rise_option.item_selected.emit(TileBrushTool.RISE_CYCLE.find(WEST))

	_dc.handle_tile_brush(_press(MOUSE_BUTTON_LEFT, true))

	assert_int(game.board_heights.elevation_at(picked)).override_failure_message(
			"the 3D view's picked column took no elevation").is_equal(3)
	assert_int(game.board_heights.ramp_rise_at(picked)).is_equal(WEST)
	assert_int(game.board_heights.elevation_at(by_mouse)).override_failure_message(
			"painted the raw mouse cell instead of the picked column").is_equal(0)


func test_the_injected_cell_is_where_erase_lands() -> void:
	var picked := Vector2i(12, 9)
	_give_ground(picked)
	game.board_heights.set_cell(picked, 4, EAST)
	_dc.cell_source = func() -> Vector2i: return picked

	_dc.handle_tile_brush(_press(MOUSE_BUTTON_RIGHT, true))

	assert_int(game.board_heights.elevation_at(picked)).is_equal(0)
	assert_int(game.board_heights.ramp_rise_at(picked)).is_equal(NONE)


# ---- elevation goes with the ground (#245's rule, #260's store) ----

func test_painting_an_empty_cell_gives_it_ground_AND_the_brushs_level() -> void:
	# The REVERSAL #340 makes: a height write used to be refused on a groundless cell, because the
	# elevation brush could not create ground. The merged brush paints the tile first, so the guard
	# is answered by ORDERING rather than by a refusal -- and raising virgin board is now one click.
	var cell := Vector2i(80, 80)
	game.grid.erase_cell(cell)
	_dc.cell_source = func() -> Vector2i: return cell
	_brush.set_elevation(3)

	_dc.handle_tile_brush(_press(MOUSE_BUTTON_LEFT, true))

	assert_int(game.grid.get_cell_source_id(cell)).override_failure_message(
			"painting an empty cell left it empty").is_equal(_brush.selected_source)
	assert_int(game.board_heights.elevation_at(cell)).override_failure_message(
			"the height was refused on a cell this very click had just given ground").is_equal(3)


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


# ---- only flat ground can slope (#340) ----

# Which tile stands up is ASKED of the tileset, never named by coords: authored content is not
# pinnable (the content razor), and prop_shape is the same fact the gate itself reads.
func _find_tile(standing: bool) -> Vector2i:
	var source := game.grid.tile_set.get_source(_brush.selected_source) as TileSetAtlasSource
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		if source.get_tile_size_in_atlas(coords) != Vector2i.ONE:
			continue
		if GridUtils.stands_up_of(source.get_tile_data(coords, 0)) == standing:
			return coords
	return Vector2i(-1, -1)


func test_a_tile_that_stands_up_paints_flat_however_the_rise_is_set() -> void:
	# The dev's rule: "only tiles that are flat, not things like rocks, lanterns". A rock has no top
	# face to tilt. The FLAT half is the control -- without it this case also passes against a gate
	# that simply refused every rise.
	var prop := _find_tile(true)
	var ground := _find_tile(false)
	assert_bool(prop != Vector2i(-1, -1) and ground != Vector2i(-1, -1)).override_failure_message(
			"fixture: this source needs both a standing and a flat tile to tell the two apart"
			).is_true()
	var cell := _hover_cell()
	_brush._rise_option.item_selected.emit(TileBrushTool.RISE_CYCLE.find(NORTH))

	_brush.selected_tile = prop
	_dc.handle_tile_brush(_press(MOUSE_BUTTON_LEFT, true))
	assert_int(game.board_heights.ramp_rise_at(cell)).override_failure_message(
			"a tile that stands up was painted as a ramp").is_equal(NONE)

	_brush.selected_tile = ground
	_dc.handle_tile_brush(_press(MOUSE_BUTTON_LEFT, true))
	assert_int(game.board_heights.ramp_rise_at(cell)).override_failure_message(
			"the gate refused a rise to flat ground too, so it is not a gate").is_equal(NORTH)


# ---- the readout ----

func test_the_height_readout_lights_with_the_terrain_brush() -> void:
	var readout: HeightDebugOverlay = game.height_debug_overlay
	assert_object(readout).is_not_null()
	assert_bool(readout.visible).is_true()   # before_test entered TERRAIN mode

	_brush._set_paint_mode(TileBrushTool.PaintMode.ZONE)
	assert_bool(readout.visible).is_false()


func test_an_f5_readout_survives_leaving_the_terrain_brush() -> void:
	# Visibility is DERIVED from both reasons, not assigned by either: a brush that switched off a
	# readout F5 asked for is the second-authority bug this shape exists to prevent.
	var readout: HeightDebugOverlay = game.height_debug_overlay
	readout.toggle()                                           # F5 on, on top of the brush's own
	_brush._set_paint_mode(TileBrushTool.PaintMode.ZONE)

	assert_bool(readout.visible).is_true()


# ---- the dev keys reach the brush from EITHER OS window (#340 follow-up) ----

func test_the_rise_keys_work_from_the_dev_tools_window_too() -> void:
	# Found in play. The project runs two real OS windows and a key reaches only the FOCUSED one;
	# DevController lives in the GAME subtree, so Z/C were dead exactly where authoring puts you --
	# in the dev-tools window, having just picked a tile. The dev: "maybe the 5th time this issue
	# has bit us". This drives the overlay's own arm, so the FORWARD is asserted, not assumed.
	game.dev_overlay._input(_key(KEY_C))

	assert_int(_brush.selected_rise()).override_failure_message(
			"a dev key pressed in the dev-tools window never reached the brush").is_equal(NORTH)


func test_typing_in_a_dev_field_does_not_fire_the_dev_keys() -> void:
	# The cost of forwarding: a name field in the dev window would otherwise reset the board every
	# time you typed an 'r'. Godot consumes a focused LineEdit's keys before _input in most paths,
	# but not all, so the guard is explicit.
	var field := LineEdit.new()
	game.dev_overlay.add_child(field)
	field.grab_focus()
	await await_idle_frame()

	game.dev_overlay._input(_key(KEY_C))

	assert_int(_brush.selected_rise()).override_failure_message(
			"typing in a dev-tools text field turned the ramp rise").is_equal(NONE)
	field.free()


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
