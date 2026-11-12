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


# --- the readout --------------------------------------------------------------------------------

# The badge of `kind` drawn on `cell` among `sprites` (the overlay's live or plan-time list), or null.
func _badge_at(sprites: Array[Sprite2D], cell: Vector2i, kind: Pace.Kind) -> Sprite2D:
	var om: OverlayManager = game.overlay_manager
	var at := GridUtils.cell_world(om.board_tilemap, cell) + OverlayManager.TIME_MARK_OFFSET
	for sprite in sprites:
		if is_instance_valid(sprite) and sprite.texture == OverlayManager.TIME_MARK_ICONS[kind] \
				and sprite.global_position.is_equal_approx(at):
			return sprite
	return null


# What the tile card says about `cell`, opened the way a click opens it.
func _card(cell: Vector2i) -> Array[String]:
	game.hover_info_panel.show_tile(cell, GridUtils.cell_world(game.grid, cell))
	await await_idle_frame()
	var said: Array[String] = game.hover_info_panel.tile_texts()
	return said


# The card's line for a mark of `kind` on substance `id`, or "".
static func _mark_line(said: Array[String], kind: Pace.Kind, id: String) -> String:
	var head := "%s (%s)" % [Glossary.title(Glossary.term_for_pace(kind)), SubstanceCatalog.name_of(id)]
	for line in said:
		if line.begins_with(head):
			return line
	return ""


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


# The wind's twin (#1660): the gas Alt forecasts under a wind is the gas the round leaves, a quickened
# cloud drifting on both steps, and that forecast is not the calm board's -- so neither the forecast's
# board nor the round's dropped the wind. Its rules are injected, and put back before the asserts.
func test_the_gas_forecast_is_the_round_under_a_wind() -> void:
	_bystander()
	var cache := WindRules._rules_by_kind.duplicate()
	var rules := WindRules.new()
	rules.drift = 1
	WindRules._rules_by_kind[Wind.Kind.GALE] = rules
	sm.current_wind = Wind.Kind.GALE
	sm.current_wind_direction = Wind.Direction.EAST
	var cloud := Vector2i(3, 1)
	game.gas_field.set_level(cloud, Gas.Kind.SMOKE, Gas.MAX_LEVEL)
	var quick: Array[Vector2i] = [cloud, cloud + Vector2i.RIGHT]
	_mark(quick, _smoke_part(), Pace.Kind.QUICK, 1)

	var board: BoardContext = game.next_round_board()
	var forecast := _plain(game.gas_field.next_round(board))
	board.wind = Wind.Kind.CALM
	var calm := _plain(game.gas_field.next_round(board))
	await _end_round()
	var after := _gas_now()
	WindRules._rules_by_kind = cache
	assert_dict(forecast).override_failure_message("precondition: the wind moved nothing in the forecast") \
		.is_not_equal(calm)
	assert_dict(after).is_equal(forecast)


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


# The board shows a mark: a ghost badge on every cell a queued Still strikes, a solid one once it lands,
# and none once its rounds are spent.
func test_the_board_ghosts_a_queued_mark_and_wears_a_landed_one() -> void:
	var circle: Array[Vector2i] = [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0)]
	var carving := _carving("Still(%s)" % _fire_part(), circle)
	var caster := _caster(Vector2i(2, 1), carving)
	var om: OverlayManager = game.overlay_manager

	_queue_cast(caster, FIRE_CELL)
	for offset in circle:
		var ghost := _badge_at(om.terrain_preview_sprites, FIRE_CELL + offset, Pace.Kind.HELD)
		assert_object(ghost).override_failure_message(
				"no ghost badge on %s, which the queued Still strikes" % (FIRE_CELL + offset)).is_not_null()
		if ghost != null:
			assert_that(ghost.modulate).is_equal(OverlayManager.TERRAIN_PREVIEW_MODULATE)
	assert_object(_badge_at(om.terrain_live_sprites, FIRE_CELL, Pace.Kind.HELD)) \
		.override_failure_message("a queued mark stood on the board before it landed").is_null()

	await game.order_executor.execute_orders(caster.squad.get_leader())
	await await_idle_frame()
	for offset in circle:
		var badge := _badge_at(om.terrain_live_sprites, FIRE_CELL + offset, Pace.Kind.HELD)
		assert_object(badge).override_failure_message(
				"no badge on %s once the Still landed" % (FIRE_CELL + offset)).is_not_null()
		if badge != null:
			assert_that(badge.modulate).is_equal(Color.WHITE)

	for round_number in range(carving.time_rounds):
		await _end_round()
	assert_bool(game.terrain_states.paces_at(FIRE_CELL).is_empty()) \
		.override_failure_message("fixture: the mark outlived its rounds").is_true()
	assert_object(_badge_at(om.terrain_live_sprites, FIRE_CELL, Pace.Kind.HELD)) \
		.override_failure_message("the badge outlived its mark").is_null()


# One badge a cell, the hold outranking the hurry as it does in the round; a cell only hurried wears the
# quickened badge. Drawn by the round's own redraw.
func test_a_cell_wears_one_badge_and_a_hold_outranks_a_hurry() -> void:
	_bystander()
	var both := Vector2i(3, 0)
	var hurried := Vector2i(5, 0)
	var quick: Array[Vector2i] = [both, hurried]
	var held: Array[Vector2i] = [both]
	_mark(quick, Atmosphere.SUBSTANCES[0], Pace.Kind.QUICK, 3)
	_mark(held, Atmosphere.SUBSTANCES[1], Pace.Kind.HELD, 3)

	await _end_round()
	var live: Array[Sprite2D] = game.overlay_manager.terrain_live_sprites
	assert_object(_badge_at(live, both, Pace.Kind.HELD)).override_failure_message(
			"a cell both held and hurried does not show the hold").is_not_null()
	assert_object(_badge_at(live, both, Pace.Kind.QUICK)).override_failure_message(
			"a cell both held and hurried wears two badges").is_null()
	assert_object(_badge_at(live, hurried, Pace.Kind.QUICK)).override_failure_message(
			"a hurried cell wears no badge").is_not_null()


# The tile card names each mark: what it does, the substance it names, and the rounds it has left.
func test_the_tile_card_says_what_a_mark_holds_and_for_how_long() -> void:
	_bystander()
	var held_id: String = Atmosphere.SUBSTANCES[0]
	var quick_id: String = Atmosphere.SUBSTANCES[1]
	var cells: Array[Vector2i] = [FIRE_CELL]
	_mark(cells, held_id, Pace.Kind.HELD, 3)
	_mark(cells, quick_id, Pace.Kind.QUICK, 3)
	await _end_round()

	var said := await _card(FIRE_CELL)
	var held_line := _mark_line(said, Pace.Kind.HELD, held_id)
	assert_str(held_line).override_failure_message("the card names no hold:\n%s" % "\n".join(said)).is_not_empty()
	assert_str(held_line).contains(Glossary.short(Glossary.term_for_pace(Pace.Kind.HELD))).ends_with("2 rounds left.")
	assert_str(_mark_line(said, Pace.Kind.QUICK, quick_id)).override_failure_message(
			"the card names no hurry:\n%s" % "\n".join(said)).ends_with("2 rounds left.")

	await _end_round()
	assert_str(_mark_line(await _card(FIRE_CELL), Pace.Kind.HELD, held_id)).ends_with("1 round left.")
