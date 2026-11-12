# The sky strikes the ground (#1660): at each round's end the weather's element hits every tile's
# ground through the terrain reactions (WeatherStrike), before the gas round and the fire tick, and
# GasField.next_round folds it so every forecast of the round is the round.
#
# The content razor applies: which weather strikes with what is AUTHORED, so each case gives the sky
# its own rules in memory (_sky) and restores the file's after. The reactions are found by what they
# DO (the one that puts fire out, the one that freezes), and every expectation is read off their
# fields, off GasSpread.released_onto, or off the store's own forecast.
#
# Needs the real game scene: the round is game.end_turn's, through TurnBoundary.end_round, and the
# weather reaches it from ScenarioManager.current_weather.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const WIDTH := 8
const HEIGHT := 6
const FIRE := Vector2i(2, 2)
const NEXT := Vector2i(3, 2)
const POOL := Vector2i(5, 4)
const STANDER := Vector2i(7, 0)   # the one unit the turn flow needs, away from everything struck
# Any kind with a rules file will do: its rules are replaced by each case's own, in memory.
const SKY := Weather.Kind.RAIN

var _main: Node
var game: Node2D
var _authored: Variant = null   # the cache's own entry for SKY, put back after


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
	var dirt := _tile_where(func(d: TileData) -> bool:
		return d.get_custom_data("terrain_type") == Terrain.Kind.DIRT and d.get_custom_data("walkable"))
	for x in range(WIDTH):
		for y in range(HEIGHT):
			game.grid.paint(Vector2i(x, y), dirt[0], dirt[1])
	await await_idle_frame()
	WeatherRules.for_kind(SKY)
	_authored = WeatherRules._rules_by_kind[SKY]


func after_test() -> void:
	WeatherRules._rules_by_kind[SKY] = _authored
	await DialogFixtures.end_all_dialog(self)
	game.scenario_manager.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# --- the fixtures --------------------------------------------------------------------------------

# The sky striking with `element` from the end of round `from`, as this suite's own rules.
func _sky(element: Elemental.Element, from := 1) -> void:
	var rules := WeatherRules.new()
	rules.ground = element
	rules.ground_from = from
	WeatherRules._rules_by_kind[SKY] = rules
	game.scenario_manager.current_weather = SKY


# The first ground reaction that does what `does` asks of it.
func _reaction_that(does: Callable, what: String) -> TerrainReaction:
	for reaction in TerrainReactionCatalog.get_all():
		if not reaction.in_the_air and does.call(reaction):
			return reaction
	assert_bool(false).override_failure_message("precondition: no ground reaction %s" % what).is_true()
	return null


func _douse() -> TerrainReaction:
	return _reaction_that(func(r: TerrainReaction) -> bool:
		return r.required_tile_state == Terrain.TileState.BURNING \
				and r.remove_tile_states.has(Terrain.TileState.BURNING), "puts fire out")


func _freeze() -> TerrainReaction:
	return _reaction_that(func(r: TerrainReaction) -> bool:
		return r.add_tile_states.has(Terrain.TileState.FROZEN) and r.required_kind != Terrain.Kind.NONE \
				and r.required_tile_state == Terrain.TileState.NONE and r.required_made_of == "", "freezes a kind of ground")


func _tile_where(test: Callable) -> Array:
	var tiles: TileSet = game.grid.tile_set
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			if test.call(source.get_tile_data(coords, 0)):
				return [source_id, coords]
	assert_bool(false).override_failure_message("precondition: no tile in the TileSet fits").is_true()
	return [0, Vector2i.ZERO]


func _paint_kind(cell: Vector2i, kind: Terrain.Kind, walkable: bool) -> void:
	var tile := _tile_where(func(d: TileData) -> bool:
		return d.get_custom_data("terrain_type") == kind and d.get_custom_data("walkable") == walkable)
	game.grid.paint(cell, tile[0], tile[1])


func _lay(cell: Vector2i, state: Terrain.TileState) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([state])
	game.terrain_states.apply(effect)
	assert_bool(game.terrain_states.states_at(cell).has(state)).override_failure_message(
			"fixture: %s did not take at %s" % [Terrain.TileState.keys()[state], cell]).is_true()


func _stander() -> void:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), STANDER)
	assert_object(unit).override_failure_message("fixture: nobody to take the turn").is_not_null()


func _end_round() -> void:
	await game.end_turn()
	await await_idle_frame()


# Every cell the store and the forecast name, each holding what the forecast said.
func _assert_field_is(forecast: Dictionary[Vector2i, int], why: String) -> void:
	var cells: Dictionary = {}
	for cell: Vector2i in forecast:
		cells[cell] = true
	for cell: Vector2i in game.gas_field.cells():
		cells[cell] = true
	for cell: Vector2i in cells:
		assert_int(game.gas_field.packed_at(cell)).override_failure_message(
				"%s: the round left %s holding %d, the forecast said %d" % [why, cell,
				game.gas_field.packed_at(cell), forecast.get(cell, 0)]).is_equal(forecast.get(cell, 0))


# ==============================================================================
#  What the round does
# ==============================================================================

# Fire on grass in a sky that douses: out at the round's end, its gas lying where it burned, and the
# grass beside it never catches -- the fire tick reads the strike. The round is the forecast.
func test_the_strike_puts_fire_out_before_it_spreads_and_the_forecast_is_the_round() -> void:
	var douse := _douse()
	_paint_kind(FIRE, Terrain.Kind.GRASS, true)
	_paint_kind(NEXT, Terrain.Kind.GRASS, true)
	_lay(FIRE, Terrain.TileState.BURNING)
	_stander()
	assert_bool(game.terrain_states.cells_fire_takes().has(NEXT)).override_failure_message(
			"fixture: the grass beside the fire would not catch under a clear sky").is_true()
	_sky(douse.incoming_element)
	var forecast: Dictionary[Vector2i, int] = game.gas_field.next_round(game._board())

	await _end_round()

	assert_bool(game.terrain_states.has_state(FIRE, Terrain.TileState.BURNING)).override_failure_message(
			"the sky struck and the fire still burns").is_false()
	assert_bool(game.terrain_states.has_state(NEXT, Terrain.TileState.BURNING)).override_failure_message(
			"the fire the sky put out still spread at the round's end").is_false()
	for kind: Gas.Kind in Gas.released(douse.gases):
		assert_int(game.gas_field.level_at(FIRE, kind)).override_failure_message(
				"the doused fire released no %s" % Gas.Kind.keys()[kind]).is_greater(0)
	_assert_field_is(forecast, "a doused fire")


# A burning tree holds no gas, so what the douse releases spills to its open sides (#1537), as every
# release's does.
func test_a_doused_tree_spills_its_gas_to_its_open_sides() -> void:
	var douse := _douse()
	assert_bool(Gas.released(douse.gases).is_empty()).override_failure_message(
			"precondition: putting fire out releases nothing").is_false()
	_paint_kind(FIRE, Terrain.Kind.TREE, false)
	_lay(FIRE, Terrain.TileState.BURNING)
	_stander()
	var board: BoardContext = game._board()
	assert_bool(GasSpread.holds_gas(FIRE, board)).override_failure_message(
			"fixture: the tree holds gas").is_false()
	var sides := GasSpread.released_onto(FIRE, board)
	assert_int(sides.size()).override_failure_message("fixture: the tree has no open side").is_greater(0)
	_sky(douse.incoming_element)
	var forecast: Dictionary[Vector2i, int] = game.gas_field.next_round(game._board())

	await _end_round()

	assert_int(game.gas_field.packed_at(FIRE)).override_failure_message(
			"gas lies on a tree").is_equal(0)
	for side in sides:
		for kind: Gas.Kind in Gas.released(douse.gases):
			assert_int(game.gas_field.level_at(side, kind)).override_failure_message(
					"the doused tree's gas never reached its open side %s" % side).is_greater(0)
	_assert_field_is(forecast, "a doused tree")


# Every reaction the sky's element fires on a tile STATE lands at the round's end, each as its own
# fields say -- the douse, and whatever else that element answers on a state.
func test_every_state_reaction_of_the_strike_lands() -> void:
	var element := _douse().incoming_element
	var cases: Array[TerrainReaction] = []
	for reaction in WeatherStrike.reactions(element):
		if reaction.required_tile_state != Terrain.TileState.NONE and reaction.required_kind == Terrain.Kind.NONE \
				and reaction.required_made_of == "" and reaction.forbidden_tile_state == Terrain.TileState.NONE:
			cases.append(reaction)
	var at: Dictionary[TerrainReaction, Vector2i] = {}
	for i in cases.size():
		at[cases[i]] = Vector2i(i * 2, 0)
		_lay(at[cases[i]], cases[i].required_tile_state)
	_stander()
	_sky(element)

	await _end_round()

	for reaction in cases:
		for state in reaction.remove_tile_states:
			assert_bool(game.terrain_states.has_state(at[reaction], state)).override_failure_message(
					"the strike left %s it should clear" % Terrain.TileState.keys()[state]).is_false()
		for state in reaction.add_tile_states:
			assert_bool(game.terrain_states.has_state(at[reaction], state)).override_failure_message(
					"the strike never set %s" % Terrain.TileState.keys()[state]).is_true()


# A strike from a later round leaves the ground alone until that round ends, then lands.
func test_the_strike_waits_for_its_round() -> void:
	var freeze := _freeze()
	_paint_kind(POOL, freeze.required_kind, true)
	_stander()
	var from := 3
	_sky(freeze.incoming_element, from)

	for ended in range(1, from):
		await _end_round()
		assert_bool(game.terrain_states.has_state(POOL, Terrain.TileState.FROZEN)).override_failure_message(
				"the strike landed at the end of round %d, before its round %d" % [ended, from]).is_false()
	await _end_round()
	assert_bool(game.terrain_states.has_state(POOL, Terrain.TileState.FROZEN)).override_failure_message(
			"the strike never landed at the end of its round %d" % from).is_true()


# A sky that strikes with nothing changes nothing: no effect, and the round's gas is the gas alone.
func test_a_sky_that_strikes_nothing_changes_nothing() -> void:
	_paint_kind(FIRE, Terrain.Kind.GRASS, true)
	_lay(FIRE, Terrain.TileState.BURNING)
	_sky(Elemental.Element.NONE)
	var board: BoardContext = game._board()
	assert_int(WeatherStrike.effects(board).size()).is_equal(0)
	assert_dict(game.gas_field.next_round(board)).is_equal(game.gas_field.next_round(board, false))


# The dev page's Step gas runs the gas alone: it never steams a fire it does not put out.
func test_step_gas_leaves_the_strike_to_the_round() -> void:
	var douse := _douse()
	_paint_kind(FIRE, Terrain.Kind.GRASS, true)
	_lay(FIRE, Terrain.TileState.BURNING)
	_sky(douse.incoming_element)
	var board: BoardContext = game._board()
	assert_dict(game.gas_field.next_round(board)).override_failure_message(
			"fixture: the strike would release nothing here").is_not_equal(game.gas_field.next_round(board, false))
	var expected: Dictionary[Vector2i, int] = game.gas_field.next_round(board, false)

	game.dev_controller.step_gas()

	_assert_field_is(expected, "Step gas")
	assert_bool(game.terrain_states.has_state(FIRE, Terrain.TileState.BURNING)).override_failure_message(
			"Step gas put the fire out").is_true()


# The strike asks the full gate only on its candidates (WeatherStrike._candidates), so those must hold
# every cell any element's strike could change: every tile of the TileSet, bare and under each state a
# reaction needs, and a state the plan alone holds (board.tiles), for every element.
func test_the_strike_looks_at_every_cell_it_could_change() -> void:
	var needed: Array[Terrain.TileState] = []
	for reaction in TerrainReactionCatalog.get_all():
		if reaction.required_tile_state != Terrain.TileState.NONE and not needed.has(reaction.required_tile_state):
			needed.append(reaction.required_tile_state)
	var tiles: TileSet = game.grid.tile_set
	var x := 0
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			game.grid.paint(Vector2i(x, HEIGHT + 2), source_id, coords)
			for j in needed.size():
				var cell := Vector2i(x, HEIGHT + 3 + j)
				game.grid.paint(cell, source_id, coords)
				var effect := ResolvedCellEffect.new()
				effect.cell = cell
				effect.states_added.assign([needed[j]])
				game.terrain_states.apply(effect)
			x += 1
	var live: BoardContext = game._board()
	var planned_cells: Array[ResolvedCellEffect] = []
	for j in needed.size():
		var effect := ResolvedCellEffect.new()
		effect.cell = Vector2i(j % WIDTH, j / WIDTH)
		effect.states_added.assign([needed[j]])
		planned_cells.append(effect)
	var planned := PlannedTiles.after(live, planned_cells)
	var fires := 0
	for board: BoardContext in [live, planned]:
		for hit: Elemental.Element in Elemental.Element.values():
			var fired := WeatherStrike.reactions(hit)
			if fired.is_empty():
				continue
			var elements: Array[Elemental.Element] = [hit]
			var candidates := WeatherStrike._candidates(board, fired)
			for cell in game.grid.get_used_cells():
				if PlanResolver._resolve_cell_effect_at(cell, elements, board, fired) == null:
					continue
				fires += 1
				assert_bool(candidates.has(cell)).override_failure_message(
						"a %s strike would change %s, which it never looks at" % [Elemental.Element.keys()[hit], cell]).is_true()
	assert_int(fires).override_failure_message("precondition: no strike changes any cell here").is_greater(0)
