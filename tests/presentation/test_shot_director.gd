# The camera's priority table (#672): which shot owns the camera, and when that changes.
#
# SCENE-FREE -- no board, no rig, no frames. ShotDirector takes the causes as five arguments
# (CameraTrace's idiom: the caller hands in what the seam would have looked up), so every case
# here is a precedence question asked directly instead of a pass staged to provoke one. That is
# the whole reason the table was split out of _mirror_camera: the arbitration is what the #602 arc
# kept getting wrong, and a rule you cannot ask about in one line is a rule you re-derive.
extends GdUnitTestSuite

const NOBODY := 0
const SOMEBODY := 4242
const SOMEBODY_ELSE := 9999

var _cells: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 2)]
var _other_cells: Array[Vector2i] = [Vector2i(5, 5)]
var _span: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, 3)]
var _none: Array[Vector2i] = []


func _solve(locked: bool, subject: int, cells: Array[Vector2i], span: Array[Vector2i],
		death_show: bool) -> ShotDirector.Shot:
	return ShotDirector.solve(locked, subject, ShotDirector.staged(cells),
			ShotDirector.spanned(span), death_show)


func _name_of(shot: ShotDirector.Shot) -> String:
	return ShotDirector.Shot.keys()[shot]


# --- The table ----------------------------------------------------------------------------------

func test_the_lock_gates_the_whole_table_rather_than_sitting_in_it() -> void:
	# Every cause at once, and the answer is still NONE. A LOCKED row would sit somewhere in the
	# order and be outranked from above -- which is exactly how a death show still playing as the
	# lock let go would hold the camera past the end of the pass, where the release must always
	# hand the view back.
	assert_int(_solve(false, SOMEBODY, _cells, _span, true)).override_failure_message(
			"playback does not own the camera and a shot claimed it anyway") \
		.is_equal(ShotDirector.Shot.NONE)
	assert_int(_solve(true, NOBODY, _none, _none, false)).override_failure_message(
			"playback owns the camera and no shot took it").is_equal(ShotDirector.Shot.WIDE)


func test_the_death_show_outranks_the_shot_a_release_would_fall_to() -> void:
	# #602 round 8, as one row rather than three hand-rolled fixes. Note WHICH rank does the work:
	# the show's condition is "nobody is followed" and TRAINED's is "somebody is", so those two
	# never compete -- DEATH_SHOW stands in TRAINED's place once the body is gone. What makes the
	# release a DEFERRAL is this row outranking the STAGE it would otherwise fall to.
	assert_int(_solve(true, NOBODY, _cells, _none, true)).override_failure_message(
			"the subject died into a void and the shot fell straight back to the stage -- a "
			+ "farther camera's frame bottom is deeper, so the edge walks down onto the forming "
			+ "bar").is_equal(ShotDirector.Shot.DEATH_SHOW)


func test_a_death_show_somebody_else_is_dying_in_does_not_take_the_frame() -> void:
	# The hold's condition is "the show is live AND nobody is followed". A show playing while the
	# camera is still tracking a live subject is another unit's death and owns nothing -- otherwise
	# any kill anywhere would freeze the shot for the rest of the beat.
	assert_int(_solve(true, SOMEBODY, _cells, _none, true)).override_failure_message(
			"a death show elsewhere on the board stole the frame from a live subject") \
		.is_equal(ShotDirector.Shot.TRAINED)


func test_a_trained_subject_outranks_the_stage_it_is_standing_on() -> void:
	# The close-up wins over the establishing frame. Both are live through every beat of a staged
	# fight, so this is the pair the table exists to order.
	assert_int(_solve(true, SOMEBODY, _cells, _none, false)).override_failure_message(
			"a beat's subject did not get the close-up over the stage's wide frame") \
		.is_equal(ShotDirector.Shot.TRAINED)


func test_a_stage_outranks_a_walk_left_published_behind_it() -> void:
	assert_int(_solve(true, NOBODY, _cells, _span, false)).override_failure_message(
			"a walk's framing outranked the fight staged after it").is_equal(ShotDirector.Shot.STAGE)


func test_a_walk_frames_both_its_ends_only_when_it_has_two() -> void:
	# The publisher's rule (a walk that goes nowhere publishes nothing) spelled where it decides a
	# shot: a one-cell span is not a span, and must fall through rather than frame a point.
	assert_int(_solve(true, NOBODY, _none, _span, false)) \
		.is_equal(ShotDirector.Shot.SPAN)
	var stub: Array[Vector2i] = [Vector2i(1, 1)]
	assert_int(_solve(true, NOBODY, _none, stub, false)).override_failure_message(
			"a one-ended span framed a walk across itself").is_equal(ShotDirector.Shot.WIDE)


# --- The edge -----------------------------------------------------------------------------------

func test_the_first_look_at_a_claimed_camera_is_a_change() -> void:
	var shots := ShotDirector.new()
	assert_int(shots.active).override_failure_message(
			"a director nobody has run already thinks a shot owns the camera") \
		.is_equal(ShotDirector.Shot.NONE)
	assert_bool(shots.update(true, NOBODY, _none, _none, false)).override_failure_message(
			"playback claimed the camera and nothing needed applying").is_true()
	assert_bool(shots.update(true, NOBODY, _none, _none, false)).override_failure_message(
			"the same causes twice asked for a second apply -- the framings re-latch the staged "
			+ "height and re-fit against the live basis, so applying one per frame walks the "
			+ "shot down after any body thrown mid-fight").is_false()


func test_a_stage_republished_over_different_cells_reframes() -> void:
	# The shot does not change -- STAGE either way -- but the VOLUME it frames does, and the whole
	# reason the edge is the input rather than the verdict.
	var shots := ShotDirector.new()
	shots.update(true, NOBODY, _cells, _none, false)
	assert_bool(shots.update(true, NOBODY, _other_cells, _none, false)).override_failure_message(
			"a fight staged somewhere else kept the last stage's framing").is_true()


func test_the_shot_moving_to_a_new_subject_is_a_change() -> void:
	# Same shot, same distance, different unit: it still has to be applied, because the trace row
	# is what a bug report reads to learn which unit the camera was on.
	var shots := ShotDirector.new()
	shots.update(true, SOMEBODY, _cells, _none, false)
	assert_bool(shots.update(true, SOMEBODY_ELSE, _cells, _none, false)).override_failure_message(
			"the beat moved to another subject and the transcript never said so").is_true()
	assert_str(shots.transition_note("Bruiser")).override_failure_message(
			"a trained transition did not name its subject").contains("Bruiser")


# --- The deferral (#602 round 8) ----------------------------------------------------------------

func test_a_release_due_under_a_death_show_is_deferred_and_then_fires() -> void:
	# The sequence that cost round 8, asked as three lines. A deferred release and a skipped one
	# leave the camera in the same place one frame later; only the ORDER tells them apart, so the
	# case is written as the order.
	var shots := ShotDirector.new()
	shots.update(true, SOMEBODY, _cells, _none, false)
	assert_int(shots.active).is_equal(ShotDirector.Shot.TRAINED)

	# The body is freed and the cubes are in the air. The release is now due and must NOT happen.
	assert_bool(shots.update(true, NOBODY, _cells, _none, true)).is_true()
	assert_int(shots.active).override_failure_message(
			"the subject died and the shot released while the cubes were still assembling -- the "
			+ "frame's bottom edge walks down onto the forming bar") \
		.is_equal(ShotDirector.Shot.DEATH_SHOW)
	assert_str(shots.transition_note("")).override_failure_message(
			"the hold went unnamed, so a report of it reads like an ordinary shot change") \
		.contains("holds")

	# ...and the moment it clears, the deferred release fires. DEFERRED, never skipped.
	assert_bool(shots.update(true, NOBODY, _cells, _none, false)).override_failure_message(
			"the show ended and the release never fired -- the defer became a skip").is_true()
	assert_str(shots.transition_note("")).override_failure_message(
			"the release that fired after a hold did not read as a deferred one") \
		.contains("deferred release")


func test_a_pass_ending_hands_the_camera_back_from_any_shot() -> void:
	var shots := ShotDirector.new()
	shots.update(true, NOBODY, _cells, _none, true)
	assert_int(shots.active).is_equal(ShotDirector.Shot.DEATH_SHOW)
	assert_bool(shots.update(false, NOBODY, _cells, _none, true)).override_failure_message(
			"the lock released and the director kept the camera").is_true()
	assert_int(shots.active).override_failure_message(
			"a shot outlived the pass that claimed it: %s" % _name_of(shots.active)) \
		.is_equal(ShotDirector.Shot.NONE)


func test_a_fresh_pass_inherits_nothing_from_the_last_one() -> void:
	# The claim edge is a reset. Two passes staging the identical cells still each get their own
	# framing, which is the rule the shipped claim edge already keeps by clearing its latches.
	var shots := ShotDirector.new()
	shots.update(true, SOMEBODY, _cells, _none, false)
	shots.update(true, NOBODY, _cells, _none, false)
	shots.update(false, NOBODY, _none, _none, false)
	assert_bool(shots.update(true, NOBODY, _cells, _none, false)).override_failure_message(
			"a new pass staging the same cells was told nothing had changed").is_true()
	assert_int(shots.active).override_failure_message(
			"the previous pass's release still governed the new pass's opening shot: %s"
			% _name_of(shots.active)).is_equal(ShotDirector.Shot.STAGE)
