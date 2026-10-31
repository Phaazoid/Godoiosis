# Which substances are present for a cast (CellSubstances.available_near) -- the presence half of
# Deep Alchemy Phase 2's fizzle rule. Canon: docs/design/deep-alchemy.md -> What is built.
#
# The board is stubbed, test_materia_sources.gd's fixture one store wider: kinds and lit props are
# authored directly, who stands where is the board's own units at their own cells (the fizzle reads
# them where the plan puts them, #1480), STATES ride a real TerrainStateManager and gas a real GasField.
# Every case hands available_near its own catalog AND its own SubstanceMap, so nothing here reads an
# authored substance file or the authored rows (tests/README.md rule 9, #1532): what grass is made of
# is content, and these cases ask only what the code does with a row.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const HERE := Vector2i(4, 4)
const NEXT_DOOR := Vector2i(5, 4)
const TWO_AWAY := Vector2i(6, 4)


class _SubstanceBoard extends BoardContext:
	var kinds: Dictionary
	var lit: Dictionary
	func _init(states: TerrainStateManager, gas_field: GasField, k: Dictionary, l: Dictionary, standing: Array[Unit]) -> void:
		super(null, standing, null, states, null, null, gas_field)
		kinds = k
		lit = l
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.NONE)
	func prop_lit_at(cell: Vector2i) -> bool:
		return lit.get(cell, false)


func _sub(formula: String, name: String = "", lends := true) -> Substance:
	var s := Substance.new()
	s.formula = formula
	s.display_name = name
	s.lends_its_parts = lends
	return s


# The fixture's own chemistry: the ambient four, the grounds its map names, and their parts. Its plants
# lend nothing, c3potheds@'s rule for the real ones.
func _catalog() -> Dictionary:
	return {
		"inert_air": _sub("A2"), "vital_air": _sub("FA"), "vapor": _sub("AW"), "atom_aether": _sub("Q"),
		"atom_fire": _sub("F"), "atom_air": _sub("A"), "atom_water": _sub("W"), "atom_earth": _sub("E"),
		"water": _sub("W2", "Water"), "ice": _sub("QW", "Ice"), "flame": _sub("F2", "Flame"),
		"steam": _sub("FW", "Steam"), "salt": _sub("E2", "Salt"), "ash": _sub("AE", "Ash"),
		"lightning": _sub("QF", "Lightning"),
		"dirt": _sub("E2 + AE", "Dirt"),
		"mud": _sub("dirt + W2", "Mud"),
		"smoke": _sub("AE + A2", "Smoke"),
		"green_plant": _sub("AE + 2FA + W2", "Green plant", false),
		"dry_plant": _sub("AE + 2FA", "Dry plant", false),
	}


# The fixture's own rows: what each thing it paints is made of. Rock holds nothing here, so the cases
# about what lies ON a cell read alone. Grass stands on dirt, a row naming two substances.
func _map(burning: Array = ["flame"]) -> SubstanceMap:
	var map := SubstanceMap.new()
	map.grounds = {
		Terrain.Kind.GRASS: PackedStringArray(["green_plant", "dirt"]),
		Terrain.Kind.TALL_GRASS: PackedStringArray(["dry_plant", "dirt"]),
		Terrain.Kind.MUD: PackedStringArray(["mud"]),
		Terrain.Kind.ROCK: PackedStringArray(),
		Terrain.Kind.WATER: PackedStringArray(["water"]),
		Terrain.Kind.DIRT: PackedStringArray(["dirt"]),
		Terrain.Kind.VOID: PackedStringArray(),
	}
	map.tile_states = {
		Terrain.TileState.BURNING: PackedStringArray(burning),
		Terrain.TileState.FROZEN: PackedStringArray(["ice"]),
	}
	map.gases = {
		Gas.Kind.STEAM: PackedStringArray(["steam"]),
		Gas.Kind.SMOKE: PackedStringArray(["smoke"]),
	}
	map.unit_states = {
		Elemental.State.WET: PackedStringArray(["water"]),
		Elemental.State.CHILLED: PackedStringArray(["ice"]),
	}
	return map


func _store(cell_states: Dictionary = {}) -> TerrainStateManager:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	for cell: Vector2i in cell_states:
		var effect := ResolvedCellEffect.new()
		effect.cell = cell
		effect.states_added.assign(cell_states[cell])
		tsm.apply(effect)
	return tsm


func _board(kinds: Dictionary, cell_states: Dictionary = {}, lit: Dictionary = {},
		gas: GasField = null, standing: Array[Unit] = []) -> _SubstanceBoard:
	return _SubstanceBoard.new(_store(cell_states), gas, kinds, lit, standing)


func _supply(board: BoardContext, caster: Unit = null, map: SubstanceMap = _map(),
		catalog: Dictionary = _catalog()) -> Dictionary[String, int]:
	return CellSubstances.available_near(HERE, board, UnitState.of(caster), catalog, {}, map)


func _present(board: BoardContext, caster: Unit = null, catalog: Dictionary = _catalog()) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_supply(board, caster, _map(), catalog).keys())
	return ids


func _fizzle(recipe: String, board: BoardContext, caster: Unit = null, map: SubstanceMap = _map()) -> String:
	var parsed := CarvingRecipe.parse(recipe, _catalog())
	assert_str(parsed.error).override_failure_message("fixture recipe '%s' does not parse: %s"
			% [recipe, parsed.error]).is_empty()
	return parsed.fizzle_reason(_supply(board, caster, map), _catalog())


# --- the baseline ---------------------------------------------------------------------------

func test_the_ambient_air_is_present_everywhere() -> void:
	var present := _present(_board({}))
	for id: String in Atmosphere.SUBSTANCES:
		assert_bool(present.has(id)).override_failure_message("ambient '%s' missing" % id).is_true()


func test_a_null_board_still_has_the_ambient_air() -> void:
	assert_array(_present(null)).contains_exactly(Atmosphere.SUBSTANCES)


# The ids this file names are real substances -- a renamed file would otherwise leave a silent hole.
func test_every_id_cell_substances_names_is_a_real_substance() -> void:
	var real := SubstanceCatalog.get_all()
	for id: String in Atmosphere.SUBSTANCES:
		assert_bool(real.has(id)).override_failure_message("'%s' names no substance file" % id).is_true()


# --- the ground and its parts ---------------------------------------------------------------

func test_the_ground_and_its_compound_parts_are_present() -> void:
	var present := _present(_board({ NEXT_DOOR: Terrain.Kind.DIRT }))
	assert_bool(present.has("dirt")).is_true()
	assert_bool(present.has("salt")).override_failure_message("dirt lent no salt").is_true()
	assert_bool(present.has("ash")).override_failure_message("dirt lent no ash").is_true()


# Recursively: mud is dirt and water, and the dirt in it lends its salt.
func test_parts_lend_their_own_parts() -> void:
	var present := _present(_board({ HERE: Terrain.Kind.MUD }))
	for id: String in ["mud", "dirt", "water", "salt", "ash"]:
		assert_bool(present.has(id)).override_failure_message("mud's '%s' missing" % id).is_true()


# Rock Throw's Push(E2) works off a dirt ground because dirt lends its salt.
func test_a_push_of_salt_does_not_fizzle_beside_dirt() -> void:
	assert_str(_fizzle("Push(E2)", _board({ NEXT_DOOR: Terrain.Kind.DIRT }))).is_empty()


# A compound whose lends_its_parts is off is present as itself and lends NOTHING (plant matter,
# c3potheds@): a grass field holds no water. The dirt the fixture's grass row also names still lends.
func test_plant_matter_lends_no_water_and_grass_stands_on_dirt() -> void:
	var present := _present(_board({ HERE: Terrain.Kind.GRASS, NEXT_DOOR: Terrain.Kind.TALL_GRASS }))
	assert_bool(present.has("green_plant")).is_true()
	assert_bool(present.has("dry_plant")).is_true()
	assert_bool(present.has("water")).override_failure_message(
			"a plant lent its water -- organic matter lends nothing").is_false()
	assert_bool(present.has("dirt")).override_failure_message("grass stands on no dirt").is_true()
	assert_bool(present.has("salt")).is_true()
	assert_str(_fizzle("Focus(W2) + Push(W2)", _board({ HERE: Terrain.Kind.GRASS }))).contains("water")


# THE MISSING-WIRE CASE for the tick: the same plant, ticked on, lends its water. Read off the field,
# never off a list of ids, so authoring the tick is what moves it.
func test_a_compound_ticked_to_lend_lends_its_parts() -> void:
	var catalog := _catalog()
	(catalog["green_plant"] as Substance).lends_its_parts = true
	var present := _present(_board({ HERE: Terrain.Kind.GRASS }), null, catalog)
	assert_bool(present.has("water")).override_failure_message(
			"a plant ticked to lend its parts lent no water").is_true()


func test_a_hole_offers_nothing() -> void:
	var present := _present(_board({ HERE: Terrain.Kind.VOID, NEXT_DOOR: Terrain.Kind.VOID }))
	assert_array(present).contains_exactly(Atmosphere.SUBSTANCES)


# Ice is a floor, not a well: frozen water offers its ice and not its water.
func test_frozen_water_counts_as_ice_and_not_water() -> void:
	var present := _present(_board({ HERE: Terrain.Kind.WATER }, { HERE: [Terrain.TileState.FROZEN] }))
	assert_bool(present.has("ice")).is_true()
	assert_bool(present.has("water")).override_failure_message("frozen water still offered water").is_false()


func test_open_water_is_water() -> void:
	assert_bool(_present(_board({ NEXT_DOOR: Terrain.Kind.WATER })).has("water")).is_true()


# --- what lies on the ground -----------------------------------------------------------------

func test_a_burning_cell_offers_flame() -> void:
	var board := _board({ NEXT_DOOR: Terrain.Kind.ROCK }, { NEXT_DOOR: [Terrain.TileState.BURNING] })
	assert_bool(_present(board).has("flame")).is_true()


func test_a_lit_prop_offers_flame() -> void:
	var board := _board({ NEXT_DOOR: Terrain.Kind.ROCK }, {}, { NEXT_DOOR: true })
	assert_bool(_present(board).has("flame")).is_true()


# Heat is in the air everywhere (#1324, Phaazoid@ 2026-10-16), so a lone Push(F) holds with no fire
# near; flame is not, so a tied fire basic still needs a real fire.
func test_heat_is_in_the_air_and_flame_is_not() -> void:
	var bare := _board({ NEXT_DOOR: Terrain.Kind.ROCK })
	assert_bool(_present(bare).has("atom_fire")).override_failure_message(
			"heat is missing with no fire near").is_true()
	assert_str(_fizzle("Push(F)", bare)).is_empty()
	assert_str(_fizzle("Push(F2)", bare)).is_not_empty()
	var by_fire := _board({ NEXT_DOOR: Terrain.Kind.ROCK }, { NEXT_DOOR: [Terrain.TileState.BURNING] })
	assert_str(_fizzle("Push(F2)", by_fire)).is_empty()


# --- what a row names (#1532) ------------------------------------------------------------------

# A row may name several substances, and the cell then holds each of them as a real source.
func test_a_row_naming_two_substances_lends_both() -> void:
	var board := _board({ NEXT_DOOR: Terrain.Kind.ROCK }, { NEXT_DOOR: [Terrain.TileState.BURNING] })
	var supply := _supply(board, null, _map(["flame", "atom_fire"]))
	for id: String in ["flame", "atom_fire"]:
		assert_int(supply.get(id, 0)).override_failure_message(
				"a Burning row naming '%s' did not supply it" % id).is_equal(CellSubstances.PLENTY)


# #1535's question, asked of the mechanism: a fire whose row lends heat is a real source of it, so a
# recipe asking more heat than the air's one holds beside it, and fizzles beside one whose row does not.
# A lit prop reads Burning's row, so it answers the same.
func test_heat_beyond_the_airs_one_holds_only_beside_a_fire_that_lends_it() -> void:
	var by_fire := _board({ NEXT_DOOR: Terrain.Kind.ROCK }, { NEXT_DOOR: [Terrain.TileState.BURNING] })
	var by_lamp := _board({ NEXT_DOOR: Terrain.Kind.ROCK }, {}, { NEXT_DOOR: true })
	var lends := _map(["flame", "atom_fire"])
	for board: BoardContext in [by_fire, by_lamp]:
		assert_str(_fizzle("Push(3F)", board)).contains("source of")
		assert_str(_fizzle("Push(3F)", board, null, lends)).is_empty()
	assert_str(_fizzle("Push(3F)", _board({}), null, lends)).override_failure_message(
			"Push(3F) held with no fire near").contains("source of")


# The map a caller hands in is the one read, never the authored file behind it: a fixture rock made of
# water offers water, and the fixture's own empty rock does not.
func test_the_map_handed_in_is_the_one_read() -> void:
	var map := _map()
	map.grounds[Terrain.Kind.ROCK] = PackedStringArray(["water"])
	var board := _board({ NEXT_DOOR: Terrain.Kind.ROCK })
	assert_bool(_present(board).has("water")).is_false()
	assert_bool(_supply(board, null, map).has("water")).override_failure_message(
			"available_near read some other map than the one it was handed").is_true()


func test_a_gas_on_a_neighbour_is_present() -> void:
	var gas := GasField.new()
	gas.set_level(NEXT_DOOR, Gas.Kind.STEAM, 1)
	assert_bool(_present(_board({}, {}, {}, gas)).has("steam")).is_true()


# --- who stands there ------------------------------------------------------------------------

func test_a_wet_unit_on_a_neighbour_offers_water() -> void:
	var wet := H.spawn_unit(self, Team.Faction.ENEMY, NEXT_DOOR)
	wet.add_element_state(Elemental.State.WET)
	var on_board: Array[Unit] = [wet]
	assert_bool(_present(_board({}, {}, {}, null, on_board)).has("water")).is_true()


# The caster counts wherever it CASTS from: its body is handed in, so the scan of who stands nearby
# need not find it.
func test_a_wet_caster_brings_its_own_water() -> void:
	var caster := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(20, 20))
	caster.add_element_state(Elemental.State.WET)
	var board := _board({})
	assert_bool(_present(board).has("water")).is_false()
	assert_bool(_present(board, caster).has("water")).override_failure_message(
			"the caster's own wetness was not counted where it casts").is_true()
	assert_str(_fizzle("Focus(W2) + Push(W2)", board, caster)).is_empty()


# --- reach -----------------------------------------------------------------------------------

# Materia's footprint: the caster's cell and its neighbours, and nothing past them.
func test_reach_is_materias_two_away_is_not_present() -> void:
	assert_int(GridUtils.manhattan_distance(HERE, TWO_AWAY)).override_failure_message(
			"fixture: TWO_AWAY must sit past Materia.REACH").is_greater(Materia.REACH)
	var far := _board({ TWO_AWAY: Terrain.Kind.WATER }, { TWO_AWAY: [Terrain.TileState.BURNING] },
			{ TWO_AWAY: true })
	var present := _present(far)
	assert_bool(present.has("water")).is_false()
	assert_bool(present.has("flame")).is_false()
	assert_bool(_present(_board({ NEXT_DOOR: Terrain.Kind.WATER })).has("water")).is_true()


# --- how much (#1328) ------------------------------------------------------------------------

# The air supplies one of what it holds, whatever the board's reading says.
func test_the_air_supplies_one_of_what_it_holds() -> void:
	var supply := _supply(_board({}))
	for id: String in Atmosphere.SUBSTANCES:
		assert_int(supply.get(id, 0)).override_failure_message(
				"ambient '%s' is not the air's one" % id).is_equal(CellSubstances.AIR)


# Every real source supplies any amount: a ground and its parts, a tile state, a gas, a lit prop, a
# neighbour's states and the caster's own.
func test_every_real_source_supplies_plenty() -> void:
	var gas := GasField.new()
	gas.set_level(NEXT_DOOR, Gas.Kind.STEAM, 1)
	var wet := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(4, 5))
	wet.add_element_state(Elemental.State.WET)
	var on_board: Array[Unit] = [wet]
	var board := _board({ HERE: Terrain.Kind.DIRT, NEXT_DOOR: Terrain.Kind.ROCK },
			{ Vector2i(3, 4): [Terrain.TileState.BURNING] }, {}, gas, on_board)
	var supply := _supply(board)
	for id: String in ["dirt", "salt", "flame", "steam", "water"]:
		assert_int(supply.get(id, 0)).override_failure_message(
				"'%s' is not plenty" % id).is_equal(CellSubstances.PLENTY)
	var caster := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(20, 20))
	caster.add_element_state(Elemental.State.WET)
	assert_int(_supply(_board({}), caster).get("water", 0)).override_failure_message(
			"the caster's own water is not plenty").is_equal(CellSubstances.PLENTY)


# A source that lends an ambient substance raises it past the air's one: smoke is ash and inert air,
# so a gale's worth of air holds in smoke and fizzles on a bare board.
func test_a_source_raises_an_ambient_substance_to_plenty() -> void:
	var gas := GasField.new()
	gas.set_level(NEXT_DOOR, Gas.Kind.SMOKE, 1)
	var smoky := _board({}, {}, {}, gas)
	assert_int(_supply(smoky).get("inert_air", 0)).is_equal(CellSubstances.PLENTY)
	assert_str(_fizzle("Push(3A2)", _board({}))).contains("source of")
	assert_str(_fizzle("Push(3A2)", smoky)).is_empty()


# The proposal's jet: a number means a real source in reach, and making the water from the air is not
# one -- the air's one vapor makes one water.
func test_a_jet_needs_real_water_and_cannot_be_made_from_air() -> void:
	var bare := _board({})
	var by_water := _board({ NEXT_DOOR: Terrain.Kind.WATER })
	assert_str(_fizzle("Focus(3W2) + Push(3W2)", bare)).contains("source of water")
	assert_str(_fizzle("Focus(3W2) + Push(3W2)", by_water)).is_empty()
	assert_str(_fizzle("Break(A, W) + Push(3W2)", bare)).contains("source of water")
	assert_str(_fizzle("Break(A, W) + Push(3W2)", by_water)).is_empty()
	assert_str(_fizzle("Break(A, W) + Push(W2)", bare)).is_empty()


# The dev tools' readout of a row (#1532) is the same walk: what a row makes present is exactly what a
# cast on that ground finds, beside what the air holds.
func test_what_a_row_makes_present_is_what_a_cast_finds() -> void:
	var map := _map()
	for kind: Terrain.Kind in [Terrain.Kind.GRASS, Terrain.Kind.MUD, Terrain.Kind.DIRT]:
		var row := map.of_kind(kind)
		var expected: Array[String] = row.duplicate()
		expected.append_array(Atmosphere.SUBSTANCES)
		var from_row := CellSubstances.present_from(expected, _catalog())
		from_row.sort()
		var found: Array[String] = []
		found.assign(_supply(_board({ HERE: kind })).keys())
		found.sort()
		assert_array(found).override_failure_message("%s's row" % Terrain.Kind.keys()[kind]).is_equal(from_row)
