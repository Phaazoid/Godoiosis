# BLAZE (#174): authored set-dressing fire -- BURNING's permanent sibling. No STATE_DURATIONS
# entry, so it never ticks out and a LOAD arms no clock (the two-state answer to "authored fire
# burns out"). "Is this tile on fire?" has one spelling: Terrain.FIRE_STATES / is_burning /
# TerrainStateManager.burning_cells -- and a cell legally holding BOTH fire states burns ONCE.
# Tick counts derive from STATE_DURATIONS, never a literal (the tuning-value law).
extends GdUnitTestSuite

const CELL := Vector2i(1, 0)
const BURN_TICKS: int = TerrainStateManager.STATE_DURATIONS[Terrain.TileState.BURNING]

func _deposit(tsm: TerrainStateManager, cell: Vector2i, state: Terrain.TileState) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([state])
	tsm.apply(effect)

func test_blaze_never_ticks_out() -> void:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	_deposit(tsm, CELL, Terrain.TileState.BLAZE)
	for _i in range(BURN_TICKS * 2):
		tsm.tick_states()
	assert_bool(tsm.has_state(CELL, Terrain.TileState.BLAZE)).is_true()

func test_a_loaded_blaze_arms_no_clock() -> void:
	# The contrast case to test_burnout's loaded-BURNING-gets-a-fresh-timer: no timer exists to arm.
	var src: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(src)
	_deposit(src, CELL, Terrain.TileState.BLAZE)

	var dst: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(dst)
	dst.load_state_dict(src.to_state_dict())
	for _i in range(BURN_TICKS * 2):
		dst.tick_states()
	assert_bool(dst.has_state(CELL, Terrain.TileState.BLAZE)).is_true()

func test_is_burning_answers_for_both_fire_states_and_no_others() -> void:
	var bare: Array[Terrain.TileState] = []
	var cold: Array[Terrain.TileState] = [Terrain.TileState.FROZEN, Terrain.TileState.COVER]
	var burning: Array[Terrain.TileState] = [Terrain.TileState.BURNING]
	var blazing: Array[Terrain.TileState] = [Terrain.TileState.COVER, Terrain.TileState.BLAZE]
	assert_bool(Terrain.is_burning(bare)).is_false()
	assert_bool(Terrain.is_burning(cold)).is_false()
	assert_bool(Terrain.is_burning(burning)).is_true()
	assert_bool(Terrain.is_burning(blazing)).is_true()

func test_burning_cells_lists_a_double_fire_cell_once() -> void:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	_deposit(tsm, CELL, Terrain.TileState.BLAZE)
	_deposit(tsm, CELL, Terrain.TileState.BURNING)   # painted BLAZE, then a fireball lands
	_deposit(tsm, Vector2i(4, 0), Terrain.TileState.FROZEN)
	var cells: Array[Vector2i] = tsm.burning_cells()
	assert_array(cells).contains_exactly([CELL])
