# THE TIME PAIR (#1311): Still(X) holds what is made of X in the cells its carving strikes, and Quicken(X)
# runs it twice there, for the carving's time_rounds rounds. Every case ends its rounds through the real
# turn cycle (TurnManager.round_completed -> game._on_round_completed), and the casts go through the
# player's own doors: select, aim, click, execute.
#
# No authored content is pinned. Which substance a recipe names is read off the authored SubstanceMap
# (what fire and smoke are made of), how long grass burns off its own ignition reaction, and what a
# spreading fire gives off off that same reaction; each is a precondition with its own message.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const FLOOR_ATLAS := Vector2i(10, 6)   # TestTiles' stone floor: walkable, and no ignition reaction keys on it
const WIDTH := 10
const FIRE_CELL := Vector2i(2, 0)
const PARKED := Vector2i(9, 2)          # a bystander's cell, out of every case's fire and gas

var _main: Node
var game: Node2D
var sm: ScenarioManager


# The whole board: a grass row to burn (y 0) and stone floor beside it to stand on (y 1 and 2), nothing
# else. Ordinary grass throws fire to its four sides only, so along the row a fire's front moves one cell
# a tick.
func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	sm = game.scenario_manager
	game.mission_controller._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	game.grid.reset()   # clear_board keeps the scene's own tiles, and a fire would find them
	for x in range(WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
		game.grid.paint(Vector2i(x, 1), GRASS_SOURCE, FLOOR_ATLAS)
		game.grid.paint(Vector2i(x, 2), GRASS_SOURCE, FLOOR_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# --- the board ----------------------------------------------------------------------------------

func _spawn(cell: Vector2i) -> Unit:
	var why: String = RulesService.spawn_block_reason(game._board(), cell)
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).override_failure_message("fixture: nothing would spawn at %s: %s" % [cell, why]).is_not_null()
	return unit


# A faction has to be PRESENT or TurnManager.end_turn returns before it emits anything.
func _bystander() -> void:
	_spawn(PARKED)


func _ignite(cell: Vector2i) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BURNING])
	game.terrain_states.apply(effect)


# Marks laid straight into the store, through its one deposit door, for the cases about the round
# rather than the cast.
func _mark(cells: Array[Vector2i], id: String, kind: Pace.Kind, rounds: int) -> void:
	for cell in cells:
		var effect := ResolvedCellEffect.new()
		effect.cell = cell
		effect.time_marks[id] = Pace.mark(kind, rounds)
		game.terrain_states.apply(effect)


# One whole round. A single present faction wraps at once, so TurnManager emits round_completed here.
func _end_round() -> void:
	await game.end_turn()
	await await_idle_frame()


func _row(from: int, to: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(from, to + 1):
		cells.append(Vector2i(x, 0))
	return cells


func _burning() -> Array[Vector2i]:
	var cells: Array[Vector2i] = game.terrain_states.burning_cells()
	cells.sort()
	return cells


# Turns a fire has left, 0 once it is out.
func _left(cell: Vector2i) -> int:
	if not game.terrain_states.has_state(cell, Terrain.TileState.BURNING):
		return 0
	return game.terrain_states.turns_remaining(cell, Terrain.TileState.BURNING)


func _grass_fuel() -> TerrainReaction:
	var fuel: TerrainReaction = TerrainReactionCatalog.fuel_for_kind(Terrain.Kind.GRASS, TerrainReactionCatalog.get_all())
	assert_object(fuel).override_failure_message(
			"precondition: grass authors no ignition reaction, so nothing here burns").is_not_null()
	return fuel


func _burn_turns(at_least: int) -> int:
	var fuel := _grass_fuel()
	if fuel == null:
		return 0
	var turns: int = fuel.add_state_turns.get(Terrain.TileState.BURNING, -1)
	assert_int(turns).override_failure_message(
			"precondition: grass burns %d turns, too few for this case to tell its ticks apart" % turns) \
		.is_greater_equal(at_least)
	return turns


# --- what a recipe names ------------------------------------------------------------------------

# Something fire is made of that every cell's air holds (Atmosphere.SUBSTANCES), so a cast naming it
# finds it anywhere and cannot fizzle.
func _fire_part() -> String:
	for id in CellSubstances.present_from(SubstanceMap.authored().of_tile_state(Terrain.TileState.BURNING)):
		if Atmosphere.SUBSTANCES.has(id):
			return id
	fail("precondition: fire is made of nothing every cell's air holds, so a cast cannot name it without a source in reach")
	return ""


# Something smoke is made of: the marks the round-only cases lay straight into the store.
func _smoke_part() -> String:
	var parts := CellSubstances.present_from(SubstanceMap.authored().of_gas(Gas.Kind.SMOKE))
	if parts.is_empty():
		fail("precondition: smoke is made of nothing in the authored map")
		return ""
	return parts[0]


# --- the cast -----------------------------------------------------------------------------------

# A placed carving at range 3 over `offsets` from the aimed cell, touching no unit.
func _carving(recipe: String, offsets: Array[Vector2i]) -> TransmutationData:
	var carving := TransmutationData.new()
	carving.display_name = "Time"
	carving.recipe = recipe
	carving.deals_no_damage = true
	carving.damage_kind = AttackData.Kind.NONE
	carving.hits_allies = true
	carving.can_counter = false
	carving.targets = EquippableData.TargetMode.BOTH
	P.stamped(carving, 3, offsets)
	assert_str(carving.recipe_error()).override_failure_message("fixture: '%s' does not parse" % recipe).is_empty()
	return carving


# A caster at `cell` whose one carving is `carving`, with the aura it demands.
func _caster(cell: Vector2i, carving: TransmutationData) -> Unit:
	var unit := _spawn(cell)
	if unit == null:
		return null
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


# Aimed and queued through the player's own doors, not yet played.
func _queue_cast(caster: Unit, at: Vector2i) -> void:
	game.select_unit(caster, caster.movement.cell)
	game.enter_attack_mode(caster)
	game._click_attack_targeting(at)
	assert_bool(caster.has_action_type_queued(BaseAction.ActionType.ATTACK)) \
		.override_failure_message("the game refused the cast at %s" % at).is_true()


func _cast(caster: Unit, at: Vector2i) -> void:
	_queue_cast(caster, at)
	await game.order_executor.execute_orders(caster.squad.get_leader())
	await await_idle_frame()


# --- gas ----------------------------------------------------------------------------------------

func _gas_now() -> Dictionary:
	var out := {}
	for cell in game.gas_field.cells():
		out[cell] = game.gas_field.packed_at(cell)
	return out


static func _plain(cells: Dictionary[Vector2i, int]) -> Dictionary:
	var out := {}
	for cell: Vector2i in cells:
		out[cell] = cells[cell]
	return out


# --- the cases ----------------------------------------------------------------------------------

# A stilled fire neither spreads nor burns down while the mark lasts, then picks up where it stopped.
func test_a_still_holds_a_fire_until_its_rounds_run_out() -> void:
	var turns := _burn_turns(2)
	var carving := _carving("Still(%s)" % _fire_part(), [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0)])
	_ignite(FIRE_CELL)
	await _cast(_caster(Vector2i(2, 1), carving), FIRE_CELL)
	assert_bool(game.terrain_states.paces_at(FIRE_CELL).is_empty()) \
		.override_failure_message("the cast laid no mark on the fire it struck").is_false()

	var only_the_fire: Array[Vector2i] = [FIRE_CELL]
	for round_number in range(carving.time_rounds):
		await _end_round()
		assert_array(_burning()).override_failure_message(
				"round %d: a stilled fire spread" % (round_number + 1)).is_equal(only_the_fire)
		assert_int(_left(FIRE_CELL)).override_failure_message(
				"round %d: a stilled fire's clock ran" % (round_number + 1)).is_equal(turns)
	assert_bool(game.terrain_states.paces_at(FIRE_CELL).is_empty()) \
		.override_failure_message("the mark outlived its %d rounds" % carving.time_rounds).is_true()

	await _end_round()
	assert_array(_burning()).override_failure_message(
			"the fire stayed held once its mark was gone: %s" % str(_burning())).is_equal(_row(1, 3))
	assert_int(_left(FIRE_CELL)).is_equal(turns - 1)


# A quickened fire ticks twice: inside the circle its front moves two cells a round and its clock runs
# down twice, while the side of it outside the circle moves one.
func test_a_quicken_runs_a_fire_twice_inside_its_circle() -> void:
	var turns := _burn_turns(3)
	var circle: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)]
	var carving := _carving("Quicken(%s)" % _fire_part(), circle)
	_ignite(FIRE_CELL)
	await _cast(_caster(Vector2i(4, 1), carving), Vector2i(4, 0))   # the circle is x 2..6

	await _end_round()
	assert_array(_burning()).override_failure_message(
			"inside the circle the front should reach x 4, outside it x 1") .is_equal(_row(1, 4))
	assert_int(_left(FIRE_CELL)).override_failure_message("the quickened fire's clock ran once") \
		.is_equal(turns - 2)
	assert_int(_left(Vector2i(3, 0))).override_failure_message(
			"a cell the first tick lit inside the circle loses a turn to the second").is_equal(turns - 1)
	assert_int(_left(Vector2i(1, 0))).override_failure_message(
			"a cell lit outside the circle ran fast").is_equal(turns)


# A held gas keeps its level and its age, and spills nothing; the same cloud unheld spills.
func test_a_held_gas_keeps_its_level_and_its_cell() -> void:
	_bystander()
	var held := Vector2i(2, 0)
	var free := Vector2i(7, 0)
	game.gas_field.set_level(held, Gas.Kind.SMOKE, Gas.MAX_LEVEL)
	game.gas_field.set_level(free, Gas.Kind.SMOKE, Gas.MAX_LEVEL)
	var cells: Array[Vector2i] = [held]
	_mark(cells, _smoke_part(), Pace.Kind.HELD, 2)
	var before: int = game.gas_field.packed_at(held)

	await _end_round()
	assert_int(Gas.level_in(game.gas_field.packed_at(free + Vector2i.LEFT), Gas.Kind.SMOKE)) \
		.override_failure_message("precondition: the unheld cloud spilled nothing either, so this proves nothing") \
		.is_greater(0)
	assert_int(game.gas_field.packed_at(held)).override_failure_message("a held cloud changed") \
		.is_equal(before)
	for side in GasSpread.SIDES:
		assert_int(Gas.level_in(game.gas_field.packed_at(held + side), Gas.Kind.SMOKE)) \
			.override_failure_message("a held cloud spilled to %s" % (held + side)).is_equal(0)


# Law #2: the gas Alt forecasts is the gas the round leaves, with both steps run -- a quickened cloud
# spilling twice, and the smoke of a quickened fire's second tick. Every mark has ONE round left, so a
# round that aged the marks or lit the fire before the gas moved would leave other gas than forecast.
func test_the_gas_forecast_is_the_round() -> void:
	_bystander()
	_burn_turns(3)
	_ignite(FIRE_CELL)
	_mark(_row(1, 4), _fire_part(), Pace.Kind.QUICK, 1)
	var cloud := Vector2i(7, 0)
	game.gas_field.set_level(cloud, Gas.Kind.SMOKE, Gas.MAX_LEVEL)
	var around: Array[Vector2i] = [Vector2i(6, 0), cloud, Vector2i(8, 0), Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1)]
	_mark(around, _smoke_part(), Pace.Kind.QUICK, 1)

	var forecast := _plain(game.gas_field.next_round(game.next_round_board()))
	assert_int(int(forecast.get(Vector2i(4, 0), 0))).override_failure_message(
			"precondition: no gas where only the fire's second tick reaches, so the second step went unseen") \
		.is_not_equal(0)
	assert_int(Gas.level_in(int(forecast.get(Vector2i(5, 0), 0)), Gas.Kind.SMOKE)).override_failure_message(
			"precondition: the quickened cloud spilled only once in the forecast").is_greater(0)

	await _end_round()
	assert_dict(_gas_now()).is_equal(forecast)


# A Still still QUEUED already holds in the forecast (PlannedTiles carries its marks), and the round
# that follows the pass leaves exactly that gas.
func test_a_queued_still_holds_in_the_forecast() -> void:
	_burn_turns(2)
	var fuel := _grass_fuel()
	assert_bool(fuel != null and not Gas.released(fuel.gases).is_empty()).override_failure_message(
			"precondition: a grass fire gives off no gas, so the forecast cannot see the fire held").is_true()
	var carving := _carving("Still(%s)" % _fire_part(), [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0)])
	_ignite(FIRE_CELL)
	var caster := _caster(Vector2i(2, 1), carving)
	var unheld := _plain(game.gas_field.next_round(game.next_round_board()))

	_queue_cast(caster, FIRE_CELL)
	assert_object(game.previewed_plan()).override_failure_message("fixture: nothing previews the queued cast") \
		.is_not_null()
	var forecast := _plain(game.gas_field.next_round(game.next_round_board()))
	assert_dict(forecast).override_failure_message("the queued Still changed nothing in the forecast") \
		.is_not_equal(unheld)

	await game.order_executor.execute_orders(caster.squad.get_leader())
	await await_idle_frame()
	await _end_round()
	assert_dict(_gas_now()).is_equal(forecast)


# A save carries every mark with the rounds it has LEFT; an authored save carries none, as it carries
# no live clock (#1483).
func test_a_save_keeps_each_mark_with_its_rounds_left() -> void:
	_bystander()
	var id := _smoke_part()
	var cells: Array[Vector2i] = [FIRE_CELL]
	_mark(cells, id, Pace.Kind.HELD, 3)
	await _end_round()
	var left := {id: Pace.mark(Pace.Kind.HELD, 2)}
	assert_dict(game.terrain_states.paces_at(FIRE_CELL)).override_failure_message(
			"precondition: a round did not age the mark, so the save cannot show rounds left").is_equal(left)

	assert_dict(sm.capture_scenario("time_marks_authored", true).terrain_paces) \
		.override_failure_message("an authored save wrote a battle's time marks").is_empty()
	var saved := sm.capture_scenario("time_marks")
	sm.clear_board()
	await await_idle_frame()
	assert_dict(game.terrain_states.paces_at(FIRE_CELL)).override_failure_message(
			"fixture: clearing the board kept the mark").is_empty()
	sm.apply_scenario(saved)
	await await_idle_frame()
	assert_dict(game.terrain_states.paces_at(FIRE_CELL)).override_failure_message(
			"the load lost the mark or its rounds left").is_equal(left)
