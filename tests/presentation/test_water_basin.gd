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


# --- Gas, shock and landing dust over water (#1363) --------------------------------------------------

func _gas() -> GasMirror:
	return _scene.get_node("GasMirror") as GasMirror


# A gas whose look flashes, so a cell holding it is a strike.
func _flashing_kind() -> Gas.Kind:
	for kind: Gas.Kind in Gas.Kind.values():
		if GasLook.for_kind(kind).flash > 0.0:
			return kind
	assert_bool(false).override_failure_message("no gas look flashes; vacuous").is_true()
	return Gas.Kind.STEAM


# The cell of the two whose centre a puff stands nearer: a puff leans toward a gassy neighbour but
# never past half a cell.
func _nearer(at: Vector3, a: Vector2i, b: Vector2i) -> Vector2i:
	var to_a := Vector2(at.x, at.z).distance_to(Vector2(a) + Vector2(0.5, 0.5))
	var to_b := Vector2(at.x, at.z).distance_to(Vector2(b) + Vector2(0.5, 0.5))
	return a if to_a <= to_b else b


func test_gas_over_water_lies_in_the_basin() -> void:
	var lake := await _lake()
	var shallow: Vector2i = lake["shallow"]
	var dry: Vector2i = lake["dry"]
	var field: GasField = _game.gas_field
	field.set_level(dry, Gas.Kind.STEAM, Gas.Level.THICK)
	field.set_level(shallow, Gas.Kind.STEAM, Gas.Level.THICK)
	await _settle()
	assert_int(Gas.level_in(field.packed_at(shallow), Gas.Kind.STEAM)).override_failure_message(
			"the store refused gas over water; vacuous").is_equal(Gas.Level.THICK)
	var gas := _gas()
	var drawn := {dry: _rules_y(dry), shallow: _rules_y(shallow) - DEPTH}

	# The floor: each fan's centre vertex lies on the surface you see, lifted into the markup stack.
	var lift := (_scene.get_node("BoardOverlays") as BoardOverlays).gas_floor_lift()
	var vertices: PackedVector3Array = (gas.floor_node().mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var centres := 0
	for v in vertices:
		for cell: Vector2i in [dry, shallow]:
			if is_equal_approx(v.x, cell.x + 0.5) and is_equal_approx(v.z, cell.y + 0.5):
				centres += 1
				assert_float(v.y).override_failure_message("the gas floor at %s floats off the drawn surface" % cell) \
						.is_equal_approx(float(drawn[cell]) + lift, 0.0001)
	assert_int(centres).override_failure_message("no floor fan centre on either cell; vacuous").is_greater(0)

	# The volume's ground, corner by corner and at the middle, and the box its march is bounded by.
	var rect: Rect2i = _game.grid.get_used_rect()
	var ground := (gas.board_textures()[3] as Texture2D).get_image()
	var mid := (gas.board_textures()[4] as Texture2D).get_image()
	for cell: Vector2i in [dry, shallow]:
		var want: float = drawn[cell]
		var corners := ground.get_pixelv(cell - rect.position)
		for y: float in [corners.r, corners.g, corners.b, corners.a]:
			assert_float(y).override_failure_message("the volume's ground at %s is not the drawn surface" % cell) \
					.is_equal_approx(want, 0.0001)
		assert_float(mid.get_pixelv(cell - rect.position).r).is_equal_approx(want, 0.0001)
	var lowest := INF
	for box: AABB in gas.region_boxes():
		lowest = minf(lowest, box.position.y)
	assert_float(lowest).override_failure_message("the region box would clip the pool lying in the basin") \
			.is_equal_approx(_rules_y(shallow) - DEPTH - GasRegions.BELOW, 0.0001)

	# A strike glows over the water you see.
	field.clear()
	field.set_level(shallow, _flashing_kind(), Gas.Level.THICK)
	await _settle()
	var strikes := gas.strike_points()
	assert_int(strikes.size()).override_failure_message("the flashing gas struck nowhere; vacuous").is_equal(1)
	assert_float(strikes.values()[0].y).is_equal_approx(_rules_y(shallow) - DEPTH + GasMirror.FLASH_LIFT, 0.0001)
	field.clear()


# The WIRE: a depth move changes no gas, no height and no grid, so only the basin's own version can
# tell the mirror to re-place what it already drew.
func test_moving_the_depth_knob_re_places_gas_already_drawn() -> void:
	var lake := await _lake()
	var shallow: Vector2i = lake["shallow"]
	var dry: Vector2i = lake["dry"]
	var field: GasField = _game.gas_field
	field.set_level(dry, Gas.Kind.STEAM, Gas.Level.THICK)
	field.set_level(shallow, Gas.Kind.STEAM, Gas.Level.THICK)
	await _settle()
	var before: Array = _gas().puff_entries().duplicate()
	assert_int(before.size()).override_failure_message("no puffs drawn; vacuous").is_greater(0)

	BoardSpace.WATER_BASIN_DEPTH = DEPTH * 0.5
	await _settle()
	var after: Array = _gas().puff_entries()
	assert_int(after.size()).is_equal(before.size())
	var wet := 0
	for i in before.size():
		var was: Vector3 = before[i][0]
		var now: Vector3 = after[i][0]
		var rise := DEPTH * 0.5 if _nearer(was, dry, shallow) == shallow else 0.0
		wet += 1 if rise > 0.0 else 0
		assert_float(now.y - was.y).override_failure_message(
				"a puff at %s did not follow the basin depth" % was).is_equal_approx(rise, 0.0001)
	assert_int(wet).override_failure_message("no puff stands over the water; vacuous").is_greater(0)
	field.clear()


# The two answers the shock is handed (#887): where a cell is drawn, for the bolts, and where a body
# standing on it is drawn, for its sparks -- asked through the callables battle3d really wired.
func test_a_shock_over_water_arcs_off_the_water_and_sparks_off_the_body() -> void:
	var lake := await _lake()
	var shallow: Vector2i = lake["shallow"]
	var dry: Vector2i = lake["dry"]
	var arc: ArcLightning = _scene._arc
	assert_float((arc.point_of.call(shallow) as Vector3).y).is_equal_approx(_rules_y(shallow) - DEPTH, 0.0001)
	assert_float((arc.point_of.call(dry) as Vector3).y).is_equal_approx(_rules_y(dry), 0.0001)

	var unit := _a_unit()
	assert_object(unit).override_failure_message("no active unit on the board; vacuous").is_not_null()
	var mirror := _scene.get_node("UnitMirror") as UnitMirror
	unit.movement.set_cell(shallow)
	await _settle()
	var feet: Vector3 = arc.feet_of.call(unit, shallow)
	assert_float(feet.y).override_failure_message("a wader's sparks do not start from its drawn feet") \
			.is_equal_approx(_rules_y(shallow) - DEPTH - WADE, 0.0001)
	assert_float(feet.y).override_failure_message("the sparks and the mirror disagree where the body stands") \
			.is_equal_approx(mirror.sprite_for(unit).position.y, 0.0001)

	var states: Dictionary = {}
	states[shallow] = [Terrain.TileState.FROZEN]
	_game.terrain_states.load_state_dict(states)
	await _settle()
	assert_float((arc.feet_of.call(unit, shallow) as Vector3).y).override_failure_message(
			"a body standing ON frozen water wades no deeper than the ice").is_equal_approx(_rules_y(shallow) - DEPTH, 0.0001)


func test_a_landing_on_water_puffs_from_the_water() -> void:
	var lake := await _lake()
	var dust: StagingDust = _scene._staging_dust
	for key: String in ["shallow", "dry"]:
		var cell: Vector2i = lake[key]
		var cells: Array[Vector2i] = [cell]
		_scene._puff_landings(cells)
		var want := _rules_y(cell) - (DEPTH if key == "shallow" else 0.0)
		assert_float(dust.last_origin.y).override_failure_message("the %s landing's dust starts off the surface" % key) \
				.is_equal_approx(want, 0.0001)


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
