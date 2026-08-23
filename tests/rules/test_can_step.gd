# RulesService.can_step (#257) — the EDGE question elevation needed. can_traverse answers "may this
# unit be on that cell"; this answers "may it get there from here", which is the only shape that can
# express "only via a ramp, and only along the ramp's slope".
#
# Uses the REAL TestTiles-backed board (BoardBuilder) because movement_cost reads tile custom data
# straight off the grid. Elevation itself needs no new tiles or art — it is a per-cell store, which
# is exactly why the design put it there instead of in tileset custom data.
#
# Heights are in UNITS (#427): one level is 2, so a 45 degree ramp climbs 2. The numbers below are
# LITERAL on purpose — writing them as Terrain.UNITS_PER_LEVEL would make this suite agree with any
# value that constant took, and these boards are only ramps while a level really is 2.
#
# Ramp geometry used throughout, laid out west→east on row y=1 (a ramp's own height is its LOW
# side, so the climb happens LEAVING it):
#
#   (0,1) flat h0   (1,1) RAMP h0 rising EAST   (2,1) flat h2
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
	heights.set_cell(Vector2i(2, 1), 2)
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
	_heights(board).set_cell(Vector2i(1, 1), 2)   # a bare rise: no ramp anywhere
	var unit := _spawn(board, Vector2i(0, 1))
	assert_bool(RulesService.can_step(Vector2i(0, 1), Vector2i(1, 1), unit, _context(board, unit))).is_false()

func test_a_drop_without_a_ramp_is_refused() -> void:
	# The mirror clause, and a separate one in the code: descending reads the DESTINATION's ramp.
	var board := _board()
	_heights(board).set_cell(Vector2i(0, 1), 2)
	var unit := _spawn(board, Vector2i(0, 1))
	assert_bool(RulesService.can_step(Vector2i(0, 1), Vector2i(1, 1), unit, _context(board, unit))).is_false()

func test_two_levels_is_never_one_step() -> void:
	# Ramps connect exactly one level. A cliff of five is a staircase of five ramps or unclimbable.
	var board := _board()
	var heights := _heights(board)
	heights.set_cell(Vector2i(1, 1), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 1), 4)
	var unit := _spawn(board, Vector2i(0, 1))
	assert_bool(RulesService.can_step(Vector2i(1, 1), Vector2i(2, 1), unit, _context(board, unit))).is_false()


# --- the HALF level, newly representable (#427) ---

func test_a_half_level_edge_is_refused_like_any_other_sheer_edge() -> void:
	# Dev, 2026-08-23: "half height still blocks movement and melee range."
	#
	# OVER-DETERMINED, deliberately kept: on flat ground the ramp clause refuses this edge too, so a
	# mutant that relaxed the LEVEL clause alone left this case green (measured while falsifying).
	# It pins the ruling; the case below is the one that isolates the rule.
	var board := _board()
	_heights(board).set_cell(Vector2i(1, 1), 1)
	var unit := _spawn(board, Vector2i(0, 1))
	assert_bool(RulesService.can_step(Vector2i(0, 1), Vector2i(1, 1), unit, _context(board, unit))).is_false()

func test_a_ramp_does_not_connect_a_half_level_either() -> void:
	# A ramp is not a licence to cross any gap: this one climbs a full level, so a neighbour half a
	# level above its base is still unreachable from it.
	#
	# THE case with teeth for #427's blocking ruling: the ramp points the right way, so the height
	# clause is the only thing left that can refuse. Falsified twice — by relaxing slice 1's level
	# clause to `>`, and by slice 2's version of the same mistake, dropping the climb comparison so
	# a ramp crosses whatever gap it faces. Slice 2 added a second case saying exactly this on an
	# identical board; falsification found the duplicate and it was deleted rather than kept.
	var board := _board()
	var heights := _heights(board)
	heights.set_cell(Vector2i(1, 1), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 1), 1)
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
	heights.set_cell(Vector2i(0, 1), 2)   # high ground on the ramp's LOW side
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
	# without any Z arithmetic beyond one level either way.
	var board := _board()
	var heights := _heights(board)
	heights.set_cell(Vector2i(1, 1), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 1), 2, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(3, 1), 4)
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
		heights.set_cell(Vector2i(2, y), 2)   # a full-height ridge across the board, no ramps
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
		heights.set_cell(Vector2i(2, y), 2)
	heights.set_cell(Vector2i(2, 0), 0, Terrain.RampRise.NORTH)   # unreachable rise dir on purpose
	heights.set_cell(Vector2i(2, 1), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(3, 1), 2)
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
		heights.set_cell(Vector2i(2, y), 2)
	var unit := _spawn(board, Vector2i(0, 1))
	var result := RulesService.compute_move_range(unit, _context(board, unit))

	assert_bool(result.reachable.has(Vector2i(1, 1))).is_true()
	assert_bool(result.reachable.has(Vector2i(2, 1))).is_false()


# --- the corner store (#427): both accessors are DERIVED, so pin what they derive ---

func test_a_cells_height_is_its_lowest_corner() -> void:
	# Canon's "a ramp's height is its LOW side" (verticality.md, DECIDED) — the property that lets
	# every rule keep reading elevation_at unchanged across the corner migration.
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 1), 4, Terrain.RampRise.EAST)
	assert_bool(heights.corners_at(Vector2i(1, 1)) == Vector4i(4, 6, 6, 4)) \
		.override_failure_message("EAST at height 4 should raise its two east corners a level: got %s"
			% heights.corners_at(Vector2i(1, 1))).is_true()
	assert_int(heights.elevation_at(Vector2i(1, 1))).is_equal(4)

func test_every_cardinal_rise_round_trips_through_the_corners() -> void:
	# rise_of_corners is the ONLY reading RampRise's callers get now, so a direction that composed
	# one way and read back another would be silently wrong on a quarter of every ramp.
	#
	# Every CLIMB too since slice 2 (#427): direction and steepness are two derived views of one
	# store, and a composer that folded them would read one back through the other.
	var heights := BoardHeights.new()
	for climb in [1, Terrain.UNITS_PER_LEVEL]:
		for rise in [Terrain.RampRise.NONE, Terrain.RampRise.NORTH, Terrain.RampRise.SOUTH,
				Terrain.RampRise.EAST, Terrain.RampRise.WEST]:
			heights.set_cell(Vector2i(0, 0), 2, rise, climb)
			assert_int(heights.ramp_rise_at(Vector2i(0, 0))) \
				.override_failure_message("rise %d at climb %d read back wrong" % [rise, climb]) \
				.is_equal(rise)
			var expected_climb: int = 0 if rise == Terrain.RampRise.NONE else climb
			assert_int(heights.ramp_climb_at(Vector2i(0, 0))) \
				.override_failure_message("rise %d at climb %d lost its steepness" % [rise, climb]) \
				.is_equal(expected_climb)


func test_a_half_rise_ramp_connects_a_half_level_and_nothing_else() -> void:
	# #427 slice 2's whole point: a step crosses exactly what the ramp under it CLIMBS. The refusal
	# half is what stops "ramps come in two sizes" from becoming "a ramp crosses any gap".
	var board := _board()
	var heights := _heights(board)
	heights.set_cell(Vector2i(1, 1), 0, Terrain.RampRise.EAST, 1)
	heights.set_cell(Vector2i(2, 1), 1)                      # the half level it arrives at
	var unit := _spawn(board, Vector2i(0, 1))
	var context := _context(board, unit)
	assert_bool(RulesService.can_step(Vector2i(1, 1), Vector2i(2, 1), unit, context)) \
		.override_failure_message("a gentle ramp does not reach the half level it climbs to").is_true()

	heights.set_cell(Vector2i(2, 1), Terrain.UNITS_PER_LEVEL)   # a full level instead
	assert_bool(RulesService.can_step(Vector2i(1, 1), Vector2i(2, 1), unit, _context(board, unit))) \
		.override_failure_message("a gentle ramp climbed a whole level").is_false()


func test_two_gentle_ramps_climb_a_whole_level_between_them() -> void:
	# The RCT shape the slice exists for: half a level per cell, so a level takes two cells of run
	# and the walk up is legal at every step.
	var board := _board()
	var heights := _heights(board)
	heights.set_cell(Vector2i(1, 1), 0, Terrain.RampRise.EAST, 1)
	heights.set_cell(Vector2i(2, 1), 1, Terrain.RampRise.EAST, 1)
	heights.set_cell(Vector2i(3, 1), Terrain.UNITS_PER_LEVEL)
	var unit := _spawn(board, Vector2i(0, 1))
	var context := _context(board, unit)
	for step in [[Vector2i(0, 1), Vector2i(1, 1)], [Vector2i(1, 1), Vector2i(2, 1)],
			[Vector2i(2, 1), Vector2i(3, 1)]]:
		assert_bool(RulesService.can_step(step[0], step[1], unit, context)) \
			.override_failure_message("the gentle staircase breaks at %s -> %s" % [step[0], step[1]]) \
			.is_true()


# --- persistence ---

func test_heights_round_trip_through_a_scenario() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 1), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 1), 6)

	var scenario := ScenarioData.new()
	scenario.corner_heights = heights.to_corner_dict()

	var restored := BoardHeights.new()
	restored.load_corner_dict(scenario.corner_heights)

	assert_int(restored.elevation_at(Vector2i(2, 1))).is_equal(6)
	assert_int(restored.ramp_rise_at(Vector2i(1, 1))).is_equal(Terrain.RampRise.EAST)
	# A ramp at height 0 is legal and must survive the round trip — its corners are NOT all zero,
	# which is what lets one sparse field carry what two used to.
	assert_int(restored.elevation_at(Vector2i(1, 1))).is_equal(0)
	assert_bool(restored.is_ramp(Vector2i(1, 1))).is_true()
