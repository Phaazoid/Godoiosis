# #50 burnout: a BURNING tile goes out after STATE_DURATIONS ticks. tick_states runs once per turn
# cycle (TurnManager.round_completed); spreading/other elements are a later PR. Pure store, headless.
extends GdUnitTestSuite

const BURN_CELL := Vector2i(1, 0)

func _ignite(tsm: TerrainStateManager, cell: Vector2i) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BURNING])
	tsm.apply(effect)

func test_burning_clears_after_three_ticks() -> void:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	_ignite(tsm, BURN_CELL)
	assert_bool(tsm.has_state(BURN_CELL, Terrain.TileState.BURNING)).is_true()
	tsm.tick_states()  # 3 -> 2
	tsm.tick_states()  # 2 -> 1
	assert_bool(tsm.has_state(BURN_CELL, Terrain.TileState.BURNING)).is_true()
	tsm.tick_states()  # 1 -> 0 -> out
	assert_bool(tsm.has_state(BURN_CELL, Terrain.TileState.BURNING)).is_false()

func test_reigniting_resets_the_timer() -> void:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	_ignite(tsm, BURN_CELL)
	tsm.tick_states()  # 3 -> 2
	tsm.tick_states()  # 2 -> 1
	_ignite(tsm, BURN_CELL)  # restoked -> back to 3
	tsm.tick_states()  # 3 -> 2
	tsm.tick_states()  # 2 -> 1
	assert_bool(tsm.has_state(BURN_CELL, Terrain.TileState.BURNING)).is_true()

func test_loaded_burning_tile_gets_a_fresh_timer() -> void:
	# Persistence carries WHICH tiles burn, not the exact countdown -> a loaded fire restarts at full.
	var src: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(src)
	_ignite(src, BURN_CELL)
	src.tick_states()  # partway down on the source

	var dst: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(dst)
	dst.load_state_dict(src.to_state_dict())
	dst.tick_states()
	dst.tick_states()
	assert_bool(dst.has_state(BURN_CELL, Terrain.TileState.BURNING)).is_true()
	dst.tick_states()
	assert_bool(dst.has_state(BURN_CELL, Terrain.TileState.BURNING)).is_false()
