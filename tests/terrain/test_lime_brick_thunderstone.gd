# #1635's GROUND REACTIONS: a hit that changes one ground and not another of the same kind. Fire calcines
# limestone to quicklime and water slakes it into steam; fire bakes clay soil to brick; a shock fuses sand
# to thunderstone, whose lightning a carving's Extract can draw. The gate is what the tile is MADE of
# (TerrainReaction.required_made_of), read off the tile's own made_of column.
#
# Every cast goes through the player's own doors (select, aim, click, execute), and the queued plan is
# read BEFORE it plays, so each case also holds Law #2. No authored value is pinned: each reaction is
# loaded by its file and every expectation is read off its own fields, the reacting ground is whichever
# tile the TileSet says is made of that substance, and each carving is built here.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")

const FLOOR_SOURCE := 0
const FLOOR_ATLAS := Vector2i(10, 6)   # TestTiles' stone floor: walkable, made of nothing these react to
const WIDTH := 10
const HEIGHT := 7
const CASTER_CELL := Vector2i(4, 6)
const SOURCE_CELL := Vector2i(5, 6)    # beside the caster: inside Materia.REACH
const TARGET := Vector2i(4, 3)         # three tiles from the caster
const AWAY := Vector2i(1, 6)           # three tiles from the caster and from the source
const RANGE := 3
const LIFE := 2                        # the own-life case's turns, this suite's number

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
			game.grid.paint(Vector2i(x, y), FLOOR_SOURCE, FLOOR_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	game.scenario_manager.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# --- the content the cases read ------------------------------------------------------------------

func _reaction(file: String) -> TerrainReaction:
	var path := TerrainReactionCatalog.REACTION_DIR + file + ".tres"
	var reaction := load(path) as TerrainReaction
	assert_object(reaction).override_failure_message("precondition: %s is gone" % path).is_not_null()
	return reaction


# Paint `cell` with the first tile in the board's TileSet whose OWN made_of names `id`.
func _paint_made_of(cell: Vector2i, id: String) -> void:
	var tiles: TileSet = game.grid.tile_set
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			if GridUtils.made_of(source.get_tile_data(coords, 0)).has(id):
				game.grid.paint(cell, source_id, coords)
				assert_array(game._board().made_of_at(cell)).override_failure_message(
						"fixture: the painted tile does not read as made of %s" % id).contains([id])
				return
	assert_bool(false).override_failure_message("precondition: no tile in the TileSet is made of %s" % id).is_true()


# --- the board ----------------------------------------------------------------------------------

func _spawn(cell: Vector2i) -> Unit:
	var why: String = RulesService.spawn_block_reason(game._board(), cell)
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).override_failure_message("fixture: nothing would spawn at %s: %s" % [cell, why]).is_not_null()
	return unit


func _lay(cell: Vector2i, state: Terrain.TileState) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([state])
	game.terrain_states.apply(effect)
	assert_bool(game.terrain_states.states_at(cell).has(state)).override_failure_message(
			"fixture: %s did not take at %s" % [Terrain.TileState.keys()[state], cell]).is_true()


func _end_round() -> void:
	await game.end_turn()
	await await_idle_frame()


# --- the cast -----------------------------------------------------------------------------------

# A placed single-cell carving at RANGE that strikes the map, deals no damage and carries `element`.
func _carving(recipe: String, element: Elemental.Element) -> TransmutationData:
	var carving := TransmutationData.new()
	carving.display_name = "Test cast"
	carving.recipe = recipe
	carving.deals_no_damage = true
	carving.damage_kind = AttackData.Kind.NONE
	carving.hits_allies = true
	carving.can_counter = false
	carving.targets = EquippableData.TargetMode.BOTH
	P.point(carving, RANGE)
	assert_str(carving.recipe_error()).override_failure_message("fixture: '%s' does not parse" % recipe).is_empty()
	assert_array(carving.get_elements()).override_failure_message(
			"fixture: '%s' does not carry %s" % [recipe, Elemental.display_name(element)]).contains([element])
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


# What `reaction` leaves on `cell`, asked of `board`: every state it adds is held, every state it removes
# is gone, and every gas it releases lies at its level (the cell held none before).
func _assert_left(board: BoardContext, cell: Vector2i, reaction: TerrainReaction, when: String) -> void:
	var held := board.tile_states_at(cell)
	for state: Terrain.TileState in reaction.add_tile_states:
		assert_bool(held.has(state)).override_failure_message("%s: %s holds %s, not %s" % [
				when, cell, held, Terrain.TileState.keys()[state]]).is_true()
	for state: Terrain.TileState in reaction.remove_tile_states:
		assert_bool(held.has(state)).override_failure_message("%s: %s still holds %s" % [
				when, cell, Terrain.TileState.keys()[state]]).is_false()
	for kind: Gas.Kind in Gas.released(reaction.gases):
		assert_int(Gas.level_in(board.gas_at(cell), kind)).override_failure_message("%s: %s holds %s at the wrong level" % [
				when, cell, Gas.display_name(kind)]).is_equal(reaction.gases[kind])


# Queue `caster`'s cast at `cell`, check the queued plan leaves what `reaction` says, play it, and check
# the board was left exactly that.
func _cast_and_check(caster: Unit, cell: Vector2i, reaction: TerrainReaction) -> void:
	assert_bool(_queue_cast(caster, cell)).override_failure_message("the game refused the cast").is_true()
	var plan: ResolvedPlan = game.previewed_plan()
	assert_object(plan).override_failure_message("nothing is previewed for the queued cast").is_not_null()
	_assert_left(game._board().planned(plan.tiles), cell, reaction, "the queued plan")
	await _execute(caster)
	_assert_left(game._board(), cell, reaction, "the played cast")


# --- the cases ----------------------------------------------------------------------------------

func test_fire_on_limestone_calcines_it_where_the_queue_said() -> void:
	var calcines := _reaction("Calcines")
	_paint_made_of(TARGET, calcines.required_made_of)
	_lay(SOURCE_CELL, Terrain.TileState.BURNING)   # the flame the cast draws on
	var caster := _caster(CASTER_CELL, _carving("Push(F2)", calcines.incoming_element))
	await _cast_and_check(caster, TARGET, calcines)


# The fire quicklime holds comes out as water hits it: the cell's quicklime goes, steam rises, and whoever
# stands in it pays at the end of the turn exactly what its health bar forecast.
func test_water_on_quicklime_slakes_it_and_the_steam_scalds_as_forecast() -> void:
	var slakes := _reaction("Slakes")
	_lay(TARGET, slakes.required_tile_state)
	var bystander := _spawn(TARGET)
	var carving := _carving("Push(W2)", slakes.incoming_element)
	var caster := _caster(CASTER_CELL, carving)
	caster.add_element_state(Elemental.State.WET)   # the water the cast draws on
	assert_bool(_queue_cast(caster, TARGET)).override_failure_message("the game refused the cast").is_true()
	var plan: ResolvedPlan = game.previewed_plan()
	_assert_left(game._board().planned(plan.tiles), TARGET, slakes, "the queued plan")
	var rows: Array[TileHitAction] = []
	for hit in plan.tile_hits:
		if hit.actor == bystander:
			rows.append(hit)
	assert_array(rows).override_failure_message(
			"the slaking forecasts nothing for whoever stands in it; does its gas no longer do anything?").is_not_empty()
	var forecast := TileHitAction.shown_hp_after(rows)
	assert_int(forecast).override_failure_message("the forecast rows name no HP").is_greater_equal(0)

	await _execute(caster)
	_assert_left(game._board(), TARGET, slakes, "the played cast")
	await _end_round()
	assert_int(bystander.get_current_hp()).override_failure_message(
			"the bystander ended the turn on %d HP; its bar forecast %d" % [bystander.get_current_hp(), forecast]) \
		.is_equal(forecast)


func test_fire_on_clay_bakes_it_once() -> void:
	var bakes := _reaction("Bakes")
	_paint_made_of(TARGET, bakes.required_made_of)
	_lay(SOURCE_CELL, Terrain.TileState.BURNING)
	var caster := _caster(CASTER_CELL, _carving("Push(F2)", bakes.incoming_element))
	await _cast_and_check(caster, TARGET, bakes)

	await _end_round()
	assert_bool(_queue_cast(caster, TARGET)).override_failure_message("the second cast was refused").is_true()
	var plan: ResolvedPlan = game.previewed_plan()
	for deposit: Dictionary in plan.pending_deposits():
		assert_bool(deposit.get("cell") == TARGET and deposit.has("state")).override_failure_message(
				"fire on brick deposited %s again" % Terrain.TileState.keys()[deposit.get("state", 0)]).is_false()


func test_a_shock_on_sand_fuses_it_to_thunderstone() -> void:
	var fuses := _reaction("Fuses")
	_paint_made_of(TARGET, fuses.required_made_of)
	_lay(SOURCE_CELL, fuses.add_tile_states[0])   # thunderstone's own held lightning is what the cast draws
	var caster := _caster(CASTER_CELL, _carving("Extract(2QF) + Push(2QF)", fuses.incoming_element))
	await _cast_and_check(caster, TARGET, fuses)


# Thunderstone HOLDS its strike: an Extract finds the lightning beside it, so the cast queues with nothing
# carried; away from it, it is refused; and a verb that is not an Extract finds none even beside it.
func test_thunderstone_lends_its_lightning_to_an_extract_alone() -> void:
	var fuses := _reaction("Fuses")
	var stone: Terrain.TileState = fuses.add_tile_states[0]
	var extract := _caster(CASTER_CELL, _carving("Extract(2QF) + Push(2QF)", Elemental.Element.SHOCK))
	assert_bool(_queue_cast(extract, TARGET)).override_failure_message(
			"precondition: the cast queued with no thunderstone in reach; the fixture has another lightning source").is_false()
	game.exit_current_mode()

	_lay(SOURCE_CELL, stone)
	assert_bool(_queue_cast(extract, TARGET)).override_failure_message(
			"an Extract beside thunderstone found no lightning").is_true()
	game.exit_current_mode()

	# A second caster beside a second stone, out of reach of the first.
	var push_cell := AWAY + Vector2i(0, -1)
	var push_carving := _carving("Push(2QF)", Elemental.Element.SHOCK)
	var push := _caster(push_cell, push_carving)
	_lay(AWAY, stone)
	assert_str(CellSubstances.fizzle_reason(push_carving, push_cell, game._board(), push.state)).override_failure_message(
			"a Push drew thunderstone's held lightning; only an Extract may").is_not_empty()
	assert_bool(_queue_cast(push, push_cell + Vector2i(0, -RANGE))).override_failure_message(
			"the game queued a Push on thunderstone's held lightning").is_false()


# The gate reads the tile's OWN column: a ground that merely lends the substance (loam lends alumina) is
# not made of it.
func test_the_made_of_gate_reads_the_tiles_own_column() -> void:
	var reaction := TerrainReaction.new()
	reaction.incoming_element = Elemental.Element.FIRE
	reaction.required_made_of = "alumina"
	var none: Array[Terrain.TileState] = []
	assert_bool(reaction.applies_to_tile(Terrain.Kind.DIRT, none, ["alumina"] as Array[String])).is_true()
	assert_bool(reaction.applies_to_tile(Terrain.Kind.DIRT, none, ["loam"] as Array[String])).override_failure_message(
			"a lent part counted as what the tile is made of").is_false()
	assert_bool(reaction.applies_to_tile(Terrain.Kind.DIRT, none, [] as Array[String])).is_false()
	reaction.required_made_of = ""
	assert_bool(reaction.applies_to_tile(Terrain.Kind.DIRT, none, [] as Array[String])).override_failure_message(
			"an empty gate stopped meaning any ground").is_true()


# The tile card lists a made-of reaction on its own ground and nowhere else: TileReadout hands the
# cell's makeup to the same predicate the resolver runs.
func test_the_tile_card_lists_a_made_of_reaction_on_its_ground_only() -> void:
	var calcines := _reaction("Calcines")
	_paint_made_of(TARGET, calcines.required_made_of)
	var word := "sets %s" % Terrain.tile_state_display_name(calcines.add_tile_states[0])
	assert_bool(_card_says(TARGET, word)).override_failure_message(
			"the card on %s does not say '%s'" % [calcines.required_made_of, word]).is_true()
	assert_bool(_card_says(AWAY, word)).override_failure_message(
			"the card on the stone floor says '%s'" % word).is_false()


func _card_says(cell: Vector2i, text: String) -> bool:
	for line: String in TileReadout.ground_lines(game, cell):
		if line.contains(text):
			return true
	return false


# THE MISSING-WIRE CASE: a ground reaction's add_state_turns is the deposit's own life. Resolved by the
# pass's own per-tile step (both ground and air reactions fire through it) on the real board, applied to
# the real store, and run down by the round's own tick. The reaction is built here: no shipped one
# authors turns on a ground that is not its fuel.
func test_a_ground_reactions_turns_are_its_states_own_life() -> void:
	var state := Terrain.TileState.QUICKLIME
	var reaction := TerrainReaction.new()
	reaction.incoming_element = Elemental.Element.FIRE
	reaction.add_tile_states.assign([state])
	reaction.add_state_turns[state] = LIFE
	var fire: Array[Elemental.Element] = [Elemental.Element.FIRE]
	var ground: Array[TerrainReaction] = [reaction]
	var effect := PlanResolver._resolve_cell_effect_at(TARGET, fire, game._board(), ground)
	assert_object(effect).override_failure_message("the reaction left nothing on the struck tile").is_not_null()
	assert_int(effect.state_turns.get(state, -1)).override_failure_message(
			"the reaction's turns never reached its deposit").is_equal(LIFE)

	game.terrain_states.apply(effect)
	for _i in range(LIFE - 1):
		game.terrain_states.tick_states()
	assert_bool(game.terrain_states.has_state(TARGET, state)).override_failure_message("it wore off early").is_true()
	game.terrain_states.tick_states()
	assert_bool(game.terrain_states.has_state(TARGET, state)).override_failure_message("it outlived its turns").is_false()
