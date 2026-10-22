# Steam soaks (#508 PR 3): a unit still standing in steam when ITS faction's turn ends gains the
# state the gas's rules file names, from the file's authored level up -- fire's end-of-turn burn,
# with a state instead of damage, and riding the same phase and the same list. Since #1331 it SCALDS
# as well, on the same row: the damage the file authors at that level, stopped by its insulation.
#
# The content razor applies twice: the state, the threshold and the damage are AUTHORED (Resources/
# GasRules/STEAM.tres), so every expectation reads them off GasRules.for_kind and
# RulesService.gas_damage_for rather than naming WET, MEDIUM or a number.
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


# The rows that give the gas's state -- what the soak cases are about, now that a scald alone is a row.
func _rows_giving(hits: Array[TileHitAction], state: Elemental.State) -> Array[TileHitAction]:
	var giving: Array[TileHitAction] = []
	for hit in hits:
		if hit.gas >= 0 and hit.resolved.states_added.has(state):
			giving.append(hit)
	return giving


# The thinnest level steam scalds at, or NONE when it scalds at none.
func _thinnest_scald() -> int:
	for level in range(Gas.Level.THIN, Gas.MAX_LEVEL + 1):
		if int(rules.damage.get(level, 0)) > 0:
			return level
	return Gas.Level.NONE


# Armour granting the insulation that stops the scald, built ad hoc as test_burning_damage's
# _fireproof is: the rule, through the real kit path, not the Asbestos Shroud.
func _insulated() -> ArmorData:
	var piece := ArmorData.new()
	piece.display_name = "Test Shroud"
	var ability := AbilityData.new()
	ability.id = Abilities.INSULATION[rules.damage_element]
	ability.kind = AbilityData.AbilityKind.PASSIVE
	var grants: Array[AbilityData] = [ability]
	piece.granted_abilities = grants
	return piece


func _live_hits() -> Array[TileHitAction]:
	return TurnBoundary.tile_hits(game._all_units(), game.terrain_states, game.gas_field,
			game.scenario_manager.current_weather, Team.Faction.PLAYER)


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
	assert_int(_rows_giving(plan.tile_hits, rules.state).size()).override_failure_message(
			"the queue forecast a soak a held state keeps off").is_equal(0)
	assert_int(_rows_giving(_live_hits(), rules.state).size()).override_failure_message(
			"the turn end would soak a unit a held state keeps dry").is_equal(0)

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
	# The row prints an HP arrow exactly when the same level also scalds (#1331).
	var scalds := RulesService.gas_damage_for(unit, STEAM, rules.state_from) > 0
	assert_bool(soaks[0].resolved.reads_hp).override_failure_message(
			"the soak row's HP arrow disagrees with whether this level scalds").is_equal(scalds)

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_bool(unit.element_states.has(rules.state)).override_failure_message(
			"the queue forecast a soak the turn end never applied").is_true()


# A row says what CHANGED, so a unit already holding the state is soaked by none -- in the forecast and
# the pass alike. What is left is the scald alone (#1331): a row with the damage and no state chip, or
# no row at all where this level does not scald, so the camera never visits a unit to show it nothing.
func test_a_unit_already_holding_the_state_is_only_scalded() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	unit.add_element_state(rules.state)
	_steam(CELL, Gas.MAX_LEVEL)
	var scald := RulesService.gas_damage_for(unit, STEAM, Gas.MAX_LEVEL)

	var plan: ResolvedPlan = game.squad_manager.resolve_plan(unit.squad, game._board())
	var live := _live_hits()

	for hits: Array[TileHitAction] in [_soaks_of(plan), live]:
		assert_int(hits.size()).override_failure_message(
				"an already-soaked unit grew a row the scald does not account for").is_equal(1 if scald > 0 else 0)
		for hit in hits:
			assert_array(hit.resolved.states_added).override_failure_message(
					"a row soaked a unit already soaked").is_empty()
			assert_int(hit.resolved.damage).is_equal(scald)


# Air soaks (and scalds), then the ground burns -- in the forecast and the pass, so the soak never
# lands on a body its own burn killed.
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
	assert_int(unit.get_current_hp()).is_equal(hp_before - Terrain.BURNING_TILE_DAMAGE
			- RulesService.gas_damage_for(unit, STEAM, Gas.MAX_LEVEL))


# ==============================================================================
#  It scalds (#1331)
# ==============================================================================

func test_steam_scalds_by_its_authored_damage_when_the_units_turn_ends() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	var scald := RulesService.gas_damage_for(unit, STEAM, Gas.MAX_LEVEL)
	assert_int(scald).override_failure_message("fixture: thick steam scalds nobody").is_greater(0)
	_steam(CELL, Gas.MAX_LEVEL)
	var hp_before: int = unit.get_current_hp()

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_int(unit.get_current_hp()).override_failure_message(
			"thick steam did not take its authored damage at the turn end").is_equal(hp_before - scald)


func test_steam_one_level_below_its_thinnest_scald_deals_nothing() -> void:
	var thinnest := _thinnest_scald()
	assert_int(thinnest).override_failure_message(
			"fixture: steam scalds at no level, so nothing here is checked").is_not_equal(Gas.Level.NONE)
	if thinnest <= Gas.Level.THIN:
		return   # every level that holds steam scalds: there is no thinner one to ask
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	_steam(CELL, thinnest - 1)
	var hp_before: int = unit.get_current_hp()

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_int(unit.get_current_hp()).override_failure_message(
			"steam thinner than its thinnest scald hurt a unit").is_equal(hp_before)


# The scald's insulation stops the damage and only the damage: the soak is a different rule.
func test_an_insulated_unit_is_soaked_and_not_scalded() -> void:
	assert_bool(Abilities.INSULATION.has(rules.damage_element)).override_failure_message(
			"fixture: nothing insulates against steam's scald").is_true()
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	unit.worn_armor = _insulated()
	_steam(CELL, Gas.MAX_LEVEL)
	var hp_before: int = unit.get_current_hp()

	var plan: ResolvedPlan = game.squad_manager.resolve_plan(unit.squad, game._board())
	for hit in _soaks_of(plan):
		assert_bool(hit.resolved.reads_hp).override_failure_message(
				"the queue forecast a scald for a unit insulated against it").is_false()

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_int(unit.get_current_hp()).override_failure_message(
			"insulation did not stop the scald").is_equal(hp_before)
	assert_bool(unit.element_states.has(rules.state)).override_failure_message(
			"insulation against the scald kept the soak off too").is_true()


# Law #2: the HP the END OF TURN row shows is the HP the pass leaves.
func test_the_queue_forecasts_exactly_the_scald_the_pass_deals() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	_steam(CELL, Gas.MAX_LEVEL)
	var plan: ResolvedPlan = game.squad_manager.resolve_plan(unit.squad, game._board())
	var soaks := _soaks_of(plan)
	assert_int(soaks.size()).override_failure_message(
			"the queue forecast no row for a unit standing in thick steam").is_equal(1)
	if soaks.size() != 1:
		return
	assert_bool(soaks[0].resolved.reads_hp).override_failure_message(
			"the scald row prints no HP arrow").is_true()
	var predicted: int = LethalityRules.displayed_hp(soaks[0].resolved.target_hp_after,
			LethalityRules.lifecycle_for(soaks[0].resolved.lethality))

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_int(unit.get_current_hp()).override_failure_message(
			"the queue previewed one number and the turn end dealt another").is_equal(predicted)


# A downed body holds 1 HP, so a scald finishes it, forecast and pass alike -- the burn's rule (#191).
func test_a_downed_body_in_steam_is_forecast_dead_and_dies() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	unit.force_down()
	_steam(CELL, Gas.MAX_LEVEL)

	var plan: ResolvedPlan = game.squad_manager.resolve_plan(unit.squad, game._board())
	var soaks := _soaks_of(plan)
	assert_int(soaks.size()).override_failure_message(
			"the queue forecast nothing for a downed body in thick steam").is_equal(1)
	if soaks.size() == 1:
		assert_int(soaks[0].resolved.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)
		assert_array(soaks[0].resolved.states_added).override_failure_message(
				"a row soaks the body its own scald killed").is_empty()

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_bool(unit.is_dead()).override_failure_message(
			"a downed body in thick steam survived its faction's turn end").is_true()


# THE THREADING CASE (#1331): steam over fire is two damage rows on one unit, and the burn must be
# predicted on the HP the scald leaves. Each alone leaves this unit standing; together they fell it.
# Read without the thread, the burn would preview HP -> HP - burn and the pass would down the unit.
func test_a_burn_after_a_scald_is_forecast_on_the_hp_the_scald_leaves() -> void:
	var unit := _spawn(CELL, Team.Faction.PLAYER)
	var scald := RulesService.gas_damage_for(unit, STEAM, Gas.MAX_LEVEL)
	var burn := Terrain.BURNING_TILE_DAMAGE
	assert_int(scald).override_failure_message("fixture: thick steam scalds nobody").is_greater(0)
	unit.set_current_hp(maxi(scald, burn) + 1)
	assert_int(unit.get_current_hp()).override_failure_message(
			"fixture: the unit cannot hold enough HP for this case").is_equal(maxi(scald, burn) + 1)
	_steam(CELL, Gas.MAX_LEVEL)
	_ignite(CELL)

	var plan: ResolvedPlan = game.squad_manager.resolve_plan(unit.squad, game._board())
	assert_int(plan.tile_hits.size()).override_failure_message(
			"steam over fire should forecast a scald AND a burn").is_equal(2)
	if plan.tile_hits.size() != 2:
		return
	var burn_row := plan.tile_hits[1]
	assert_int(burn_row.resolved.hp_before).override_failure_message(
			"the burn was predicted on the HP before the scald").is_equal(plan.tile_hits[0].resolved.target_hp_after)
	var forecast := burn_row.resolved.lethality
	assert_int(forecast).override_failure_message(
			"the burn's row does not say the two rows fell the unit").is_not_equal(ResolvedOutcome.Lethality.NONE)
	var live := _live_hits()
	assert_int(live.size()).is_equal(2)
	if live.size() == 2:
		assert_int(live[1].resolved.lethality).override_failure_message(
				"the pass's own burn row was predicted on the HP before the scald").is_equal(forecast)

	await game.order_executor.apply_end_of_turn_tiles(Team.Faction.PLAYER)

	assert_bool(unit.is_active()).override_failure_message(
			"the scald and the burn together left the unit standing").is_false()


func _ignite(cell: Vector2i) -> void:
	var fire := ResolvedCellEffect.new()
	fire.cell = cell
	fire.states_added.assign([Terrain.TileState.BURNING])
	game.terrain_states.apply(fire)


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
