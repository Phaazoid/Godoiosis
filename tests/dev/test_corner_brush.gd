# The corner-drag tool (#427 slice 4): the Tile Brush's fourth mode, which moves the POINT four cells
# share instead of painting a whole tile.
#
# Cases drive real InputEvents through DevController.handle_tile_brush, because the ROUTING is what a
# store-level test cannot see: the paint dispatch is a match statement, and a mode with no arm paints
# nothing at all while every piece under it stays correct. The vocabulary and the clamp are pinned
# where they are cheapest, in tests/terrain/test_corner_drag.gd; this is the wire.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const LEVEL := Terrain.UNITS_PER_LEVEL
const NW := Terrain.CORNER_NW

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
	game.dev_overlay.show_leaf(_brush)
	_brush.brush_active = true
	_brush._set_paint_mode(TileBrushTool.PaintMode.CORNER)
	# A corner drag never creates ground -- it moves a point on ground that is already there -- so
	# the fixture paints the four cells the hover vertex touches.
	for offset: Vector2i in Terrain.VERTEX_CORNERS:
		_give_ground(_vertex() + offset)


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _vertex() -> Vector2i:
	return _dc._mouse_vertex()


func _give_ground(cell: Vector2i) -> void:
	game.grid.set_cell(cell, _brush.selected_source, _brush.selected_tile)


func _press(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _stroke(button: MouseButton) -> void:
	_dc.handle_tile_brush(_press(button, true))
	_dc.handle_tile_brush(_press(button, false))


func _corner(cell: Vector2i, bit: int) -> int:
	return Terrain.corner_height(game.board_heights.corners_at(cell), bit)


# --- the wire ------------------------------------------------------------------------

func test_a_click_in_corner_mode_moves_the_point_and_not_the_tile() -> void:
	# The arm exists at all. A missing one is silent: the match simply falls through and the whole
	# mode does nothing, which no store-level case can see.
	_brush.set_elevation(LEVEL)
	_stroke(MOUSE_BUTTON_LEFT)
	assert_int(_corner(_vertex(), NW)).override_failure_message(
			"the CORNER arm of _paint() never reached the store").is_equal(LEVEL)


func test_it_welds_all_four_cells_rather_than_painting_one() -> void:
	# The difference from the cell brush, at the surface the dev actually uses: one click, four
	# tiles, and the tile art untouched in every one of them.
	_brush.set_elevation(1)
	_stroke(MOUSE_BUTTON_LEFT)
	var vertex := _vertex()
	for offset: Vector2i in Terrain.VERTEX_CORNERS:
		var cell := vertex + offset
		assert_int(_corner(cell, Terrain.VERTEX_CORNERS[offset])).override_failure_message(
				"cell %s did not follow the point" % cell).is_equal(1)


func test_a_corner_click_leaves_the_tile_art_alone() -> void:
	# It is a height tool, not a paint one: nothing about which tile is where may move.
	var grid: TileMapLayer = game.grid
	var vertex := _vertex()
	var before: Vector2i = grid.get_cell_atlas_coords(vertex)
	_brush.set_elevation(LEVEL)
	_stroke(MOUSE_BUTTON_LEFT)
	assert_object(grid.get_cell_atlas_coords(vertex)).is_equal(before)


func test_a_point_with_no_ground_under_it_is_left_unwritten() -> void:
	# Height goes with the ground (#245). Erasing one of the four and dragging must not put a height
	# back into the cell that lost its tile.
	var vertex := _vertex()
	var bare := vertex + Vector2i(-1, -1)
	game.grid.erase(bare)
	_brush.set_elevation(1)
	_stroke(MOUSE_BUTTON_LEFT)
	assert_int(_corner(vertex, NW)).is_equal(1)
	assert_object(game.board_heights.corners_at(bare)).override_failure_message(
			"a groundless cell was given a height").is_equal(Vector4i.ZERO)


func test_right_click_pulls_the_point_back_down() -> void:
	# Erase's corner reading: take the point away, i.e. down to the board floor, as far as the clamp
	# will legally let it go.
	_brush.set_elevation(LEVEL)
	_stroke(MOUSE_BUTTON_LEFT)
	assert_int(_corner(_vertex(), NW)).is_equal(LEVEL)
	_stroke(MOUSE_BUTTON_RIGHT)
	assert_int(_corner(_vertex(), NW)).is_equal(0)


func test_the_ghost_previews_the_point_and_not_a_tile() -> void:
	# The preview has to name what the click MOVES (#285). A TILE-kind ghost here would draw a block
	# over one of the four cells, which is the wrong object entirely.
	_brush.set_elevation(1)
	var ghost := _dc.brush_ghost()
	assert_object(ghost).is_not_null()
	assert_int(ghost.kind).is_equal(BrushGhost.Kind.VERTEX)
	assert_object(ghost.vertex).is_equal(_vertex())
	assert_int(ghost.height).is_equal(1)


func test_the_flat_tile_ghost_stays_hidden_in_corner_mode() -> void:
	# The 2D layer has no way to draw a point, and its hide gate reads the KIND before the source --
	# a source compare alone matches null against a layer that has never been built, and paints a
	# tile at the origin.
	_dc._sync_brush_ghost()
	var layer: TileMapLayer = _dc._brush_ghost
	assert_bool(layer == null or not layer.visible).override_failure_message(
			"the 2D tile ghost drew something during a corner drag").is_true()


# --- undo ----------------------------------------------------------------------------

func test_a_corner_stroke_undoes_as_one_step() -> void:
	# Undo comes free -- a stroke is already bracketed and BoardSnapshot learned corners in slice 1 --
	# which is worth a case precisely because "free" means nothing here was written for it.
	var vertex := _vertex()
	_brush.set_elevation(LEVEL)
	_stroke(MOUSE_BUTTON_LEFT)
	assert_int(_corner(vertex, NW)).is_equal(LEVEL)
	_dc.undo_board()
	assert_int(_corner(vertex, NW)).override_failure_message(
			"Ctrl+Z did not reach a corner stroke").is_equal(0)
