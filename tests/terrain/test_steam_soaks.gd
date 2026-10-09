# Steam soaks (#508 PR 3): a unit still standing in steam when ITS faction's turn ends gains the
# state the gas's rules file names, from the file's authored level up -- fire's end-of-turn burn,
# with a state instead of damage, and riding the same phase and the same list.
#
# The content razor applies twice: the state and the threshold are AUTHORED (Resources/GasRules/
# STEAM.tres), so every expectation reads them off GasRules.for_kind rather than naming WET or MEDIUM.
#
# Needs the real game scene for the same reasons test_burning_damage does: the pass is
# OrderExecutor.apply_end_of_turn_tiles, and the forecast is the squad manager's resolve.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const CELL := Vector2i(1, 0)
const STEAM := Gas.Kind.STEAM

var _main: Node
var game: Node2D
var rules: GasRules


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
	await await_idle_frame()
	rules = GasRules.for_kind(STEAM)
	assert_object(rules).override_failure_message("fixture: steam has no rules file").is_not_null()
	assert_int(rules.state).override_failure_message(
			"fixture: steam's rules name no state, so nothing here can soak").is_not_equal(Elemental.State.NONE)


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(cell: Vector2i, faction: Team.Faction) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


func _steam(cell: Vector2i, level: int) -> void:
	game.gas_field.set_level(cell, STEAM, level)


func _soaks_of(plan: ResolvedPlan) -> Array[TileHitAction]:
	var soaks: Array[TileHitAction] = []
	for hit in plan.tile_hits:
		if hit.gas >= 0:
			soaks.append(hit)
	return soaks


# A state on the books that keeps `gained` off a unit (Elemental.OVERRIDES), or NONE.
func _blocker_of(gained: Elemental.State) -> Elemental.State:
	for winner: Elemental.State in Elemental.OVERRIDES:
		if Elemental.OVERRIDES[winner] == gained:
			return winner
	return Elemental.State.NONE


# ==============================================================================
#  What the pass does
# ==============================================================================

func test_steam_at_its_soaking_level_gives_the_state_when_the_units_turn_ends() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	_steam(CELL, rules.state_from)

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_bool(unit.element_states.has(rules.state)).override_failure_message(
			"a unit standing in steam at its soaking level ended its turn without the state").is_true()


func test_steam_one_level_thinner_leaves_the_unit_untouched() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	_steam(CELL, rules.state_from - 1)

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_bool(unit.element_states.has(rules.state)).override_failure_message(
			"steam thinner than its soaking level soaked a unit").is_false()


func test_steam_spares_the_faction_whose_turn_is_not_ending() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	_steam(CELL, Gas.MAX_LEVEL)

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.ENEMY)

	assert_bool(unit.element_states.has(rules.state)).override_failure_message(
			"the enemy's turn end soaked a player unit").is_false()


# Chilled keeps Wet off (#1092); the soak asks the same Elemental.is_blocked every other door asks.
# The ROWS are the half with teeth: Unit.add_element_state refuses a blocked state on its own, so the
# unit comes out right either way, while a row the builder failed to refuse would forecast a soak
# that never lands and take the camera to a unit to show it nothing.
func test_a_state_that_keeps_the_soak_off_wins_and_stays() -> void:
	var blocker := _blocker_of(rules.state)
	assert_int(blocker).override_failure_message(
			"fixture: nothing on the books keeps this gas's state off a unit").is_not_equal(Elemental.State.NONE)
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	unit.add_element_state(blocker)
	_steam(CELL, Gas.MAX_LEVEL)

	var plan: ResolvedPlan = game.squad_manager.resolve_plan(unit.squad, game._board())
	var live := TurnBoundary.tile_hits(game._all_units(), game.terrain_states, game.gas_field,
			game.scenario_manager.current_weather, Team.Faction.PLAYER)
	assert_int(_soaks_of(plan).size()).override_failure_message(
			"the queue forecast a soak a held state keeps off").is_equal(0)
	assert_int(live.size()).override_failure_message(
			"the turn end would visit a unit a held state keeps dry").is_equal(0)

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_bool(unit.element_states.has(rules.state)).override_failure_message(
			"steam soaked a unit holding a state that keeps the soak off").is_false()
	assert_bool(unit.element_states.has(blocker)).override_failure_message(
			"the soak stripped the state that should have kept it off").is_true()


# ==============================================================================
#  The queue says so first (Law #2)
# ==============================================================================

func test_the_queue_forecasts_exactly_the_soak_the_pass_applies() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	_steam(CELL, rules.state_from)
	var plan: ResolvedPlan = game.squad_manager.resolve_plan(unit.squad, game._board())
	var soaks := _soaks_of(plan)
	assert_int(soaks.size()).override_failure_message(
			"the queue forecast no soak for a unit standing in steam").is_equal(1)
	if soaks.size() != 1:
		return
	assert_array(soaks[0].resolved.states_added).contains_exactly([rules.state])
	assert_bool(soaks[0].resolved.reads_hp).override_failure_message(
			"a soak row would print an HP arrow for a hit nobody took").is_false()

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_bool(unit.element_states.has(rules.state)).override_failure_message(
			"the queue forecast a soak the turn end never applied").is_true()


# A row says what CHANGED, so a unit already holding the state grows none -- in the forecast and the
# pass alike, or the camera visits a unit to show it nothing.
func test_a_unit_already_holding_the_state_grows_no_row() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	unit.add_element_state(rules.state)
	_steam(CELL, Gas.MAX_LEVEL)

	var plan: ResolvedPlan = game.squad_manager.resolve_plan(unit.squad, game._board())
	var live := TurnBoundary.tile_hits(game._all_units(), game.terrain_states, game.gas_field,
			game.scenario_manager.current_weather, Team.Faction.PLAYER)

	assert_int(_soaks_of(plan).size()).override_failure_message(
			"the queue forecast a soak for a unit already soaked").is_equal(0)
	assert_int(live.size()).override_failure_message(
			"the turn end would visit a unit already soaked").is_equal(0)


# Air soaks, then the ground burns -- in the forecast and the pass, so the soak never lands on a body
# its own burn killed.
func test_steam_over_fire_soaks_first_and_still_burns() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	_steam(CELL, Gas.MAX_LEVEL)
	var fire := ResolvedCellEffect.new()
	fire.cell = CELL
	fire.states_added.assign([Terrain.TileState.BURNING])
	game.terrain_states.apply(fire)
	var hp_before: int = unit.get_current_hp()

	var plan: ResolvedPlan = game.squad_manager.resolve_plan(unit.squad, game._board())
	assert_int(plan.tile_hits.size()).override_failure_message(
			"steam over fire should forecast a soak AND a burn").is_equal(2)
	if plan.tile_hits.size() != 2:
		return
	assert_int(plan.tile_hits[0].gas).override_failure_message(
			"the burn was forecast ahead of the soak").is_equal(STEAM)

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_bool(unit.element_states.has(rules.state)).is_true()
	assert_int(unit.get_current_hp()).is_equal(hp_before - Terrain.BURNING_TILE_DAMAGE)


# ==============================================================================
#  It is SHOWN (#534)
# ==============================================================================

# A soak takes the same camera beat a burn does -- inside a claimed camera, for the reason
# test_burning_damage's twin gives: releasing the lock clears follow_unit.
func test_the_post_turn_pass_takes_the_camera_to_a_soaked_unit() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	_steam(CELL, Gas.MAX_LEVEL)
	game.camera_controller.set_playback_locked(true)

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_object(game.camera_controller.follow_unit).override_failure_message(
			"the turn end soaked a unit without the camera going to it").is_same(unit)
	game.camera_controller.set_playback_locked(false)
