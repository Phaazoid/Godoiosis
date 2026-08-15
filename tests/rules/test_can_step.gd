# RulesService.can_step (#257) — the EDGE question elevation needed. can_traverse answers "may this
# unit be on that cell"; this answers "may it get there from here", which is the only shape that can
# express "only via a ramp, and only along the ramp's slope".
#
# Uses the REAL TestTiles-backed board (BoardBuilder) because movement_cost reads tile custom data
# straight off the grid. Elevation itself needs no new tiles or art — it is a per-cell store, which
# is exactly why the design put it there instead of in tileset custom data.
#
# Ramp geometry used throughout, laid out west→east on row y=1 (a ramp's own elevation is its LOW
# side, so the climb happens LEAVING it):
#
#   (0,1) flat h0   (1,1) RAMP h0 rising EAST   (2,1) flat h1
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

func _board() -> Dictionary:
	var board := BoardBuilder.build(self)
	auto_free(board.root)
	BoardBuilder.paint_rect(board.grid, Rect2i(0, 0, 6, 3))
	return board

func _heights(board: Dictionary) -> BoardHeights:
	var heights: BoardHeights = board.board_heights
	return heights

func _spawn(board: Dictionary, cell: Vector2i) -> Unit:
	return BoardBuilder.spawn(board, H.make_unit_data({}, PLAYER), cell)

func _context(board: Dictionary, unit: Unit) -> BoardContext:
	var units: Array[Unit] = [unit]
	return BoardContext.new(board.grid, units, board.squad_manager, null, null, board.board_heights)

# One ramp at (1,1) rising east, its high neighbour (2,1) one level up.
func _ramp_board() -> Dictionary:
	var board := _board()
	var heights := _heights(board)
	heights.set_cell(Vector2i(1, 1), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 1), 1)
	return board


# --- the defaults, which are decisions rather than gaps ---

func test_absent_cell_is_elevation_zero() -> void:
	# Sparse storage: a flat board saves as {}. BoardHeights is the ONE place that default lives, so
	# it is pinned here rather than left to whichever caller reads the dictionary first.
	var board := _board()
	assert_int(_heights(board).elevation_at(Vector2i(4, 2))).is_equal(0)
	assert_int(_heights(board).ramp_rise_at(Vector2i(4, 2))).is_equal(Terrain.RampRise.NONE)

func test_board_without_heights_reads_perfectly_flat() -> void:
	# The contract that let can_step ship without touching a single existing caller: a BoardContext
	# built with no heights store behaves exactly as the game did before elevation existed.
	var board := _board()
	var unit := _spawn(board, Vector2i(0, 1))
	var units: Array[Unit] = [unit]
	var flat := BoardContext.new(board.grid, units, board.squad_manager)

	assert_int(flat.elevation_at(Vector2i(2, 1))).is_equal(0)
	assert_bool(RulesService.can_step(Vector2i(0, 1), Vector2i(1, 1), unit, flat)).is_true()


# --- height changes need a ramp ---

func test_flat_step_is_legal() -> void:
	var board := _board()
	var unit := _spawn(board, Vector2i(0, 1))
	assert_bool(RulesService.can_step(Vector2i(0, 1), Vector2i(1, 1), unit, _context(board, unit))).is_true()

func test_a_climb_without_a_ramp_is_refused() -> void:
	var board := _board()
	_heights(board).set_cell(Vector2i(1, 1), 1)   # a bare rise: no ramp anywhere
	var unit := _spawn(board, Vector2i(0, 1))
	assert_bool(RulesService.can_step(Vector2i(0, 1), Vector2i(1, 1), unit, _context(board, unit))).is_false()

func test_a_drop_without_a_ramp_is_refused() -> void:
	# The mirror clause, and a separate one in the code: descending reads the DESTINATION's ramp.
	var board := _board()
	_heights(board).set_cell(Vector2i(0, 1), 1)
	var unit := _spawn(board, Vector2i(0, 1))
	assert_bool(RulesService.can_step(Vector2i(0, 1), Vector2i(1, 1), unit, _context(board, unit))).is_false()

func test_two_levels_is_never_one_step() -> void:
	# Ramps connect exactly +/-1. A cliff of five is a staircase of five ramps or it is unclimbable.
	var board := _board()
	var heights := _heights(board)
	heights.set_cell(Vector2i(1, 1), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 1), 2)
	var unit := _spawn(board, Vector2i(0, 1))
	assert_bool(RulesService.can_step(Vector2i(1, 1), Vector2i(2, 1), unit, _context(board, unit))).is_false()


# --- the ramp itself ---

func test_stepping_onto_a_ramp_from_its_low_side() -> void:
	var board := _ramp_board()
	var unit := _spawn(board, Vector2i(0, 1))
	assert_bool(RulesService.can_step(Vector2i(0, 1), Vector2i(1, 1), unit, _context(board, unit))).is_true()

func test_ramp_climbs_to_its_high_side() -> void:
	var board := _ramp_board()
	var unit := _spawn(board, Vector2i(0, 1))
	assert_bool(RulesService.can_step(Vector2i(1, 1), Vector2i(2, 1), unit, _context(board, unit))).is_true()

func test_ramp_descends_from_its_high_side() -> void:
	var board := _ramp_board()
	var unit := _spawn(board, Vector2i(2, 1))
	assert_bool(RulesService.can_step(Vector2i(2, 1), Vector2i(1, 1), unit, _context(board, unit))).is_true()

func test_climbing_the_wrong_way_off_a_ramp_is_refused() -> void:
	# A ramp rising EAST does not also climb WEST. Without this the rise direction would be doing no
	# work at all and a bare axis would have been enough.
	var board := _board()
	var heights := _heights(board)
	heights.set_cell(Vector2i(1, 1), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(0, 1), 1)   # high ground on the ramp's LOW side
	var unit := _spawn(board, Vector2i(2, 1))
	assert_bool(RulesService.can_step(Vector2i(1, 1), Vector2i(0, 1), unit, _context(board, unit))).is_false()


# --- no sideways entry: TWO clauses, tested in both directions ---
#
# The 2026-08-12 lesson from the stage-2 falsification round: a case covering only one direction let
# the entering-guard mutant survive. Leaving a ramp sideways and entering one sideways are separate
# guards in can_step and each needs its own case.

func test_a_ramp_refuses_sideways_ENTRY() -> void:
	var board := _ramp_board()
	var unit := _spawn(board, Vector2i(1, 0))
	assert_bool(RulesService.can_step(Vector2i(1, 0), Vector2i(1, 1), unit, _context(board, unit))).is_false()

func test_a_ramp_refuses_sideways_EXIT() -> void:
	var board := _ramp_board()
	var unit := _spawn(board, Vector2i(1, 1))
	assert_bool(RulesService.can_step(Vector2i(1, 1), Vector2i(1, 2), unit, _context(board, unit))).is_false()


# --- staircases and routing ---

func test_a_staircase_of_ramps_chains() -> void:
	# Each ramp's low side equals the previous ramp's height, which is what makes the chain work
	# without any Z arithmetic beyond +/-1.
	var board := _board()
	var heights := _heights(board)
	heights.set_cell(Vector2i(1, 1), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 1), 1, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(3, 1), 2)
	var unit := _spawn(board, Vector2i(0, 1))
	var context := _context(board, unit)

	assert_bool(RulesService.can_step(Vector2i(0, 1), Vector2i(1, 1), unit, context)).is_true()
	assert_bool(RulesService.can_step(Vector2i(1, 1), Vector2i(2, 1), unit, context)).is_true()
	assert_bool(RulesService.can_step(Vector2i(2, 1), Vector2i(3, 1), unit, context)).is_true()

func test_an_unramped_cliff_severs_the_connectivity_field() -> void:
	# path_hops is what SquadCohesion.field walks, so this is also the dev's "a 1-block rise blocks
	# squad range the way unwalkable terrain does" ruling — satisfied with no cohesion code at all.
	var board := _board()
	var heights := _heights(board)
	for y in range(0, 3):
		heights.set_cell(Vector2i(2, y), 1)   # a full-height ridge across the board, no ramps
	var unit := _spawn(board, Vector2i(0, 1))
	var field := RulesService.path_hops(Vector2i(0, 1), _context(board, unit), unit)

	assert_bool(field.has(Vector2i(1, 1))).is_true()    # near side reachable
	assert_bool(field.has(Vector2i(2, 1))).is_false()   # the ridge itself is unclimbable
	assert_bool(field.has(Vector2i(4, 1))).is_false()   # and nothing beyond it

func test_one_ramp_reopens_the_cliff() -> void:
	# The same ridge with a single ramp cut into it: the detour IS the cost, since climbing is free.
	var board := _board()
	var heights := _heights(board)
	for y in range(0, 3):
		heights.set_cell(Vector2i(2, y), 1)
	heights.set_cell(Vector2i(2, 0), 0, Terrain.RampRise.NORTH)   # unreachable rise dir on purpose
	heights.set_cell(Vector2i(2, 1), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(3, 1), 1)
	var unit := _spawn(board, Vector2i(0, 1))
	var field := RulesService.path_hops(Vector2i(0, 1), _context(board, unit), unit)

	assert_bool(field.has(Vector2i(2, 1))).is_true()
	assert_bool(field.has(Vector2i(3, 1))).is_true()

func test_move_range_refuses_an_unramped_cliff() -> void:
	# The weighted twin of the field test above — compute_move_range must agree with path_hops about
	# legality even though only one of them is weighted.
	var board := _board()
	var heights := _heights(board)
	for y in range(0, 3):
		heights.set_cell(Vector2i(2, y), 1)
	var unit := _spawn(board, Vector2i(0, 1))
	var result := RulesService.compute_move_range(unit, _context(board, unit))

	assert_bool(result.reachable.has(Vector2i(1, 1))).is_true()
	assert_bool(result.reachable.has(Vector2i(2, 1))).is_false()


# --- persistence ---

func test_heights_round_trip_through_a_scenario() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 1), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 1), 3)

	var scenario := ScenarioData.new()
	scenario.elevations = heights.to_elevation_dict()
	scenario.ramp_rises = heights.to_ramp_dict()

	var restored := BoardHeights.new()
	restored.load_dicts(scenario.elevations, scenario.ramp_rises)

	assert_int(restored.elevation_at(Vector2i(2, 1))).is_equal(3)
	assert_int(restored.ramp_rise_at(Vector2i(1, 1))).is_equal(Terrain.RampRise.EAST)
	# A ramp at height 0 is legal and must survive — which is why the two facts serialize separately.
	assert_int(restored.elevation_at(Vector2i(1, 1))).is_equal(0)
	assert_bool(restored.is_ramp(Vector2i(1, 1))).is_true()
