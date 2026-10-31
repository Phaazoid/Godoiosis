# #1444: "is this cell water a body is IN rather than ON" has ONE answer, BoardContext.is_open_water,
# and the readers that ask it -- the current, a water source, a carving's draw, a soak, and since #894
# where a laid tile effect fizzles -- agree with it on every cell the question forks on. A reader that
# keeps its own copy drifts here first.
#
# Kinds are AUTHORED per cell rather than painted (test_wets_in.gd's idiom) and FROZEN rides a real
# TerrainStateManager. The probes sit apart, so CellSubstances' reach never meets a second one.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const PLAYER := Team.Faction.PLAYER

const OPEN := Vector2i(0, 0)
const FROZEN := Vector2i(4, 0)
const CHILLED_IN := Vector2i(8, 0)   # open water with a CHILLED body in it: #1092 is the callers' rule
const DRY := Vector2i(12, 0)
const ELSEWHERE := Vector2i(20, 20)  # where the ordinary asker stands, beside no probe


class _WaterBoard extends BoardContext:
	func _init(states: TerrainStateManager, unit_list: Array[Unit]) -> void:
		super(null, unit_list, null, states)
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		if cell == OPEN or cell == FROZEN or cell == CHILLED_IN:
			return Terrain.Kind.WATER
		return Terrain.Kind.GRASS if cell == DRY else Terrain.Kind.NONE


func _water() -> Substance:
	var water := Substance.new()
	water.formula = "W2"
	return water


func test_the_readers_agree_with_is_open_water() -> void:
	var states: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(states)
	var freeze := ResolvedCellEffect.new()
	freeze.cell = FROZEN
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	states.apply(freeze)
	var walker := H.spawn_unit(self, PLAYER, ELSEWHERE)
	var chilled := H.spawn_unit(self, PLAYER, CHILLED_IN)
	chilled.add_element_state(Elemental.State.CHILLED)
	var units: Array[Unit] = [walker, chilled]
	var board := _WaterBoard.new(states, units)
	var water_id := SubstanceMap.of_kind(Terrain.Kind.WATER)
	var catalog := { water_id: _water() }
	var no_wet: Dictionary[Vector2i, bool] = {}
	var laying := AttackData.new()
	laying.tile_effect = Elemental.Element.FIRE
	var expected := { OPEN: true, FROZEN: false, CHILLED_IN: true, DRY: false }
	for cell: Vector2i in expected:
		var open := board.is_open_water(cell)
		assert_bool(open == bool(expected[cell])).override_failure_message(
			"is_open_water(%s) answered %s" % [cell, open]).is_true()
		var asker := chilled if cell == CHILLED_IN else walker
		var answers := {
			"Conduction.conducts": Conduction.conducts(cell, board, no_wet),
			"Materia.sources_at": Materia.sources_at(cell, board).has(Elemental.Element.WATER),
			"CellSubstances.available_near": CellSubstances.available_near(cell, board, null, catalog).has(water_id),
			"RulesService.wets_in": RulesService.wets_in(cell, asker.state, board),
			"PlanResolver._lay_tile_effect fizzles": PlanResolver._lay_tile_effect(cell, laying, board, null) == null,
		}
		for reader: String in answers:
			assert_bool(bool(answers[reader]) == open).override_failure_message(
				"%s says %s at %s, but is_open_water says %s" % [reader, answers[reader], cell, open]).is_true()
