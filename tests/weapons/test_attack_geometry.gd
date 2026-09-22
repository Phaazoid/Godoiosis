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


func test_an_anchored_stamp_lands_on_the_aimed_cell_UNTURNED() -> void:
	# #818, and the whole of it: a placed shape never turns. What the grid draws is what the board
	# gets, wherever the attacker is standing -- the direction model is for self-anchored attacks,
	# where the aim IS a direction.
	var o := Vector2i.ZERO
	# A cross at range 2: symmetric, so it could not tell turned from unturned either way.
	var plus: Array[Vector2i] = [Vector2i.ZERO, U, D, L, R]
	var cross := P.stamped(_attack(), 2, plus)
	var t := Vector2i(2, 0)
	assert_array(_affected(cross, o, t)).contains_exactly_in_any_order([t, t + U, t + D, t + L, t + R])

	# The asymmetric hook is what can. Aimed straight DOWN it lands grid-up regardless: two cells
	# NORTH of the aim and the hook's tip east of the far one. Turned, it would run further south
	# and hook west -- which is exactly what this attack used to do.
	var hook := _hook(3)
	var down := Vector2i(0, 3)
	assert_array(_affected(hook, o, down)).override_failure_message(
		"an anchored shape turned to face the aim -- #818 says it lands as drawn"
	).contains_exactly([Vector2i(0, 2), Vector2i(0, 1), Vector2i(1, 1)])

	# LEFT and RIGHT land the same footprint on the same cell, which is the property in one line:
	# where the attacker stands cannot change the shape any more.
	assert_array(_affected(hook, Vector2i(3, 3), down)).contains_exactly(_affected(hook, Vector2i(-3, 3), down))

	# The aim itself is the RING, not the stamp: the aimed cell is selectable, the cell beyond is not.
	var ring := _selectable(hook, o, down)
	assert_bool(ring.has(down)).is_true()
	assert_bool(ring.has(Vector2i(0, 4))).is_false()


func test_a_self_anchored_stamp_still_turns() -> void:
	# The other half of the same rule, stated where the flip above cannot hide it: the direction
	# model survives untouched wherever the aim genuinely IS a direction.
	var hook := _hook()
	var o := Vector2i(5, 5)
	assert_array(_affected(hook, o, o + R)).contains_exactly([Vector2i(6, 5), Vector2i(7, 5), Vector2i(7, 6)])


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
	# min_range 0 is authored content (a self-heal). It used to need a clause of its own -- no
	# cardinal to turn to -- and since #818 it is just the anchored rule applied at range zero. Kept
	# because the self-aim is a real authored state worth pinning, not because it is special.
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


func test_an_anchored_footprint_emits_in_board_order() -> void:
	# Victim order is volley order, so what the sort does is a RULE and not an implementation
	# detail. With the shape no longer turning (#818) the same near-to-far sort reads out in BOARD
	# terms: the southern row first, then northward, west to east within a row. Deterministic, which
	# is all law #1 asks -- but it is no longer *nearest the attacker first*, because an anchored
	# footprint has no attacker in it to be near. Ordering a placed blast outward from where it
	# lands is #805's question, and this case is here so that change is a decision rather than a
	# surprise.
	var column: Array[Vector2i] = [Vector2i(0, -1), Vector2i.ZERO, Vector2i(0, 1)]
	var attack := P.stamped(_attack(), 3, column)
	var t := Vector2i(0, 3)
	assert_array(_affected(attack, Vector2i.ZERO, t)).contains_exactly(
		[Vector2i(0, 4), Vector2i(0, 3), Vector2i(0, 2)])


# --- The spread: a placed blast propagates from where it lands (#805) --------------------------
#
# Pure, on test_vertical_tolerance's terms: Reach's geometry never touches the unit and a grid-less
# BoardContext answers 0 for every prop column, so a bare BoardHeights IS the board and the blocking
# column is ground alone. Anchored placement is unturned (#818), so a grid offset is a board offset
# and every stamp below reads as the board picture it draws.

const NO_UNITS: Array[Unit] = []


func _board(heights: Dictionary) -> BoardContext:
	var h := BoardHeights.new()
	for cell: Vector2i in heights:
		h.set_cell(cell, heights[cell])
	return BoardContext.new(null, NO_UNITS, null, null, null, h)


# A placed, shaped attack aimed at `target`, over a real board. `tolerance` is the attack's OWN
# up/down tolerance: the spread asks its ordinary aim gate with the impact cell standing in for the
# shooter, so a blast's vertical reach is the same three fields a shot's is, measured from where it
# landed. The attacker is parked far away to make the point that nothing reads it.
func _blast(offsets: Array[Vector2i], target: Vector2i, board: BoardContext, tolerance := -1) -> Array[Vector2i]:
	return _placed(offsets, target, board, tolerance, true)


# The SAME aim with Swing off -- a TRUE AoE (#1055). Beside _blast rather than folded into it so a
# case can put the two answers on one board and show the flag is the only difference between them.
func _aoe(offsets: Array[Vector2i], target: Vector2i, board: BoardContext, tolerance := -1) -> Array[Vector2i]:
	return _placed(offsets, target, board, tolerance, false)


func _placed(offsets: Array[Vector2i], target: Vector2i, board: BoardContext, tolerance: int, swinging: bool) -> Array[Vector2i]:
	var attack := P.stamped(_attack(), 4, offsets)
	attack.swing = swinging
	attack.up_tolerance = tolerance
	attack.down_tolerance = tolerance
	return Reach.get_affected_cells_from(null, Vector2i(9, 9), target, attack, board)


func test_a_wall_between_the_impact_and_the_shape_cuts_what_is_behind_it() -> void:
	# The shape reaches three cells east; a 2-high column stands on the second, which is not itself
	# a member. The near cell is clear, the far one's flat trace crosses the column and is cut.
	# This is the ticket's own sentence -- "that second half of the attack could be blocked by
	# walls" -- and it is the TRACE clause doing the work.
	var east: Array[Vector2i] = [Vector2i(1, 0), Vector2i(3, 0)]
	var board := _board({Vector2i(2, 0): 2})
	assert_array(_blast(east, Vector2i.ZERO, board)).contains_exactly([Vector2i(1, 0)])
	# The control: with that column gone, both land. Without this the case would pass just as well
	# against a rule that cut the far cell for some reason of its own.
	assert_array(_blast(east, Vector2i.ZERO, _board({}))).contains_exactly([Vector2i(1, 0), Vector2i(3, 0)])


func test_a_cell_the_blast_cannot_propagate_THROUGH_is_cut_even_though_it_is_reachable_itself() -> void:
	# THE CASE THAT SEPARATES THE TWO CLAUSES, and the only shape that can. The impact stands on a
	# plateau; the next cell out is a dip below the burst tolerance, and the cell beyond it is back
	# at the impact's own height with a clean flat line over the dip.
	#
	# So the far cell passes BOTH of its own clauses -- its height is level with the impact and
	# nothing blocks its trace -- and is cut only because the cell the blast had to cross was. A
	# wall version of this asserts nothing extra: there the trace from the impact crosses the wall
	# too, so the far cell fails on its own account and connectivity is never consulted.
	var east: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	var dip := _board({Vector2i.ZERO: 4, Vector2i(2, 0): 4})
	assert_array(_blast(east, Vector2i.ZERO, dip, 2)).override_failure_message(
		"a cell past a gap the blast could not cross was reached anyway").is_empty()
	# The control: level the dip and the same two cells, the same tolerance, both land.
	var level := _board({Vector2i.ZERO: 4, Vector2i(1, 0): 4, Vector2i(2, 0): 4})
	assert_array(_blast(east, Vector2i.ZERO, level, 2)).contains_exactly([Vector2i(1, 0), Vector2i(2, 0)])


func test_the_attacks_own_tolerance_decides_how_far_the_blast_carries_vertically() -> void:
	# A bomb on a terrace does not catch the men on the plateau above: one arm climbs out of reach,
	# the other stays level. The blast asks the attack's ORDINARY vertical gate, with the impact
	# cell standing in for the shooter -- so the reach is measured from where it landed, and no
	# blast-only field is needed to say so.
	var arms: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	var board := _board({Vector2i(1, 0): 4})
	assert_array(_blast(arms, Vector2i.ZERO, board, 2)).contains_exactly([Vector2i(0, 1)])
	# -1 is unlimited, spelled the way its two siblings are: the same board, the same shape, both.
	# In the shape's own emission order, which is board order -- the southern cell before the
	# eastern one -- since the spread filters that order rather than re-sorting it.
	assert_array(_blast(arms, Vector2i.ZERO, board, -1)).contains_exactly([Vector2i(0, 1), Vector2i(1, 0)])


func test_the_blast_travels_through_the_board_and_not_through_the_stamp() -> void:
	# A stamp whose cells do not touch each other -- or its centre -- still lands in full over open
	# ground. The stamp says what the blast COVERS; the terrain says what stops it. A flood confined
	# to stamp membership would answer empty here, and would collapse the authored Test shape (whose
	# stamp holds no orthogonal neighbour of its own centre) to a single cell.
	var scattered: Array[Vector2i] = [Vector2i(3, 0), Vector2i(-2, 2)]
	assert_array(_blast(scattered, Vector2i.ZERO, _board({}))).contains_exactly_in_any_order(scattered)


func test_a_flat_arm_survives_whichever_end_of_it_is_emitted_first() -> void:
	# The ORDERING guard, and the direction is the whole point. An anchored shape emits in BOARD
	# order -- southern row first -- so this arm's FAR cell is handed out before the near cell it
	# must propagate through. Deciding membership in emission order with a predecessor rule (which
	# is what pointing _truncate at the landing cell would do) cuts every cell whose predecessor has
	# not been reached yet, leaving only the nearest. Walking outward by distance from the impact is
	# what makes the answer independent of the sort.
	var south: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
	assert_array(_blast(south, Vector2i.ZERO, _board({}))).override_failure_message(
		"a flat arm lost cells to the order its own shape emits them in").contains_exactly(
		[Vector2i(0, 3), Vector2i(0, 2), Vector2i(0, 1)])


func test_the_survivors_keep_the_shapes_own_emission_order() -> void:
	# Victim order is volley order, and that is the SHAPE's rule (AttackShape.place). The spread is
	# a filter over it, never a re-sort into flood order -- which for this shape would be the exact
	# reverse, the flood running outward while the sort reads southern row first.
	var column: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
	var board := _board({Vector2i(0, 2): 4})
	# The middle of the arm climbs out of reach, so it and everything past it go.
	assert_array(_blast(column, Vector2i.ZERO, board, 2)).contains_exactly([Vector2i(0, 1)])


func test_a_null_board_hands_back_the_whole_authored_shape() -> void:
	# ShapePlate draws the authored footprint on the mod-fitting card and passes a null board on
	# purpose to get it. A blast that narrowed there would draw the player a shape no board was
	# being consulted about.
	var scattered: Array[Vector2i] = [Vector2i(1, 0), Vector2i(3, 0), Vector2i(-2, 2)]
	var attack := P.stamped(_attack(), 4, scattered)
	attack.up_tolerance = 0
	attack.down_tolerance = 0
	assert_array(Reach.get_affected_cells_from(null, Vector2i(9, 9), Vector2i.ZERO, attack, null)) \
		.contains_exactly_in_any_order(scattered)


func test_a_swung_shape_is_still_truncated_from_the_shooter_and_not_from_its_own_far_end() -> void:
	# #756 is untouched: a self-anchored spread is a SWING, cut lane by lane from the ATTACKER, so
	# its gate is measured from the shooter's cell where a blast's is measured from the impact. One
	# rule, two anchors, and which one applies is the anchor question max_range already answers.
	# A one-level step two cells ahead stops the lane at the step under a melee rule, which is the
	# same answer this suite's vertical cases give.
	var swung := P.line(_attack(), 3)
	swung.vertical_rule = AttackData.VerticalRule.MELEE
	var board := _board({Vector2i(0, -2): 2})
	var hit := Reach.get_affected_cells_from(null, Vector2i.ZERO, Vector2i(0, -1), swung, board)
	assert_array(hit).contains_exactly([Vector2i(0, -1)])


# --- Swing off: a TRUE AoE covers its whole stamp (#1055) ---------------------------------------
#
# The modifier's own cases. Each one puts the two answers on ONE board, because what is being pinned
# is the FORK -- an assertion about the true AoE alone would pass just as well against a build where
# the flag reached nothing and the propagation had simply been deleted.


func test_a_true_aoe_lands_straight_through_the_wall_a_swing_stops_at() -> void:
	# The wall case above, with the modifier off. Same shape, same board, same aim: a blast stops at
	# the column and a true AoE does not notice it. "Attacks which just hit all of their tiles at
	# once" (dev, 2026-09-20).
	var east: Array[Vector2i] = [Vector2i(1, 0), Vector2i(3, 0)]
	var board := _board({Vector2i(2, 0): 2})
	assert_array(_blast(east, Vector2i.ZERO, board)).override_failure_message(
		"the swing half moved -- #756/#805 are meant to be untouched by the flag"
	).contains_exactly([Vector2i(1, 0)])
	assert_array(_aoe(east, Vector2i.ZERO, board)).override_failure_message(
		"a true AoE was stopped by a wall, so the propagation is still unconditional"
	).contains_exactly([Vector2i(1, 0), Vector2i(3, 0)])


func test_a_true_aoe_reaches_a_cell_no_blast_could_propagate_to() -> void:
	# CONNECTIVITY, which the wall case cannot separate from the trace: past a dip deeper than the
	# tolerance, the far cell sits back at the impact's own height and has a clean flat line of its
	# own -- so a blast loses it only because it could not travel THROUGH the dip. A true AoE
	# propagates through nothing, so it is there.
	var east: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	var board := _board({Vector2i.ZERO: 4, Vector2i(2, 0): 4})
	assert_array(_blast(east, Vector2i.ZERO, board, 2)).is_empty()
	assert_array(_aoe(east, Vector2i.ZERO, board, 2)).override_failure_message(
		"the connectivity clause survived the flag -- a true AoE walks through nothing"
	).contains_exactly([Vector2i(2, 0)])


func test_a_true_aoe_still_misses_what_its_own_height_rule_refuses() -> void:
	# THE HALF THE FLAG DOES NOT TOUCH, and the dev's ruling over a fully terrain-blind AoE: each
	# cell still asks this attack's own vertical rule from the anchor. The near cell in the case
	# above is the one that shows it -- a dip past the tolerance, reached by nothing and refused on
	# its own account, so it is absent from BOTH answers while the far cell is not.
	var east: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	var board := _board({Vector2i.ZERO: 4, Vector2i(2, 0): 4})
	assert_array(_aoe(east, Vector2i.ZERO, board, 2)).override_failure_message(
		"a true AoE reached a cell outside its own tolerance -- the height clause went with the trace"
	).not_contains([Vector2i(1, 0)])
	# The control: lift the tolerance and that same cell lands, so its absence above is the RULE
	# rather than the shape or the board.
	assert_array(_aoe(east, Vector2i.ZERO, board)).contains_exactly_in_any_order(east)


func test_the_flag_forks_a_self_anchored_swing_too() -> void:
	# The other anchor. A one-level step two cells ahead ends the lane under a melee rule (the
	# truncation case below asserts exactly that); with the modifier off the whole line lands, step
	# and all -- so one flag covers both propagations, which is what max_range already deciding the
	# anchor is what buys.
	var swung := P.line(_attack(), 3)
	swung.vertical_rule = AttackData.VerticalRule.MELEE
	var board := _board({Vector2i(0, -2): 2})
	assert_array(Reach.get_affected_cells_from(null, Vector2i.ZERO, Vector2i(0, -1), swung, board)) \
		.contains_exactly([Vector2i(0, -1)])
	swung.swing = false
	# The raised cell is refused by the MELEE rule on its own account (a sheer step at range), and
	# the cell BEHIND it -- flat, and unreachable for a swing because the lane ended -- comes back.
	assert_array(Reach.get_affected_cells_from(null, Vector2i.ZERO, Vector2i(0, -1), swung, board)) \
		.override_failure_message("the directional branch never asks the flag") \
		.contains_exactly([Vector2i(0, -1), Vector2i(0, -3)])
