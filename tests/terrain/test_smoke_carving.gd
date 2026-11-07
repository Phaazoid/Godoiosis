# A CARVING THAT LAYS SMOKE (#1421): the cloud does the blinding. A carving's `gases` (#508) lands on every
# tile it strikes, and whoever stands in medium or thick smoke is Smoked (#1335), so a leader in the cloud
# holds its squad on a shorter leash. Every cast goes through the player's own doors (select, aim, click,
# execute) and every round through the real turn cycle (game.end_turn -> round_completed).
#
# No authored content is pinned. Each carving is built here; how long smoke lingers, the level Smoked starts
# at and what Smoked does to COH are read off the smoke's own rules files, and the ash source off the
# authored SubstanceMap, each a precondition with its own message. One faction on the board, so ending a
# turn ends the round, and the smoked squad is the caster's own side: the cloud blinds anyone.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")

const SOURCE := 0
const FLOOR_ATLAS := Vector2i(10, 6)   # TestTiles' stone floor: walkable, and no ignition reaction keys on it
const WIDTH := 12
const HEIGHT := 7
const CASTER_CELL := Vector2i(4, 6)
const LEADER_CELL := Vector2i(4, 3)   # three tiles from the caster: inside every case's range 3
const PLUS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	game.grid.reset()
	for x in range(WIDTH):
		for y in range(HEIGHT):
			game.grid.paint(Vector2i(x, y), SOURCE, FLOOR_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	game.scenario_manager.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# --- the rules the cases read -------------------------------------------------------------------

func _rules() -> GasRules:
	var rules := GasRules.for_kind(Gas.Kind.SMOKE)
	assert_object(rules).override_failure_message("precondition: smoke has no rules file").is_not_null()
	assert_bool(rules.while_standing and rules.state == Elemental.State.SMOKED).override_failure_message(
			"precondition: smoke no longer holds Smoked while standing in it").is_true()
	return rules


# An ambient substance a carving can always find (the air holds it everywhere) that delivers no element,
# so the cast neither fizzles nor reacts with the tiles or the gas it lands on.
func _inert_ambient() -> String:
	for id: String in Atmosphere.SUBSTANCES:
		if SubstanceMap.element_carried_by(id) == Elemental.Element.NONE:
			return id
	assert_bool(false).override_failure_message("precondition: every ambient substance carries an element").is_true()
	return ""


# --- the board ----------------------------------------------------------------------------------

func _spawn(cell: Vector2i) -> Unit:
	var why: String = RulesService.spawn_block_reason(game._board(), cell)
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).override_failure_message("fixture: nothing would spawn at %s: %s" % [cell, why]).is_not_null()
	return unit


# A leader at LEADER_CELL and one member exactly as far as its clear-sighted leash reaches, which the
# cloud's Smoked must leave out.
func _smokable_squad() -> Array[Unit]:
	var leader := _spawn(LEADER_CELL)
	var reach := Squad.range_of(leader.state)
	var member_cell := LEADER_CELL + Vector2i(reach, 0)
	assert_bool(member_cell.x < WIDTH).override_failure_message(
			"fixture: a leash of %d does not fit the board" % reach).is_true()
	var member := _spawn(member_cell)
	game.squad_manager.join_squad(member, leader.squad)
	var squad: Array[Unit] = [leader, member]
	return squad


func _gas_level(cell: Vector2i) -> int:
	return Gas.level_in(game._board().gas_at(cell), Gas.Kind.SMOKE)


func _smoked(cell: Vector2i) -> bool:
	return GasRules.states_while_standing(game._board().gas_at(cell)).has(Elemental.State.SMOKED)


func _end_round() -> void:
	await game.end_turn()
	await await_idle_frame()


# --- the cast -----------------------------------------------------------------------------------

# A placed carving at range 3 over a plus, laying `level` smoke, dealing no damage.
func _carving(recipe: String, level: Gas.Level) -> TransmutationData:
	var carving := TransmutationData.new()
	carving.display_name = "Smoke"
	carving.recipe = recipe
	carving.deals_no_damage = true
	carving.damage_kind = AttackData.Kind.NONE
	carving.hits_allies = true
	carving.can_counter = false
	carving.targets = EquippableData.TargetMode.BOTH
	P.stamped(carving, 3, PLUS)
	carving.swing = false   # a true blast over its tiles, as an authored carving is by default
	carving.gases[Gas.Kind.SMOKE] = level
	assert_str(carving.recipe_error()).override_failure_message("fixture: '%s' does not parse" % recipe).is_empty()
	assert_bool(carving.get_elements().is_empty()).override_failure_message(
			"fixture: '%s' carries an element, which would react with what it lands on" % recipe).is_true()
	return carving


# A caster at `cell` whose one carving is `carving`, with the aura it demands.
func _caster(cell: Vector2i, carving: TransmutationData) -> Unit:
	var unit := _spawn(cell)
	var aura := carving.demand().duplicate()
	var affinity: Array[Elemental.Element] = []
	for element: Elemental.Element in aura:
		affinity.append(element)
	unit.unit_instance.aura = aura
	unit.unit_instance.affinity = affinity
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	rune.inscriptions.assign([carving])
	assert_bool(unit.add_item(rune)).override_failure_message("fixture: the rune did not fit").is_true()
	return unit


# Aimed and clicked through the player's own doors; true when the game queued it.
func _queue_cast(caster: Unit, at: Vector2i) -> bool:
	game.select_unit(caster, caster.movement.cell)
	game.enter_attack_mode(caster)
	game._click_attack_targeting(at)
	return caster.has_action_type_queued(BaseAction.ActionType.ATTACK)


func _execute(caster: Unit) -> void:
	await game.order_executor.execute_orders(caster.squad.get_leader())
	await await_idle_frame()


# --- the cases ----------------------------------------------------------------------------------

# The queue never lies (Law #2): the cloud the queued cast ghosts is the cloud the cast lays, tile for tile,
# at the carving's level.
func test_the_cloud_lands_where_the_queue_said() -> void:
	var carving := _carving("Push(%s)" % _inert_ambient(), Gas.Level.MEDIUM)
	var caster := _caster(CASTER_CELL, carving)
	_spawn(LEADER_CELL)
	assert_bool(_queue_cast(caster, LEADER_CELL)).override_failure_message("the game refused the cast").is_true()

	var plan: ResolvedPlan = game.previewed_plan()
	assert_object(plan).override_failure_message("nothing is previewed for the queued cast").is_not_null()
	var ghosted := {}
	for deposit: Dictionary in plan.pending_deposits():
		if deposit.get("gas", -1) == Gas.Kind.SMOKE:
			ghosted[deposit["cell"]] = true
	assert_bool(ghosted.is_empty()).override_failure_message("the queued cast ghosts no smoke").is_false()

	await _execute(caster)
	var landed := {}
	for cell in game.gas_field.cells():
		if _gas_level(cell) > 0:
			landed[cell] = true
			assert_int(_gas_level(cell)).override_failure_message(
					"%s took smoke at a level the carving does not lay" % cell).is_equal(Gas.Level.MEDIUM)
	assert_array(landed.keys()).override_failure_message(
			"the cloud landed on %s, the queue ghosted %s" % [landed.keys(), ghosted.keys()]) \
		.contains_exactly_in_any_order(ghosted.keys())


# Smoked bites where the cloud lies: the leader's leash shrinks by Smoked's own COH change, and the members
# that leaves out are cut loose at the pass's end, exactly the ones the queued row forecast.
func test_a_leader_in_the_cloud_is_smoked_and_its_squad_splits_as_forecast() -> void:
	var rules := _rules()
	var carving := _carving("Push(%s)" % _inert_ambient(), rules.state_from)
	var caster := _caster(CASTER_CELL, carving)
	var squad := _smokable_squad()
	var leader := squad[0]
	var member := squad[1]
	var clear_reach := Squad.range_of(leader.state)
	var change := int(Elemental.paired_stat_mods(Elemental.State.SMOKED).get(Stats.Stat.COH, 0))
	assert_bool(change < 0).override_failure_message(
			"precondition: Smoked's rules no longer shorten a leash (COH %+d)" % change).is_true()

	assert_bool(_queue_cast(caster, LEADER_CELL)).override_failure_message("the game refused the cast").is_true()
	var forecast: Array[Unit] = []
	for attack in (game.previewed_plan() as ResolvedPlan).attacks:
		if attack.resolved != null:
			for split in attack.resolved.splits:
				if not forecast.has(split):
					forecast.append(split)

	await _execute(caster)
	assert_bool(_smoked(LEADER_CELL)).override_failure_message("the leader in the cloud is not Smoked").is_true()
	assert_int(SquadCohesion.reach_at(leader.state, LEADER_CELL, game._board())).override_failure_message(
			"the leader's leash is not docked by Smoked").is_equal(maxi(clear_reach + change, 0))
	var cut: Array[Unit] = []
	if member.squad != leader.squad:
		cut.append(member)
	assert_array(cut).override_failure_message(
			"the member past the smoked leash is still in the squad (the queue forecast %s)" % [forecast]).is_not_empty()
	assert_array(forecast).override_failure_message(
			"the queue forecast %s cut loose, the pass cut %s" % [forecast, cut]).contains_exactly_in_any_order(cut)


# The cloud blinds until it thins below the level Smoked starts at: a level holds for the smoke's
# hold_rounds, so smoke laid at level L lifts Smoked after (L - state_from + 1) * hold_rounds rounds.
func test_the_cloud_blinds_until_it_thins() -> void:
	var rules := _rules()
	var level := rules.state_from
	var carving := _carving("Push(%s)" % _inert_ambient(), level)
	var caster := _caster(CASTER_CELL, carving)
	_spawn(LEADER_CELL)
	assert_bool(_queue_cast(caster, LEADER_CELL)).override_failure_message("the game refused the cast").is_true()
	await _execute(caster)
	assert_bool(_smoked(LEADER_CELL)).override_failure_message("the cast left the leader unsmoked").is_true()

	var blinding_rounds: int = (level - rules.state_from + 1) * rules.hold_rounds
	for round_number in range(1, blinding_rounds + 1):
		await _end_round()
		var expected := round_number < blinding_rounds
		assert_bool(_smoked(LEADER_CELL)).override_failure_message(
				"after round %d of %d the leader is %s (smoke level %d, Smoked from %d)" % [
				round_number, blinding_rounds, "Smoked" if not expected else "clear", _gas_level(LEADER_CELL),
				rules.state_from]).is_equal(expected)


# A carving that names ash fizzles where there is none, so the game will not queue it and no cloud is laid;
# beside ground the map says holds ash, it casts and lays its cloud.
func test_away_from_ash_the_cast_is_refused_and_beside_ash_it_lands() -> void:
	var ash := AlchemyFormula.resolve("AE", SubstanceCatalog.get_all())
	assert_str(ash.error).override_failure_message("precondition: no substance is ash (AE)").is_empty()
	var source := Terrain.TileState.NONE
	for state: int in Terrain.TileState.values():
		if state == Terrain.TileState.NONE or Terrain.RETIRED_STATES.has(state):
			continue
		if CellSubstances.present_from(SubstanceMap.authored().of_tile_state(state)).has(ash.id):
			source = state as Terrain.TileState
			break
	assert_int(source).override_failure_message(
			"precondition: the authored map names no tile state that holds %s" % ash.id).is_not_equal(Terrain.TileState.NONE)

	var carving := _carving("Push(AE)", _rules().state_from)
	var caster := _caster(CASTER_CELL, carving)
	_spawn(LEADER_CELL)
	assert_bool(CellSubstances.available_near(CASTER_CELL, game._board(), caster.state).has(ash.id)) \
		.override_failure_message("precondition: the fixture floor already offers %s; pick a floor whose made_of holds none"
			% ash.id).is_false()
	assert_bool(_queue_cast(caster, LEADER_CELL)).override_failure_message(
			"the game queued a cast with no %s in reach" % ash.id).is_false()
	game.exit_current_mode()

	var beside := CASTER_CELL + Vector2i(1, 0)
	var effect := ResolvedCellEffect.new()
	effect.cell = beside
	effect.states_added.assign([source])
	game.terrain_states.apply(effect)
	assert_bool(game.terrain_states.states_at(beside).has(source)).override_failure_message(
			"fixture: %s did not take" % Terrain.TileState.keys()[source]).is_true()
	assert_bool(_queue_cast(caster, LEADER_CELL)).override_failure_message(
			"the game refused the cast beside %s" % Terrain.TileState.keys()[source]).is_true()
	await _execute(caster)
	assert_int(_gas_level(LEADER_CELL)).override_failure_message("the cast beside ash laid no cloud") \
		.is_equal(_rules().state_from)
