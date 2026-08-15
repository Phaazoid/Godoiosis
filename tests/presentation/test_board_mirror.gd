# BoardMirror (#215): the Kind->item table's completeness (law-style: every Kind
# except the declared NONE skip), the board wire against the REAL Prolog mission
# loaded through the real funnel inside the Battle3D fixture, fire markers derived
# from terrain_states.burning_cells (never a pinned count), and clear-board
# emptiness. The fixture disables auto_play so no AI churns during asserts.
#
# The live half (#231) is the second section: terrain paints and state changes reach
# the diorama without an F2 or a turn boundary. Those cases drive the AUTHORITY —
# game.grid / terrain_states.apply — and never call sync()/refresh_states themselves,
# so a mirror that only works when a test pokes it goes red rather than green.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"

var _scene: Node3D
var _game: Node2D


func before_test() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_game = _scene.game


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func test_every_kind_is_mapped_or_declared_skip() -> void:
	for kind: Terrain.Kind in Terrain.Kind.values():
		if kind == Terrain.Kind.NONE:
			assert_bool(BoardMirror.KIND_TO_ITEM.has(kind)).is_false()  # the declared skip
		else:
			assert_bool(BoardMirror.KIND_TO_ITEM.has(kind)).is_true()


func test_prolog_mirrors_cell_for_cell() -> void:
	_scene.load_mission(PROLOG)
	await await_idle_frame()
	var board := _scene.get_node("Board") as GridMap
	var grid_cells: Array[Vector2i] = _game.grid.get_used_cells()
	assert_int(board.get_used_cells().size()).is_equal(grid_cells.size())
	assert_bool(grid_cells.size() > 100).is_true()  # Prolog is a real board, not a stub
	# Spot-check: every mirrored block is the block for THAT TILE, named off the 2D cell's own
	# atlas coords. Deliberately not asked through item_for_cell — that would assert the mirror
	# against itself. Prolog paints only single-cell tiles, so every one has an item of its own.
	for i in 25:
		var cell := grid_cells[i * maxi(1, grid_cells.size() / 25)]
		var source_id: int = _game.grid.get_cell_source_id(cell)
		var coords: Vector2i = _game.grid.get_cell_atlas_coords(cell)
		var expected := BoardMirror.tile_item_name(source_id, coords)
		var item := board.get_cell_item(Vector3i(cell.x, 0, cell.y))
		assert_str(board.mesh_library.get_item_name(item)).override_failure_message(
				"cell %s paints tile %s but got block '%s'" \
				% [cell, coords, board.mesh_library.get_item_name(item)]).is_equal(expected)


# Which cells burn comes off the ONE enumeration form (Terrain.gd: "no reader may
# enumerate fire members itself"). This helper used to walk FIRE_STATES itself — a third
# copy beside BoardMirror._has_fire, both deleted by #231.
func _burning() -> Array[Vector2i]:
	return _game.terrain_states.burning_cells()


func test_fire_markers_match_the_games_own_burning_cells() -> void:
	_scene.load_mission(PROLOG)
	await await_idle_frame()
	var expected := _burning().size()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	assert_int(mirror.fire_marker_count()).is_equal(expected)
	assert_bool(expected > 0).is_true()  # Prolog authors BLAZE content; a zero here means the load broke


func test_the_flame_actually_carries_the_flame_priority() -> void:
	# Test the WIRE: a sort constant is worth nothing if no flame reads it, and this one exists
	# because the flame read NOTHING — it sat at the default 0, below every overlay layer, so
	# painting a frost icon onto a burning tile drew straight over the fire and it looked erased
	# (#245, found in play). The store was correct throughout, which is why only a render-side
	# assertion could ever have caught it.
	_scene.load_mission(PROLOG)
	await await_idle_frame()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var burning := _burning()
	assert_bool(burning.size() > 0).override_failure_message(
			"precondition: nothing is burning, so there is no flame to inspect").is_true()
	var marker := mirror.fire_marker_at(burning[0])
	assert_object(marker).override_failure_message("no marker for a burning cell").is_not_null()
	var flame: MeshInstance3D = null
	for child in marker.get_children():
		var mesh_child := child as MeshInstance3D
		if mesh_child != null:
			flame = mesh_child
			break
	assert_object(flame).override_failure_message("the fire marker has no mesh child").is_not_null()
	var material := (flame.mesh as QuadMesh).material as StandardMaterial3D
	assert_int(material.render_priority).override_failure_message(
			"the flame does not apply FLAME_RENDER_PRIORITY — the constant is inert and overlay markup draws over fire again"
	).is_equal(BoardOverlays.FLAME_RENDER_PRIORITY)


func test_a_unit_going_down_on_fire_does_not_take_the_flame_with_it() -> void:
	# Reported in play: a unit downed while standing in fire makes that fire vanish for the
	# rest of the turn, returning at the next turn boundary. This isolates WHICH half is
	# wrong — the marker being freed, or the marker still existing and being drawn under the
	# downed sprite (both flame and unit are transparent quads at the same standing point).
	# A held count means the node is alive and it is a render-order question, not a logic one.
	_scene.load_mission(PROLOG)
	await await_idle_frame()
	#
	# NB the reason this still holds CHANGED with #231. It used to be true by construction
	# — nothing freed a marker between turn boundaries. Now the reconcile runs every frame,
	# and it holds because a downing alters no terrain state, so the cell stays in
	# burning_cells and its marker is left standing. That is a weaker guarantee, which is
	# why test_a_standing_flame_survives_a_reconcile_that_lights_another exists beside it.
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var burning := _burning()
	assert_bool(not burning.is_empty()).override_failure_message(
			"Prolog authored no fire; the case is vacuous").is_true()
	var fire_cell: Vector2i = burning[0]

	var unit: Unit = null
	for child in _game.units_root.get_children():
		var candidate := child as Unit
		if candidate != null:
			unit = candidate
			break
	assert_object(unit).is_not_null()
	unit.movement.set_cell(fire_cell)   # teleport onto the burning tile
	await await_idle_frame()
	var before := mirror.fire_marker_count()
	assert_int(before).override_failure_message("no flame to lose; the case is vacuous").is_greater(0)

	unit._go_downed(false)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(mirror.fire_marker_count()).override_failure_message(
			"the flame marker was FREED when the unit went down").is_equal(before)


func test_rebuild_tracks_the_authority_after_clear_board() -> void:
	_scene.load_mission(PROLOG)
	await await_idle_frame()
	_game.scenario_manager.clear_board()
	# clear_board detaches units then queue_frees them ("same-frame respawns don't
	# see dying units") — flush the deferred deletions or they read as orphans.
	await await_idle_frame()
	_scene.rebuild()
	var board := _scene.get_node("Board") as GridMap
	# clear_board deliberately leaves TERRAIN painted (the pieces clear, the map
	# stays — sandbox behavior). The mirror's contract is parity with the
	# authority, whatever the authority does — never an assumption of emptiness.
	assert_int(board.get_used_cells().size()).is_equal(_game.grid.get_used_cells().size())
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	assert_int(mirror.fire_marker_count()).is_equal(_burning().size())


# --- Live mirroring (#231) -------------------------------------------------------

func _settle() -> void:
	# process_frame resumes coroutines BEFORE node _process — one frame reads stale.
	await await_idle_frame()
	await await_idle_frame()


func test_a_standing_flame_survives_a_reconcile_that_lights_another() -> void:
	# fire_marker_count() is BLIND to churn: free-all-and-recreate reads identical through
	# it, so node identity is the only thing that can tell a reconcile from a rebuild.
	#
	# The change of state is load-bearing, and its absence made an earlier version of this
	# case VACUOUS — it passed against the free-all mutant. OverlayMirror value-diffs the
	# burning set before pushing, so with a static board refresh_states is never called
	# twice and nothing gets the chance to churn. Only a reconcile that actually RUNS,
	# while an unrelated cell keeps burning, can distinguish the two.
	_scene.load_mission(PROLOG)
	await _settle()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var burning := _burning()
	assert_bool(not burning.is_empty()).override_failure_message(
			"Prolog authored no fire; the case is vacuous").is_true()
	var standing: Vector2i = burning[0]
	var id := mirror.fire_marker_at(standing).get_instance_id()

	var effect := ResolvedCellEffect.new()
	effect.cell = _a_cell_that_is_not_burning()
	effect.states_added.assign([Terrain.TileState.BLAZE])
	_game.terrain_states.apply(effect)
	await _settle()
	assert_object(mirror.fire_marker_at(effect.cell)).override_failure_message(
			"the reconcile never ran; the case proves nothing").is_not_null()
	assert_int(mirror.fire_marker_at(standing).get_instance_id()).override_failure_message(
			"an untouched flame was rebuilt rather than left standing").is_equal(id)


func test_fire_lit_mid_turn_appears_without_a_turn_boundary() -> void:
	# The retirement of the v1 approximation: an ignition used to wait for turn_started.
	# Deposited through terrain_states.apply — the sim's OWN seam, not a dev-only path.
	_scene.load_mission(PROLOG)
	await _settle()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var before := mirror.fire_marker_count()
	var cell := _a_cell_that_is_not_burning()
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BLAZE])
	_game.terrain_states.apply(effect)
	await _settle()
	assert_int(mirror.fire_marker_count()).override_failure_message(
			"a mid-turn ignition did not reach the diorama").is_equal(before + 1)
	assert_object(mirror.fire_marker_at(cell)).is_not_null()


func test_fire_going_out_frees_its_marker() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var burning := _burning()
	assert_bool(not burning.is_empty()).override_failure_message(
			"Prolog authored no fire; the case is vacuous").is_true()
	var cell: Vector2i = burning[0]
	var before := mirror.fire_marker_count()
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_removed.assign(_game.terrain_states.states_at(cell))
	_game.terrain_states.apply(effect)
	await _settle()
	assert_int(mirror.fire_marker_count()).is_equal(before - 1)
	assert_object(mirror.fire_marker_at(cell)).override_failure_message(
			"the reconcile adds but never removes").is_null()


func _a_cell_that_is_not_burning() -> Vector2i:
	var burning := _burning()
	for cell: Vector2i in _game.grid.get_used_cells():
		if not burning.has(cell):
			return cell
	return Vector2i.ZERO


func test_a_live_terrain_paint_reaches_the_3d_board_per_cell() -> void:
	# The WIRE case: it writes through game.grid and never calls sync() itself, so a
	# mirror that only works when a test drives it by hand goes red here.
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var board := _scene.get_node("Board") as GridMap
	var cell: Vector2i = _game.grid.get_used_cells()[0]
	var at := BoardSpace.of_cell(cell, 0)
	var before := board.get_cell_item(at)
	var other := _a_tile_of_a_different_kind(cell)
	assert_bool(other.source >= 0).override_failure_message(
			"the tileset offers no second kind; the case is vacuous").is_true()
	_game.grid.set_cell(cell, other.source, other.coords)
	await _settle()
	var after := board.get_cell_item(at)
	assert_int(after).override_failure_message("the paint never reached the 3D board").is_not_equal(before)
	assert_str(board.mesh_library.get_item_name(after)).is_equal(
			BoardMirror.tile_item_name(other.source, other.coords))


func test_an_erased_cell_leaves_a_hole_in_the_3d_board() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var board := _scene.get_node("Board") as GridMap
	var cell: Vector2i = _game.grid.get_used_cells()[0]
	var at := BoardSpace.of_cell(cell, 0)
	assert_int(board.get_cell_item(at)).is_not_equal(GridMap.INVALID_CELL_ITEM)
	_game.grid.erase_cell(cell)
	await _settle()
	assert_int(board.get_cell_item(at)).override_failure_message(
			"sync paints but never erases").is_equal(GridMap.INVALID_CELL_ITEM)


func test_a_drag_of_paints_inside_one_frame_costs_one_sync_pass() -> void:
	# The falsifiable form of "coalesced": per-event syncing would cost N.
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var cells: Array[Vector2i] = _game.grid.get_used_cells()
	var before := mirror.sync_passes
	for i in 8:
		_game.grid.erase_cell(cells[i])
	await await_idle_frame()
	var spent := mirror.sync_passes - before
	assert_int(spent).override_failure_message(
			"8 writes in one frame cost %s sync passes" % spent).is_less_equal(2)


func _a_tile_of_a_different_kind(cell: Vector2i) -> Dictionary:
	var current := GridUtils.get_terrain_kind_at_cell(_game.grid, cell)
	var tiles: TileSet = _game.grid.tile_set
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			var data := source.get_tile_data(coords, 0)
			if data == null or not data.has_custom_data("terrain_type"):
				continue
			var kind: int = data.get_custom_data("terrain_type")
			if kind != current and kind != Terrain.Kind.NONE:
				return {"source": source_id, "coords": coords}
	return {"source": -1, "coords": Vector2i.ZERO}


# --- #250: the SURFACE question -------------------------------------------------------------

# Every single-cell tile the tileset declares, in atlas order. The completeness cases and the
# fallback case all need to walk the real tileset rather than name coordinates that an atlas
# swap would invalidate.
func _declared_tiles(multi_cell: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tiles: TileSet = _game.grid.tile_set
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			var is_multi := source.get_tile_size_in_atlas(coords) != Vector2i.ONE
			if is_multi == multi_cell:
				out.append({"source": source_id, "coords": coords})
	return out


# THE case #250 exists for. Four grass variants are one Terrain.Kind, so a board keyed on kind
# renders them as one repeated block — which is what the 3D did for every board ever loaded.
# Nothing else in this suite can see it: kind-keyed and atlas-keyed agree on every assertion
# that only ever looks at one tile per kind.
func test_two_tiles_of_one_kind_render_as_two_different_blocks() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var pair := _two_tiles_sharing_a_kind()
	assert_bool(not pair.is_empty()).override_failure_message(
			"the tileset has no kind with two single-cell tiles; the case is vacuous").is_true()

	var board := _scene.get_node("Board") as GridMap
	var cells: Array[Vector2i] = _game.grid.get_used_cells()
	var a: Vector2i = cells[0]
	var b: Vector2i = cells[1]
	_game.grid.set_cell(a, pair[0].source, pair[0].coords)
	_game.grid.set_cell(b, pair[1].source, pair[1].coords)
	await _settle()

	var item_a := board.get_cell_item(BoardSpace.of_cell(a, 0))
	var item_b := board.get_cell_item(BoardSpace.of_cell(b, 0))
	assert_int(item_a).override_failure_message(
			"two tiles of the same kind (%s and %s) render as the SAME block — the board is still keyed on Kind" \
			% [pair[0].coords, pair[1].coords]).is_not_equal(item_b)


# Two single-cell tiles that share a Terrain.Kind, or [] if the tileset offers none.
func _two_tiles_sharing_a_kind() -> Array[Dictionary]:
	var by_kind: Dictionary[int, Array] = {}
	var tiles: TileSet = _game.grid.tile_set
	for entry in _declared_tiles(false):
		var source := tiles.get_source(entry.source) as TileSetAtlasSource
		var kind := GridUtils.terrain_kind_of(source.get_tile_data(entry.coords, 0))
		if kind == Terrain.Kind.NONE:
			continue
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append(entry)
		if by_kind[kind].size() == 2:
			return [by_kind[kind][0], by_kind[kind][1]]
	return []


# Law-style, beside test_every_kind_is_mapped_or_declared_skip: the generated meshlib must cover
# every single-cell tile the brush can paint. A tile with no block of its own is not broken —
# it falls back — but it is silently back to kind-keyed rendering, which is the bug this closes.
func test_every_single_cell_tile_has_a_block_of_its_own() -> void:
	var board := _scene.get_node("Board") as GridMap
	var library := board.mesh_library
	var missing: PackedStringArray = []
	for entry in _declared_tiles(false):
		var wanted := BoardMirror.tile_item_name(entry.source, entry.coords)
		if library.find_item_by_name(wanted) < 0:
			missing.append(wanted)
	assert_int(missing.size()).override_failure_message(
			"%d declared tiles have no block: %s — rerun tools/lookdev/gen_lookdev_assets.gd --meshlib" \
			% [missing.size(), ", ".join(missing)]).is_equal(0)


# The declared fallback, and the one thing it must never do. A multi-cell tile is skipped by the
# generator on purpose (its art is taller than a cell and would squash onto a 1x1 top face), so
# it lands on its Kind block — NOT on INVALID_CELL_ITEM, which would be a hole in the board where
# the 2D shows a tile.
func test_a_tile_with_no_block_of_its_own_falls_back_to_its_kind() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var multi := _declared_tiles(true)
	assert_bool(not multi.is_empty()).override_failure_message(
			"the tileset declares no multi-cell tile; the case is vacuous").is_true()

	var board := _scene.get_node("Board") as GridMap
	var cell: Vector2i = _game.grid.get_used_cells()[0]
	var entry: Dictionary = multi[0]
	_game.grid.set_cell(cell, entry.source, entry.coords)
	await _settle()

	var item := board.get_cell_item(BoardSpace.of_cell(cell, 0))
	assert_int(item).override_failure_message(
			"a skipped tile left the cell EMPTY — the 2D paints a tile there and the 3D shows a hole" \
			).is_not_equal(GridMap.INVALID_CELL_ITEM)
	var kind := GridUtils.get_terrain_kind_at_cell(_game.grid, cell)
	assert_int(item).is_equal(BoardMirror.KIND_TO_ITEM.get(kind, BoardMirror.FALLBACK_ITEM))


# --- #255: props stand up --------------------------------------------------------------------

# Tiles carrying stands_up (or not), in atlas order. Derived from the tileset so an atlas swap
# cannot invalidate a hardcoded coordinate.
func _tiles_that_stand(standing: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tiles: TileSet = _game.grid.tile_set
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			if GridUtils.stands_up_of(source.get_tile_data(coords, 0)) == standing:
				out.append({"source": source_id, "coords": coords})
	return out


# Tiles carrying one specific shape, in atlas order. The shape-blind _tiles_that_stand above stays
# for the cases that only care WHETHER a tile stands; a case asserting HOW it is built must name
# the shape, or it silently depends on which tile the atlas happens to list first.
func _tiles_with_shape(shape: GridUtils.PropShape) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tiles: TileSet = _game.grid.tile_set
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			if GridUtils.prop_shape_of(source.get_tile_data(coords, 0)) == shape:
				out.append({"source": source_id, "coords": coords})
	return out


func _tile_named(name: String) -> Dictionary:
	var tiles: TileSet = _game.grid.tile_set
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			if GridUtils.authored_tile_display_name(source.get_tile_data(coords, 0)) == name:
				return {"source": source_id, "coords": coords}
	return {}


func _light_under(node: Node3D) -> OmniLight3D:
	for child in node.get_children():
		var light := child as OmniLight3D
		if light != null:
			return light
	return null


# THE case #255 exists for. Before it, a tree was painted flat into the ground it should be
# standing on; the fix is only real if a stands_up tile produces a standing node and a ground
# tile produces none — the second half matters as much, or "props stand up" degenerates into
# "everything stands up".
func test_a_standing_tile_stands_up_and_a_ground_tile_does_not() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var standing := _tiles_that_stand(true)
	var flat := _tiles_that_stand(false)
	assert_bool(not standing.is_empty()).override_failure_message(
			"no tile carries stands_up; the case is vacuous").is_true()

	var cells: Array[Vector2i] = _game.grid.get_used_cells()
	var prop_cell: Vector2i = cells[0]
	var ground_cell: Vector2i = cells[1]
	_game.grid.set_cell(prop_cell, standing[0].source, standing[0].coords)
	_game.grid.set_cell(ground_cell, flat[0].source, flat[0].coords)
	await _settle()

	assert_object(mirror.prop_at(prop_cell)).override_failure_message(
			"a stands_up tile did not stand up — it is still painted flat into the ground").is_not_null()
	assert_object(mirror.prop_at(ground_cell)).override_failure_message(
			"a GROUND tile stood up; stands_up is not being read").is_null()


# The other half of standing up: the cell's top face must go back to being ground, or the tree
# renders twice — once flat under itself and once standing. Asserted against the SOURCE atlas
# rather than against a colour: a prop's baked region must DIFFER from its art (the art was left
# off), while an opaque ground tile's must match it exactly (nothing was left off).
func test_a_prop_cell_bakes_ground_not_the_prop() -> void:
	var board := _scene.get_node("Board") as GridMap
	var tiles: TileSet = _game.grid.tile_set
	var source := tiles.get_source(tiles.get_source_id(0)) as TileSetAtlasSource
	var baked := _baked_atlas(board)
	assert_object(baked).override_failure_message("the meshlib carries no baked atlas").is_not_null()
	var art := source.texture.get_image()
	if art.is_compressed():
		art.decompress()

	# The prop must be an OPAQUE one, and that is not a detail — it is the whole reason this case
	# has teeth. The art is BLENDED over the kind base, so wherever the art is transparent the bake
	# shows the base through it and the regions differ no matter what. A 43%-open tile (Tree, which
	# this case used until #264) therefore cannot match its art even when the bug is present:
	# measured by falsification, a mutant that baked every prop's art passed against it. Picking the
	# most opaque standing tile off the tileset keeps that true through an atlas swap.
	var prop := _most_opaque_standing_tile(source, art)
	assert_bool(not prop.is_empty()).override_failure_message("no standing tile; the case is vacuous").is_true()
	assert_int(prop.clear).override_failure_message(
			"the most opaque standing tile still has %s see-through pixels — this case cannot tell a " \
			% [prop.clear] + "baked prop from a based one, and would pass against the bug").is_equal(0)
	assert_bool(_regions_match(baked, art, source.get_tile_texture_region(prop.coords, 0))) \
			.override_failure_message("the prop's own art is baked onto its top face — it will render twice") \
			.is_false()

	var ground := _tile_named("Grass Basic")
	assert_bool(not ground.is_empty()).override_failure_message("no grass tile; the case is vacuous").is_true()
	assert_bool(_regions_match(baked, art, source.get_tile_texture_region(ground.coords, 0))) \
			.override_failure_message("a GROUND tile lost its art — stands_up is being read too broadly") \
			.is_true()


func _baked_atlas(board: GridMap) -> Image:
	var mesh := board.mesh_library.get_item_mesh(BoardMirror.FALLBACK_ITEM + 4)
	for id: int in board.mesh_library.get_item_list():
		if board.mesh_library.get_item_name(id).begins_with("tile_"):
			mesh = board.mesh_library.get_item_mesh(id)
			break
	var material := mesh.surface_get_material(0) as StandardMaterial3D
	if material == null or material.albedo_texture == null:
		return null
	return material.albedo_texture.get_image()


# The standing tile with the fewest see-through pixels, and how many it has. Measured rather than
# named, so the case above states its own precondition instead of trusting a tile to stay opaque.
func _most_opaque_standing_tile(source: TileSetAtlasSource, art: Image) -> Dictionary:
	var best: Dictionary = {}
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		if source.get_tile_size_in_atlas(coords) != Vector2i.ONE:
			continue
		if not GridUtils.stands_up_of(source.get_tile_data(coords, 0)):
			continue
		var region := source.get_tile_texture_region(coords, 0)
		var clear := 0
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				if art.get_pixel(x, y).a < 1.0:
					clear += 1
		if best.is_empty() or clear < int(best.clear):
			best = {"coords": coords, "clear": clear}
	return best


func _regions_match(a: Image, b: Image, region: Rect2i) -> bool:
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				return false
	return true


# The multi-cell case 5a could not serve: a 1x2 lantern is 16x32 of art, which cannot go onto a
# 1x1 top face un-squashed but is exactly what a billboard is for. Two cells tall, measured in
# world units off the sprite's own density rather than from a pinned number.
func test_the_lantern_stands_two_cells_tall() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var lantern := _tile_named("Lantern")
	assert_bool(not lantern.is_empty()).override_failure_message("no Lantern tile; the case is vacuous").is_true()

	var cell: Vector2i = _game.grid.get_used_cells()[0]
	_game.grid.set_cell(cell, lantern.source, lantern.coords)
	await _settle()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var prop := mirror.prop_at(cell)
	assert_object(prop).override_failure_message("the lantern did not stand up").is_not_null()
	var sprite := prop.get_child(0) as Sprite3D
	assert_object(sprite).is_not_null()
	# TALLER THAN ONE CELL is the property, not exactly two. The point of this case is that
	# multi-cell art survives instead of being cropped onto a 1x1 face — and since the sprite is now
	# planted by its DRAWN pixels rather than by its region, the exact height is the art's, not the
	# region's. Asserted against the art itself so a crop-to-one-cell mutant still reds it.
	var height: float = sprite.texture.region.size.y * sprite.pixel_size
	assert_bool(height > BoardSpace.CELL_SIZE * 1.05).override_failure_message(
			"the lantern stands %s cells tall — its multi-cell art was cropped to a single cell" \
			% [height / BoardSpace.CELL_SIZE]).is_true()
	var source := _game.grid.tile_set.get_source(lantern.source) as TileSetAtlasSource
	var drawn := _opaque_bounds(_readable(source.texture), source.get_tile_texture_region(lantern.coords, 0))
	assert_float(height).override_failure_message(
			"the lantern is %s tall but its art measures %s" \
			% [height, drawn.size.y * sprite.pixel_size]) \
			.is_equal_approx(drawn.size.y * sprite.pixel_size, 0.001)


# The lamp floated for months and nobody could say why: the quad was planted correctly and its ART
# was not. A tile region may carry transparent padding — the lantern's stops 5 rows above its
# region's bottom edge — so planting by the REGION leaves the visible sprite hanging 5/16 of a cell
# in the air. Stated as a property of every billboard rather than as that one measurement.
func test_a_billboard_is_planted_by_its_art_not_by_its_region() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var tiles: TileSet = _game.grid.tile_set
	var cells: Array[Vector2i] = _game.grid.get_used_cells()
	var checked := 0
	for entry in _tiles_with_shape(GridUtils.PropShape.BILLBOARD):
		var cell: Vector2i = cells[checked]
		_game.grid.set_cell(cell, entry.source, entry.coords)
		await _settle()
		var sprite := mirror.prop_at(cell).get_child(0) as Sprite3D
		assert_object(sprite).override_failure_message("a BILLBOARD tile did not build a sprite").is_not_null()
		var source := tiles.get_source(entry.source) as TileSetAtlasSource
		var art := _readable(source.texture)
		var region := Rect2i(sprite.texture.region)
		var drawn := 0
		for x in range(region.position.x, region.end.x):
			if art.get_pixel(x, region.end.y - 1).a >= 0.5:
				drawn += 1
		assert_int(drawn).override_failure_message(
				"'%s' is planted by a rectangle whose bottom row is empty — its art floats above " \
				% [GridUtils.authored_tile_display_name(source.get_tile_data(entry.coords, 0))] \
				+ "the tile instead of standing on it").is_greater(0)
		checked += 1
	assert_int(checked).override_failure_message(
			"no BILLBOARD tiles authored; the case is vacuous").is_greater(0)


func _readable(texture: Texture2D) -> Image:
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	return image


# Test the WIRE: a light table nothing reads looks exactly like a table with no entries. The
# negative half is what gives it teeth — every prop lighting up would also pass the first, so the
# pairing must be two things that BOTH stand up and differ only in whether they glow.
func test_the_lantern_carries_a_light_and_the_tree_does_not() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var lantern := _tile_named("Lantern")
	var tree := _tile_named("Tree")
	assert_bool(not lantern.is_empty() and not tree.is_empty()).override_failure_message(
			"Lantern or Tree missing from the tileset; the case is vacuous").is_true()

	var cells: Array[Vector2i] = _game.grid.get_used_cells()
	_game.grid.set_cell(cells[0], lantern.source, lantern.coords)
	_game.grid.set_cell(cells[1], tree.source, tree.coords)
	await _settle()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	assert_object(_light_under(mirror.prop_at(cells[0]))).override_failure_message(
			"the lantern casts no light — LIT_PROPS is inert").is_not_null()
	assert_object(_light_under(mirror.prop_at(cells[1]))).override_failure_message(
			"the tree casts light — every prop is lit, so the table is not being consulted").is_null()


# A prop REPLACED on a cell must be rebuilt, and a prop merely re-seen must be left standing.
# The second half cannot be seen through prop_count(), which is why the pin is node identity —
# the same lesson the fire markers already carry.
func test_a_prop_is_rebuilt_only_when_its_tile_changes() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var standing := _tiles_that_stand(true)
	assert_bool(standing.size() >= 2).override_failure_message(
			"fewer than two standing tiles; the case is vacuous").is_true()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var cell: Vector2i = _game.grid.get_used_cells()[0]

	_game.grid.set_cell(cell, standing[0].source, standing[0].coords)
	await _settle()
	var first := mirror.prop_at(cell)
	assert_object(first).is_not_null()

	await _settle()   # reconciled again, same tile
	assert_object(mirror.prop_at(cell)).override_failure_message(
			"the prop is rebuilt every frame").is_same(first)

	_game.grid.set_cell(cell, standing[1].source, standing[1].coords)
	await _settle()
	assert_object(mirror.prop_at(cell)).override_failure_message(
			"painting a DIFFERENT prop left the old one standing").is_not_same(first)

	_game.grid.erase_cell(cell)
	await _settle()
	assert_object(mirror.prop_at(cell)).override_failure_message(
			"erasing the tile left its prop standing").is_null()


# Props sort against units by DEPTH, not by a hand-maintained priority — which is only true while
# they write depth. Cut-out alpha in the opaque pass is what buys that, so it is the property
# worth pinning rather than the render layer (nothing culls by layer in this project).
func test_props_write_depth_so_units_sort_against_them() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var standing := _tiles_with_shape(GridUtils.PropShape.BILLBOARD)
	assert_bool(not standing.is_empty()).override_failure_message(
			"no BILLBOARD tile; the case is vacuous").is_true()
	var cell: Vector2i = _game.grid.get_used_cells()[0]
	_game.grid.set_cell(cell, standing[0].source, standing[0].coords)
	await _settle()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var sprite := mirror.prop_at(cell).get_child(0) as Sprite3D
	assert_int(sprite.alpha_cut).override_failure_message(
			"a prop that does not write depth loses its sort against unit sprites" \
			).is_equal(SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS)
	assert_int(sprite.layers).is_equal(BoardOverlays.WORLD_RENDER_LAYER)


# --- #264: solid props get real geometry -----------------------------------------------------

# The DEFAULT is the whole reason a retype from a bool was safe: every tile that was never authored
# has to keep reading as ground. A null TileData is the same question asked from the other end —
# item_for_cell reaches it on an empty cell.
func test_an_unauthored_tile_reads_flat() -> void:
	assert_int(GridUtils.prop_shape_of(null)).override_failure_message(
			"a tile with no data does not read FLAT — empty cells would sprout props" \
			).is_equal(GridUtils.PropShape.FLAT)
	var ground := _tile_named("Grass Basic")
	assert_bool(not ground.is_empty()).override_failure_message("no grass tile; the case is vacuous").is_true()
	var source := _game.grid.tile_set.get_source(ground.source) as TileSetAtlasSource
	assert_int(GridUtils.prop_shape_of(source.get_tile_data(ground.coords, 0))).override_failure_message(
			"an unauthored GROUND tile no longer reads FLAT — the retype changed what it means" \
			).is_equal(GridUtils.PropShape.FLAT)


# THE wire this issue exists for: the authored column has to reach the RENDERER, not merely be
# readable. Both halves matter — a mirror that built geometry for everything would pass the first
# assert alone, and that is exactly the failure #255 shipped in reverse.
func test_a_solid_tile_builds_geometry_and_a_thin_one_builds_a_sprite() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var crate := _tile_named("Crate")
	var tree := _tile_named("Tree")
	assert_bool(not crate.is_empty() and not tree.is_empty()).override_failure_message(
			"Crate or Tree missing from the tileset; the case is vacuous").is_true()

	var cells: Array[Vector2i] = _game.grid.get_used_cells()
	_game.grid.set_cell(cells[0], crate.source, crate.coords)
	_game.grid.set_cell(cells[1], tree.source, tree.coords)
	await _settle()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	assert_object(mirror.prop_at(cells[0]).get_child(0) as MeshInstance3D).override_failure_message(
			"a CUBE tile did not build geometry — it is still the billboard the dev rejected" \
			).is_not_null()
	assert_object(mirror.prop_at(cells[1]).get_child(0) as Sprite3D).override_failure_message(
			"a BILLBOARD tile built geometry — every prop is solid, so the column is not being read" \
			).is_not_null()


# A prop's mesh is sized by its ART's opaque bounds, not by the cell. Measured here from the atlas
# independently rather than read back off the generator, so the case can disagree with it: a rock
# is 32% clear, and a cell-wide box around it would be mostly air. The base sitting at y = 0 is the
# other half — the mesh is planted on the tile's top face, so a centred one would be half buried.
#
# PLANE is excluded, and the exclusion is the rule rather than a concession (#263): a wall is thin BY
# DEFINITION in the axis it does not run along, so a bound measured off its sprite is not what sizes
# it. The half of the rule a plane DOES obey — standing at y = 0 — is asserted in its own case below,
# so nothing is dropped by narrowing this one.
func test_a_prop_block_is_sized_by_its_art_not_by_the_cell() -> void:
	var board := _scene.get_node("Board") as GridMap
	var tiles: TileSet = _game.grid.tile_set
	var checked := 0
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		var art := source.texture.get_image()
		if art.is_compressed():
			art.decompress()
		for entry in _solid_entries(source, source_id):
			var item_name: String = BoardMirror.prop_item_name(source_id, entry.coords)
			var mesh := _mesh_named(board, item_name)
			assert_object(mesh).override_failure_message(
					"no geometry item '%s' — the generator skipped a solid tile" % item_name).is_not_null()
			var bounds := _opaque_bounds(art, source.get_tile_texture_region(entry.coords, 0))
			var aabb := mesh.get_aabb()
			# HEIGHT is the exact one across all three shapes: a prism's cap sits at the full height
			# while its jittered footprint is INSCRIBED in the width, so only the vertical extent is
			# the measurement itself rather than something inside it.
			assert_float(aabb.size.y).override_failure_message(
					"'%s' is %s tall but its art measures %s — the bounds are not being read" \
					% [item_name, aabb.size.y, float(bounds.size.y) / GridUtils.TILE_SIZE]) \
					.is_equal_approx(float(bounds.size.y) / GridUtils.TILE_SIZE, 0.001)
			assert_bool(aabb.size.x <= float(bounds.size.x) / GridUtils.TILE_SIZE + 0.001) \
					.override_failure_message("'%s' is wider than its own art (%s vs %s)" \
					% [item_name, aabb.size.x, float(bounds.size.x) / GridUtils.TILE_SIZE]).is_true()
			assert_float(aabb.position.y).override_failure_message(
					"'%s' starts at y=%s — a prop must stand ON the tile, not sink into it" \
					% [item_name, aabb.position.y]).is_equal_approx(0.0, 0.001)
			checked += 1
	assert_int(checked).override_failure_message(
			"no solid tiles authored; the case is vacuous").is_greater(0)


func _solid_entries(source: TileSetAtlasSource, source_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		if source.get_tile_size_in_atlas(coords) != Vector2i.ONE:
			continue
		var shape := GridUtils.prop_shape_of(source.get_tile_data(coords, 0))
		if shape == GridUtils.PropShape.PLANE:
			continue   # sized by the wall convention, not by its art — see the caller
		if GridUtils.SOLID_SHAPES.has(shape):
			out.append({"source": source_id, "coords": coords})
	return out


func _mesh_named(board: GridMap, item_name: String) -> Mesh:
	for id: int in board.mesh_library.get_item_list():
		if board.mesh_library.get_item_name(id) == item_name:
			return board.mesh_library.get_item_mesh(id)
	return null


# The test's OWN measurement of the art's opaque extent — deliberately a second implementation, so
# the case is evidence about the generator rather than a restatement of it.
func _opaque_bounds(image: Image, region: Rect2i) -> Rect2i:
	var min_p := region.size
	var max_p := Vector2i(-1, -1)
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if image.get_pixel(x, y).a < 0.5:
				continue
			var p := Vector2i(x, y) - region.position
			min_p = Vector2i(mini(min_p.x, p.x), mini(min_p.y, p.y))
			max_p = Vector2i(maxi(max_p.x, p.x), maxi(max_p.y, p.y))
	if max_p.x < 0:
		return Rect2i(Vector2i.ZERO, region.size)
	return Rect2i(min_p, max_p - min_p + Vector2i.ONE)


# --- #274: generated side faces ---------------------------------------------------------------

# THE bug this issue exists for, stated directly. #264 put the whole texture on EVERY facet, because
# that texture was the tile's sprite and a sprite cannot wrap -- so a 10-sided pot rendered as ten
# overlapping copies of itself. Every facet must own a DISTINCT, contiguous, equal slice of the strip.
#
# The facet count is derived from the mesh rather than read from the generator's table: a prism's
# side surface is one 6-vertex quad plus one 3-vertex bottom-cap triangle per facet, so the vertex
# count is 9 per facet. That keeps the case independent of the constant it is checking.
func test_every_facet_of_a_prism_owns_a_distinct_slice_of_its_side_strip() -> void:
	var board := _scene.get_node("Board") as GridMap
	var checked := 0
	for entry in _prism_entries():
		var item_name: String = BoardMirror.prop_item_name(entry.source, entry.coords)
		var mesh := _mesh_named(board, item_name)
		assert_object(mesh).override_failure_message(
				"no geometry item '%s'" % item_name).is_not_null()
		var spans := _facet_spans(mesh)
		assert_bool(spans.size() >= 7).override_failure_message(
				"'%s' reports %d facets; the side surface is not the expected shape" \
				% [item_name, spans.size()]).is_true()

		var texel := 1.0 / _atlas_size(mesh).x
		var width: float = spans[0].y - spans[0].x
		for i in spans.size():
			# Non-overlapping: the whole failure was every facet sharing one span.
			if i > 0:
				assert_bool(spans[i].x >= spans[i - 1].y - texel).override_failure_message(
						"'%s' facets %d and %d overlap (%s vs %s) -- the strip is not being sliced" \
						% [item_name, i - 1, i, spans[i - 1], spans[i]]).is_true()
				# Contiguous: only the two half-texel insets may sit between neighbours.
				assert_bool(spans[i].x - spans[i - 1].y <= texel * 2.0).override_failure_message(
						"'%s' leaves a gap between facets %d and %d" % [item_name, i - 1, i]).is_true()
			# Equal: a wrap that is not evenly divided stretches some facets and squashes others.
			assert_bool(absf((spans[i].y - spans[i].x) - width) <= texel).override_failure_message(
					"'%s' facet %d is %s wide against %s for facet 0" \
					% [item_name, i, spans[i].y - spans[i].x, width]).is_true()
		checked += 1
	assert_int(checked).override_failure_message(
			"no FACETED or ROUND props authored; the case is vacuous").is_greater(0)


# The faces are GENERATED, but their colours are MEASURED -- that is what keeps #274 from
# contradicting #250 (the 3D shows the game's tiles). Every colour a prop wears must be one its own
# sprite contains, within one quantization bucket, since a palette shade is a bucket's mean.
func test_a_generated_face_only_wears_colours_from_its_own_sprite() -> void:
	var board := _scene.get_node("Board") as GridMap
	var tiles: TileSet = _game.grid.tile_set
	var bucket := 1.0 / 32.0   # the generator groups colours at 5 bits per channel
	var checked := 0
	for entry in _prism_entries():
		var source := tiles.get_source(entry.source) as TileSetAtlasSource
		var art := source.texture.get_image()
		if art.is_compressed():
			art.decompress()
		var mesh := _mesh_named(board, BoardMirror.prop_item_name(entry.source, entry.coords))
		var atlas := _baked_atlas(board)
		var spans := _facet_spans(mesh)
		var size := _atlas_size(mesh)
		# Read exactly what the mesh points at: facet 0's own slice, inset a pixel off each edge so
		# the half-texel inset cannot put the sample on a neighbour.
		var from := int(spans[0].x * size.x) + 1
		var to := int(spans[0].y * size.x) - 1
		var rows := _uv_rows(mesh, size)
		var painted := _distinct_colours(atlas, Rect2i(Vector2i(from, rows.x + 1),
				Vector2i(maxi(1, to - from), maxi(1, rows.y - rows.x - 2))))
		var sprite := _distinct_colours(art, source.get_tile_texture_region(entry.coords, 0))
		assert_bool(not painted.is_empty()).override_failure_message("read no generated pixels").is_true()
		for c: Color in painted:
			assert_bool(_nearest_distance(c, sprite) <= bucket).override_failure_message(
					"a generated face wears %s, which is not a colour tile %s contains -- the " \
					% [c, entry.coords] + "palette is not being read off the art").is_true()
		checked += 1
	assert_int(checked).is_greater(0)


func _prism_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tiles: TileSet = _game.grid.tile_set
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			if source.get_tile_size_in_atlas(coords) != Vector2i.ONE:
				continue
			var shape := GridUtils.prop_shape_of(source.get_tile_data(coords, 0))
			if shape == GridUtils.PropShape.FACETED or shape == GridUtils.PropShape.ROUND:
				out.append({"source": source_id, "coords": coords})
	return out


# Each facet's [min u, max u], read off the side surface as the set of DISTINCT triangle u-spans.
#
# Derived rather than counted: a facet is one quad per profile band, so the vertices-per-facet is
# whatever the mesh's silhouette needs and cannot be assumed. What IS structural is that the side
# surface holds facet quads and nothing else — both caps live on the top surface — so every triangle
# spans exactly one facet's slice, and the distinct spans ARE the facets. That keeps the case
# independent of the facet table it exists to check.
func _facet_spans(mesh: Mesh) -> Array[Vector2]:
	var uvs: PackedVector2Array = mesh.surface_get_arrays(1)[Mesh.ARRAY_TEX_UV]
	var spans: Array[Vector2] = []
	for t in uvs.size() / 3:
		var lo := 1.0
		var hi := 0.0
		for k in 3:
			var u := uvs[t * 3 + k].x
			lo = minf(lo, u)
			hi = maxf(hi, u)
		var seen := false
		for s: Vector2 in spans:
			if absf(s.x - lo) < 0.0001 and absf(s.y - hi) < 0.0001:
				seen = true
				break
		if not seen:
			spans.append(Vector2(lo, hi))
	spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return spans


# The vertical extent of the side strip in atlas pixels, taken from the same surface.
func _uv_rows(mesh: Mesh, size: Vector2) -> Vector2i:
	var uvs: PackedVector2Array = mesh.surface_get_arrays(1)[Mesh.ARRAY_TEX_UV]
	var lo := 1.0
	var hi := 0.0
	for uv in uvs:
		lo = minf(lo, uv.y)
		hi = maxf(hi, uv.y)
	return Vector2i(int(lo * size.y), int(hi * size.y))


func _atlas_size(mesh: Mesh) -> Vector2:
	var material := mesh.surface_get_material(1) as StandardMaterial3D
	return Vector2(material.albedo_texture.get_size())


func _distinct_colours(image: Image, region: Rect2i) -> Array[Color]:
	var seen: Dictionary[Color, bool] = {}
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var c := image.get_pixel(x, y)
			if c.a >= 0.5:
				seen[Color(c.r, c.g, c.b)] = true
	return seen.keys()


func _nearest_distance(c: Color, palette: Array[Color]) -> float:
	var best := 1.0
	for p: Color in palette:
		best = minf(best, maxf(absf(c.r - p.r), maxf(absf(c.g - p.g), absf(c.b - p.b))))
	return best


func test_the_flame_never_sits_in_the_ground_plane() -> void:
	# A QuadMesh is centred on its origin, so a 0.7-tall flame lifted 0.35 has its BOTTOM EDGE
	# at exactly y = 0 — coplanar with the tile top face it stands on. Harmless while the
	# flame did not write depth; the worst z-fighting on the board once it did. Clamped in
	# flame_base_lift, so this holds for any authored knob value, including a hostile one.
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	mirror.flame_writes_depth = true
	for lift in [0.0, 0.1, 0.35, 0.4, 2.0]:
		mirror.flame_lift = lift
		var bottom: float = mirror.flame_base_lift() - mirror.flame_size.y * 0.5
		assert_float(bottom).override_failure_message(
				"flame_lift %s puts the flame's bottom edge at %s — in/through the ground plane" \
				% [lift, bottom]).is_greater_equal(mirror.flame_ground_gap)
	# Non-vacuous: the clamp is doing work at the authored default, not just at absurd values.
	mirror.flame_lift = 0.35
	assert_float(mirror.flame_base_lift()).override_failure_message(
			"the clamp is inert at the value that caused the bug").is_greater(0.35)

	# ...and with depth off — the shipped default — the authored lift stands untouched, so
	# the flame renders exactly as it did before #236 rather than approximately.
	mirror.flame_writes_depth = false
	assert_float(mirror.flame_base_lift()).override_failure_message(
			"the clamp moved the flame even with depth-write off, so the revert is not exact" \
			).is_equal_approx(0.35, 0.0001)


# --- Elevation (#273) --------------------------------------------------------------

# All three drive the AUTHORITY (game.board_heights) and never call sync() themselves — the same
# rule the #231 live cases follow, so a mirror that only works when a test pokes it goes red.

func test_a_raised_cell_fills_its_whole_column() -> void:
	# A terrace is a slab with a FACE, not a floating tile: the surface block repeats down to the
	# floor. A mirror that writes only the top leaves the board hovering.
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var board := _scene.get_node("Board") as GridMap
	var cell: Vector2i = _game.grid.get_used_cells()[0]
	var surface := board.get_cell_item(BoardSpace.of_cell(cell, 0))

	_game.board_heights.set_cell(cell, 2, Terrain.RampRise.NONE)
	await _settle()

	for level in [0, 1, 2]:
		assert_int(board.get_cell_item(BoardSpace.of_cell(cell, level))) \
			.override_failure_message("level %d of the column is missing" % level) \
			.is_equal(surface)
	assert_int(board.get_cell_item(BoardSpace.of_cell(cell, 3))) \
		.override_failure_message("the column runs past the level it was painted at") \
		.is_equal(GridMap.INVALID_CELL_ITEM)


func test_lowering_a_cell_clears_the_column_it_used_to_fill() -> void:
	# The stranding case: a 3-level cut leaves 3 orphans if the erase assumes one stale block.
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var board := _scene.get_node("Board") as GridMap
	var cell: Vector2i = _game.grid.get_used_cells()[0]
	_game.board_heights.set_cell(cell, 3, Terrain.RampRise.NONE)
	await _settle()

	_game.board_heights.set_cell(cell, 0, Terrain.RampRise.NONE)
	await _settle()

	for level in [1, 2, 3]:
		assert_int(board.get_cell_item(BoardSpace.of_cell(cell, level))) \
			.override_failure_message("level %d survived the cut" % level) \
			.is_equal(GridMap.INVALID_CELL_ITEM)


func test_a_ramp_puts_its_wedge_one_level_above_its_own() -> void:
	# The off-by-one that is INVISIBLE on a flat board: a level-E block occupies [E..E+1], so E's
	# surface is E+1 and a ramp whose elevation is its LOW side must slope from E+1 to E+2.
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var board := _scene.get_node("Board") as GridMap
	var mirror: BoardMirror = _scene._board_mirror
	var cell: Vector2i = _game.grid.get_used_cells()[0]

	_game.board_heights.set_cell(cell, 1, Terrain.RampRise.NORTH)
	await _settle()

	assert_int(mirror.ramp_item()).override_failure_message(
			"the meshlib has no '%s'; the case is vacuous" % BoardMirror.RAMP_ITEM_NAME) \
		.is_not_equal(GridMap.INVALID_CELL_ITEM)
	assert_int(board.get_cell_item(BoardSpace.of_cell(cell, 2))) \
		.override_failure_message("the wedge is not one level above the ramp's own") \
		.is_equal(mirror.ramp_item())


func test_each_rise_points_the_wedges_high_side_the_way_it_names() -> void:
	# The orientation is DERIVED from Terrain.rise_direction, so this asserts the GEOMETRY rather
	# than a magic orthogonal index: rotating the authored wedge's high side by the basis the
	# mirror chose must land on the direction the rise names.
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var board := _scene.get_node("Board") as GridMap
	var cell: Vector2i = _game.grid.get_used_cells()[0]

	for rise: Terrain.RampRise in [Terrain.RampRise.NORTH, Terrain.RampRise.EAST,
			Terrain.RampRise.SOUTH, Terrain.RampRise.WEST]:
		_game.board_heights.set_cell(cell, 0, rise)
		await _settle()
		var basis := board.get_cell_item_basis(BoardSpace.of_cell(cell, 1))
		var high := basis * BoardMirror.RAMP_MESH_HIGH_SIDE
		var want := Terrain.rise_direction(rise)
		assert_float(high.x).override_failure_message(
			"%s rises the wrong way on X" % Terrain.ramp_rise_display_name(rise)) \
			.is_equal_approx(float(want.x), 0.01)
		assert_float(high.z).override_failure_message(
			"%s rises the wrong way on Z" % Terrain.ramp_rise_display_name(rise)) \
			.is_equal_approx(float(want.y), 0.01)


# --- #263: oriented planes ---------------------------------------------------------------------

# Every tile authored PLANE in this atlas, with the mask it carries. A content law's input, so it is
# read off the tileset rather than listed here — the point is that an ATLAS SWAP cannot slip a
# directionless plane past the cases below.
func _plane_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tiles: TileSet = _game.grid.tile_set
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			var data := source.get_tile_data(coords, 0)
			if GridUtils.prop_shape_of(data) != GridUtils.PropShape.PLANE:
				continue
			out.append({"source": source_id, "coords": coords,
					"edges": GridUtils.wall_edges_of(data),
					"name": GridUtils.authored_tile_display_name(data)})
	return out


# A PLANE is real geometry, not the billboard #255 shipped and the dev rejected: *"the fences don't
# work at all."* The mirror needs no code of its own for this — the generator bakes each piece's
# orientation into that tile's mesh — so what this really pins is that PLANE reaches _make_prop_block
# rather than falling through to the sprite branch.
func test_a_plane_tile_builds_geometry_not_a_billboard() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var planes := _plane_entries()
	assert_bool(not planes.is_empty()).override_failure_message(
			"no PLANE tiles authored; the case is vacuous").is_true()

	var cell: Vector2i = _game.grid.get_used_cells()[0]
	_game.grid.set_cell(cell, planes[0].source, planes[0].coords)
	await _settle()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var prop := mirror.prop_at(cell)
	assert_object(prop).override_failure_message("a PLANE tile did not stand up").is_not_null()
	assert_object(prop.get_child(0) as MeshInstance3D).override_failure_message(
			"a PLANE tile built a sprite — it is still the billboard a camera turns to face" \
			).is_not_null()


# THE case #263 exists for, in the issue's own words: *a horizontal run and a vertical run must be
# visibly different.* A billboard cannot satisfy this from any angle, which is the whole ticket.
#
# Asserted as a RELATIONSHIP between each piece's authored mask and its geometry, never against a
# measured extent: a wall is thin across the axis it does not run along, so an east-west piece is thin
# in Z and a north-south one is thin in X. Nothing here pins PLANE_THICKNESS, so the dev can retune
# the look without reddening it — only IGNORING the mask reddens it.
func test_a_plane_is_thin_across_the_axis_it_runs_along() -> void:
	var board := _scene.get_node("Board") as GridMap
	var checked := 0
	for entry in _plane_entries():
		var item_name: String = BoardMirror.prop_item_name(entry.source, entry.coords)
		var mesh := _mesh_named(board, item_name)
		assert_object(mesh).override_failure_message(
				"no geometry item '%s' — the generator skipped a PLANE tile" % item_name).is_not_null()
		var size := mesh.get_aabb().size
		var runs_ew: bool = (entry.edges & GridUtils.EW_EDGES) != 0
		var runs_ns: bool = (entry.edges & GridUtils.NS_EDGES) != 0
		if runs_ew and not runs_ns:
			assert_bool(size.x > size.z).override_failure_message(
					"'%s' runs east-west but is not wider than it is deep (%s)" \
					% [entry.name, size]).is_true()
		elif runs_ns and not runs_ew:
			assert_bool(size.z > size.x).override_failure_message(
					"'%s' runs north-south but is not deeper than it is wide (%s)" \
					% [entry.name, size]).is_true()
		else:
			# A corner runs BOTH ways, so it is thin in neither — that is what makes it an L rather
			# than a wall, and it is the clause a "treat every plane as one axis" mutant cannot meet.
			assert_bool(absf(size.x - size.z) < 0.001).override_failure_message(
					"'%s' is a corner but reaches further one way than the other (%s)" \
					% [entry.name, size]).is_true()
		# The half of the block rule a plane still obeys: it stands ON the tile, never sunk into it.
		assert_float(mesh.get_aabb().position.y).override_failure_message(
				"'%s' starts at y=%s — a wall must stand on the tile" \
				% [entry.name, mesh.get_aabb().position.y]).is_equal_approx(0.0, 0.001)
		checked += 1
	assert_int(checked).override_failure_message(
			"no PLANE tiles authored; the case is vacuous").is_greater(0)


# The two straight runs must differ from EACH OTHER, not merely each match its own mask. Stated
# separately because the case above is satisfied by any consistent rule — including one that reads the
# mask and then builds every piece the same way, which is precisely the bug a billboard has.
func test_a_horizontal_run_and_a_vertical_run_are_different_meshes() -> void:
	var board := _scene.get_node("Board") as GridMap
	var ew: Array[Vector3] = []
	var ns: Array[Vector3] = []
	for entry in _plane_entries():
		var mesh := _mesh_named(board, BoardMirror.prop_item_name(entry.source, entry.coords))
		if mesh == null:
			continue
		if entry.edges == GridUtils.EW_EDGES:
			ew.append(mesh.get_aabb().size)
		elif entry.edges == GridUtils.NS_EDGES:
			ns.append(mesh.get_aabb().size)
	assert_bool(not ew.is_empty() and not ns.is_empty()).override_failure_message(
			"the atlas has no straight run in both axes; the case is vacuous").is_true()
	assert_bool(absf(ew[0].x - ns[0].x) > 0.001).override_failure_message(
			"a horizontal run and a vertical one measure the same (%s vs %s) — they read identically " \
			% [ew[0], ns[0]] + "from every angle, which is the billboard behaviour #263 replaces").is_true()


# A content law over the tileset (#263). A PLANE with no authored edges has no geometry to build, and
# the generator refuses it loudly — but a refusal at generate time is only a backstop, and the sheet
# itself is where the mistake would be made. The non-empty guard is load-bearing, not decoration: the
# loop passes over zero tiles otherwise.
func test_every_plane_tile_declares_which_way_it_runs() -> void:
	var checked := 0
	for entry in _plane_entries():
		assert_int(entry.edges).override_failure_message(
				"'%s' is a PLANE with no wall_edges — it declares a form but not a facing, so nothing " \
				% [entry.name] + "can say which way it points").is_greater(0)
		checked += 1
	assert_int(checked).override_failure_message(
			"no PLANE tiles authored; the case is vacuous").is_greater(0)
