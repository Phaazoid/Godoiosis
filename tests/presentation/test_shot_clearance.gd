# The shot clearance (#1132): what stands between the lens and the action, which way the battle zoom
# turns to see past it, and what it hides when no angle clears.
#
# SCENE-FREE, ShotDirector's shape: the world is a few tables and two callables, the lens a callable
# from turn to point, so every rule is asked directly rather than staged on a board. The wire --
# that battle3d reads the mirrors and pushes the answer back at them -- is test_camera_clearance's.
extends GdUnitTestSuite

const SUBJECT := 1001
const BYSTANDER := 77
const HERE := Vector2i(5, 5)

# Column extents and prop boxes the world callables read, per case.
var _columns: Dictionary[Vector2i, Vector2] = {}
var _props: Dictionary[Vector2i, AABB] = {}


func before_test() -> void:
	_columns.clear()
	_props.clear()


func _world() -> ShotClearance.World:
	var world := ShotClearance.World.new()
	world.column_extent = func(cell: Vector2i) -> Vector2:
		return _columns.get(cell, Vector2(NAN, NAN))
	world.prop_box = func(cell: Vector2i) -> AABB:
		return _props.get(cell, AABB())
	return world


func _body(id: int, cell: Vector2i) -> ShotClearance.Body:
	var body := ShotClearance.Body.new()
	body.unit_id = id
	body.cell = cell
	body.feet = Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)
	body.half_width = 0.3
	body.height = 0.6
	body.heights.append(0.3)
	body.heights.append(0.5)
	return body


func _stand(world: ShotClearance.World, body: ShotClearance.Body) -> void:
	var here: Array = world.bodies_at.get(body.cell, [])
	here.append(body)
	world.bodies_at[body.cell] = here


# The lens for a turn: five cells out from the subject and four up, turn 0 due SOUTH (low z) --
# the camera rig's own convention, a yaw t standing the camera at (sin t, cos t) from its aim,
# mirrored so turn 0 is the side these cases put their blockers on.
func _lens(turn: float) -> Vector3:
	var t := deg_to_rad(turn)
	return Vector3(HERE.x + 0.5 + sin(t) * 5.0, 4.0, HERE.y + 0.5 - cos(t) * 5.0)


func _lens_of() -> Callable:
	return func(turn: float) -> Vector3:
		return _lens(turn)


func _subjects() -> Array[ShotClearance.Body]:
	var out: Array[ShotClearance.Body] = [_body(SUBJECT, HERE)]
	return out


func _none() -> Array[ShotClearance.Target]:
	var out: Array[ShotClearance.Target] = []
	return out


func _found(world: ShotClearance.World, turn: float) -> ShotClearance.Found:
	return ShotClearance.survey(world, _lens(turn), _subjects(), _none())


# --- the sight line ------------------------------------------------------------------------------

func test_a_column_taller_than_the_sight_line_blocks_it() -> void:
	_columns[Vector2i(5, 3)] = Vector2(-1.0, 3.0)
	assert_bool(_found(_world(), 0.0).columns.has(Vector2i(5, 3))).override_failure_message(
			"a column standing three tall between the lens and the subject was not seen").is_true()


func test_the_same_column_beyond_the_subject_blocks_nothing() -> void:
	_columns[Vector2i(5, 7)] = Vector2(-1.0, 3.0)
	assert_bool(_found(_world(), 0.0).is_clear()).override_failure_message(
			"a column BEHIND the subject was reported in the way").is_true()


func test_a_column_under_the_sight_line_blocks_nothing() -> void:
	_columns[Vector2i(5, 3)] = Vector2(-1.0, 1.0)
	assert_bool(_found(_world(), 0.0).is_clear()).override_failure_message(
			"a low column the line passes OVER was reported in the way").is_true()


func test_a_line_passing_under_a_floating_column_is_not_blocked_by_it() -> void:
	# A torn-out stage floats forty cells up, so "anything below the top" is the wrong test: the
	# column is a box from its underside to its top, and a line under the box clears it. The
	# non-vacuity half is the case above it with the same top and a floor at -1.
	_columns[Vector2i(5, 3)] = Vector2(2.6, 3.0)
	assert_bool(_found(_world(), 0.0).is_clear()).override_failure_message(
			"a line passing UNDER a column's floor was reported blocked by it").is_true()


func test_a_lens_inside_a_column_is_blocked_by_it() -> void:
	_columns[Vector2i(5, 0)] = Vector2(-1.0, 6.0)
	assert_bool(_found(_world(), 0.0).columns.has(Vector2i(5, 0))).override_failure_message(
			"the camera sat inside a column and the column was not reported").is_true()


func test_the_subjects_own_ground_never_blocks_its_own_sight_lines() -> void:
	# A body standing on a ramp sits BELOW its own column's drawn top (the high corner), so a ray to
	# its middle passes inside that column. Its feet stand on it; it is never the obstruction.
	_columns[HERE] = Vector2(-1.0, 1.0)
	assert_bool(_found(_world(), 0.0).is_clear()).override_failure_message(
			"the subject's own ground was reported standing between the lens and the subject") \
		.is_true()


func test_protected_ground_blocks_an_angle_but_is_never_offered_for_hiding() -> void:
	_columns[Vector2i(5, 3)] = Vector2(-1.0, 3.0)
	var world := _world()
	world.protected[Vector2i(5, 3)] = true
	var found := ShotClearance.survey(world, _lens(0.0), _subjects(), _none())
	assert_int(found.columns.size()).override_failure_message(
			"ground under the action was offered for hiding").is_equal(0)
	assert_int(found.fixed).override_failure_message(
			"protected ground stopped counting against the angle it blocks").is_greater(0)


# A body tall enough to stand INTO the sight line at the lens's pitch -- the ordinary 0.6 sits under a
# line looking down at forty degrees until it is right beside the subject.
func _tall(id: int, cell: Vector2i) -> ShotClearance.Body:
	var body := _body(id, cell)
	body.height = 4.0
	return body


func test_a_bystander_on_the_line_is_hidden_and_a_participant_is_not() -> void:
	var world := _world()
	_stand(world, _tall(BYSTANDER, Vector2i(5, 3)))
	_stand(world, _body(SUBJECT, HERE))
	var found := ShotClearance.survey(world, _lens(0.0), _subjects(), _none())
	assert_bool(found.units.has(BYSTANDER)).override_failure_message(
			"a unit standing on the line was not reported").is_true()
	assert_bool(found.units.has(SUBJECT)).override_failure_message(
			"the subject was reported blocking itself").is_false()
	world.participants[BYSTANDER] = true
	found = ShotClearance.survey(world, _lens(0.0), _subjects(), _none())
	assert_int(found.units.size()).override_failure_message(
			"a unit in the action was offered for hiding").is_equal(0)
	assert_int(found.fixed).override_failure_message(
			"a participant in front of the subject stopped counting against the angle") \
		.is_greater(0)


func test_a_prop_overhanging_into_the_line_is_found_from_its_own_cell() -> void:
	# The art of a prop can spill past its cell, so the ring AROUND each crossed cell is asked. This
	# prop's cell is off the line; only its box reaches across it.
	_props[Vector2i(4, 3)] = AABB(Vector3(4.3, 0.0, 3.0), Vector3(1.4, 3.0, 1.0))
	assert_bool(_found(_world(), 0.0).props.has(Vector2i(4, 3))).override_failure_message(
			"a prop leaning across the line from the next cell was not found").is_true()


func test_a_body_is_looked_at_across_its_whole_width_and_both_heights() -> void:
	var targets := _body(SUBJECT, HERE).targets(_lens(0.0))
	assert_int(targets.size()).override_failure_message(
			"two heights at three points each is six sight lines").is_equal(6)
	var xs: Dictionary[float, bool] = {}
	for target in targets:
		xs[snappedf(target.point.x, 0.001)] = true
	assert_int(xs.size()).override_failure_message(
			"the edge rays did not spread across the body's width").is_equal(3)


# --- the ranking ---------------------------------------------------------------------------------

func test_side_on_is_both_sides_and_end_on_is_the_last_resort() -> void:
	assert_float(ShotClearance.deviation(0.0)).is_equal(0.0)
	assert_float(ShotClearance.deviation(180.0)).is_equal(0.0)
	assert_float(ShotClearance.deviation(45.0)).is_equal(45.0)
	assert_float(ShotClearance.deviation(-135.0)).is_equal(45.0)
	assert_float(ShotClearance.deviation(90.0)).is_equal(90.0)
	assert_float(ShotClearance.deviation(-90.0)).is_equal(90.0)


# --- the latch -----------------------------------------------------------------------------------

func _step(clearance: ShotClearance, world: ShotClearance.World, can_turn := true) -> bool:
	return clearance.step(world, _subjects(), _none(), _lens_of(), can_turn)


func test_a_clear_view_never_moves() -> void:
	var clearance := ShotClearance.new()
	clearance.renew(true)
	assert_bool(_step(clearance, _world())).override_failure_message(
			"a shot with nothing in its way changed something").is_false()
	assert_float(clearance.turn).is_equal(0.0)
	assert_int(clearance.hidden.hideable()).is_equal(0)


func test_a_blocked_side_turns_to_the_other_side_on_angle() -> void:
	_columns[Vector2i(5, 3)] = Vector2(-1.0, 3.0)
	var clearance := ShotClearance.new()
	clearance.renew(true)
	assert_bool(_step(clearance, _world())).is_true()
	assert_float(clearance.turn).override_failure_message(
			"the near side was blocked and the clear far side was not taken").is_equal(180.0)
	assert_int(clearance.hidden.hideable()).override_failure_message(
			"a clear angle existed and something was hidden anyway").is_equal(0)


# A shot whose subject is not drawn yet (a unit the mirror has not placed this frame) has nobody to
# look at -- and the search its edge owed must survive that frame rather than be spent on nothing.
# The geometry is chosen so the FULL search and the per-frame check disagree: no angle is clear, and
# the far side has one blocker fewer. The search takes the far side; the check, finding nothing
# clear, would hide in place and leave the turn at 0.
func test_a_search_owed_by_the_edge_waits_out_a_frame_with_nobody_to_look_at() -> void:
	_ring()
	_columns[Vector2i(5, 3)] = Vector2(-1.0, 10.0)
	var clearance := ShotClearance.new()
	clearance.renew(true)
	var nobody: Array[ShotClearance.Body] = []
	assert_bool(clearance.step(_world(), nobody, _none(), _lens_of(), true)).is_false()
	_step(clearance, _world())
	assert_float(clearance.turn).override_failure_message(
			"the search owed by the edge was spent on a frame with nobody in the shot").is_equal(180.0)


func _ring() -> void:
	# A tall column on every neighbour of the subject: no angle sees it clear.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx != 0 or dy != 0:
				_columns[HERE + Vector2i(dx, dy)] = Vector2(-1.0, 10.0)


func test_when_no_angle_is_clear_the_held_side_hides_its_blockers() -> void:
	_ring()
	var clearance := ShotClearance.new()
	clearance.renew(true)
	_step(clearance, _world())
	assert_float(ShotClearance.deviation(clearance.turn)).override_failure_message(
			"with every angle blocked the shot left side-on").is_equal(0.0)
	assert_int(clearance.hidden.columns.size()).override_failure_message(
			"no angle was clear and nothing was hidden").is_greater(0)
	for cell: Vector2i in clearance.hidden.columns:
		assert_bool(_found(_world(), clearance.turn).columns.has(cell)).override_failure_message(
				"hid %s, which does not stand in the chosen angle's way" % cell).is_true()


func test_a_shot_with_no_line_to_turn_can_only_hide() -> void:
	_columns[Vector2i(5, 3)] = Vector2(-1.0, 3.0)
	var clearance := ShotClearance.new()
	clearance.renew(true)
	_step(clearance, _world(), false)
	assert_float(clearance.turn).override_failure_message(
			"a shot with no aim line was turned").is_equal(0.0)
	assert_bool(clearance.hidden.columns.has(Vector2i(5, 3))).override_failure_message(
			"a shot that cannot turn left its blocker standing").is_true()


func test_a_held_angle_that_becomes_blocked_hides_the_blocker_and_never_turns() -> void:
	# #972's shape: the shot was clear when chosen, and the subject's own movement put something in
	# the way. Round 3 of the play-check (2026-10-07): a turn there swings the camera MID-BLOW, so the
	# per-frame check hides what came into the way and holds the angle -- even with a clear one free.
	var clearance := ShotClearance.new()
	clearance.renew(true)
	_step(clearance, _world())
	assert_float(clearance.turn).is_equal(0.0)
	_columns[Vector2i(5, 3)] = Vector2(-1.0, 3.0)
	assert_bool(_found(_world(), 180.0).is_clear()).override_failure_message(
			"precondition: the far side is blocked too, so a turn would have had nowhere to go") \
		.is_true()
	assert_bool(_step(clearance, _world())).override_failure_message(
			"the held angle became blocked and nothing changed").is_true()
	assert_float(clearance.turn).override_failure_message(
			"the camera turned while the shot played -- the mid-blow swing").is_equal(0.0)
	assert_bool(clearance.hidden.columns.has(Vector2i(5, 3))).override_failure_message(
			"the column that came into the way was left standing in it").is_true()


func test_hides_grow_within_a_shot_and_come_back_with_the_next() -> void:
	_ring()
	var clearance := ShotClearance.new()
	clearance.renew(true)
	_step(clearance, _world())
	var first := clearance.hidden.columns.duplicate()
	var world := _world()
	# On whichever side-on line the shot holds: south of the subject at turn 0, north at 180.
	var side := -3 if is_zero_approx(clearance.turn) else 3
	_stand(world, _tall(BYSTANDER, HERE + Vector2i(0, side)))
	_step(clearance, world)
	assert_bool(clearance.hidden.units.has(BYSTANDER)).override_failure_message(
			"a new blocker in a shot with no clear angle was not hidden").is_true()
	for cell: Vector2i in first:
		assert_bool(clearance.hidden.columns.has(cell)).override_failure_message(
				"%s came back while its shot still played" % cell).is_true()
	assert_bool(clearance.renew(false)).override_failure_message(
			"a new shot kept what the last one hid").is_true()
	assert_int(clearance.hidden.hideable()).is_equal(0)


func test_a_reset_puts_everything_back() -> void:
	_columns[Vector2i(5, 3)] = Vector2(-1.0, 3.0)
	var clearance := ShotClearance.new()
	clearance.renew(true)
	_step(clearance, _world(), false)
	assert_bool(clearance.reset()).override_failure_message(
			"a reset over a hidden column said nothing changed").is_true()
	assert_int(clearance.hidden.hideable()).is_equal(0)
	assert_float(clearance.turn).is_equal(0.0)
