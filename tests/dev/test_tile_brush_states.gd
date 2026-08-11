# The Tile Brush STATE paint mode (#174): _paint_state writes through TerrainStateManager.apply
# -- the ONE deposit seam -- so a painted BURNING carries the real 3-turn clock while a painted
# BLAZE never expires; right-click clears the whole cell. The round-trip case pins the two
# load-path fixes this feature exposed: clear_board clears terrain state (and its icons), and
# apply_scenario redraws it (authored fire visible at turn one, not at the first round tick).
#
# The mouse->cell half (_paint reading get_global_mouse_position) can't be aimed headless; these
# cases drive _paint_state/_erase_state directly beneath the dispatch match, and set the brush's
# private _tile_state pick because the dropdown->field wire is the same one-liner as Zone Kind's.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const CELL := Vector2i(2, 0)
const BURN_TICKS: int = TerrainStateManager.STATE_DURATIONS[Terrain.TileState.BURNING]

var _main: Node
var game: Node2D
var _brush: TileBrushTool

func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	var overlay: DevOverlay = game.dev_overlay
	_brush = overlay.tile_brush
	_brush.paint_mode = TileBrushTool.PaintMode.STATE
	await await_idle_frame()

func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()

func _live_icon_count() -> int:
	var count: int = game.overlay_manager.terrain_live_sprites.size()
	return count

func test_painting_deposits_the_picked_state_and_draws_its_icon() -> void:
	_brush._tile_state = Terrain.TileState.BLAZE
	game.dev_controller._paint_state(CELL)
	assert_bool(game.terrain_states.has_state(CELL, Terrain.TileState.BLAZE)).is_true()
	assert_int(_live_icon_count()).is_equal(1)

func test_a_painted_burning_carries_the_real_clock() -> void:
	_brush._tile_state = Terrain.TileState.BURNING
	game.dev_controller._paint_state(CELL)
	for _i in range(BURN_TICKS):
		game.terrain_states.tick_states()
	assert_bool(game.terrain_states.has_state(CELL, Terrain.TileState.BURNING)).is_false()

func test_a_painted_blaze_never_expires() -> void:
	_brush._tile_state = Terrain.TileState.BLAZE
	game.dev_controller._paint_state(CELL)
	for _i in range(BURN_TICKS * 2):
		game.terrain_states.tick_states()
	assert_bool(game.terrain_states.has_state(CELL, Terrain.TileState.BLAZE)).is_true()

func test_repainting_does_not_rewind_a_burning_clock() -> void:
	# The has_state guard: a drag repaints the same cell every motion event, and that must not
	# restoke the fire -- one tick spent, then a repaint, then the REMAINING ticks put it out.
	_brush._tile_state = Terrain.TileState.BURNING
	game.dev_controller._paint_state(CELL)
	game.terrain_states.tick_states()
	game.dev_controller._paint_state(CELL)
	for _i in range(BURN_TICKS - 1):
		game.terrain_states.tick_states()
	assert_bool(game.terrain_states.has_state(CELL, Terrain.TileState.BURNING)).is_false()

func test_erase_clears_every_state_on_the_cell() -> void:
	_brush._tile_state = Terrain.TileState.BLAZE
	game.dev_controller._paint_state(CELL)
	_brush._tile_state = Terrain.TileState.COVER
	game.dev_controller._paint_state(CELL)
	game.dev_controller._erase_state(CELL)
	assert_array(game.terrain_states.states_at(CELL)).is_empty()
	assert_int(_live_icon_count()).is_equal(0)

func test_clear_all_asks_first_then_wipes_the_board() -> void:
	# The board-wide wipe (2026-08-11): confirmed via the same dialog Delete rides, then the
	# clear_board pair (store clear + full redraw). In-memory only.
	_brush._tile_state = Terrain.TileState.BLAZE
	game.dev_controller._paint_state(CELL)
	game.dev_controller._paint_state(Vector2i(4, 0))

	_brush._clear_states_button.pressed.emit()

	var dialog: ConfirmationDialog = null
	for child in _brush.get_children():
		if child is ConfirmationDialog:
			dialog = child as ConfirmationDialog
	assert_object(dialog).is_not_null()
	assert_bool(game.terrain_states.has_state(CELL, Terrain.TileState.BLAZE)).is_true()   # not yet

	dialog.confirmed.emit()
	dialog.hide()
	await await_idle_frame()

	assert_array(game.terrain_states.states_at(CELL)).is_empty()
	assert_array(game.terrain_states.states_at(Vector2i(4, 0))).is_empty()
	assert_int(_live_icon_count()).is_equal(0)

func test_the_authoring_loop_round_trips_with_icons() -> void:
	# paint -> capture -> clear_board (store AND icons empty: the clear fix) -> apply_scenario
	# (state back AND icons drawn: the redraw fix). In memory only -- no Scenarios/ writes.
	_brush._tile_state = Terrain.TileState.BLAZE
	game.dev_controller._paint_state(CELL)
	var captured: ScenarioData = game.scenario_manager.capture_scenario("brush-roundtrip", false)

	game.scenario_manager.clear_board()
	assert_bool(game.terrain_states.has_state(CELL, Terrain.TileState.BLAZE)).is_false()
	assert_int(_live_icon_count()).is_equal(0)

	game.scenario_manager.apply_scenario(captured)
	assert_bool(game.terrain_states.has_state(CELL, Terrain.TileState.BLAZE)).is_true()
	assert_int(_live_icon_count()).is_equal(1)
