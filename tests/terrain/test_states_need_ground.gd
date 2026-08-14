# The ground rule at the STORE (#245). TerrainStateManager is the ONE seam every tile-state deposit
# passes through -- three producers (PlanResolver, SquadManager's Burrow COVER, the dev brush) and
# three appliers (OrderExecutor, PlaySession, the brush) -- so "a tile state needs a tile under it"
# lives there rather than in six guards that would drift apart.
#
# These drive the store directly with a STUBBED ground_source, because what is under test is the
# store's contract, not the predicate. GridUtils.has_ground against a real grid with a real TileSet
# is covered end-to-end by tests/dev/test_tile_brush_states.gd.
extends GdUnitTestSuite

const GROUND := Vector2i(0, 0)
const VOID := Vector2i(9, 9)

var _states: TerrainStateManager


func before_test() -> void:
	_states = auto_free(TerrainStateManager.new()) as TerrainStateManager
	add_child(_states)


# Wire the rule up. Split from before_test on purpose: one case below needs the UNWIRED store.
func _wire_ground() -> void:
	_states.ground_source = func(cell: Vector2i) -> bool: return cell != VOID


func _deposit(cell: Vector2i, state: Terrain.TileState) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([state])
	_states.apply(effect)


func test_a_deposit_on_a_groundless_cell_is_dropped() -> void:
	_wire_ground()
	_deposit(VOID, Terrain.TileState.FROZEN)
	assert_bool(_states.has_state(VOID, Terrain.TileState.FROZEN)) \
		.override_failure_message("a state landed on a cell with no ground").is_false()
	# Non-vacuous: the identical deposit on real ground still lands. Without this the case would
	# pass just as happily against a store that refused everything.
	_deposit(GROUND, Terrain.TileState.FROZEN)
	assert_bool(_states.has_state(GROUND, Terrain.TileState.FROZEN)).is_true()


func test_a_removal_on_a_groundless_cell_still_applies() -> void:
	# The asymmetry is the whole design. A state can be legal when deposited and lose its ground
	# afterwards; if removals were forbidden alongside deposits, nothing could ever clean that up
	# and the reported bug would survive its own fix.
	_deposit(VOID, Terrain.TileState.FROZEN)   # unwired store: it lands
	_wire_ground()                              # ...and now the ground is gone from under it
	assert_bool(_states.has_state(VOID, Terrain.TileState.FROZEN)) \
		.override_failure_message("precondition: the deposit never landed").is_true()
	assert_bool(_states.prune_groundless()) \
		.override_failure_message("the sweep found nothing to prune").is_true()
	assert_bool(_states.has_state(VOID, Terrain.TileState.FROZEN)) \
		.override_failure_message("a groundless cell cannot be cleaned up").is_false()


func test_the_sweep_leaves_grounded_states_alone() -> void:
	# Non-vacuous partner to the case above: a sweep that dropped everything would satisfy it just
	# as well, and would quietly delete the board's real fire on the next map resize.
	_wire_ground()
	_deposit(GROUND, Terrain.TileState.FROZEN)
	_states.prune_groundless()
	assert_bool(_states.has_state(GROUND, Terrain.TileState.FROZEN)) \
		.override_failure_message("the sweep took a state that still had ground under it").is_true()


func test_an_unwired_store_judges_nothing() -> void:
	# Deliberate, and load-bearing: unset means NO JUDGEMENT, not "no ground". Every bare-store
	# terrain fixture -- test_ice, test_douse, test_burnout -- builds TerrainStateManager.new() with
	# no board at all and expects its deposits to land. Tightening this to a default-deny reds the
	# lot of them, so this case exists to make that consequence visible before someone tries.
	_deposit(VOID, Terrain.TileState.FROZEN)
	assert_bool(_states.has_state(VOID, Terrain.TileState.FROZEN)).is_true()
