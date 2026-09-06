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

# BLAZE is authored set-dressing fire; Terrain.is_burning owns which members count, and asking it
# rather than naming BURNING is what makes this pass without a second list here.
func test_a_blazing_cell_is_a_fire_source() -> void:
	var board := _board({ HERE: Terrain.Kind.GRASS }, { HERE: [Terrain.TileState.BLAZE] })
	assert_array(Materia.sources_at(HERE, board)).contains([FIRE])

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
