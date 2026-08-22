# Vertical tolerance (#258): the per-attack up/down height gate on the AIM question.
#
# Pure suite -- Reach's fallback geometry never touches the unit and BoardContext.elevation_at
# never touches the grid, so a bare BoardHeights inside a grid-less BoardContext is the whole
# board. The rule under test is Reach.vertical_aim_ok; can_hit_cell_from's cases pin that the
# gate CONJOINS with membership rather than replacing it.
extends GdUnitTestSuite

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
	var attack := _attack(1, 2)
	var origin := Vector2i(0, 0)
	var target := Vector2i(1, 0)
	assert_bool(Reach.vertical_aim_ok(attack, origin, target, _step_board(1))).is_true()
	assert_bool(Reach.vertical_aim_ok(attack, origin, target, _step_board(2))).is_false()
	# The same edge judged downhill: the defender-side read of the same two boards.
	assert_bool(Reach.vertical_aim_ok(attack, target, origin, _step_board(2))).is_true()
	assert_bool(Reach.vertical_aim_ok(attack, target, origin, _step_board(3))).is_false()


func test_minus_one_reads_unlimited() -> void:
	var attack := AttackData.new()   # both tolerances at the -1 default
	assert_bool(Reach.vertical_aim_ok(attack, Vector2i(0, 0), Vector2i(1, 0), _step_board(10))).is_true()
	assert_bool(Reach.vertical_aim_ok(attack, Vector2i(1, 0), Vector2i(0, 0), _step_board(10))).is_true()


# Punching is melee (dev, 2026-08-20): a null attack follows the STEP rule, not tolerance.
func test_bare_fists_are_melee_step() -> void:
	assert_bool(Reach.vertical_aim_ok(null, Vector2i(0, 0), Vector2i(1, 0), _step_board(1))).is_false()
	assert_bool(Reach.vertical_aim_ok(null, Vector2i(0, 0), Vector2i(1, 0), _step_board(0))).is_true()


# --- The STEP rule (dev, 2026-08-20): "same step, or a facing half step" -----------------------

func _step_attack() -> AttackData:
	var attack := AttackData.new()
	attack.vertical_rule = AttackData.VerticalRule.MELEE
	return attack


func test_step_same_level_is_legal_at_range() -> void:
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(0, 0), Vector2i(3, 0), _step_board(0))).is_true()


func test_step_refuses_a_sheer_edge_in_both_directions() -> void:
	var board := _step_board(1)
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(0, 0), Vector2i(1, 0), board)).is_false()
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(1, 0), Vector2i(0, 0), board)).is_false()


# The half step: a ramp's low side facing its high side is melee-legal both ways -- the same edge
# movement climbs (RulesService.height_step_ok is the shared core).
func test_step_allows_a_facing_half_step() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 0), 1)
	var board := _board_with(heights)
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(1, 0), Vector2i(2, 0), board)).is_true()
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(2, 0), Vector2i(1, 0), board)).is_true()


func test_step_refuses_a_half_step_off_the_rise_axis() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(1, -1), 1)   # the +1 neighbour NORTH of the ramp -- not along the rise
	var board := _board_with(heights)
	assert_bool(Reach.vertical_aim_ok(_step_attack(), Vector2i(1, 0), Vector2i(1, -1), board)).is_false()


func test_step_judges_the_direct_edge_only() -> void:
	# A +1 target two cells away is refused: STEP is adjacency-shaped, ramps or not.
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 0), 1)
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
	heights.set_cell(Vector2i(1, 0), 1, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 0), 2)
	var board := _board_with(heights)
	var zero_up := _attack(0, 2)
	assert_bool(Reach.vertical_aim_ok(zero_up, Vector2i(1, 0), Vector2i(2, 0), board)).is_false()
	assert_bool(Reach.vertical_aim_ok(_attack(1, 2), Vector2i(1, 0), Vector2i(2, 0), board)).is_true()


# Directional spreads are exempt in v1 (dev call, 2026-08-20): their per-cell height question is
# the deferred footprint/blast-extent question, so even a zero-tolerance spread passes the gate.
func test_directional_attacks_are_exempt() -> void:
	var attack := _attack(0, 0)
	attack.attack_pattern = ForwardWidePattern.new()
	assert_bool(Reach.vertical_aim_ok(attack, Vector2i(0, 0), Vector2i(1, 0), _step_board(5))).is_true()


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


func test_blocked_cells_are_empty_for_a_directional_attack() -> void:
	var attack := _attack(0, 0)
	attack.attack_pattern = ForwardWidePattern.new()
	assert_array(Reach.blocked_cells_from(null, Vector2i(0, 0), attack, _step_board(5))).is_empty()
