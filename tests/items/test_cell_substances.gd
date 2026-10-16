# Which substances are present for a cast (CellSubstances.available_near) -- the presence half of
# Deep Alchemy Phase 2's fizzle rule. Canon: docs/design/deep-alchemy.md -> What is built.
#
# The board is stubbed, test_materia_sources.gd's fixture one store wider: kinds, lit props and who
# stands where are authored directly, STATES ride a real TerrainStateManager and gas a real GasField.
# Every case hands available_near its own catalog, so nothing here reads an authored substance file
# (tests/README.md rule 9) -- the ids match SubstanceMap's rows, which is what the code looks up.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const HERE := Vector2i(4, 4)
const NEXT_DOOR := Vector2i(5, 4)
const TWO_AWAY := Vector2i(6, 4)


class _SubstanceBoard extends BoardContext:
	var kinds: Dictionary
	var lit: Dictionary
	var standing: Dictionary   # cell -> Unit
	func _init(states: TerrainStateManager, gas_field: GasField, k: Dictionary, l: Dictionary, s: Dictionary) -> void:
		var no_units: Array[Unit] = []
		super(null, no_units, null, states, null, null, gas_field)
		kinds = k
		lit = l
		standing = s
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.NONE)
	func prop_lit_at(cell: Vector2i) -> bool:
		return lit.get(cell, false)
	func unit_at_cell(cell: Vector2i) -> Unit:
		return standing.get(cell) as Unit


func _sub(formula: String, name: String = "") -> Substance:
	var s := Substance.new()
	s.formula = formula
	s.display_name = name
	return s


# The fixture's own chemistry: the ambient four, the grounds SubstanceMap names, and their parts.
func _catalog() -> Dictionary:
	return {
		"inert_air": _sub("A2"), "vital_air": _sub("FA"), "vapor": _sub("AW"), "atom_aether": _sub("Q"),
		"atom_fire": _sub("F"), "atom_air": _sub("A"), "atom_water": _sub("W"), "atom_earth": _sub("E"),
		"water": _sub("W2", "Water"), "ice": _sub("QW", "Ice"), "flame": _sub("F2", "Flame"),
		"steam": _sub("FW", "Steam"), "salt": _sub("E2", "Salt"), "ash": _sub("AE", "Ash"),
		"lightning": _sub("QF", "Lightning"),
		"dirt": _sub("E2 + AE", "Dirt"),
		"mud": _sub("dirt + W2", "Mud"),
		"green_plant": _sub("AE + 2FA + W2", "Green plant"),
		"dry_plant": _sub("AE + 2FA", "Dry plant"),
	}


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
		gas: GasField = null, standing: Dictionary = {}) -> _SubstanceBoard:
	return _SubstanceBoard.new(_store(cell_states), gas, kinds, lit, standing)


func _present(board: BoardContext, caster: Unit = null) -> Array[String]:
	return CellSubstances.available_near(HERE, board, caster, _catalog())


func _fizzle(recipe: String, board: BoardContext, caster: Unit = null) -> String:
	var parsed := CarvingRecipe.parse(recipe, _catalog())
	assert_str(parsed.error).override_failure_message("fixture recipe '%s' does not parse: %s"
			% [recipe, parsed.error]).is_empty()
	return parsed.fizzle_reason(CellSubstances.available_near(HERE, board, caster, _catalog()), _catalog())


# --- the baseline ---------------------------------------------------------------------------

func test_the_ambient_air_is_present_everywhere() -> void:
	var present := _present(_board({}))
	for id: String in Atmosphere.SUBSTANCES:
		assert_bool(present.has(id)).override_failure_message("ambient '%s' missing" % id).is_true()


func test_a_null_board_still_has_the_ambient_air() -> void:
	assert_array(CellSubstances.available_near(HERE, null, null, _catalog())) \
		.contains_exactly(Atmosphere.SUBSTANCES)


# The ids this file names are real substances -- a renamed file would otherwise leave a silent hole.
func test_every_id_cell_substances_names_is_a_real_substance() -> void:
	var real := SubstanceCatalog.get_all()
	for id: String in Atmosphere.SUBSTANCES + CellSubstances.LENDS_NOTHING:
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


# Plant matter is present as itself and lends NOTHING (c3potheds@): a grass field holds no water.
# The dirt it stands on still lends its parts -- the #1315 default.
func test_plant_matter_lends_no_water_and_grass_stands_on_dirt() -> void:
	var present := _present(_board({ HERE: Terrain.Kind.GRASS, NEXT_DOOR: Terrain.Kind.TALL_GRASS }))
	assert_bool(present.has("green_plant")).is_true()
	assert_bool(present.has("dry_plant")).is_true()
	assert_bool(present.has("water")).override_failure_message(
			"a plant lent its water -- organic matter lends nothing").is_false()
	assert_bool(present.has("dirt")).override_failure_message("grass stands on no dirt").is_true()
	assert_bool(present.has("salt")).is_true()
	assert_str(_fizzle("Focus(W2) + Push(W2)", _board({ HERE: Terrain.Kind.GRASS }))).contains("water")


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


func test_a_gas_on_a_neighbour_is_present() -> void:
	var gas := GasField.new()
	gas.set_level(NEXT_DOOR, Gas.Kind.STEAM, 1)
	assert_bool(_present(_board({}, {}, {}, gas)).has("steam")).is_true()


# --- who stands there ------------------------------------------------------------------------

func test_a_wet_unit_on_a_neighbour_offers_water() -> void:
	var wet := H.spawn_unit(self, Team.Faction.ENEMY, NEXT_DOOR)
	wet.add_element_state(Elemental.State.WET)
	assert_bool(_present(_board({}, {}, {}, null, { NEXT_DOOR: wet })).has("water")).is_true()


# The caster counts wherever it CASTS from, which is often a cell it has only queued a move to: the
# live scan would not find it there.
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
