# Undo for the tile brush (#391): a mis-drag on a board you have been authoring for an hour used to
# be unrecoverable except by reloading and losing everything since the last save.
#
# Two things these cases exist to hold, and both are the reason the recorder does NOT live in
# BoardGrid the way the issue proposed. Since #340 one click writes the grid AND BoardHeights, and
# an erase additionally prunes that cell's tile states and its height (#245/#260) -- so a recorder
# on the grid alone would put a raised cell back flat, and put an erased cell back with its fire
# gone. The step is therefore a whole-board snapshot taken by the AUTHORING layer.
#
# A STEP IS A STROKE. Cases drive real InputEvents through DevController.handle_tile_brush rather
# than calling _paint, because the bracket is a routing fact: a press that never opens a stroke and
# a release that never closes one both leave every individual piece correct.
#
# The board cell is INJECTED (DevController.cell_source, the #231 seam) rather than hovered --
# _mouse_cell() cannot be steered headless, and a drag across three cells is the whole point of the
# first case. The cursor is an Array because a GDScript lambda captures locals by VALUE.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D
var _brush: TileBrushTool
var _dc: DevController
var _cursor: Array[Vector2i] = [Vector2i.ZERO]


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	# clear_board does NOT touch the grid, and game.tscn ships an authored board -- so without this
	# every "has ground?" assertion below would read the scene's own tiles and pass whatever the
	# undo did. Starting bare also puts the EMPTY board into the history's first slot, which is the
	# case BoardGrid.restore's clear() exists for.
	game.grid.reset()
	game.game_state = game.GameState.DEV_MODE
	_brush = game.dev_overlay.tile_brush
	_dc = game.dev_controller
	game.dev_overlay.show_leaf(_brush)   # the page owns the brush's input (2026-08-23)
	_brush.brush_active = true
	_brush._set_paint_mode(TileBrushTool.PaintMode.TERRAIN)
	_cursor = [Vector2i.ZERO]
	var cursor := _cursor
	_dc.cell_source = func() -> Vector2i: return cursor[0]


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# ---- helpers ----

func _at(cell: Vector2i) -> void:
	_cursor[0] = cell


func _press(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _key(code: Key, ctrl: bool, shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	return event


# One gesture: press on the first cell, drag through the rest, release.
func _stroke(button: MouseButton, cells: Array[Vector2i]) -> void:
	_at(cells[0])
	_dc.handle_tile_brush(_press(button, true))
	for i in range(1, cells.size()):
		_at(cells[i])
		_dc.handle_tile_brush(InputEventMouseMotion.new())
	_dc.handle_tile_brush(_press(button, false))


func _paint_stroke(cells: Array[Vector2i]) -> void:
	_stroke(MOUSE_BUTTON_LEFT, cells)


func _erase_stroke(cells: Array[Vector2i]) -> void:
	_stroke(MOUSE_BUTTON_RIGHT, cells)


func _has_ground(cell: Vector2i) -> bool:
	return GridUtils.has_ground(game.grid, cell)


# ---- a step is a STROKE, not a cell ----

func test_a_three_cell_drag_undoes_as_one_step() -> void:
	var cells: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
	_paint_stroke(cells)
	assert_bool(_has_ground(cells[2])).override_failure_message(
			"the drag did not paint -- the fixture is wrong, not the undo").is_true()

	_dc.undo_board()

	for cell: Vector2i in cells:
		assert_bool(_has_ground(cell)).override_failure_message(
				("%s survived the undo: the stroke was recorded per CELL, so one press took back "
				+ "only part of one drag") % cell).is_false()
	assert_bool(_dc.history.can_undo()).is_false()


func test_a_stroke_that_changed_nothing_records_no_step() -> void:
	var cells: Array[Vector2i] = [Vector2i(4, 4)]
	_paint_stroke(cells)
	var depth := _dc.history.depth()

	_paint_stroke(cells)   # same tile, same level, same cell

	# Also where BoardSnapshot.equals gets MEASURED rather than assumed: Godot's Dictionary
	# comparison semantics are the thing this leans on, and a reference compare would push here.
	assert_int(_dc.history.depth()).override_failure_message(
			"repainting a cell with what was already there pushed a step, so the first Ctrl+Z "
			+ "would appear to do nothing").is_equal(depth)


# ---- what a snapshot has to carry ----

func test_undo_restores_the_tile_AND_its_elevation() -> void:
	# The case a recorder inside BoardGrid fails: the grid half comes back and the height does not,
	# so an undone repaint drops the cell to the floor.
	var cell := Vector2i(2, 2)
	_brush.set_elevation(2)
	_paint_stroke([cell] as Array[Vector2i])
	_brush.set_elevation(6)
	_paint_stroke([cell] as Array[Vector2i])
	assert_int(game.board_heights.elevation_at(cell)).is_equal(6)

	_dc.undo_board()

	assert_int(game.board_heights.elevation_at(cell)).override_failure_message(
			"the tile came back at the wrong height -- the snapshot is missing BoardHeights"
			).is_equal(2)
	assert_bool(_has_ground(cell)).is_true()


func test_undo_of_an_erase_brings_back_the_states_the_erase_pruned() -> void:
	# Erasing a tile prunes that cell's states, because state goes with the ground (#245). Undo has
	# to put both back, and the state store is not something a grid-shaped recorder can see.
	var cell := Vector2i(3, 3)
	_paint_stroke([cell] as Array[Vector2i])
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BURNING] as Array[Terrain.TileState])
	game.terrain_states.apply(effect)   # deposited OUTSIDE a stroke, which begin() re-stamps

	_erase_stroke([cell] as Array[Vector2i])
	assert_bool(game.terrain_states.has_state(cell, Terrain.TileState.BURNING)).is_false()

	_dc.undo_board()

	assert_bool(_has_ground(cell)).is_true()
	assert_bool(game.terrain_states.has_state(cell, Terrain.TileState.BURNING)
			).override_failure_message(
			"the tile came back without the fire that was on it -- the snapshot is missing "
			+ "TerrainStateManager").is_true()


func test_a_zone_erased_to_nothing_comes_back_with_its_kind() -> void:
	# A zone whose last cell is erased is DELETED, so undo has to recreate it -- and its kind locks
	# at creation, so a resurrection that guessed PATROL would silently retype the objective.
	var cell := Vector2i(5, 5)
	_brush._set_paint_mode(TileBrushTool.PaintMode.ZONE)
	_brush._zone_name = "Alpha"
	_brush._zone_kind = ZoneManager.Kind.CAPTURE
	_paint_stroke([cell] as Array[Vector2i])
	_erase_stroke([cell] as Array[Vector2i])
	assert_array(game.zone_manager.zone_names()).is_empty()

	_dc.undo_board()

	assert_array(game.zone_manager.zone_names()).contains(["Alpha"])
	assert_int(game.zone_manager.kind_of("Alpha")).is_equal(ZoneManager.Kind.CAPTURE)
	assert_bool(game.zone_manager.contains("Alpha", cell)).is_true()


# ---- redo, and the tail a new edit abandons ----

func test_redo_reapplies_and_a_new_stroke_truncates_the_tail() -> void:
	var first := Vector2i(1, 6)
	var second := Vector2i(2, 6)
	_paint_stroke([first] as Array[Vector2i])
	_paint_stroke([second] as Array[Vector2i])

	_dc.undo_board()
	assert_bool(_has_ground(second)).is_false()
	_dc.redo_board()
	assert_bool(_has_ground(second)).override_failure_message(
			"redo did not put the stroke back").is_true()

	_dc.undo_board()
	_paint_stroke([Vector2i(3, 6)] as Array[Vector2i])
	assert_bool(_dc.history.can_redo()).override_failure_message(
			"a new edit left the redo tail in place -- redo would jump to a future this board is "
			+ "no longer in").is_false()


# ---- the board-wide acts are steps too ----

func test_a_resize_is_one_undo_step() -> void:
	var outside := Vector2i(7, 7)
	_paint_stroke([outside] as Array[Vector2i])

	_dc.resize_map(3, 3, _brush.selected_source, _brush.selected_tile)
	assert_bool(_has_ground(outside)).is_false()
	assert_bool(_has_ground(Vector2i(2, 2))).is_true()

	_dc.undo_board()

	assert_bool(_has_ground(outside)).override_failure_message(
			"the cell the shrink stranded did not come back -- resize is the most destructive "
			+ "thing in the panel and has to be one step").is_true()
	assert_bool(_has_ground(Vector2i(2, 2))).is_false()


func test_the_board_wide_state_wipe_is_one_undo_step() -> void:
	var cell := Vector2i(6, 2)
	_paint_stroke([cell] as Array[Vector2i])
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BURNING] as Array[Terrain.TileState])
	game.terrain_states.apply(effect)

	_dc.clear_tile_states()
	assert_bool(game.terrain_states.has_state(cell, Terrain.TileState.BURNING)).is_false()

	_dc.undo_board()

	assert_bool(game.terrain_states.has_state(cell, Terrain.TileState.BURNING)).is_true()


# ---- the history belongs to ONE board ----

func test_a_board_load_resets_the_history() -> void:
	_paint_stroke([Vector2i(1, 2)] as Array[Vector2i])
	assert_bool(_dc.history.can_undo()).is_true()

	var scenario: ScenarioData = game.scenario_manager.capture_scenario("undo-fixture")   # typed: game is untyped
	game.scenario_manager.apply_scenario(scenario)

	assert_bool(_dc.history.can_undo()).override_failure_message(
			"the stack outlived its board -- one more Ctrl+Z would paste the previous board's "
			+ "terrain onto this one").is_false()


# ---- the wire to the 3D mirror ----

func test_a_restore_marks_the_whole_board_dirty() -> void:
	# The mirror reconciles only what a writer announced (#319). A bulk restore has no cell list, so
	# ALL is the announcement -- and without it the 2D board is right while the diorama renders the
	# board you just undid, silently.
	_paint_stroke([Vector2i(8, 1)] as Array[Vector2i])
	game.grid.dirty.clear()

	_dc.undo_board()

	assert_bool(game.grid.dirty.all).override_failure_message(
			"the restore never announced itself: the 3D mirror keeps rendering the undone board"
			).is_true()


func test_capture_board_round_trips_through_restore_board() -> void:
	_brush.set_elevation(6)
	_paint_stroke([Vector2i(2, 8), Vector2i(3, 8)] as Array[Vector2i])
	var snapshot: BoardSnapshot = game.scenario_manager.capture_board()   # typed: game is untyped

	_erase_stroke([Vector2i(2, 8)] as Array[Vector2i])
	game.scenario_manager.restore_board(snapshot)

	assert_bool(game.scenario_manager.capture_board().equals(snapshot)).is_true()


# ---- the keys, and the two OS windows ----

func test_ctrl_z_undoes_from_the_dev_tools_window_too() -> void:
	# The project runs two real OS windows and a key reaches only the FOCUSED one. Authoring leaves
	# you in the dev window with a tile just picked, which is exactly where a mis-drag gets noticed
	# -- so this drives the OVERLAY's own arm, asserting the forward rather than assuming it.
	var cell := Vector2i(9, 9)
	_paint_stroke([cell] as Array[Vector2i])

	game.dev_overlay._input(_key(KEY_Z, true))

	assert_bool(_has_ground(cell)).override_failure_message(
			"Ctrl+Z pressed in the dev-tools window never reached the board").is_false()


func test_ctrl_shift_z_redoes_from_the_dev_tools_window_too() -> void:
	var cell := Vector2i(9, 8)
	_paint_stroke([cell] as Array[Vector2i])
	_dc.undo_board()

	game.dev_overlay._input(_key(KEY_Z, true, true))

	assert_bool(_has_ground(cell)).is_true()


func test_ctrl_z_does_not_also_turn_the_ramp_rise() -> void:
	# Bare Z already cycles the rise backwards. Both bindings live on the same key in the same
	# handler, so without a modifier guard one press would undo AND retune the brush.
	_brush.set_rise(Terrain.RampRise.NONE)

	_dc.handle_dev_key(_key(KEY_Z, true))

	assert_int(_brush.selected_rise()).override_failure_message(
			"Ctrl+Z turned the ramp rise as well as undoing").is_equal(Terrain.RampRise.NONE)


func test_the_undo_keys_are_inert_outside_dev_mode() -> void:
	# There is no authoring to take back outside dev mode, and rewinding the board mid-battle would
	# take whatever a played round deposited with it.
	var cell := Vector2i(4, 9)
	_paint_stroke([cell] as Array[Vector2i])
	game.game_state = game.GameState.IDLE

	_dc.handle_dev_key(_key(KEY_Z, true))

	assert_bool(_has_ground(cell)).is_true()


# ---- the panel's own row ----

func test_the_undo_row_greys_until_there_is_something_to_undo() -> void:
	assert_bool(_brush._undo_button.disabled).is_true()
	assert_bool(_brush._redo_button.disabled).is_true()

	_paint_stroke([Vector2i(5, 1)] as Array[Vector2i])

	# Pushed off history_changed, not polled: a button that only refreshed on the next _process
	# would read the previous edit's answer.
	assert_bool(_brush._undo_button.disabled).override_failure_message(
			"the panel never heard that a step was recorded").is_false()
	assert_bool(_brush._redo_button.disabled).is_true()

	_dc.undo_board()

	assert_bool(_brush._undo_button.disabled).is_true()
	assert_bool(_brush._redo_button.disabled).is_false()
