# The WATER BASIN (#654): water drawn below the ground around it, and the SUBMERGED BANK's walls the
# board mask carries beside it. Both were Experiments until the dev ruled them in (2026-10-10), so
# there is no off side left to pin; what can still drift is the depth knob's poll and every reader
# that places something off the drop.
#
# The cases paint their OWN water onto whatever board loads and flatten it, so nothing here leans on
# what a mission contains (the content razor), and they set every depth they assert against, so a
# re-tuned default cannot redden them (the tuning razor).
#
# WHAT NO CASE HERE CAN SEE: whether the dip LOOKS right. The drop happens in the water shader's
# vertex stage, which a headless renderer never runs; what these cases pin is everything that can
# DRIFT -- which item each column's top block is, what BoardSpace says the drop is, where every reader
# places itself off that, and the poll that turns the depth knob into all of it.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"
const TILESET_PATH := "res://Resources/TestTiles.tres"
const DEPTH := 0.3
const WADE := 0.1

var _board := SharedBoard.new(SCENE_PATH, PROLOG)
var _scene: Node3D
var _game: Node2D
var _saved := {}


func before() -> void:
	await _board.open(self)


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	_game = _board.game
	_saved = {"depth": BoardSpace.WATER_BASIN_DEPTH, "wade": BoardSpace.WATER_WADE_DEPTH,
			"step": BoardSpace.WATER_STEP_TIME}
	BoardSpace.WATER_BASIN_DEPTH = DEPTH
	BoardSpace.WATER_WADE_DEPTH = WADE
	# Snap, so a case reads the settled sink rather than one frame of a step.
	BoardSpace.WATER_STEP_TIME = 0.0


func after_test() -> void:
	BoardSpace.WATER_BASIN_DEPTH = _saved["depth"]
	BoardSpace.WATER_WADE_DEPTH = _saved["wade"]
	BoardSpace.WATER_STEP_TIME = _saved["step"]
	await _settle()
	await _board.check(self)


func after() -> void:
	_board.close()


func _settle() -> void:
	# process_frame resumes coroutines BEFORE node _process, so one frame reads stale.
	await await_idle_frame()
	await await_idle_frame()


# A 1x1 tile off the tileset: WATER of a stated depth, or flat walkable GROUND.
func _tile(water: bool, walkable: bool) -> Dictionary:
	var tiles := load(TILESET_PATH) as TileSet
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var atlas := tiles.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		for i in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(i)
			if atlas.get_tile_size_in_atlas(coords) != Vector2i.ONE:
				continue
			var data := atlas.get_tile_data(coords, 0)
			var kind := GridUtils.terrain_kind_of(data)
			if water != (kind == Terrain.Kind.WATER):
				continue
			if not water and (kind == Terrain.Kind.VOID or kind == Terrain.Kind.NONE \
					or GridUtils.prop_shape_of(data) != GridUtils.PropShape.FLAT):
				continue
			if GridUtils.walkable_of(data) == walkable:
				return {"source": source_id, "coords": coords}
	return {}


# Three free cells in a row painted dry ground, shallow water, deep water, every one flat at the
# board floor's level so each column's top is a block rather than a cap.
func _lake() -> Dictionary:
	var dry := _tile(false, true)
	var shallow := _tile(true, true)
	var deep := _tile(true, false)
	assert_bool(dry.is_empty() or shallow.is_empty() or deep.is_empty()).override_failure_message(
			"the tileset lacks flat ground, wadeable water or drowning water; vacuous").is_false()
	var start := Vector2i.ZERO
	var found := false
	for cell: Vector2i in _game.grid.get_used_cells():
		var free := true
		for dx in 3:
			if _game.get_unit_at_cell(cell + Vector2i(dx, 0)) != null:
				free = false
		if free:
			start = cell
			found = true
			break
	assert_bool(found).override_failure_message("no three free cells in a row; vacuous").is_true()
	_game.game_state = _game.GameState.DEV_MODE
	var lake := {"dry": start, "shallow": start + Vector2i(1, 0), "deep": start + Vector2i(2, 0)}
	var tiles := {"dry": dry, "shallow": shallow, "deep": deep}
	for key: String in lake:
		var cell: Vector2i = lake[key]
		_game.grid.paint(cell, tiles[key]["source"], tiles[key]["coords"])
		_game.board_heights.set_corners(cell, Vector4i.ZERO)
	await _settle()
	lake["tiles"] = tiles
	return lake


func _mirror() -> BoardMirror:
	return _scene.get_node("BoardMirror") as BoardMirror


func _top_item_name(cell: Vector2i, below := 0) -> String:
	var heights: BoardHeights = _game.board_heights
	var board := _scene.get_node("Board") as GridMap
	var at := BoardSpace.of_cell(cell, BoardSpace.top_row_of(heights.elevation_at(cell)) - below)
	var item := board.get_cell_item(at)
	return "" if item == GridMap.INVALID_CELL_ITEM else board.mesh_library.get_item_name(item)


func _rules_y(cell: Vector2i) -> float:
	return BoardSpace.surface_point(cell, _game.board_heights).y


func _base_name(lake: Dictionary, key: String) -> String:
	return BoardMirror.tile_item_name(lake["tiles"][key]["source"], lake["tiles"][key]["coords"])


func _a_unit() -> Unit:
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit != null and unit.is_active():
			return unit
	return null


func test_every_flat_water_column_dips() -> void:
	var lake := await _lake()
	for key: String in ["shallow", "deep"]:
		var cell: Vector2i = lake[key]
		assert_str(_top_item_name(cell)).override_failure_message(
				"the %s column's top block is not its basin twin" % key) \
				.is_equal(BoardMirror.basin_twin_name(_base_name(lake, key)))
		# The block UNDER the top keeps its own item, or the column's walls would open.
		var below := _top_item_name(cell, 1)
		if below != "":
			assert_str(below).is_equal(_base_name(lake, key))
		assert_float(BoardSpace.basin_drop(cell)).is_equal_approx(DEPTH, 0.0001)
	assert_bool(_top_item_name(lake["dry"]).ends_with(BoardMirror.BASIN_TWIN_SUFFIX)).is_false()
	assert_float(BoardSpace.basin_drop(lake["dry"])).is_equal(0.0)
	# The poll is what turns the depth knob into the shader's drop -- the wire.
	assert_float(_mirror().basin_drop_pushed).is_equal_approx(DEPTH, 0.0001)


func test_moving_the_depth_knob_reaches_the_shader_and_the_drop() -> void:
	var lake := await _lake()
	BoardSpace.WATER_BASIN_DEPTH = DEPTH * 0.5
	await _settle()
	assert_float(_mirror().basin_drop_pushed).is_equal_approx(DEPTH * 0.5, 0.0001)
	assert_float(BoardSpace.basin_drop(lake["shallow"])).is_equal_approx(DEPTH * 0.5, 0.0001)


# Two doors take a column off the water: a repaint goes through the column WRITER, an erase through the
# column CLEARER. Each has to unpublish the drop, so the case walks both.
func test_repainting_or_erasing_dipped_water_stops_it_dipping() -> void:
	var lake := await _lake()
	var cell: Vector2i = lake["shallow"]
	assert_float(BoardSpace.basin_drop(cell)).is_greater(0.0)
	_game.grid.paint(cell, lake["tiles"]["dry"]["source"], lake["tiles"]["dry"]["coords"])
	await _settle()
	assert_float(BoardSpace.basin_drop(cell)).override_failure_message(
			"a cell painted back to ground still reports a basin drop").is_equal(0.0)
	assert_str(_top_item_name(cell)).is_equal(_base_name(lake, "dry"))

	var deep: Vector2i = lake["deep"]
	assert_float(BoardSpace.basin_drop(deep)).is_greater(0.0)
	_game.grid.erase(deep)
	await _settle()
	assert_float(BoardSpace.basin_drop(deep)).override_failure_message(
			"an erased cell still reports a basin drop").is_equal(0.0)


func test_a_unit_wades_in_water_and_stands_on_frozen_water() -> void:
	var lake := await _lake()
	var unit := _a_unit()
	assert_object(unit).override_failure_message("no active unit on the board; vacuous").is_not_null()
	var mirror := _scene.get_node("UnitMirror") as UnitMirror
	var shallow: Vector2i = lake["shallow"]
	unit.movement.set_cell(shallow)
	await _settle()
	assert_float(mirror.sprite_for(unit).position.y).override_failure_message(
			"a unit in water should stand in the basin AND wade") \
			.is_equal_approx(_rules_y(shallow) - DEPTH - WADE, 0.0001)

	# FROZEN water is stood ON: RulesService.wets_in says so, and the wade asks it.
	var states: Dictionary = {}
	states[shallow] = [Terrain.TileState.FROZEN]
	_game.terrain_states.load_state_dict(states)
	await _settle()
	assert_float(mirror.sprite_for(unit).position.y).override_failure_message(
			"a unit on frozen water should stand in the basin without wading") \
			.is_equal_approx(_rules_y(shallow) - DEPTH, 0.0001)

	unit.movement.set_cell(lake["dry"])
	await _settle()
	assert_float(mirror.sprite_for(unit).position.y).override_failure_message(
			"a unit on dry ground should be untouched by the basin") \
			.is_equal_approx(_rules_y(lake["dry"]), 0.0001)


func test_a_recess_is_not_a_drop() -> void:
	var lake := await _lake()
	assert_float(BoardSpace.basin_drop(lake["shallow"])).is_greater(0.0)
	# The knockback edge-drop pair reads these, and the dev ruled a recess is not a fall: the edge a
	# shove crosses from the bank into the water must still MEET at the rules height.
	var heights: BoardHeights = _game.board_heights
	var out_of := BoardSpace.surface_height_at_edge(lake["dry"], Vector2i(1, 0), heights)
	var into := BoardSpace.surface_height_at_edge(lake["shallow"], Vector2i(-1, 0), heights)
	assert_float(into).override_failure_message(
			"the edge into dipped water reads %f against the bank's %f -- the edge-drop pair would " \
			% [into, out_of] + "draw a fall the rules never score").is_equal_approx(out_of, 0.0001)


func test_markup_on_water_lies_on_the_dropped_surface() -> void:
	var lake := await _lake()
	var shallow: Vector2i = lake["shallow"]
	var dry: Vector2i = lake["dry"]
	var mirror := _scene.get_node("OverlayMirror") as OverlayMirror
	var marker_wet := (mirror._anchor(shallow)["surface"] as Transform3D).origin.y
	var marker_dry := (mirror._anchor(dry)["surface"] as Transform3D).origin.y
	assert_float(marker_wet).is_equal_approx(_rules_y(shallow) - DEPTH, 0.0001)
	assert_float(marker_dry).is_equal_approx(_rules_y(dry), 0.0001)

	var overlays := _scene.get_node("BoardOverlays") as BoardOverlays
	var heights: BoardHeights = _game.board_heights
	var wet_cell := BoardSpace.of_cell(shallow, BoardSpace.top_row_of(heights.elevation_at(shallow)))
	var dry_cell := BoardSpace.of_cell(dry, BoardSpace.top_row_of(heights.elevation_at(dry)))
	var fill: Dictionary = BoardOverlays.LAYERS[BoardOverlays.Layer.MOVE]
	var fill_gap := overlays._marker_transform(fill, wet_cell, heights).origin.y \
			- overlays._marker_transform(fill, dry_cell, heights).origin.y
	assert_float(fill_gap).override_failure_message("a fill on water does not sit on the dip") \
			.is_equal_approx(-DEPTH, 0.0001)
	for layer: BoardOverlays.Layer in BoardOverlays.LAYERS:
		var spec: Dictionary = BoardOverlays.LAYERS[layer]
		if spec["kind"] != BoardOverlays.Kind.BRACKET:
			continue
		var bracket_gap := overlays._marker_transform(spec, wet_cell, heights).origin.y \
				- overlays._marker_transform(spec, dry_cell, heights).origin.y
		assert_float(bracket_gap).override_failure_message(
				"the hover bracket over water does not sit on the dip").is_equal_approx(-DEPTH, 0.0001)


# The WIRE for an already-drawn fill: its cells and the heights have not moved, so only the basin's
# own version can tell OverlayMirror to re-place it when the depth knob moves (#308's law).
func test_a_fill_already_drawn_re_places_when_the_depth_moves() -> void:
	var lake := await _lake()
	var deep: Vector2i = lake["deep"]
	var om := _game.overlay_manager as OverlayManager
	var cells: Array[Vector2i] = [lake["dry"], deep]
	om.show_attack_reach(cells, [] as Array[Vector2i])
	await _settle()
	var overlays := _scene.get_node("BoardOverlays") as BoardOverlays
	var heights: BoardHeights = _game.board_heights
	var at := BoardSpace.of_cell(deep, BoardSpace.top_row_of(heights.elevation_at(deep)))
	var index := overlays.cells_of(BoardOverlays.Layer.ATTACK).find(at)
	assert_int(index).override_failure_message("the reach never reached the 3D layer").is_greater_equal(0)
	var before := (overlays._pool_for(BoardOverlays.Layer.ATTACK)[index] as Node3D).position.y

	BoardSpace.WATER_BASIN_DEPTH = DEPTH * 0.5
	await _settle()
	index = overlays.cells_of(BoardOverlays.Layer.ATTACK).find(at)
	var after := (overlays._pool_for(BoardOverlays.Layer.ATTACK)[index] as Node3D).position.y
	assert_float(after - before).override_failure_message(
			"the reach fill over water stayed put when the basin depth moved") \
			.is_equal_approx(DEPTH * 0.5, 0.0001)
	om.show_attack_reach([] as Array[Vector2i], [] as Array[Vector2i])


# The submerged bank's bits (#654) for one board cell, off the mask the mirror last pushed. Read off
# the recorded image, since a headless ImageTexture reads back only the first picture it was given.
func _mask_bits(cell: Vector2i) -> int:
	var image := _mirror().water_mask_built
	var origin: Vector2i = _game.grid.get_used_rect().position
	return int(round(image.get_pixel(cell.x - origin.x, cell.y - origin.y).a * 255.0))


# The real board's mask carries the banks, through the same sync doors a brush stroke takes. The lake
# runs dry, shallow, deep from west to east, so the shallow cell has ground behind its west edge and
# water behind its east one.
func test_the_real_board_bakes_its_banks() -> void:
	var lake := await _lake()
	var bits := _mask_bits(lake["shallow"])
	assert_int(bits & 8).override_failure_message("the dry cell to the west is not a bank").is_equal(8)
	assert_int(bits & 2).override_failure_message("the deep water to the east is a bank").is_equal(0)
	assert_int(_mask_bits(lake["dry"])).override_failure_message(
			"a land cell carries bank bits; only water draws a bank").is_equal(0)
