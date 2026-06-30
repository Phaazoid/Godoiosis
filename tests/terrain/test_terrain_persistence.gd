# #50 persistence: deposited tile states (BURNING, ...) survive a ScenarioData round-trip -- the
# data half of save/load + F2 reset. Static terrain TYPES already ride grid.tile_map_data; this
# covers the dynamic states TerrainStateManager holds.
extends GdUnitTestSuite

const ROUNDTRIP_PATH := "user://test_terrain_persistence.tres"

func after_test() -> void:
	if FileAccess.file_exists(ROUNDTRIP_PATH):
		DirAccess.remove_absolute(ROUNDTRIP_PATH)

func _ignite(tsm: TerrainStateManager, cell: Vector2i) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BURNING])
	tsm.apply(effect)

func test_state_dict_round_trips_in_memory() -> void:
	var src: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(src)
	_ignite(src, Vector2i(1, 0))
	_ignite(src, Vector2i(4, 2))

	var dst: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(dst)
	dst.load_state_dict(src.to_state_dict())

	assert_bool(dst.has_state(Vector2i(1, 0), Terrain.TileState.BURNING)).is_true()
	assert_bool(dst.has_state(Vector2i(4, 2), Terrain.TileState.BURNING)).is_true()
	assert_int(dst.cells_with(Terrain.TileState.BURNING).size()).is_equal(2)

func test_state_dict_survives_a_resource_save() -> void:
	var src: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(src)
	_ignite(src, Vector2i(3, 5))

	var scenario := ScenarioData.new()
	scenario.terrain_states = src.to_state_dict()
	assert_int(ResourceSaver.save(scenario, ROUNDTRIP_PATH)).is_equal(OK)

	var loaded: ScenarioData = ResourceLoader.load(ROUNDTRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var restored: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(restored)
	restored.load_state_dict(loaded.terrain_states)

	assert_bool(restored.has_state(Vector2i(3, 5), Terrain.TileState.BURNING)).is_true()
	assert_int(restored.cells_with(Terrain.TileState.BURNING).size()).is_equal(1)

func test_empty_load_clears_existing_states() -> void:
	# A scenario with no deposits (or an old save predating the field) loads as {} -> clears.
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	_ignite(tsm, Vector2i(2, 2))
	tsm.load_state_dict({})
	assert_int(tsm.cells_with(Terrain.TileState.BURNING).size()).is_equal(0)
