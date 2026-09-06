# AttackPattern geometry (#25, #803): a range plus a stamp. Pure Resource logic -- no scene; the
# `user` arg is unused, so null is safe. Every pattern here is BUILT, never loaded (dev, 2026-09-06).
extends GdUnitTestSuite

const P := preload("res://tests/support/pattern_fixtures.gd")

const U := Vector2i.UP
const D := Vector2i.DOWN
const L := Vector2i.LEFT
const R := Vector2i.RIGHT


# A hook: two ahead, then one to the RIGHT of the far cell. Asymmetric on purpose -- a rotation
# and a mirror disagree on it, and so do the four facings.
static func _hook(max_range := 0) -> AttackPattern:
	return P.stamped(max_range, [Vector2i(0, -1), Vector2i(0, -2), Vector2i(1, -2)])


func test_manhattan_pattern_all_eight_neighbours() -> void:
	# max_and_a_half on a range-1 pattern selects the full Chebyshev ring (all 8); min_range 1
	# drops the origin. Confirms the range half threads the blended helper through.
	var p := P.point(1, 1, true)
	var cells := p.get_selectable_cells(null, Vector2i.ZERO, Vector2i.ZERO)
	assert_int(cells.size()).is_equal(8)
	assert_array(cells).not_contains([Vector2i.ZERO])
	assert_array(cells).contains([Vector2i(1, 1), Vector2i(-1, 1)])


func test_manhattan_pattern_plain_is_unchanged() -> void:
	# and_a_half defaults false -> the plain Manhattan diamond; min_range 0 keeps the origin.
	var p := P.point(2, 0)
	var cells := p.get_selectable_cells(null, Vector2i.ZERO, Vector2i.ZERO)
	assert_array(cells).contains_exactly_in_any_order(GridUtils.cells_within_manhattan_range(Vector2i.ZERO, 2))


func test_the_anchor_is_the_range() -> void:
	# Max range 0 = the stamp sits on the attacker and aims a facing; anything else aims a cell.
	assert_bool(P.line(2).is_directional()).is_true()
	assert_bool(P.wide().is_directional()).is_true()
	assert_bool(P.stamped(0, [Vector2i.ZERO]).is_directional()).is_true()
	assert_bool(P.point().is_directional()).is_false()
	assert_bool(_hook(3).is_directional()).is_false()


func test_a_self_anchored_stamp_turns_to_each_facing() -> void:
	# Grid-up is forward; each facing is a ROTATION of that, so the hook's side cell lands on the
	# shooter's right every time. A mirror would put it on the left for two of the four.
	var p := _hook()
	var o := Vector2i(5, 5)
	assert_array(p.get_affected_cells(null, o, o + U)).contains_exactly([Vector2i(5, 4), Vector2i(5, 3), Vector2i(6, 3)])
	assert_array(p.get_affected_cells(null, o, o + R)).contains_exactly([Vector2i(6, 5), Vector2i(7, 5), Vector2i(7, 6)])
	assert_array(p.get_affected_cells(null, o, o + D)).contains_exactly([Vector2i(5, 6), Vector2i(5, 7), Vector2i(4, 7)])
	assert_array(p.get_affected_cells(null, o, o + L)).contains_exactly([Vector2i(4, 5), Vector2i(3, 5), Vector2i(3, 4)])


func test_a_facings_selectable_cells_are_its_footprint_and_a_zero_hint_is_a_dud() -> void:
	var p := _hook()
	var facing := p.get_affected_cells(null, Vector2i.ZERO, R)
	assert_array(p.get_selectable_cells(null, Vector2i.ZERO, R)).contains_exactly(facing)
	assert_array(p.get_selectable_cells(null, Vector2i.ZERO, Vector2i.ZERO)).is_empty()
	assert_array(p.get_affected_cells(null, Vector2i.ZERO, Vector2i.ZERO)).is_empty()


func test_the_union_over_facings_is_what_the_overlay_draws() -> void:
	var cells := P.line(2).get_all_selectable_cells(null, Vector2i.ZERO)
	assert_array(cells).contains_exactly_in_any_order([U, U * 2, D, D * 2, L, L * 2, R, R * 2])


func test_an_anchored_stamp_lands_on_the_aimed_cell_turned_away_from_the_attacker() -> void:
	var o := Vector2i.ZERO
	# A cross at range 2: symmetric, so the turn is invisible and the shape simply sits on the aim.
	var cross := P.stamped(2, [Vector2i.ZERO, U, D, L, R])
	var t := Vector2i(2, 0)
	assert_array(cross.get_affected_cells(null, o, t)).contains_exactly_in_any_order([t, t + U, t + D, t + L, t + R])
	# The hook at range 3 aimed straight down shows the turn: forward is AWAY from the attacker.
	var hook := _hook(3)
	var down := Vector2i(0, 3)
	assert_array(hook.get_affected_cells(null, o, down)).contains_exactly([Vector2i(0, 4), Vector2i(0, 5), Vector2i(-1, 5)])
	# The aim itself is the RING, not the stamp: the aimed cell is selectable, the cell beyond is not.
	var ring := hook.get_selectable_cells(null, o, down)
	assert_bool(ring.has(down)).is_true()
	assert_bool(ring.has(Vector2i(0, 4))).is_false()


func test_emission_runs_near_to_far_then_left_to_right() -> void:
	# The retired wide pattern's sequence, cell for cell: row 1 left to right, then row 2. Volley
	# order is victim order, and Reach._truncate needs a predecessor emitted before its successor.
	var o := Vector2i.ZERO
	var expected: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2)]
	assert_array(P.wide(2, 3).get_affected_cells(null, o, U)).contains_exactly(expected)
	# Authoring order is NOT emission order: the same cells shuffled emit identically.
	var shuffled := P.stamped(0, [Vector2i(1, -2), Vector2i(-1, -1), Vector2i(0, -2), Vector2i(1, -1), Vector2i(-1, -2), Vector2i(0, -1)])
	assert_array(shuffled.get_affected_cells(null, o, U)).contains_exactly(expected)
	# Facing RIGHT the rule holds in the turned frame: the near column first, the shooter's left
	# (screen up) before its right.
	var turned: Array[Vector2i] = [Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, -1), Vector2i(2, 0), Vector2i(2, 1)]
	assert_array(shuffled.get_affected_cells(null, o, R)).contains_exactly(turned)


func test_the_centre_offset_puts_the_attacker_in_their_own_footprint() -> void:
	# Forward 0 sorts before forward 1, so the shooter's own cell is emitted first.
	var p := P.stamped(0, [U, Vector2i.ZERO])
	assert_array(p.get_affected_cells(null, Vector2i(3, 3), Vector2i(3, 2))).contains_exactly([Vector2i(3, 3), Vector2i(3, 2)])


func test_a_duplicated_offset_counts_once() -> void:
	var p := P.stamped(0, [U, U])
	assert_int(p.get_affected_cells(null, Vector2i.ZERO, U).size()).is_equal(1)


func test_an_aim_at_the_attackers_own_cell_places_the_stamp_unturned() -> void:
	# min_range 0 is authored content (a self-heal). No cardinal, so grid-up stays forward.
	var o := Vector2i(4, 4)
	var p := P.stamped(2, [Vector2i.ZERO, U], 0)
	assert_bool(p.get_selectable_cells(null, o, o).has(o)).is_true()
	assert_array(p.get_affected_cells(null, o, o)).contains_exactly([o, o + U])
