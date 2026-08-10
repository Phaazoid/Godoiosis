# #50 burnout: a BURNING tile goes out after STATE_DURATIONS ticks. tick_states runs once per turn
# cycle (TurnManager.round_completed); spreading/other elements are a later PR. Pure store, headless.
#
# Tick counts derive from STATE_DURATIONS, never a literal (2026-08-10 sweep): the duration is a
# tuning dial, and retuning it must not turn this suite red. Each case walks to the last tick the
# state should survive, asserts it held, then ticks once more -- a real boundary at any duration.
extends GdUnitTestSuite

const BURN_CELL := Vector2i(1, 0)
const BURN_TICKS: int = TerrainStateManager.STATE_DURATIONS[Terrain.TileState.BURNING]

func _ignite(tsm: TerrainStateManager, cell: Vector2i) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BURNING])
	tsm.apply(effect)

func test_burning_clears_after_its_authored_duration() -> void:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	_ignite(tsm, BURN_CELL)
	assert_bool(tsm.has_state(BURN_CELL, Terrain.TileState.BURNING)).is_true()
	for _i in range(BURN_TICKS - 1):
		tsm.tick_states()
	assert_bool(tsm.has_state(BURN_CELL, Terrain.TileState.BURNING)).is_true()   # last authored tick
	tsm.tick_states()
	assert_bool(tsm.has_state(BURN_CELL, Terrain.TileState.BURNING)).is_false()  # ...and out

func test_reigniting_resets_the_timer() -> void:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	_ignite(tsm, BURN_CELL)
	for _i in range(BURN_TICKS - 1):
		tsm.tick_states()   # down to the fire's final tick
	_ignite(tsm, BURN_CELL)  # restoked -> back to full
	for _i in range(BURN_TICKS - 1):
		tsm.tick_states()   # a full countdown less one: only survivable on the reset timer
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
	for _i in range(BURN_TICKS - 1):
		dst.tick_states()
	assert_bool(dst.has_state(BURN_CELL, Terrain.TileState.BURNING)).is_true()   # outlived the source's remainder
	dst.tick_states()
	assert_bool(dst.has_state(BURN_CELL, Terrain.TileState.BURNING)).is_false()
