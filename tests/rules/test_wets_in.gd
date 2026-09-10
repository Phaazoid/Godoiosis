# RulesService.wets_in (#884) -- does OCCUPYING this cell soak this unit? drowns_in's sibling, and
# the four answers it has to get right off one comparison: shallow soaks, deep soaks, ice does not,
# and a Waterwalker crossing either stays dry.
#
# Kinds are AUTHORED per cell rather than painted, the test_ice.gd idiom: which atlas coordinate is
# water is content (the content razor), and what is under test is the rule.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const PLAYER := Team.Faction.PLAYER

const SHALLOW := Vector2i(1, 0)   # water a unit may stand on
const DEEP := Vector2i(2, 0)      # water it may not
const DRY := Vector2i(0, 0)

# Water authored per cell, with walkability forked so shallow and deep are genuinely different cells
# -- which is the whole point: depth is walkability, and wetness must not read it.
class _WaterBoard extends BoardContext:
	var deep_cells: Array[Vector2i]
	func _init(states: TerrainStateManager, deep: Array[Vector2i]) -> void:
		var no_units: Array[Unit] = []
		super(null, no_units, null, states)
		deep_cells = deep
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.WATER if cell != DRY else Terrain.Kind.GRASS
	func is_walkable(cell: Vector2i) -> bool:
		if has_tile_state(cell, Terrain.TileState.FROZEN):
			return true      # #109: ice is solid ground, the rule this fixture must not lose
		return not deep_cells.has(cell)

func _board(frozen: Array[Vector2i] = []) -> _WaterBoard:
	var states: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(states)
	for cell in frozen:
		var freeze := ResolvedCellEffect.new()
		freeze.cell = cell
		freeze.states_added.assign([Terrain.TileState.FROZEN])
		states.apply(freeze)
	var deep: Array[Vector2i] = [DEEP]
	return _WaterBoard.new(states, deep)

func _walker() -> Unit:
	return H.spawn_unit(self, PLAYER, DRY)

func _waterwalker() -> Unit:
	var unit := _walker()
	var granted := AbilityData.new()
	granted.id = Abilities.Id.WATERWALK
	unit.unit_instance.data.innate_abilities = [granted]
	return unit


func test_wading_shallow_water_soaks() -> void:
	assert_bool(RulesService.wets_in(SHALLOW, _walker(), _board())).is_true()

# The load-bearing half: depth is walkability and wetness does not read it, so the cell a unit CANNOT
# stand on soaks exactly like the one it can. A drowning body comes up wet.
func test_deep_water_soaks_too() -> void:
	assert_bool(RulesService.wets_in(DEEP, _walker(), _board())).is_true()

func test_dry_ground_does_not_soak() -> void:
	assert_bool(RulesService.wets_in(DRY, _walker(), _board())).is_false()

# Ice is dry ground (dev, 2026-09-10) -- and asserted over BOTH depths, because FROZEN is the one
# exemption that has to beat the kind rather than the walkability: the shallow cell is already
# walkable, so a frozen-shallow case alone would pass against a rule that only read is_walkable.
func test_frozen_water_does_not_soak_at_either_depth() -> void:
	var frozen: Array[Vector2i] = [SHALLOW, DEEP]
	var board := _board(frozen)
	assert_bool(RulesService.wets_in(SHALLOW, _walker(), board)).is_false()
	assert_bool(RulesService.wets_in(DEEP, _walker(), board)).is_false()

# Waterwalk "stands on the surface instead" (the Glossary's own promise), so it crosses both depths
# dry. Deep is the case can_traverse would already have answered; SHALLOW is the one that pins the
# ability being asked DIRECTLY, since shallow water is walkable to everybody.
func test_a_waterwalker_stays_dry_at_either_depth() -> void:
	var board := _board()
	var walker := _waterwalker()
	assert_bool(RulesService.wets_in(DEEP, walker, board)).is_false()
	assert_bool(RulesService.wets_in(SHALLOW, walker, board)).is_false()

# ...and the pairing that makes the case above mean something: the SAME cells soak an ordinary unit.
func test_the_waterwalk_exemption_is_the_abilitys_and_not_the_cells() -> void:
	var board := _board()
	assert_bool(RulesService.wets_in(SHALLOW, _walker(), board)).is_true()
	assert_bool(RulesService.wets_in(DEEP, _walker(), board)).is_true()
