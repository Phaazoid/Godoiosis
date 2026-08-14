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

# --- A state needs ground under it (#245) --------------------------------------------
#
# End-to-end over the REAL grid, so GridUtils.has_ground's choice of get_cell_source_id (rather
# than get_cell_tile_data) is exercised against a board that actually has a TileSet.

# Far outside any authored board. NOT merely off the row before_test paints -- clear_board() clears
# units, zones and states but deliberately leaves the TILEMAP alone, so Main.tscn's own terrain is
# still there and a nearby cell has ground under it. Every case below asserts that for itself.
const VOID_CELL := Vector2i(64, 64)
const FAR_CELL := Vector2i(6, 0)    # on the painted row, but outside a 3x3 resize

func _assert_void_is_void() -> void:
	assert_bool(GridUtils.has_ground(game.grid, VOID_CELL)).override_failure_message(
			"precondition: VOID_CELL has ground, so nothing below proves anything").is_false()


func test_a_state_cannot_be_painted_onto_a_cell_with_no_tile() -> void:
	# The dev ruling, verbatim: a terrain effect modifies what happens when a unit walks on a tile,
	# so if there is no tile there should be no modifier.
	_assert_void_is_void()
	_brush._tile_state = Terrain.TileState.FROZEN
	game.dev_controller._paint_state(VOID_CELL)
	assert_bool(game.terrain_states.has_state(VOID_CELL, Terrain.TileState.FROZEN)) \
		.override_failure_message("a state landed on a cell with no ground").is_false()
	# Non-vacuous: the same paint on real ground still lands, so this is not just a dead brush.
	game.dev_controller._paint_state(CELL)
	assert_bool(game.terrain_states.has_state(CELL, Terrain.TileState.FROZEN)).is_true()


func test_erasing_a_tile_takes_its_states_with_it() -> void:
	# The half a forbid alone does NOT cover, and the reported bug's actual path: the state was
	# perfectly legal when painted, and the ground went away afterwards.
	#
	# The ICON assertion is the one with teeth. The first version of this case checked has_state
	# alone, went green, and shipped a build where the store was correct and the sprite stayed on
	# screen — because _erase_tile cleared the state and never redrew, and the 3D mirror then
	# faithfully mirrored the stale sprite. Assert the WIRE, not the two ends.
	_brush._tile_state = Terrain.TileState.FROZEN
	game.dev_controller._paint_state(CELL)
	assert_bool(game.terrain_states.has_state(CELL, Terrain.TileState.FROZEN)) \
		.override_failure_message("precondition: the paint never landed").is_true()
	var painted_icons := _live_icon_count()
	assert_int(painted_icons).override_failure_message(
			"precondition: painting drew no icon, so its disappearance would prove nothing").is_greater(0)

	game.dev_controller._erase_tile(CELL)
	assert_bool(game.terrain_states.has_state(CELL, Terrain.TileState.FROZEN)) \
		.override_failure_message("the state outlived the ground it was standing on").is_false()
	assert_int(_live_icon_count()).override_failure_message(
			"the store cleared but the icon stayed — the redraw never ran").is_less(painted_icons)


func test_shrinking_the_map_drops_the_states_left_outside_it() -> void:
	# grid.clear() inside resize_map is the SECOND way to lose ground, and it never matched a search
	# for erase_cell — which is exactly why the rule sweeps rather than clearing one named cell.
	_brush._tile_state = Terrain.TileState.FROZEN
	game.dev_controller._paint_state(FAR_CELL)
	assert_bool(game.terrain_states.has_state(FAR_CELL, Terrain.TileState.FROZEN)) \
		.override_failure_message("precondition: the paint never landed").is_true()
	game.dev_controller.resize_map(3, 3, GRASS_SOURCE, GRASS_ATLAS)
	assert_bool(game.terrain_states.has_state(FAR_CELL, Terrain.TileState.FROZEN)) \
		.override_failure_message("a state survived the board shrinking out from under it").is_false()


func test_a_groundless_cell_never_becomes_walkable_through_frozen() -> void:
	# The severe half, and why this was never only a floating icon. BoardContext.is_walkable
	# short-circuits on FROZEN BEFORE the tile lookup -- deliberately, since headless fixtures carry
	# no TileSet -- so a frozen void cell read as WALKABLE and the move-range BFS would happily path
	# a unit onto nothing.
	_assert_void_is_void()
	assert_bool(game._board().is_walkable(VOID_CELL)) \
		.override_failure_message("precondition: the void cell was walkable before any freeze").is_false()
	_brush._tile_state = Terrain.TileState.FROZEN
	game.dev_controller._paint_state(VOID_CELL)
	assert_bool(game._board().is_walkable(VOID_CELL)) \
		.override_failure_message("freezing the void made it walkable").is_false()

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
