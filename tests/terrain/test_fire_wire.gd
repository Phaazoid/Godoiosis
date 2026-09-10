# THE WIRE: TurnManager.round_completed -> game._on_round_completed -> terrain_states.tick_states,
# and the fuel source the store reads its clocks from, both driven through a real board.
#
# Nothing asserted this connection before #890. test_burnout named the signal in a COMMENT and
# ticked the store by hand; test_turn_manager tested the emitter alone. Either end could have been
# correct with nothing joining them -- #103's shape, and the reason fire burning out at all was
# never actually pinned in the game.
#
# It matters more now than it did: the clock a deposit gets is composed at the two construction
# sites, so a store wired with no fuel source is a board whose fires burn forever, and every
# headless suite in tests/terrain/ would stay green through it.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const STONE_ATLAS := Vector2i(18, 10)   # "rock": no ignition reaction keys on it, so it is not fuel
const FIRE_CELL := Vector2i(2, 0)
const STONE_CELL := Vector2i(4, 0)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	game.grid.set_cell(STONE_CELL, GRASS_SOURCE, STONE_ATLAS)
	# A faction has to be PRESENT or TurnManager.end_turn returns before it emits anything, and the
	# whole suite would then pass by never running the wire at all.
	game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(0, 0))
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _ignite(cell: Vector2i) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BURNING])
	game.terrain_states.apply(effect)


# One whole round, through the real turn cycle. A single present faction wraps immediately, so
# TurnManager emits round_completed on this one hand-off.
func _end_round() -> void:
	await game.end_turn()
	await await_idle_frame()


func _burn_turns() -> int:
	var fuel: TerrainReaction = TerrainReactionCatalog.fuel_for_kind(
			Terrain.Kind.GRASS, TerrainReactionCatalog.get_all())
	assert_object(fuel) \
		.override_failure_message("precondition: grass authors no ignition reaction, so nothing below proves anything") \
		.is_not_null()
	var turns: int = fuel.add_state_turns[Terrain.TileState.BURNING]
	return turns


func test_ending_a_round_ticks_the_terrain_store() -> void:
	var turns := _burn_turns()
	_ignite(FIRE_CELL)
	assert_int(game.terrain_states.turns_remaining(FIRE_CELL, Terrain.TileState.BURNING)) \
		.override_failure_message("the deposit never got the ground's clock, so the tick has nothing to count") \
		.is_equal(turns)
	for _i in range(turns - 1):
		await _end_round()
	assert_bool(game.terrain_states.has_state(FIRE_CELL, Terrain.TileState.BURNING)) \
		.override_failure_message("the fire went out early") \
		.is_true()
	await _end_round()
	assert_bool(game.terrain_states.has_state(FIRE_CELL, Terrain.TileState.BURNING)) \
		.override_failure_message("ending rounds never reached tick_states -- the signal, the connect or the handler is not joined up") \
		.is_false()


# The other half of the wire, and the one a bare store cannot see: the clock came from THIS CELL's
# ground rather than from any constant. Same board, same deposit, two grounds, opposite answers.
func test_the_clock_comes_from_the_ground_the_fire_is_standing_on() -> void:
	var turns := _burn_turns()
	assert_bool(GridUtils.get_terrain_kind_at_cell(game.grid, STONE_CELL) == Terrain.Kind.GRASS) \
		.override_failure_message("precondition: the stone cell reads as grass, so this case proves nothing") \
		.is_false()
	_ignite(FIRE_CELL)
	_ignite(STONE_CELL)
	assert_int(game.terrain_states.turns_remaining(STONE_CELL, Terrain.TileState.BURNING)) \
		.override_failure_message("fire on ground that is not fuel was given a clock anyway") \
		.is_equal(-1)
	for _i in range(turns * 2):
		await _end_round()
	assert_bool(game.terrain_states.has_state(FIRE_CELL, Terrain.TileState.BURNING)) \
		.override_failure_message("the grass fire outlived its fuel") \
		.is_false()
	assert_bool(game.terrain_states.has_state(STONE_CELL, Terrain.TileState.BURNING)) \
		.override_failure_message("the fire on stone burned out -- a brazier on flagstones is what BLAZE used to be, and it must not need a second state to say so") \
		.is_true()
