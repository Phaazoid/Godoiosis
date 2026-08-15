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
	var at := BoardSpace.of_flat(cell)
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
	var at := BoardSpace.of_flat(cell)
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

	var item_a := board.get_cell_item(BoardSpace.of_flat(a))
	var item_b := board.get_cell_item(BoardSpace.of_flat(b))
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

	var item := board.get_cell_item(BoardSpace.of_flat(cell))
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

	var prop := _tile_named("Rock")
	assert_bool(not prop.is_empty()).override_failure_message("no Rock tile; the case is vacuous").is_true()
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
	var height: float = sprite.texture.region.size.y * sprite.pixel_size
	assert_float(height).override_failure_message(
			"the lantern stands %s cells tall, not 2 — its multi-cell art was cropped" \
			% [height / BoardSpace.CELL_SIZE]).is_equal_approx(2.0 * BoardSpace.CELL_SIZE, 0.001)


# Test the WIRE: a light table nothing reads looks exactly like a table with no entries. The
# negative half is what gives it teeth — every prop lighting up would also pass the first.
func test_the_lantern_carries_a_light_and_the_crate_does_not() -> void:
	_scene.load_mission(PROLOG)
	await _settle()
	_game.game_state = _game.GameState.DEV_MODE
	var lantern := _tile_named("Lantern")
	var crate := _tile_named("Crate")
	assert_bool(not lantern.is_empty() and not crate.is_empty()).override_failure_message(
			"Lantern or Crate missing from the tileset; the case is vacuous").is_true()

	var cells: Array[Vector2i] = _game.grid.get_used_cells()
	_game.grid.set_cell(cells[0], lantern.source, lantern.coords)
	_game.grid.set_cell(cells[1], crate.source, crate.coords)
	await _settle()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	assert_object(_light_under(mirror.prop_at(cells[0]))).override_failure_message(
			"the lantern casts no light — LIT_PROPS is inert").is_not_null()
	assert_object(_light_under(mirror.prop_at(cells[1]))).override_failure_message(
			"the crate casts light — every prop is lit, so the table is not being consulted").is_null()


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
	var standing := _tiles_that_stand(true)
	var cell: Vector2i = _game.grid.get_used_cells()[0]
	_game.grid.set_cell(cell, standing[0].source, standing[0].coords)
	await _settle()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var sprite := mirror.prop_at(cell).get_child(0) as Sprite3D
	assert_int(sprite.alpha_cut).override_failure_message(
			"a prop that does not write depth loses its sort against unit sprites" \
			).is_equal(SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS)
	assert_int(sprite.layers).is_equal(BoardOverlays.WORLD_RENDER_LAYER)


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
