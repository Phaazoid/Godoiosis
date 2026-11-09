# #694: which elements a cell OFFERS (Materia.sources_at) and which a caster standing there may
# draw on (Materia.empowered_at). Canon: docs/design/alchemy-kit.md -> Materia.
#
# The board is stubbed rather than painted -- the fixture grid has no TileSet, which is also why
# Materia reads through BoardContext METHODS instead of its stores: `super(null, ...)` here would
# crash any predicate that reached for `grid` itself.
extends GdUnitTestSuite

const HERE := Vector2i(4, 4)
const NEXT_DOOR := Vector2i(5, 4)
const TWO_AWAY := Vector2i(6, 4)

const WATER := Elemental.Element.WATER
const EARTH := Elemental.Element.EARTH
const FIRE := Elemental.Element.FIRE

# Kinds and lit-props authored directly; STATES ride a real TerrainStateManager, because the
# frozen-water and doused-fire cases are the whole point of asking the board rather than the tile.
class _MateriaBoard extends BoardContext:
	var kinds: Dictionary
	var lit: Dictionary
	func _init(states: TerrainStateManager, k: Dictionary, l: Dictionary = {}) -> void:
		var no_units: Array[Unit] = []
		super(null, no_units, null, states)
		kinds = k
		lit = l
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.NONE)
	func prop_lit_at(cell: Vector2i) -> bool:
		return lit.get(cell, false)

func _store(cell_states: Dictionary = {}) -> TerrainStateManager:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	for cell: Vector2i in cell_states:
		var effect := ResolvedCellEffect.new()
		effect.cell = cell
		effect.states_added.assign(cell_states[cell])
		tsm.apply(effect)
	return tsm

func _board(kinds: Dictionary, cell_states: Dictionary = {}, lit: Dictionary = {}) -> _MateriaBoard:
	return _MateriaBoard.new(_store(cell_states), kinds, lit)

# --- what a cell offers -------------------------------------------------------------------

func test_a_water_tile_is_a_water_source() -> void:
	var board := _board({ HERE: Terrain.Kind.WATER })
	assert_array(Materia.sources_at(HERE, board)).contains([WATER])

# Ice is a floor, not a well -- the same state-aware read is_walkable makes of the same cell.
func test_frozen_water_is_not_a_water_source() -> void:
	var board := _board({ HERE: Terrain.Kind.WATER }, { HERE: [Terrain.TileState.FROZEN] })
	assert_array(Materia.sources_at(HERE, board)).is_empty()

func test_a_rock_tile_is_an_earth_source() -> void:
	var board := _board({ HERE: Terrain.Kind.ROCK })
	assert_array(Materia.sources_at(HERE, board)).contains([EARTH])

func test_a_burning_cell_is_a_fire_source() -> void:
	var board := _board({ HERE: Terrain.Kind.GRASS }, { HERE: [Terrain.TileState.BURNING] })
	assert_array(Materia.sources_at(HERE, board)).contains([FIRE])

# The BLAZE twin of the case above went with #890, which retired that state -- with one fire member
# it was a byte-identical duplicate. Materia still asks Terrain.is_burning rather than naming
# BURNING, so a second fire spelling would reach here with no edit.

func test_a_lit_prop_is_a_fire_source() -> void:
	var board := _board({ HERE: Terrain.Kind.ROCK }, {}, { HERE: true })
	assert_array(Materia.sources_at(HERE, board)).contains([FIRE])

# The dev's 2026-09-05 ruling: an unlit flammable is FUEL, not a source. A tree offers nothing
# until it catches -- and nothing for AETHER either, which awaits authored life-dense content.
func test_an_unlit_tree_offers_nothing() -> void:
	var board := _board({ HERE: Terrain.Kind.TREE })
	assert_array(Materia.sources_at(HERE, board)).is_empty()

# AIR is parked and AETHER unauthored, so no terrain kind may yield either. Walking every kind
# states that as a rule rather than trusting the three positive cases above to have covered it.
func test_no_terrain_kind_offers_air_or_aether() -> void:
	for kind: int in Terrain.Kind.values():
		var board := _board({ HERE: kind })
		var offered := Materia.sources_at(HERE, board)
		assert_bool(offered.has(Elemental.Element.AIR)) \
			.override_failure_message("kind %d offered AIR" % kind).is_false()
		assert_bool(offered.has(Elemental.Element.AETHER)) \
			.override_failure_message("kind %d offered AETHER" % kind).is_false()

func test_a_null_board_offers_nothing() -> void:
	assert_array(Materia.sources_at(HERE, null)).is_empty()

# --- what a caster standing there may draw on ---------------------------------------------

func test_standing_on_the_source_empowers() -> void:
	var board := _board({ HERE: Terrain.Kind.WATER })
	assert_array(Materia.empowered_at(HERE, board)).contains([WATER])

func test_standing_beside_the_source_empowers() -> void:
	var board := _board({ NEXT_DOOR: Terrain.Kind.WATER })
	assert_array(Materia.empowered_at(HERE, board)).contains([WATER])

func test_two_cells_away_does_not_empower() -> void:
	var board := _board({ TWO_AWAY: Terrain.Kind.WATER })
	assert_array(Materia.empowered_at(HERE, board)).is_empty()

# Empowerment is BINARY: two sources of one element still read as empowered once, which is what
# stops a vein beside a river paying twice when #696 lands.
func test_two_sources_of_one_element_do_not_stack() -> void:
	var board := _board({ HERE: Terrain.Kind.WATER, NEXT_DOOR: Terrain.Kind.WATER })
	assert_array(Materia.empowered_at(HERE, board)).is_equal([WATER])

func test_different_elements_in_reach_both_empower() -> void:
	var board := _board({ HERE: Terrain.Kind.WATER, NEXT_DOOR: Terrain.Kind.ROCK })
	var empowered := Materia.empowered_at(HERE, board)
	assert_bool(empowered.has(WATER)).is_true()
	assert_bool(empowered.has(EARTH)).is_true()

# --- materia veins (#696) ------------------------------------------------------------------

# A vein rides the board's vein store, not its kind: the stub's grass under every cell is offered
# nothing, so whatever a case reads came from the vein.
func _vein_board(veins: Dictionary) -> _MateriaBoard:
	var board := _board({ HERE: Terrain.Kind.GRASS, NEXT_DOOR: Terrain.Kind.GRASS, TWO_AWAY: Terrain.Kind.GRASS })
	board.veins = VeinField.new()
	for cell: Vector2i in veins:
		board.veins.set_kind(cell, veins[cell])
	return board

func test_a_tagged_vein_empowers_its_own_element() -> void:
	var board := _vein_board({ NEXT_DOOR: Vein.Kind.FIRE })
	assert_array(Materia.sources_at(NEXT_DOOR, board)).is_equal([FIRE])
	assert_array(Materia.empowered_at(HERE, board)).is_equal([FIRE])

# The same reach as any source: on it or beside it, never two away.
func test_a_vein_two_cells_away_does_not_empower() -> void:
	var board := _vein_board({ TWO_AWAY: Vein.Kind.FIRE })
	assert_array(Materia.empowered_at(HERE, board)).is_empty()

# Air and aether have no terrain source (test_no_terrain_kind_offers_air_or_aether); a vein is
# the authored content they waited on.
func test_air_and_aether_veins_are_their_sources() -> void:
	var board := _vein_board({ HERE: Vein.Kind.AIR, NEXT_DOOR: Vein.Kind.AETHER })
	var empowered := Materia.empowered_at(HERE, board)
	assert_bool(empowered.has(Elemental.Element.AIR)).is_true()
	assert_bool(empowered.has(Elemental.Element.AETHER)).is_true()

# Alkahest is universal: the alkahest vial's own answer, asked rather than restated.
func test_an_alkahest_vein_empowers_every_sigil_element() -> void:
	var board := _vein_board({ HERE: Vein.Kind.ALKAHEST })
	var empowered := Materia.empowered_at(HERE, board)
	assert_array(empowered).contains_exactly_in_any_order(Elemental.SIGIL_ELEMENTS)
	var vial := VialData.new()
	vial.is_alkahest = true
	assert_array(empowered).contains_exactly_in_any_order(vial.granted_elements())

# A lightning vein makes lightning PRESENT (its SubstanceMap row) and empowers nothing (#1312's ruling).
func test_a_lightning_vein_empowers_nothing() -> void:
	var board := _vein_board({ HERE: Vein.Kind.LIGHTNING })
	assert_array(Materia.empowered_at(HERE, board)).is_empty()

# A vein beside a matching river still empowers once: binary, as any two sources of one element.
func test_a_vein_beside_its_terrain_source_does_not_stack() -> void:
	var board := _vein_board({ NEXT_DOOR: Vein.Kind.WATER })
	board.kinds[HERE] = Terrain.Kind.WATER
	assert_array(Materia.empowered_at(HERE, board)).is_equal([WATER])

# A board built without a vein store (every fixture but game's and the Play API's) reads no veins.
func test_a_board_without_a_vein_store_reads_none() -> void:
	var board := _board({ HERE: Terrain.Kind.GRASS })
	assert_int(board.vein_at(HERE)).is_equal(Vein.Kind.NONE)

# --- the aim's source outline (#699): which sources a stand this turn could draw on ---------------

const FAR := Vector2i(8, 4)

func _stands(cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(cells)
	return out

func _asked(elements: Array) -> Array[Elemental.Element]:
	var out: Array[Elemental.Element] = []
	out.assign(elements)
	return out

# A river is drawn on from its bank: the source need not be a cell anyone stands on.
func test_a_source_beside_a_stand_is_marked_though_nobody_stands_on_it() -> void:
	var board := _board({ NEXT_DOOR: Terrain.Kind.WATER })
	var found := Materia.sources_near(_stands([HERE]), _asked([WATER]), board)
	assert_array(found.keys()).is_equal([NEXT_DOOR])
	assert_array(found[NEXT_DOOR]).is_equal([WATER])

# Exactly the reach that empowers: two cells beyond every stand is no source of this aim.
func test_a_source_two_cells_beyond_every_stand_is_not_marked() -> void:
	var board := _board({ TWO_AWAY: Terrain.Kind.WATER })
	assert_dict(Materia.sources_near(_stands([HERE]), _asked([WATER]), board)).is_empty()

# The outline is sources_near read backwards from empowered_at, so for every stand the two must agree:
# a stand is empowered in an element exactly when a marked source of it lies within REACH.
func test_a_marked_source_is_exactly_one_that_would_empower_a_stand() -> void:
	var board := _vein_board({ NEXT_DOOR: Vein.Kind.FIRE, FAR: Vein.Kind.FIRE })
	var found := Materia.sources_near(_stands([HERE]), _asked([FIRE]), board)
	assert_bool(Materia.empowered_at(HERE, board).has(FIRE)).is_true()
	assert_array(found.keys()).is_equal([NEXT_DOOR])

# Only what the aim asks for: a fire vein beside a river marks the vein for fire alone.
func test_only_the_asked_elements_are_marked() -> void:
	var board := _vein_board({ NEXT_DOOR: Vein.Kind.FIRE })
	board.kinds[HERE] = Terrain.Kind.WATER
	var found := Materia.sources_near(_stands([HERE]), _asked([FIRE]), board)
	assert_array(found.keys()).is_equal([NEXT_DOOR])
	assert_dict(Materia.sources_near(_stands([HERE]), _asked([EARTH]), board)).is_empty()

# Ice is a floor, not a well: a frozen river beside the bank marks nothing.
func test_a_frozen_river_is_not_marked() -> void:
	var board := _board({ NEXT_DOOR: Terrain.Kind.WATER }, { NEXT_DOOR: [Terrain.TileState.FROZEN] })
	assert_dict(Materia.sources_near(_stands([HERE]), _asked([WATER]), board)).is_empty()

# An alkahest vein offers every asked element, in the order they were asked.
func test_an_alkahest_vein_offers_each_asked_element_in_the_asked_order() -> void:
	var board := _vein_board({ NEXT_DOOR: Vein.Kind.ALKAHEST })
	var found := Materia.sources_near(_stands([HERE]), _asked([Elemental.Element.AETHER, WATER]), board)
	assert_array(found[NEXT_DOOR]).is_equal([Elemental.Element.AETHER, WATER])

# The walk is Move's own answer plus the cell the unit already stands on, which compute_move_range omits.
func test_the_walk_counts_where_the_unit_already_stands() -> void:
	var board := _vein_board({ NEXT_DOOR: Vein.Kind.FIRE })
	var no_moves := {"reachable": {}}
	var found := Materia.sources_within_walk(HERE, no_moves, _asked([FIRE]), board)
	assert_array(found.keys()).is_equal([NEXT_DOOR])

func test_the_walk_reaches_a_source_by_a_cell_move_offers() -> void:
	var board := _vein_board({ FAR: Vein.Kind.FIRE })
	var move_range := {"reachable": {Vector2i(7, 4): 3}}
	assert_array(Materia.sources_within_walk(HERE, move_range, _asked([FIRE]), board).keys()).is_equal([FAR])
	assert_dict(Materia.sources_within_walk(HERE, {"reachable": {}}, _asked([FIRE]), board)).is_empty()

func test_nothing_asked_marks_nothing() -> void:
	var board := _vein_board({ NEXT_DOOR: Vein.Kind.ALKAHEST })
	assert_dict(Materia.sources_near(_stands([HERE]), _asked([]), board)).is_empty()
