# The Tile Brush TERRAIN palette (2026-08-12 rework): one dropdown entry per authored tile --
# a tile earns its slot by carrying a non-NONE terrain_type kind OR a non-empty terrain_name,
# across every atlas source. Labels prefer the authored name ("grass_basic" -> "Grass Basic");
# unnamed terrain falls back to kind + atlas coords. Scenery (named, kindless) sorts last.
# The paint wire carries the SOURCE too: picking a second-source tile must write that source id,
# through both _paint_tile and the Resize fill.
#
# Cases drive the tool beneath the mouse dispatch (the states suite's pattern) against a
# synthetic two-source tileset swapped onto the grid, so content edits to TestTiles.tres
# never move these assertions.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const CELL := Vector2i(1, 1)
const INJECTED := Vector2i(4, 3)   # deliberately not CELL, and not where a headless mouse sits

var _main: Node
var game: Node2D
var _brush: TileBrushTool
var _src1_id: int
var _src2_id: int

func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	_brush = game.dev_overlay.tile_brush
	game.grid.tile_set = _build_tile_set()
	_brush._populate_tile_dropdown()

func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()

# Two atlas sources, layer names mirroring TestTiles.tres. Source 1: a named GRASS tile, an
# unnamed GRASS variant, named kindless scenery, and one bare decorative tile (no kind, no
# name -- must not be listed). Source 2: one named MUD tile.
func _build_tile_set() -> TileSet:
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(16, 16)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(0, "walkable")
	tiles.set_custom_data_layer_type(0, TYPE_BOOL)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(1, "move_cost")
	tiles.set_custom_data_layer_type(1, TYPE_INT)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(2, "terrain_type")
	tiles.set_custom_data_layer_type(2, TYPE_INT)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(3, "terrain_name")
	tiles.set_custom_data_layer_type(3, TYPE_STRING)

	var src1 := _blank_source()
	var src2 := _blank_source()
	_src1_id = tiles.add_source(src1)
	_src2_id = tiles.add_source(src2)

	_author_tile(src1, Vector2i(0, 0), Terrain.Kind.GRASS, "grass_basic")
	_author_tile(src1, Vector2i(1, 0), Terrain.Kind.GRASS, "")
	_author_tile(src1, Vector2i(2, 0), Terrain.Kind.NONE, "crate")
	_author_tile(src1, Vector2i(3, 0), Terrain.Kind.NONE, "")
	_author_tile(src2, Vector2i(0, 0), Terrain.Kind.MUD, "mud_far")
	return tiles

func _blank_source() -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(
		Image.create_empty(64, 16, false, Image.FORMAT_RGBA8))
	source.texture_region_size = Vector2i(16, 16)
	return source

func _author_tile(source: TileSetAtlasSource, coords: Vector2i, kind: Terrain.Kind, tile_name: String) -> void:
	source.create_tile(coords)
	var data := source.get_tile_data(coords, 0)
	if kind != Terrain.Kind.NONE:
		data.set_custom_data("terrain_type", kind)
	if tile_name != "":
		data.set_custom_data("terrain_name", tile_name)

func _labels() -> Array[String]:
	var out: Array[String] = []
	for i in _brush.tile_dropdown.item_count:
		out.append(_brush.tile_dropdown.get_item_text(i))
	return out

func _select_label(label: String) -> void:
	var index: int = _labels().find(label)
	assert_int(index).is_not_equal(-1)
	_brush._on_tile_dropdown_item_selected(index)

func test_variants_of_one_kind_are_not_deduplicated() -> void:
	# The old scan kept one tile per kind; both grass tiles must be listed now.
	assert_array(_labels()).contains(["Grass Basic", "Grass (1:0)"])

func test_only_kinded_or_named_tiles_are_listed() -> void:
	# 4 = both grasses + crate + mud_far; the bare decorative 3:0 earns nothing.
	assert_int(_brush.tile_dropdown.item_count).is_equal(4)

func test_terrain_sorts_by_kind_and_scenery_sorts_last() -> void:
	assert_array(_labels()).is_equal(["Grass Basic", "Grass (1:0)", "Mud Far", "Crate"] as Array[String])

func test_the_first_entry_is_preselected() -> void:
	# add_item auto-selects index 0; the stored pick must agree with the visible one.
	assert_that(_brush.selected_tile).is_equal(Vector2i(0, 0))
	assert_int(_brush.selected_source).is_equal(_src1_id)

func test_painting_a_second_source_pick_writes_that_source() -> void:
	_select_label("Mud Far")
	game.dev_controller._paint_tile(CELL)
	assert_int(game.grid.get_cell_source_id(CELL)).is_equal(_src2_id)
	assert_that(game.grid.get_cell_atlas_coords(CELL)).is_equal(Vector2i(0, 0))

func test_resize_fills_with_the_selected_source() -> void:
	_select_label("Mud Far")
	_brush._width_spin.value = 3
	_brush._height_spin.value = 2
	_brush._on_resize_pressed()
	for x in range(3):
		for y in range(2):
			assert_int(game.grid.get_cell_source_id(Vector2i(x, y))).is_equal(_src2_id)

func test_entries_carry_their_tile_sprite_as_icon() -> void:
	# The row icon IS the tile: an AtlasTexture cut from the owning source's own sheet region.
	var index: int = _labels().find("Mud Far")
	var icon := _brush.tile_dropdown.get_item_icon(index) as AtlasTexture
	assert_object(icon).is_not_null()
	var source := (game.grid.tile_set as TileSet).get_source(_src2_id) as TileSetAtlasSource
	assert_object(icon.atlas).is_same(source.texture)
	assert_that(icon.region).is_equal(Rect2(source.get_tile_texture_region(Vector2i(0, 0))))

func _ghost() -> TileMapLayer:
	return game.grid.get_node_or_null("BrushGhost") as TileMapLayer

func _hover_cell() -> Vector2i:
	return game.dev_controller._mouse_cell()

func _arm_brush() -> void:
	game.set_dev_mode(true)
	_brush.brush_active = true

# The ghost POLLS per frame rather than riding mouse events, because while the Dev Tools OS
# window holds focus the game window gets no motion events until a click -- picking a tile over
# there must still show the ghost here on the very next frame, no click required. These cases
# arm the real gate and await frames; no update call is ever made directly.
func test_the_ghost_appears_from_the_gate_alone_no_click_needed() -> void:
	_select_label("Mud Far")
	_arm_brush()
	await await_idle_frame()
	var ghost := _ghost()
	assert_object(ghost).is_not_null()
	assert_bool(ghost.visible).is_true()
	assert_int(ghost.get_cell_source_id(_hover_cell())).is_equal(_src2_id)
	assert_float(ghost.modulate.a).is_less(1.0)
	assert_int(ghost.z_index).is_less(Unit.BASE_SPRITE_INDEX)

func test_the_ghost_follows_the_latest_pick() -> void:
	_select_label("Mud Far")
	_arm_brush()
	await await_idle_frame()
	_select_label("Crate")
	await await_idle_frame()
	var ghost := _ghost()
	assert_int(ghost.get_cell_source_id(_hover_cell())).is_equal(_src1_id)
	assert_that(ghost.get_cell_atlas_coords(_hover_cell())).is_equal(Vector2i(2, 0))

func test_the_ghost_hides_on_every_off_path() -> void:
	# brush off / paint-mode switch / dev-mode exit: the poll gate closes, next frame hides.
	_arm_brush()
	await await_idle_frame()
	assert_bool(_ghost().visible).is_true()

	_brush.brush_active = false
	await await_idle_frame()
	assert_bool(_ghost().visible).is_false()

	_brush.brush_active = true
	_brush._set_paint_mode(TileBrushTool.PaintMode.ZONE)
	await await_idle_frame()
	assert_bool(_ghost().visible).is_false()

	_brush._set_paint_mode(TileBrushTool.PaintMode.TERRAIN)
	game.set_dev_mode(false)
	await await_idle_frame()
	assert_bool(_ghost().visible).is_false()

# --- The injected cell source (#231) --------------------------------------------------
#
# A 3D host's pointer is not this viewport's mouse, so it hands the brush its cell directly --
# the HoverPresenter.pointer_source shape. It is applied INSIDE _mouse_cell(), and that is the
# point: paint, erase and the ghost poll inherit it from ONE place instead of three agreeing.

func test_an_injected_cell_source_redirects_the_paint() -> void:
	_select_label("Mud Far")
	assert_that(game.dev_controller._mouse_cell()).override_failure_message(
			"precondition: the mouse already sits on the injected cell, so this proves nothing"
	).is_not_equal(INJECTED)
	game.dev_controller.cell_source = func() -> Vector2i: return INJECTED
	game.dev_controller._paint()
	assert_int(game.grid.get_cell_source_id(INJECTED)).is_equal(_src2_id)


func test_the_injected_source_also_drives_the_ghost_poll() -> void:
	# The seam's whole reason for living where it does. A per-call-site fix would have moved
	# the PAINT to the 3D cell and left the preview tracking the 2D mouse — the two would
	# disagree about which cell was about to change, which is the bug that reads as unusable.
	_select_label("Mud Far")
	game.dev_controller.cell_source = func() -> Vector2i: return INJECTED
	_arm_brush()
	await await_idle_frame()
	assert_int(_ghost().get_cell_source_id(INJECTED)).is_equal(_src2_id)


func test_clearing_the_source_hands_the_brush_back_to_the_mouse() -> void:
	# F4 to the flat view clears it; an un-cleared Callable would pin the brush to a stale cell.
	game.dev_controller.cell_source = func() -> Vector2i: return INJECTED
	assert_that(game.dev_controller._mouse_cell()).is_equal(INJECTED)
	game.dev_controller.cell_source = Callable()
	var by_mouse: Vector2i = game.grid.local_to_map(game.grid.to_local(game.get_global_mouse_position()))
	assert_that(game.dev_controller._mouse_cell()).is_equal(by_mouse)


func test_the_ghost_intent_is_no_cell_unless_a_preview_is_owed() -> void:
	# What a 3D mirror reads. It has to ask the INTENT and never the 2D ghost's `.visible`:
	# under a 3D host that field has a second writer meaning "the 2D board draws at all"
	# (#232/#238), so it reads TRUE on a ghost nobody can see.
	assert_that(game.dev_controller.brush_ghost_cell()).is_equal(GridUtils.NO_CELL)
	_arm_brush()
	assert_that(game.dev_controller.brush_ghost_cell()).override_failure_message(
			"armed on TERRAIN and still claiming no cell").is_not_equal(GridUtils.NO_CELL)
	_brush._set_paint_mode(TileBrushTool.PaintMode.ZONE)
	assert_that(game.dev_controller.brush_ghost_cell()).override_failure_message(
			"a non-TERRAIN mode still claims a ghost cell").is_equal(GridUtils.NO_CELL)


func test_an_unknown_kind_number_warns_instead_of_crashing() -> void:
	# The fence_hor incident: a terrain_type outside Terrain.Kind must warn and degrade --
	# named tiles list as scenery, unnamed ones are skipped -- never index the enum out of
	# bounds building a label. Corrupts the UNNAMED grass variant because that is the tile
	# whose label would do the indexing.
	var tiles: TileSet = game.grid.tile_set
	var source := tiles.get_source(_src1_id) as TileSetAtlasSource
	source.get_tile_data(Vector2i(1, 0), 0).set_custom_data("terrain_type", 99)
	source.get_tile_data(Vector2i(2, 0), 0).set_custom_data("terrain_type", 99)
	_brush._populate_tile_dropdown()
	assert_array(_labels()).is_equal(["Grass Basic", "Mud Far", "Crate"] as Array[String])
