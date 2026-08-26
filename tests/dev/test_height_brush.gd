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
	# SHOW the page, then arm: the checkbox lives on the Tile Brush page and brush_armed() reads that
	# since 2026-08-23, so a fixture that only set the flag was arming a brush no human could.
	game.dev_overlay.show_leaf(_brush)
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
	# One notch is one UNIT -- half a level. It moved a whole level when #427 slice 2 landed, which
	# made a two-cell gentle slope unbuildable by wheel; the dev found it the first time he tried.
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


func test_the_wheel_moves_the_level_in_exactly_the_modes_that_show_it() -> void:
	# The rule, not a list of modes: a control only moves a brush you can SEE. Derived from the row's
	# own visibility and swept over EVERY mode, because a hand-written "the other modes" list is a
	# second answer that goes stale the moment a fifth mode lands -- which is exactly what #427 slice
	# 4's CORNER mode did to the pair of cases this replaced.
	for mode: TileBrushTool.PaintMode in TileBrushTool.PaintMode.values():
		_brush.set_elevation(0)
		_brush._set_paint_mode(mode)
		var expected := 1 if _brush._elevation_row.visible else 0
		_wheel(MOUSE_BUTTON_WHEEL_UP)
		assert_int(_brush.selected_elevation()).override_failure_message(
				"mode %d shows the level row: %s, but the wheel %s it"
				% [mode, _brush._elevation_row.visible, "moved" if expected == 0 else "ignored"]
				).is_equal(expected)


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


func test_the_rise_keys_turn_it_in_exactly_the_modes_that_show_it() -> void:
	# Its own sweep beside the wheel's, and the two answers genuinely differ since #427 slice 4:
	# CORNER mode picks a height and authors no cardinal shape, so it shows the level row and hides
	# the rise one. One predicate answering both would be right about neither.
	for mode: TileBrushTool.PaintMode in TileBrushTool.PaintMode.values():
		_brush.set_rise(NONE)
		_brush._set_paint_mode(mode)
		var expected: Terrain.RampRise = NORTH if _brush._rise_row.visible else NONE
		_dc._input(_key(KEY_C))
		assert_int(_brush.selected_rise()).override_failure_message(
				"mode %d shows the rise row: %s, but Z/C disagreed"
				% [mode, _brush._rise_row.visible]).is_equal(expected)


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

	assert_int(game.board_heights.elevation_at(cell)).is_equal(2)   # two notches = two units


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
	_brush.set_elevation(6)
	_brush._rise_option.item_selected.emit(TileBrushTool.RISE_CYCLE.find(WEST))

	_dc.handle_tile_brush(_press(MOUSE_BUTTON_LEFT, true))

	assert_int(game.board_heights.elevation_at(picked)).override_failure_message(
			"the 3D view's picked column took no elevation").is_equal(6)
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
	_brush.set_elevation(6)

	_dc.handle_tile_brush(_press(MOUSE_BUTTON_LEFT, true))

	assert_int(game.grid.get_cell_source_id(cell)).override_failure_message(
			"painting an empty cell left it empty").is_equal(_brush.selected_source)
	assert_int(game.board_heights.elevation_at(cell)).override_failure_message(
			"the height was refused on a cell this very click had just given ground").is_equal(6)


func test_erasing_the_ground_takes_the_elevation_with_it() -> void:
	var cell := _hover_cell()
	game.board_heights.set_cell(cell, 6, EAST)
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


# ---- only GROUND can slope (#340, widened by #342) ----

# Which tile is ground is ASKED of the tileset, never named by coords: authored content is not
# pinnable (the content razor), and prop_shape is the same fact the gate itself reads.
#
# It asked stands_up_of until #342 -- a DIFFERENT question, and a TUFT answers yes to both. Left
# alone, this helper would have started handing the "standing" case a tile the gate now ALLOWS, so
# whether the case below reddened would have come down to tileset ordering.
func _first_tile_where(matches: Callable) -> Vector2i:
	var source := game.grid.tile_set.get_source(_brush.selected_source) as TileSetAtlasSource
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		if source.get_tile_size_in_atlas(coords) != Vector2i.ONE:
			continue
		var hit: bool = matches.call(source.get_tile_data(coords, 0))   # .call() erases to Variant
		if hit:
			return coords
	return Vector2i(-1, -1)


func _find_tile(ground: bool) -> Vector2i:
	return _first_tile_where(func(data: TileData) -> bool:
			return GridUtils.is_ground_shape(data) == ground)


func _find_shape(shape: GridUtils.PropShape) -> Vector2i:
	return _first_tile_where(func(data: TileData) -> bool:
			return GridUtils.prop_shape_of(data) == shape)


func test_a_tile_that_stands_up_paints_flat_however_the_rise_is_set() -> void:
	# The dev's rule: "only tiles that are flat, not things like rocks, lanterns". A rock has no top
	# face to tilt. The GROUND half is the control -- without it this case also passes against a gate
	# that simply refused every rise.
	var prop := _find_tile(false)
	var ground := _find_tile(true)
	assert_bool(prop != Vector2i(-1, -1) and ground != Vector2i(-1, -1)).override_failure_message(
			"fixture: this source needs both a standing prop and a ground tile to tell them apart"
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


func test_a_TUFT_takes_a_rise_even_though_its_plants_stand_up() -> void:
	# #342. A flowery-grass tuft is walkable GROUND with plants growing out of it, and the corner
	# tool had been sloping one freely all along -- only the brush refused.
	var tuft := _find_shape(GridUtils.PropShape.TUFT)
	assert_bool(tuft != Vector2i(-1, -1)).override_failure_message(
			"fixture: this source has no TUFT tile, so this case checks nothing"
			).is_true()

	# The two questions really do disagree about this tile, which is what makes the case a test of
	# the WIDENING rather than of a tile that was already FLAT and would have passed before #342.
	var source := game.grid.tile_set.get_source(_brush.selected_source) as TileSetAtlasSource
	var data := source.get_tile_data(tuft, 0)
	assert_bool(GridUtils.stands_up_of(data)).override_failure_message(
			"fixture: a TUFT must read as STANDING, or this case is testing a flat tile"
			).is_true()

	var cell := _hover_cell()
	_brush._rise_option.item_selected.emit(TileBrushTool.RISE_CYCLE.find(NORTH))
	_brush.selected_tile = tuft
	_dc.handle_tile_brush(_press(MOUSE_BUTTON_LEFT, true))
	assert_int(game.board_heights.ramp_rise_at(cell)).override_failure_message(
			"a tuft was refused a rise, though it is ground with plants standing on it"
			).is_equal(NORTH)


# ---- the readout ----
#
# These wait on a FRAME rather than reading straight back, because the readout is DevController's
# per-frame derive off elevation_brush_live() and not a push from _set_paint_mode. That is the
# point: the mode is only half the predicate, and the half these cases used to miss is the brush
# being down -- see test_the_readout_goes_dark_when_the_brush_does.

# Two frames, not one: process_frame can fire either side of DevController._process inside a single
# idle frame, so one await races the poll it is waiting on.
func _polled() -> void:
	await await_idle_frame()
	await await_idle_frame()


func test_the_height_readout_lights_with_the_terrain_brush() -> void:
	var readout: HeightDebugOverlay = game.height_debug_overlay
	assert_object(readout).is_not_null()

	await _polled()
	assert_bool(readout.visible).is_true()   # before_test entered TERRAIN mode

	_brush._set_paint_mode(TileBrushTool.PaintMode.ZONE)

	await _polled()
	assert_bool(readout.visible).is_false()


func test_the_readout_goes_dark_when_the_brush_does() -> void:
	# The twin of test_the_rise_keys_are_inert_when_the_brush_is_down. That one pins that the KEYS go
	# inert with the brush down; this pins that the READOUT does. Both ask elevation_brush_live, and
	# that is the whole fix -- a mode compare of its own left the glyphs painted over a board whose
	# wheel and Z/C were already dead, until a paint-mode round trip happened to clear them.
	var readout: HeightDebugOverlay = game.height_debug_overlay

	await _polled()
	assert_bool(readout.visible).override_failure_message(
			"armed in TERRAIN, and the readout never lit").is_true()

	_brush.brush_active = false

	await _polled()
	assert_bool(readout.visible).override_failure_message(
			"the brush is down and the keys are inert, but the readout is still lit").is_false()


func test_an_f5_readout_survives_leaving_the_terrain_brush() -> void:
	# Visibility is DERIVED from both reasons, not assigned by either: a brush that switched off a
	# readout F5 asked for is the second-authority bug this shape exists to prevent. Load-bearing
	# against the poll too -- it runs every frame, so an assignment there would fight F5 forever.
	var readout: HeightDebugOverlay = game.height_debug_overlay
	readout.toggle()                                           # F5 on, on top of the brush's own
	_brush._set_paint_mode(TileBrushTool.PaintMode.ZONE)

	await _polled()

	assert_bool(readout.visible).is_true()


# ---- X cycles the steepness ----
#
# Slice 2's case, written late: RISE_CYCLE is covered nine ways above and CLIMB_CYCLE had no case at
# all, so the key shipped on the same handler as its tested neighbours with nothing watching it.
# (The hover selector's own V key is NOT here -- it needs no armed brush and no dev mode, so it lives
# with the 3D scene in tests/dev/test_game_knobs.gd.)

func test_x_alternates_the_two_steepnesses() -> void:
	assert_int(_brush.selected_climb()).is_equal(Terrain.UNITS_PER_LEVEL)
	_dc._input(_key(KEY_X))
	assert_int(_brush.selected_climb()).override_failure_message(
			"X did not reach the brush's steepness").is_equal(1)
	_dc._input(_key(KEY_X))
	assert_int(_brush.selected_climb()).override_failure_message(
			"the steepness cycle did not wrap home").is_equal(Terrain.UNITS_PER_LEVEL)


# ---- the dev keys reach the brush from EITHER OS window (#340 follow-up) ----

func test_the_rise_keys_work_from_the_dev_tools_window_too() -> void:
	# Found in play. The project runs two real OS windows and a key reaches only the FOCUSED one;
	# DevController lives in the GAME subtree, so Z/C were dead exactly where authoring puts you --
	# in the dev-tools window, having just picked a tile. The dev: "maybe the 5th time this issue
	# has bit us". This drives the overlay's own arm, so the FORWARD is asserted, not assumed.
	game.dev_overlay._input(_key(KEY_C))

	assert_int(_brush.selected_rise()).override_failure_message(
			"a dev key pressed in the dev-tools window never reached the brush").is_equal(NORTH)

	# Not just the key that found the bug: the window forwards ALL of them or none, so a case naming
	# only C would go on passing while a later key rode a route that never existed.
	game.dev_overlay._input(_key(KEY_X))
	assert_int(_brush.selected_climb()).override_failure_message(
			"X pressed in the dev-tools window never reached the brush").is_equal(1)


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

	assert_int(_brush.selected_elevation()).is_equal(1)   # one notch = one unit


func test_the_games_input_arm_ignores_the_wheel_when_the_brush_is_down() -> void:
	_brush.brush_active = false

	game._unhandled_input(_press(MOUSE_BUTTON_WHEEL_UP, true))

	assert_int(_brush.selected_elevation()).is_equal(0)
