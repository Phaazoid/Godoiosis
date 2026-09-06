# Vertical tolerance (#258): the per-attack up/down height gate on the AIM question.
#
# Pure suite -- Reach's fallback geometry never touches the unit and BoardContext.elevation_at
# never touches the grid, so a bare BoardHeights inside a grid-less BoardContext is the whole
# board. The rule under test is Reach.vertical_aim_ok; can_hit_cell_from's cases pin that the
# gate CONJOINS with membership rather than replacing it.
extends GdUnitTestSuite

const P := preload("res://tests/support/pattern_fixtures.gd")

const NO_UNITS: Array[Unit] = []


func _board_with(heights: BoardHeights) -> BoardContext:
	return BoardContext.new(null, NO_UNITS, null, null, null, heights)


# One raised cell at (1,0); everything else elevation 0.
func _step_board(level: int) -> BoardContext:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), level)
	return _board_with(heights)


func _attack(up: int, down: int) -> AttackData:
	var attack := AttackData.new()
	attack.up_tolerance = up
	attack.down_tolerance = down
	return attack


func test_tolerance_is_asymmetric_up_and_down() -> void:
	# Tolerances are authored in height UNITS since #427, so this reaches one level up, two down.
	var attack := _attack(2, 4)
	var origin := Vector2i(0, 0)
	var target := Vector2i(1, 0)
	assert_bool(Reach.vertical_aim_ok(attack, origin, target, _step_board(2))).is_true()
	assert_bool(Reach.vertical_aim_ok(attack, origin, target, _step_board(4))).is_false()
	# The same edge judged downhill: the defender-side read of the same two boards.
	assert_bool(Reach.vertical_aim_ok(attack, target, origin, _step_board(4))).is_true()
	assert_bool(Reach.vertical_aim_ok(attack, target, origin, _step_board(6))).is_false()


func test_minus_one_reads_unlimited() -> void:
	var attack := AttackData.new()   # both tolerances at the -1 default
	assert_bool(Reach.vertical_aim_ok(attack, Vector2i(0, 0), Vector2i(1, 0), _step_board(10))).is_true()
	assert_bool(Reach.vertical_aim_ok(attack, Vector2i(1, 0), Vector2i(0, 0), _step_board(10))).is_true()


# Punching is melee (dev, 2026-08-20): a null attack follows the STEP rule, not tolerance.
func test_bare_fists_are_melee_step() -> void:
	assert_bool(Reach.vertical_aim_ok(null, Vector2i(0, 0), Vector2i(1, 0), _step_board(2))).is_false()
	assert_bool(Reach.vertical_aim_ok(null, Vector2i(0, 0), Vector2i(1, 0), _step_board(0))).is_true()


# --- The STEP rule (dev, 2026-08-20): "same step, or a facing half step" -----------------------

func _step_attack() -> AttackData:
	var attack := AttackData.new()
	attack.vertical_rule = AttackData.VerticalRule.MELEE
	return attack


func test_step_same_level_is_legal_at_range() -> void:
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(0, 0), Vector2i(3, 0), _step_board(0))).is_true()


func test_step_refuses_a_sheer_edge_in_both_directions() -> void:
	var board := _step_board(2)
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(0, 0), Vector2i(1, 0), board)).is_false()
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(1, 0), Vector2i(0, 0), board)).is_false()


# The half step: a ramp's low side facing its high side is melee-legal both ways -- the same edge
# movement climbs (RulesService.height_step_ok is the shared core). NB "half step" is the dev's
# 2026-08-20 word for standing mid-ramp; it is NOT #427's half LEVEL, which blocks like any edge.
func test_step_allows_a_facing_half_step() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 0), 2)
	var board := _board_with(heights)
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(1, 0), Vector2i(2, 0), board)).is_true()
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(2, 0), Vector2i(1, 0), board)).is_true()


func test_step_refuses_a_half_step_off_the_rise_axis() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(1, -1), 2)   # the level-up neighbour NORTH of the ramp -- off the rise
	var board := _board_with(heights)
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(1, 0), Vector2i(1, -1), board)).is_false()


func test_step_judges_the_direct_edge_only() -> void:
	# A level-up target two cells away is refused: STEP is adjacency-shaped, ramps or not.
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 0), 2)
	var board := _board_with(heights)
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(0, 0), Vector2i(2, 0), board)).is_false()


func test_a_null_board_reads_flat() -> void:
	assert_bool(Reach.vertical_aim_ok(_attack(0, 0), Vector2i(0, 0), Vector2i(9, 9), null)).is_true()


func test_a_missing_heights_store_reads_flat() -> void:
	var board := BoardContext.new(null, NO_UNITS, null)
	assert_bool(Reach.vertical_aim_ok(_attack(0, 0), Vector2i(0, 0), Vector2i(1, 0), board)).is_true()


# A ramp's elevation is its LOW side (#257), so a unit standing on one is judged at that number --
# no ramp special case in the tolerance rule.
func test_a_ramp_cell_is_judged_at_its_low_side() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 2, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 0), 4)
	var board := _board_with(heights)
	var zero_up := _attack(0, 4)
	assert_bool(Reach.vertical_aim_ok(zero_up, Vector2i(1, 0), Vector2i(2, 0), board)).is_false()
	assert_bool(Reach.vertical_aim_ok(_attack(2, 4), Vector2i(1, 0), Vector2i(2, 0), board)).is_true()


# --- Directional spreads TRUNCATE (#756, dev 2026-09-04: "truncate, and all 8") ----------------
#
# The v1 exemption is repealed. A spread is cut at the first cell a lane cannot reach, and a cell
# BEHIND a cut cell is cut whether or not its own trace is clear.

func _line(length: int, up := -1, down := -1) -> AttackData:
	var attack := _attack(up, down)
	attack.attack_pattern = P.line(length)
	return attack


func _wide(length: int, width: int) -> AttackData:
	var attack := _attack(-1, -1)
	attack.attack_pattern = P.wide(length, width)
	return attack


func _aimed_east(attack: AttackData, board: BoardContext, length := 2) -> Array[Vector2i]:
	return Reach.get_affected_cells_from(null, Vector2i.ZERO, Vector2i(length, 0), attack, board)


# The headline: a line stops at the ledge it cannot see over. The raised cell itself is an ENDPOINT
# of its own lane and is hit; what stands ON it is what the shot cannot get past.
func test_a_line_stops_at_the_ledge_it_cannot_see_over() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 4)   # two levels up
	heights.set_cell(Vector2i(2, 0), 4)   # the plateau behind it
	var cells := _aimed_east(_line(2), _board_with(heights))
	assert_array(cells).contains_exactly([Vector2i(1, 0)])


# Non-vacuity twin: identical geometry, flat, and the whole line lands.
func test_the_same_line_on_flat_ground_keeps_every_cell() -> void:
	var cells := _aimed_east(_line(2), _board_with(BoardHeights.new()))
	assert_array(cells).contains_exactly([Vector2i(1, 0), Vector2i(2, 0)])


# TRUNCATION, NOT A FILTER — the one case that tells them apart. The shooter stands on a plateau
# with a dip in front of it: the near cell is below a down-tolerance of 1 and is refused, while the
# far cell is back at the shooter's own height with a clear line of its own. A filter keeps it; the
# front stops at the dip.
func test_a_cell_behind_an_unreachable_one_is_cut_though_its_own_line_is_clear() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(0, 0), 2)   # the shooter's plateau
	heights.set_cell(Vector2i(2, 0), 2)   # the far side of the dip, level with it
	var board := _board_with(heights)
	var attack := _line(2, -1, 1)         # reaches one height unit down
	assert_bool(Reach.vertical_aim_ok(attack, Vector2i(0, 0), Vector2i(2, 0), board)) \
		.override_failure_message("the far cell must pass on its own, or this case cannot see the cut") \
		.is_true()
	assert_array(_aimed_east(attack, board)).is_empty()


# A WIDE spread is cut LANE BY LANE: a column blocked in one lane leaves its neighbours standing.
func test_a_wide_spread_cuts_one_lane_and_keeps_its_neighbours() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 1), 4)   # a pillar in the right-hand lane, one cell ahead
	var cells := _aimed_east(_wide(2, 3), _board_with(heights))
	assert_bool(cells.has(Vector2i(2, 1))).override_failure_message(
			"the pillar's own lane must be cut behind it").is_false()
	for kept in [Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, -1), Vector2i(2, 0)]:
		assert_bool(cells.has(kept)).override_failure_message(
				"%s is in another lane and should still be hit" % str(kept)).is_true()


# THE DEV'S OPTION B (2026-09-04): a spread advances as a FRONT, each lane traced from the shooter's
# cell carried sideways onto that lane. Fanning one ray per cell out of the shooter's own cell
# instead would clip the diagonal corner — cells_crossed is supercover — and cut a Cleave to its
# middle cell here. Every raised cell is a lane endpoint, so the whole front lands.
func test_a_cleave_up_a_ledge_keeps_its_side_lanes() -> void:
	var heights := BoardHeights.new()
	for x_offset in [-1, 0, 1]:
		heights.set_cell(Vector2i(1, x_offset), 4)
	var cells := Reach.get_affected_cells_from(null, Vector2i.ZERO, Vector2i(1, 0), _wide(1, 3), _board_with(heights))
	assert_array(cells).contains_exactly_in_any_order([Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)])


# The same ruling from the other side: cleaving DOWN off a plateau edge. Under the fanned-ray
# alternative the plateau cells BESIDE the shooter block its own side lanes, which is #218's
# "standing on a cliff edge still shoots down past it" broken for spreads.
func test_a_cleave_down_off_a_plateau_edge_keeps_its_side_lanes() -> void:
	var heights := BoardHeights.new()
	for y in [-1, 0, 1]:
		heights.set_cell(Vector2i(0, y), 4)   # the shooter's plateau, three cells wide
	var cells := Reach.get_affected_cells_from(null, Vector2i.ZERO, Vector2i(1, 0), _wide(1, 3), _board_with(heights))
	assert_array(cells).contains_exactly_in_any_order([Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)])


# A null board reads flat here as everywhere else — every heights-less fixture is unaffected.
func test_a_null_board_leaves_a_spread_whole() -> void:
	assert_array(Reach.get_affected_cells_from(null, Vector2i.ZERO, Vector2i(2, 0), _line(2), null)) \
		.contains_exactly([Vector2i(1, 0), Vector2i(2, 0)])


# The gate's own directional clause is gone: a zero-tolerance spread is judged like anything else.
func test_a_directional_attack_is_no_longer_exempt_from_the_gate() -> void:
	var attack := _attack(0, 0)
	attack.attack_pattern = P.wide()
	assert_bool(Reach.vertical_aim_ok(attack, Vector2i(0, 0), Vector2i(1, 0), _step_board(5))).is_false()


# can_hit_cell_from = membership AND tolerance: a reachable cell past the tolerance is refused,
# the same cell on a flat board is not, and an unreachable cell stays unreachable however flat.
func test_can_hit_conjoins_membership_and_tolerance() -> void:
	var weapon_main := _attack(1, 2)   # pattern-less: Manhattan-1 fallback reach
	assert_bool(Reach.can_hit_cell_from(null, Vector2i(0, 0), Vector2i(1, 0), weapon_main, _step_board(2))).is_false()
	assert_bool(Reach.can_hit_cell_from(null, Vector2i(0, 0), Vector2i(1, 0), weapon_main, null)).is_true()
	assert_bool(Reach.can_hit_cell_from(null, Vector2i(0, 0), Vector2i(3, 0), weapon_main, null)).is_false()


func test_blocked_cells_are_the_unreachable_subset_of_the_union() -> void:
	var weapon_main := _attack(1, 2)
	var blocked := Reach.blocked_cells_from(null, Vector2i(0, 0), weapon_main, _step_board(2))
	assert_array(blocked).contains_exactly([Vector2i(1, 0)])
	assert_array(Reach.blocked_cells_from(null, Vector2i(0, 0), weapon_main, null)).is_empty()


# The hatch a SPREAD draws is the union minus what every facing can still reach (#756) — it was
# unconditionally empty while directional attacks were exempt.
func test_blocked_cells_for_a_directional_attack_are_what_the_terrain_cut() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 4)
	heights.set_cell(Vector2i(2, 0), 4)
	var blocked := Reach.blocked_cells_from(null, Vector2i(0, 0), _line(2), _board_with(heights))
	assert_array(blocked).contains_exactly([Vector2i(2, 0)])
	assert_array(Reach.blocked_cells_from(null, Vector2i(0, 0), _line(2), null)).is_empty()
