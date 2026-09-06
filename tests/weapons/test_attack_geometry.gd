# An attack's GEOMETRY (#25, #803, split at #808): a RANGE on the attack plus a SHAPE beside it.
# Asked through Reach, which is where the two halves are put back together -- the `unit` and `board`
# args are unused by everything here, so null is safe for both. Every attack is BUILT, never loaded
# (dev, 2026-09-06).
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const U := Vector2i.UP
const D := Vector2i.DOWN
const L := Vector2i.LEFT
const R := Vector2i.RIGHT


func _attack() -> WeaponAttackData:
	return WeaponAttackData.new()


# A hook: two ahead, then one to the RIGHT of the far cell. Asymmetric on purpose -- a rotation
# and a mirror disagree on it, and so do the four facings.
func _hook(max_range := 0) -> AttackData:
	var cells: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, -2), Vector2i(1, -2)]
	return P.stamped(_attack(), max_range, cells)


func _selectable(attack: AttackData, origin: Vector2i, hint: Vector2i) -> Array[Vector2i]:
	return Reach.get_attack_cells_from(null, origin, hint, attack)


func _affected(attack: AttackData, origin: Vector2i, target: Vector2i) -> Array[Vector2i]:
	return Reach.get_affected_cells_from(null, origin, target, attack, null)


func test_manhattan_range_all_eight_neighbours() -> void:
	# max_and_a_half at range 1 selects the full Chebyshev ring (all 8); min_range 1 drops the
	# origin. Confirms the range half threads the blended helper through.
	var cells := _selectable(P.point(_attack(), 1, 1, true), Vector2i.ZERO, Vector2i.ZERO)
	assert_int(cells.size()).is_equal(8)
	assert_array(cells).not_contains([Vector2i.ZERO])
	assert_array(cells).contains([Vector2i(1, 1), Vector2i(-1, 1)])


func test_manhattan_range_plain_is_unchanged() -> void:
	# and_a_half defaults false -> the plain Manhattan diamond; min_range 0 keeps the origin.
	var cells := _selectable(P.point(_attack(), 2, 0), Vector2i.ZERO, Vector2i.ZERO)
	assert_array(cells).contains_exactly_in_any_order(GridUtils.cells_within_manhattan_range(Vector2i.ZERO, 2))


func test_the_anchor_is_the_range() -> void:
	# Max range 0 = the shape sits on the attacker and aims a facing; anything else aims a cell.
	# It is the ATTACK that answers, the shape holding no range to derive it from.
	var centre: Array[Vector2i] = [Vector2i.ZERO]
	assert_bool(P.line(_attack(), 2).is_directional()).is_true()
	assert_bool(P.wide(_attack()).is_directional()).is_true()
	assert_bool(P.stamped(_attack(), 0, centre).is_directional()).is_true()
	assert_bool(P.point(_attack()).is_directional()).is_false()
	assert_bool(_hook(3).is_directional()).is_false()


func test_a_shapeless_attack_covers_the_cell_it_is_aimed_at() -> void:
	# The single-target case, which most authored attacks are and which deliberately names no shape
	# file: a null shape is the anchor cell alone, never an empty footprint.
	var attack := P.point(_attack(), 3)
	assert_object(attack.attack_shape).is_null()
	assert_array(_affected(attack, Vector2i.ZERO, Vector2i(3, 0))).contains_exactly([Vector2i(3, 0)])


func test_a_self_anchored_stamp_turns_to_each_facing() -> void:
	# Grid-up is forward; each facing is a ROTATION of that, so the hook's side cell lands on the
	# shooter's right every time. A mirror would put it on the left for two of the four.
	var attack := _hook()
	var o := Vector2i(5, 5)
	assert_array(_affected(attack, o, o + U)).contains_exactly([Vector2i(5, 4), Vector2i(5, 3), Vector2i(6, 3)])
	assert_array(_affected(attack, o, o + R)).contains_exactly([Vector2i(6, 5), Vector2i(7, 5), Vector2i(7, 6)])
	assert_array(_affected(attack, o, o + D)).contains_exactly([Vector2i(5, 6), Vector2i(5, 7), Vector2i(4, 7)])
	assert_array(_affected(attack, o, o + L)).contains_exactly([Vector2i(4, 5), Vector2i(3, 5), Vector2i(3, 4)])


func test_a_facings_selectable_cells_are_its_footprint_and_a_zero_hint_is_a_dud() -> void:
	var attack := _hook()
	var facing := _affected(attack, Vector2i.ZERO, R)
	assert_array(_selectable(attack, Vector2i.ZERO, R)).contains_exactly(facing)
	assert_array(_selectable(attack, Vector2i.ZERO, Vector2i.ZERO)).is_empty()
	assert_array(_affected(attack, Vector2i.ZERO, Vector2i.ZERO)).is_empty()


func test_the_union_over_facings_is_what_the_overlay_draws() -> void:
	var cells := Reach.get_all_attack_cells_from(null, Vector2i.ZERO, P.line(_attack(), 2))
	assert_array(cells).contains_exactly_in_any_order([U, U * 2, D, D * 2, L, L * 2, R, R * 2])


func test_an_anchored_stamp_lands_on_the_aimed_cell_turned_away_from_the_attacker() -> void:
	var o := Vector2i.ZERO
	# A cross at range 2: symmetric, so the turn is invisible and the shape simply sits on the aim.
	var plus: Array[Vector2i] = [Vector2i.ZERO, U, D, L, R]
	var cross := P.stamped(_attack(), 2, plus)
	var t := Vector2i(2, 0)
	assert_array(_affected(cross, o, t)).contains_exactly_in_any_order([t, t + U, t + D, t + L, t + R])
	# The hook at range 3 aimed straight down shows the turn: forward is AWAY from the attacker.
	var hook := _hook(3)
	var down := Vector2i(0, 3)
	assert_array(_affected(hook, o, down)).contains_exactly([Vector2i(0, 4), Vector2i(0, 5), Vector2i(-1, 5)])
	# The aim itself is the RING, not the stamp: the aimed cell is selectable, the cell beyond is not.
	var ring := _selectable(hook, o, down)
	assert_bool(ring.has(down)).is_true()
	assert_bool(ring.has(Vector2i(0, 4))).is_false()


func test_emission_runs_near_to_far_then_left_to_right() -> void:
	# The retired wide pattern's sequence, cell for cell: row 1 left to right, then row 2. Volley
	# order is victim order, and Reach._truncate needs a predecessor emitted before its successor.
	var o := Vector2i.ZERO
	var expected: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2)]
	assert_array(_affected(P.wide(_attack(), 2, 3), o, U)).contains_exactly(expected)
	# Authoring order is NOT emission order: the same cells shuffled emit identically.
	var jumbled: Array[Vector2i] = [Vector2i(1, -2), Vector2i(-1, -1), Vector2i(0, -2), Vector2i(1, -1), Vector2i(-1, -2), Vector2i(0, -1)]
	var shuffled := P.stamped(_attack(), 0, jumbled)
	assert_array(_affected(shuffled, o, U)).contains_exactly(expected)
	# Facing RIGHT the rule holds in the turned frame: the near column first, the shooter's left
	# (screen up) before its right.
	var turned: Array[Vector2i] = [Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, -1), Vector2i(2, 0), Vector2i(2, 1)]
	assert_array(_affected(shuffled, o, R)).contains_exactly(turned)


func test_the_centre_offset_puts_the_attacker_in_their_own_footprint() -> void:
	# Forward 0 sorts before forward 1, so the shooter's own cell is emitted first.
	var cells: Array[Vector2i] = [U, Vector2i.ZERO]
	var attack := P.stamped(_attack(), 0, cells)
	assert_array(_affected(attack, Vector2i(3, 3), Vector2i(3, 2))).contains_exactly([Vector2i(3, 3), Vector2i(3, 2)])


func test_a_duplicated_offset_counts_once() -> void:
	var cells: Array[Vector2i] = [U, U]
	assert_int(_affected(P.stamped(_attack(), 0, cells), Vector2i.ZERO, U).size()).is_equal(1)


func test_an_aim_at_the_attackers_own_cell_places_the_stamp_unturned() -> void:
	# min_range 0 is authored content (a self-heal). No cardinal, so grid-up stays forward.
	var o := Vector2i(4, 4)
	var cells: Array[Vector2i] = [Vector2i.ZERO, U]
	var attack := P.stamped(_attack(), 2, cells, 0)
	assert_bool(_selectable(attack, o, o).has(o)).is_true()
	assert_array(_affected(attack, o, o)).contains_exactly([o, o + U])


func test_a_shape_is_shared_between_attacks_rather_than_copied() -> void:
	# The library's whole premise (#808): two attacks naming one shape have one geometry, and
	# editing it moves both. A shape carrying its own range could not do this -- "a line at range 0"
	# and "the same line at range 3" would be two files, which is what #802 was filed to remove.
	var line: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, -2)]
	var shape := P.shape(line, "Line 2")
	var melee := _attack()
	melee.max_range = 0
	melee.attack_shape = shape
	var fired := _attack()
	fired.max_range = 3
	fired.attack_shape = shape

	assert_array(_affected(melee, Vector2i.ZERO, U)).contains_exactly([U, U * 2])
	assert_array(_affected(fired, Vector2i.ZERO, Vector2i(0, -3))).contains_exactly([Vector2i(0, -4), Vector2i(0, -5)])

	shape.stamp = [Vector2i(0, -1)]
	assert_array(_affected(melee, Vector2i.ZERO, U)).override_failure_message(
		"editing a shared shape did not reach every attack holding it").contains_exactly([U])
	assert_array(_affected(fired, Vector2i.ZERO, Vector2i(0, -3))).contains_exactly([Vector2i(0, -4)])
