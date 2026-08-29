# The 3D camera during play (#176 stage 4d): does it follow the action, does it frame
# the board it loaded, and does it refuse the player at the right moments.
#
# The headline this pins: before 4d nothing moved the 3D rig during a battle at all —
# AIController panned the HIDDEN 2D camera and awaited the full beat, so an enemy turn
# in 3D was ~1.3s of dead air per squad in front of a motionless frame.
#
# The follow is a MIRROR of the 2D camera (which already knows where the action is),
# gated on playback_locked. Two cases below decide that gate, and both are written to fail
# loudly if the gate is widened to _board_locked_for_player(): that predicate also
# covers MENU, where Mission Select opts out of the modal lock.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"
const LEVEL_1 := "res://Scenarios/missions/Level_1.tres"

var _board := SharedBoard.new(SCENE_PATH, PROLOG)
var _scene: Node3D
var _game: Node2D
var _rig: CameraRig3D
var _camera3d: Camera3D


func before() -> void:
	await _board.open(self)


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	_game = _board.scene.game
	_rig = _scene.get_node("CameraRig") as CameraRig3D
	_camera3d = _scene.get_node("CameraRig/Pitch/Camera") as Camera3D


func after_test() -> void:
	# NB the cliff-follow cases below write Pacing rows and never put them back: SharedBoard's own
	# _restore_tuning is the door for that (any CLASS_KNOBS value that MOVED is rewritten on reset),
	# and a second copy in here would be a hand-maintained duplicate of it.
	await _board.check(self)


func after() -> void:
	_board.close()


func test_the_mirror_gate_and_the_pointer_gate_are_never_open_together() -> void:
	for locked in [false, true]:
		_cam().set_playback_locked(locked)
		await _settle()
		assert_bool(_cam().playback_locked and not _game._board_locked_for_player()) \
			.override_failure_message(
				"the mirror may read the 2D camera while the pointer may still write it (#484)") \
			.is_false()
	_cam().set_playback_locked(false)


# The dev's 2026-08-26 ruling: playback owns WHERE the camera looks, the player keeps HOW FAR OUT it
# sits. Before #520 one flag killed orbit and wheel together for a whole AI turn.
func test_the_player_keeps_the_zoom_wheel_while_playback_owns_the_camera() -> void:
	_game.game_state = _game.GameState.AI_TURN
	_cam().set_playback_locked(true)
	await _settle()
	assert_bool(_game._board_locked_for_player()).override_failure_message(
			"precondition: playback should own the board here").is_true()
	assert_bool(_rig.zoom_input_enabled).override_failure_message(
			"the zoom wheel died with the rest of the rig -- the split did not take").is_true()
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE


# A pass CLAIMS the camera and hands it back to whoever held it -- it does not simply unlock.
# An AI turn owns the camera for its whole length and runs a pass inside it, so a blind release
# would unlock the camera mid-turn and let the player drag the view out from under the enemy phase.
func test_a_pass_inside_an_ai_turn_leaves_the_camera_still_owned() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	_game.game_state = _game.GameState.AI_TURN
	_cam().set_playback_locked(true)

	await _game.order_executor.execute_orders(unit)   # empty queue: walks every phase, does nothing
	await _settle()

	assert_bool(_cam().playback_locked).override_failure_message(
			"the pass released the camera it borrowed -- an AI turn is unlocked mid-turn").is_true()
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE


# ...and the mirror image: a pass on the PLAYER's own turn gives the camera back when it ends, or
# the board would stay locked to clicks forever after one Execute.
func test_a_pass_on_the_players_own_turn_gives_the_camera_back() -> void:
	var unit := _player_unit()
	assert_bool(_cam().playback_locked).override_failure_message(
			"precondition: nothing should own the camera before the pass").is_false()

	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_bool(_cam().playback_locked).override_failure_message(
			"the pass kept the camera -- the board never unlocks after an Execute").is_false()


# ...and a MENU takes it, because the surface on screen wants the wheel for itself. This is the
# other half: a gate that never shuts is not a gate.
func test_a_menu_takes_the_zoom_wheel_back() -> void:
	_game.game_state = _game.GameState.MENU
	await _settle()
	assert_bool(_rig.zoom_input_enabled).override_failure_message(
			"a menu is up and the wheel still zooms the board behind it").is_false()
	_game.game_state = _game.GameState.IDLE


# The move phase gets a camera too (dev, 2026-08-26: "when I moved on my turn, the camera just
# kinda stared off into space"). #520 diff 1 wired only the volley beats, and it had ALSO taken the
# player's own scroll away for the length of a pass -- so the move phase went from unframed-but-
# scrollable to unframed-and-frozen.
#
# Asserted on follow_unit rather than a position: pan_to ends by handing over to follow(), and a
# position would depend on the 2D camera's clamp against the board's own extent, i.e. on authored
# content. Run inside a claimed camera (what an AI turn does) because the restore at the end of a
# PLAYER pass clears follow_unit -- here the claim is put back, so the last pan survives to be read.
#
# LIMIT, stated rather than implied: pan_to snaps headless, so this pins the WIRE, not the ordering.
# That the pan precedes the walk is structural -- the await sits above the phase.
# REWRITTEN for #520 diff 2b: the rule this pins CHANGED, so patching the old assertion would have
# left its name pinning something the code no longer does. It used to read follow_unit -- the move
# phase panned to the walker and then TRACKED them. The dev's ask (scratchpad, 2026-08-26) is
# "instead of just centering on the unit, it should try to show both their start and end position in
# the initial shot", and framing both ends only means anything if the camera HOLDS while the walk
# crosses it: a follow would drag the far end straight back out of frame. So there is no follow left
# to assert, and what replaces it is where the camera actually went.
#
# The midpoint is re-derived from the walk's own two ends rather than written down, so a fixture that
# moves cannot red this and a board with different geometry still asks the same question.
func test_the_move_phase_frames_the_walk_across_both_its_ends() -> void:
	var mover := _mobile_player_unit()
	assert_object(mover).override_failure_message(
			"fixture: no player unit on this board can move").is_not_null()

	var grid: TileMapLayer = _game.grid
	_cam().set_playback_locked(true)
	await _settle()

	# Control first: the same pass with nothing queued must move the camera nowhere, or the case
	# below would pass on any pan at all rather than on the move's.
	var parked: Vector2 = _cam().global_position
	await _game.order_executor.execute_orders(mover)
	await _settle()
	assert_vector(_cam().global_position).override_failure_message(
			"an empty pass panned the camera somewhere").is_equal_approx(parked, Vector2.ONE * 0.01)

	var from: Vector2i = mover.movement.cell
	_queue_a_move(mover)
	var to: Vector2i = mover.get_projected_destination()
	assert_bool(to != from).override_failure_message(
			"fixture: the queued move goes nowhere").is_true()
	var midpoint: Vector2 = (GridUtils.cell_world(grid, from) + GridUtils.cell_world(grid, to)) * 0.5
	# ...and the midpoint is deliberately NOT either end, or "both ends" would be indistinguishable
	# from the centre-on-the-unit shot this replaced.
	assert_bool(midpoint.distance_to(GridUtils.cell_world(grid, to)) > 1.0) \
		.override_failure_message("start and end are the same point; the case proves nothing").is_true()

	await _game.order_executor.execute_orders(mover)
	await _settle()

	assert_vector(_cam().global_position).override_failure_message(
			"the move phase framed one end of the walk, not both") \
		.is_equal_approx(midpoint, Vector2.ONE * 0.01)
	assert_object(_cam().follow_unit).override_failure_message(
			"the camera tracked the walker, which drags the far end of the walk out of frame").is_null()
	_cam().set_playback_locked(false)


# ...and the 3D half of the same shot: the span is published for the rig, which widens its distance
# to hold both ends. Pinned at the SEAM (what the executor publishes) rather than at a zoom number,
# which is a fit and therefore a function of fov, pitch and the fit margin -- all knobs.
func test_the_move_phase_publishes_the_span_for_the_rig_to_widen_to() -> void:
	var mover := _mobile_player_unit()
	assert_object(mover).override_failure_message(
			"fixture: no player unit on this board can move").is_not_null()

	var from: Vector2i = mover.movement.cell
	_queue_a_move(mover)
	var to: Vector2i = mover.get_projected_destination()

	# Sampled MID-PASS: execute_orders clears the lock on its way out, and set_playback_locked wipes
	# the span on both edges, so the aftermath cannot answer this. Not awaited -- GDScript runs a
	# coroutine synchronously to its first await, so the publish has already happened by the time
	# this returns and the walk is still in front of us.
	_game.order_executor.execute_orders(mover)
	var published: Array[Vector2i] = _cam().framed_span
	while _game.order_executor.executing_plan != null:
		await await_idle_frame()
	await _settle()

	var expected: Array[Vector2i] = [from, to]
	assert_array(published).override_failure_message(
			"the move phase published no span, so the rig has nothing to widen to") \
		.is_equal(expected)
	assert_array(_cam().framed_span).override_failure_message(
			"the span outlived the pass -- the next squad's walk would open at this one's zoom") \
		.is_empty()


# ...and so does the side-channel tail. ADDED BY FALSIFICATION, not by reasoning: deleting the
# subjects argument from execute_orders' side-channel call left 587 cases green across presentation
# and squad, because everything about codas was pinned at its two ENDS (the sheet builds them, the
# schedule reads them) and nothing drove the wire between. #103's shape exactly.
#
# The camera is parked on ANOTHER unit first, so "it ended up on the rallier" cannot pass by the
# camera simply never having moved. A rally is the cheapest coda to stage: no target, no terrain,
# and _queue_action is the raw door the beat sheet suite already uses.
func test_a_side_channel_verb_takes_the_camera_too() -> void:
	var unit := _player_unit()
	var elsewhere := _any_unit_besides(unit)
	assert_object(elsewhere).override_failure_message(
			"fixture: this board has only one unit").is_not_null()

	var rally := RallyAction.new()
	rally.init(unit)
	unit.squad._queue_action(rally)

	_cam().set_playback_locked(true)
	_cam().follow(elsewhere)
	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_object(_cam().follow_unit).override_failure_message(
			"the tail played with the camera still pointed at whatever it was watching before") \
		.is_same(unit)
	_cam().set_playback_locked(false)


# --- and from which SIDE it frames them (#520 diff 2a) ----------------------------------------

# The whole wire, driven end to end: the executor publishes the beat's aim line, the mirror poll
# reads it, and the rig turns. Written this way BECAUSE the diff-1 side-channel mutant survived 587
# cases by having both ends pinned and nothing driving the middle (#103's shape) -- so this queues a
# REAL attack through the real executor rather than poking directed_line.
#
# The expected yaw is re-derived from the beat's own line rather than written down, so the case
# says "it went side-on to what it was framing", not "it went to 90 degrees" -- a fixture that
# moves, or a rig parked on a different axis, must not red this.
#
# The STRENGTH is set rather than read: it is a feel value the dev tunes, so the case pins the fork
# (full turn vs none) and never one side's number.
func test_a_pass_turns_the_camera_to_see_each_blast_side_on() -> void:
	var was := [Pacing.BOARD_DIRECTION, Pacing.CINEMATIC_DIRECTION]
	Pacing.BOARD_DIRECTION = 1.0
	Pacing.CINEMATIC_DIRECTION = 1.0

	# Claimed FIRST, the AI-turn shape: a pass on the player's own turn RELEASES at the end, and the
	# release fires the view return -- which puts the pre-pass yaw back, so an assertion taken after
	# it is looking at the camera coming home rather than at the shot. Claiming first makes the
	# pass's own save/restore land on `true`, so the angle it reached survives to be read.
	_cam().set_playback_locked(true)
	await _settle()
	var attacker := _player_unit()
	var line := _swing_at_open_ground(attacker)
	var detent: float = _rig._target_yaw_degrees

	await _game.order_executor.execute_orders(attacker)
	await _settle()

	var want := BoardSpace.side_on_yaw(line[0], line[1], detent)
	assert_bool(is_nan(want)).override_failure_message(
			"fixture drifted: the staged swing has no direction").is_false()
	# THE NON-VACUITY GUARD, and it is the whole case: an aim along a board axis is already seen
	# side-on from a detent, so a pass that turned nothing at all would satisfy the assertion below.
	# The first draft of this case aimed along +x and passed against every mutant.
	assert_float(_yaw_gap(want, detent)).override_failure_message(
			"fixture drifted: this swing is already square-on, so the case cannot fail") \
		.is_greater(10.0)
	assert_float(_yaw_gap(_rig._target_yaw_degrees, want)).override_failure_message(
			"the pass played square-on: yaw %.1f, side-on to the blast was %.1f" \
			% [_rig._target_yaw_degrees, want]).is_equal_approx(0.0, 0.5)

	Pacing.BOARD_DIRECTION = was[0]
	Pacing.CINEMATIC_DIRECTION = was[1]
	_cam().set_playback_locked(false)


# ...and at strength 0 the identical pass does not move the camera a degree. That is what makes the
# knob a DIAL rather than a switch, and it is what keeps the plain board bit-for-bit the square-on
# enemy phase it has always been. Both profiles are zeroed, so this cannot pass by the fixture
# happening to run under the other one.
func test_at_zero_strength_the_same_pass_leaves_the_camera_square_on() -> void:
	var was := [Pacing.BOARD_DIRECTION, Pacing.CINEMATIC_DIRECTION]
	Pacing.BOARD_DIRECTION = 0.0
	Pacing.CINEMATIC_DIRECTION = 0.0

	_cam().set_playback_locked(true)   # same claimed-camera shape as the case above
	await _settle()
	var attacker := _player_unit()
	_swing_at_open_ground(attacker)
	var detent: float = _rig._target_yaw_degrees

	await _game.order_executor.execute_orders(attacker)
	await _settle()

	assert_float(_yaw_gap(_rig._target_yaw_degrees, detent)).override_failure_message(
			"a zeroed camera angle still turned the camera, to %.1f" % _rig._target_yaw_degrees) \
		.is_equal_approx(0.0, 0.01)

	Pacing.BOARD_DIRECTION = was[0]
	Pacing.CINEMATIC_DIRECTION = was[1]
	_cam().set_playback_locked(false)


# ADDED BY FALSIFICATION: measuring the turn from the LIVE yaw instead of from the detent the pass
# squared up to passed all 27 cases. At strength 0 and 1 the two are identical -- 0 moves nothing
# either way, 1 lands on the full angle either way -- so only a PARTIAL turn can tell them apart,
# and no case had one.
#
# What breaks is idempotence, which matters because the mirror re-solves this EVERY FRAME: measured
# from the live yaw, each frame closes half the remaining gap again, so a half-strength turn creeps
# to the full angle over a few frames and the knob quietly stops meaning anything. Asserted as the
# property (three calls, one answer) rather than as a frame count, so it does not depend on how
# many frames an attack happens to take.
func test_a_partial_turn_is_measured_from_where_the_pass_started() -> void:
	var was := [Pacing.BOARD_DIRECTION, Pacing.CINEMATIC_DIRECTION]
	Pacing.BOARD_DIRECTION = 0.5
	Pacing.CINEMATIC_DIRECTION = 0.5

	_cam().set_playback_locked(true)   # claiming is what captures the baseline
	await _settle()
	var detent: float = _rig._target_yaw_degrees
	var line := [Vector2i(0, 0), Vector2i(3, 3)] as Array[Vector2i]

	_rig.aim_along(line)
	var once: float = _rig._target_yaw_degrees
	# Non-vacuity: a partial turn that landed ON the detent, or all the way at the full angle, would
	# satisfy the idempotence assertion for free.
	var full := BoardSpace.side_on_yaw(line[0], line[1], detent)
	assert_float(_yaw_gap(once, detent)).override_failure_message(
			"the half turn did not leave the detent, so this case cannot fail").is_greater(5.0)
	assert_float(_yaw_gap(once, full)).override_failure_message(
			"the half turn went all the way, so this case cannot fail").is_greater(5.0)

	_rig.aim_along(line)
	_rig.aim_along(line)

	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"the angle crept: one poll gave %.1f, three gave %.1f" % [once, _rig._target_yaw_degrees]) \
		.is_equal_approx(once, 0.01)

	Pacing.BOARD_DIRECTION = was[0]
	Pacing.CINEMATIC_DIRECTION = was[1]
	_cam().set_playback_locked(false)


# A beat with nothing to frame must not swing the camera back to square-on -- absence means "keep
# the angle you have", the same rule the subject schedule already follows. Driven at the rig, since
# what is being pinned is how an EMPTY line is read.
func test_a_beat_with_no_line_leaves_the_angle_where_it_was() -> void:
	_cam().set_playback_locked(true)
	await _settle()
	_rig.aim_along([Vector2i(0, 0), Vector2i(3, 0)] as Array[Vector2i])
	var turned: float = _rig._target_yaw_degrees

	_rig.aim_along([] as Array[Vector2i])

	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"an empty line snapped the camera back to square-on").is_equal_approx(turned, 0.01)
	_cam().set_playback_locked(false)


# #47's swing at open ground: a legal aim with no unit on the cell, which resolves and plays. It is
# the one attack this suite can stage without asking what the board contains (the content razor) --
# every alternative needs an enemy standing in reach. Returns the line the beat will carry.
func _swing_at_open_ground(attacker: Unit) -> Array[Vector2i]:
	var origin: Vector2i = attacker.movement.cell
	# DIAGONAL, deliberately: a pair on a board axis is already side-on from a detent, so an axial
	# aim gives a case that passes whether the camera turns or not.
	var aim := origin + Vector2i(1, 1)
	# _queue_action is the raw door -- the queue-time whiff gate would refuse an aim at nobody, and
	# what is being staged here is a beat, not a player gesture.
	attacker.squad._queue_action(AttackAction.declare(attacker, origin, aim))
	return [origin, aim] as Array[Vector2i]


func _yaw_gap(a: float, b: float) -> float:
	return absf(rad_to_deg(angle_difference(deg_to_rad(a), deg_to_rad(b))))


func _any_unit_besides(other: Unit) -> Unit:
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit != null and unit != other:
			return unit
	return null


# The camera comes BACK (dev, 2026-08-26: "the camera should return home after a pass, and after
# the enemy turn"). Playback borrows the rig -- squaring the yaw to a detent and resetting the zoom
# on the way in, then driving the aim for the whole pass -- and hands all three back on the way out.
#
# NOT the rig's _home_* triple, which is the OPENING SHOT and what R restores; this is where the
# PLAYER was standing. Both live on the rig, named apart.
#
# A REAL MOVE is queued rather than running an empty pass, and that is not incidental: the edges
# live in _mirror_camera, i.e. in _process. An empty pass claims and releases inside one call with
# no frame between, so the poll never sees the flag change and neither edge ever fires.
func test_a_pass_gives_the_player_their_view_back() -> void:
	var mover := _mobile_player_unit()
	assert_object(mover).override_failure_message(
			"fixture: no player unit on this board can move").is_not_null()
	# Deliberately OFF a detent and away from playback_distance, so the claim has something to
	# change and the restore something to undo. Set directly: "the player panned here" has no
	# production door but WASD.
	_rig._target_yaw_degrees = 37.0
	_rig.set_zoom(_rig.playback_distance - 3.0)
	await _settle()
	var aim: Vector3 = _rig.position
	var yaw: float = _rig._target_yaw_degrees
	var distance: float = _rig._target_distance

	_queue_a_move(mover)
	await _game.order_executor.execute_orders(mover)
	await _settle()

	assert_vector(_rig.position).override_failure_message(
			"the pass kept the aim it borrowed").is_equal_approx(aim, Vector3.ONE * 0.01)
	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"the yaw stayed squared to the detent playback snapped it to").is_equal_approx(yaw, 0.01)
	assert_float(_rig._target_distance).override_failure_message(
			"the zoom stayed at the playback distance").is_equal_approx(distance, 0.01)


# ...and it FLIES back rather than cutting (#520 diff 2b). The most visible of the four pans the
# dev's never-teleport rule covers: this fires at the end of every Execute and every enemy turn.
#
# Pinned as the DECISION -- the target moved, the camera did not -- because headless both position
# channels land inside the frame the release edge fires in (the rig's own escape), so the aftermath
# cannot tell a pan from a cut. The case above is the wire; this is what kind of movement it is.
func test_the_view_return_is_a_pan_rather_than_a_cut() -> void:
	_rig.hold_at(Vector3(_rig.pan_limit.position.x, _rig.position.y, _rig.pan_limit.position.y))
	await _settle()
	_rig.stash_view()

	_rig.hold_at(Vector3(_rig.pan_limit.end.x, _rig.position.y, _rig.pan_limit.end.y))
	await _settle()
	var away: Vector3 = _rig.position
	assert_bool(away.distance_to(_rig._borrowed_position) > 1.0).override_failure_message(
			"the borrowed view is where the rig already sits; the case proves nothing").is_true()

	_rig.restore_view()

	assert_that(_rig.position).override_failure_message(
			"the view return teleported -- it wrote the camera's position, not its target") \
		.is_equal(away)
	assert_that(_rig._target_aim).is_equal(_rig._borrowed_position)


# The same rule at the other three: #471's return to the acting unit. Driven through the real
# signal, and asserted with NO await for the same reason as above -- before #520 this call wrote
# position outright and would still be at the unit by the time the statement after it ran.
func test_a_committed_order_pans_the_rig_back_rather_than_cutting_to_it() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	_rig.hold_at(Vector3(_rig.pan_limit.position.x, _rig.position.y, _rig.pan_limit.position.y))
	await _settle()
	var before: Vector3 = _rig.position

	_game.focus_view_on(unit)

	assert_bool(_rig._target_aim.distance_to(before) > 1.0).override_failure_message(
			"nothing was aimed at, so 'the camera did not jump' proves nothing").is_true()
	assert_that(_rig.position).override_failure_message(
			"the return to the acting unit still cuts").is_equal(before)


# --- Riding the tear-out (#521, wired here in #520 diff 2b) -----------------------------------

# THE GAP THIS CLOSES, flagged at PR #568 and missed in its build: _aim_over answers the BOARD's own
# surface, so the fight lifted off into the diorama and the camera stayed down watching the hole.
#
# Driven through BoardSpace's real staging seam, and the expected height re-derived from that seam's
# own offset -- the lift is a GameKnobs value, so the case pins "the camera goes with it", never how
# far up "it" is.
func test_the_camera_rides_the_tear_out_up_off_the_board() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	_cam().set_playback_locked(true)
	await _cam().pan_to(unit)
	await _settle()
	var grounded: Vector3 = _rig.position

	var stage: Array[Vector2i] = [unit.movement.cell]
	BoardSpace.stage(stage, BoardSpace.lift_offset())
	await _settle()

	# Non-vacuous: the lift is a real distance rather than a knob someone has zeroed.
	assert_bool(BoardSpace.stage_offset().length() > 1.0).override_failure_message(
			"the stage lift is zero; the case proves nothing").is_true()
	# The SHOT'S OWN LIFT joins the stage's since #602 round 3 -- the diorama is framed a knobbed
	# distance above the ground its fighters stand on, so the camera rises by both. Re-derived from
	# the two seams rather than written down, for the reason the header gives: neither is this case's
	# to assert a number for. The rule pinned is still "the camera goes up with the fight".
	var shot := BoardSpace.stage_offset() + Vector3(0.0, Pacing.STAGE_AIM_LIFT * BoardSpace.CELL_SIZE, 0.0)
	assert_that(_rig.position).override_failure_message(
			"the fight lifted off the board and the camera stayed down on it") \
		.is_equal(grounded + shot)

	# ...and the poll sits ABOVE the mirror's playback gate, which is what keeps the rig out of the
	# sky once a pass ends: execute_orders clears the staging and puts the lock back in ONE
	# synchronous stretch, so a poll below the gate would never see a frame with the tiles home.
	_cam().set_playback_locked(false)
	BoardSpace.clear_staging()
	await _settle()
	assert_float(_rig.position.y - _rig._target_aim.y).override_failure_message(
			"the camera stayed lifted after playback let go -- the lift poll is below the gate") \
		.is_equal_approx(0.0, 0.001)


# ...and a BOARD SWAP drops what was borrowed, rather than flying back to a pose from a board that
# no longer exists. ScenarioManager.clear_board releases the playback lock, so without this the
# release fires the restore on the dead board. Invalidation is structural -- frame() and pose() both
# drop it, because anything that redefines the opening shot is a new board.
func test_a_board_swap_drops_the_view_playback_borrowed() -> void:
	_rig.set_zoom(_rig.playback_distance - 3.0)
	await _settle()

	_cam().set_playback_locked(true)   # claim -> stash
	await _settle()
	_scene.fit_camera()                # the board swap's own re-frame
	await _settle()
	var framed: Vector3 = _rig.position

	_cam().set_playback_locked(false)  # release -> would restore, if anything were still borrowed
	await _settle()

	assert_vector(_rig.position).override_failure_message(
			"the release flew the camera back to a pose from before the board was reframed") \
		.is_equal_approx(framed, Vector3.ONE * 0.01)


# The production door game._click_choosing_move uses, minus the click: reconstruct the path through
# the range the unit really has, and queue it through the real gate.
func _queue_a_move(unit: Unit) -> void:
	var moverange = _game.compute_move_range(unit)
	var destinations: Array[Vector2i] = _game.get_move_range(moverange, unit)
	var path := RulesService.reconstruct_path(moverange.came_from, unit.movement.cell, destinations[0])
	var move := MoveAction.new()
	move.init(unit, path, null)
	assert_bool(_game.squad_manager.queue_action(unit.squad, move)).override_failure_message(
			"fixture: the move was refused, so the pass would concede instead of playing").is_true()


# A player unit that actually has somewhere to go -- a unit stranded on a terrace with no ramp off
# it is a legal board and produces no move at all (the content razor's second hazard).
func _mobile_player_unit() -> Unit:
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit == null or unit.get_faction() != Team.Faction.PLAYER:
			continue
		var reachable: Array[Vector2i] = _game.get_move_range(_game.compute_move_range(unit), unit)
		if not reachable.is_empty():
			return unit
	return null


func _cam() -> CameraController:
	return _game.camera_controller


func _player_unit() -> Unit:
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit != null and unit.get_faction() == Team.Faction.PLAYER:
			return unit
	return null


# The rig's own settle: process_frame resumes coroutines BEFORE node _process, so one
# frame is stale.
func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


# Where a thing STANDING on this cell sits, through the seam UnitMirror places sprites with
# (BoardSpace.surface_point). Never level 0: Level_1 carries eight raised cells since b057f6e, and
# the day one of them holds a player unit an of_cell(..., 0) frustum check silently asks about a
# point in the air below them.
func _stand(cell: Vector2i) -> Vector3:
	var heights: BoardHeights = _game.board_heights
	return BoardSpace.surface_point(cell, heights)


# The screen point for a cell, off the picker's own column tops — the twin of test_input_bridge's
# _screen_of, and correct for a ramp for the same reason.
func _screen_of(cell: Vector2i) -> Vector2:
	var tops: Dictionary[Vector2i, int] = _scene._tops
	var level: int = tops.get(cell, BoardSpace.FLAT_TOP_ROW)
	return _camera3d.unproject_position(Vector3((cell.x + 0.5) * BoardSpace.CELL_SIZE,
			level * BoardSpace.ROW_HEIGHT, (cell.y + 0.5) * BoardSpace.CELL_SIZE))


# Where the rig should SIT to look at a world x/z: on the surface there, never at the board's
# ceiling. Spelled from BoardSpace rather than asked of battle3d, so a case comparing against it is
# checking the rule and not the implementation against itself.
func _surface_aim(at: Vector3) -> Vector3:
	var heights: BoardHeights = _game.board_heights
	return Vector3(at.x, BoardSpace.surface_height_at(
			Vector2i(floori(at.x), floori(at.z)), at.x, at.z, heights), at.z)


# The mirror cell the 3D pointer reports for a 2D cell — the picker's answer, not an assumed level.
func _picked(cell: Vector2i) -> Vector3i:
	var tops: Dictionary[Vector2i, int] = _scene._tops
	return BoardSpace.of_cell(cell, tops.get(cell, BoardSpace.FLAT_TOP_ROW) - 1)


# --- Following the action ----------------------------------------------------------

func test_the_3d_camera_follows_the_ai_camera() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	# `playback_locked and not _board_locked_for_player()` is the pair that must never exist -- the poll
	# re-derives on CAMERA movement since #471, so a fixture holding it lets the hover snap drag the
	# 2D camera the mirror below is reading, and the two march the view to the pan limit.
	#
	# This comment used to say the pair was unreachable BECAUSE start_faction_turn writes AI_TURN and
	# the flag together. That was false: game_state is transient, and set_dev_mode rested it on
	# _base_state() mid-enemy-phase, which is #484. The predicate now READS playback_locked, so the line
	# below is what makes the pair impossible rather than a claim about who writes what.
	_game.game_state = _game.GameState.AI_TURN
	_cam().set_playback_locked(true)
	await _cam().pan_to(unit)   # headless: lands on the destination and hands to follow
	await _settle()
	# Where the 2D camera went, in the 3D metric. The 2D answers WHERE; the BOARD answers how high
	# (2026-08-23) — this used to read _rig.position.y, i.e. whatever the opening shot left there.
	var expected := _surface_aim(BoardSpace.of_pixels(_cam().global_position, 0.0))

	# Now prove the mirror DRIVES the rig rather than that it happened to be parked there.
	# The opening shot sits over the player's squad, i.e. over this very unit, so the rig
	# has to be shoved off first — to a corner of its own pan limit, which the clamp will
	# leave alone.
	_rig.hold_at(Vector3(_rig.pan_limit.position.x, _rig.position.y, _rig.pan_limit.position.y))
	assert_bool(_rig.position.distance_to(expected) > 1.0) \
		.override_failure_message("the rig was already there; the case proves nothing").is_true()
	await _settle()

	assert_that(_rig.position).override_failure_message(
			"the 3D camera never followed the AI's pan").is_equal(expected)
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE


func test_hovering_does_not_drag_the_3d_camera() -> void:
	# The naive-mirror hazard. Pointing snaps the hidden 2D camera every time (it is what
	# parks the hover card), so a mirror that ran outside an AI turn would jerk the whole
	# diorama on every mouse move.
	var unit := _player_unit()
	var before := _rig.position
	var cell: Vector2i = unit.movement.cell
	var motion := InputEventMouseMotion.new()
	var screen := _screen_of(cell)
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _settle()

	# The 2D camera DID move (non-vacuous: the snap is what the hover card rides on)...
	assert_that(_scene._pointer_cell).is_equal(_picked(cell))
	# ...and the 3D did not.
	assert_that(_rig.position).override_failure_message(
			"a hover dragged the 3D camera — the mirror is not gated on playback_locked").is_equal(before)


func test_opening_a_menu_does_not_yank_the_3d_camera() -> void:
	# The case that decides the gate. MissionSelectScreen opts OUT of the modal lock, so
	# _board_locked_for_player() is true here while the game runs on — mirroring on that
	# predicate would snap the rig to wherever the 2D camera happens to be parked.
	var before := _rig.position
	_game.game_state = _game.GameState.MENU
	assert_bool(_game._board_locked_for_player()).is_true()
	assert_bool(_cam().playback_locked).is_false()
	_cam().snap_to_position(Vector2(-4000.0, -4000.0))
	await _settle()

	assert_that(_rig.position).override_failure_message(
			"the menu yanked the rig — the mirror is gated on the wrong predicate").is_equal(before)


# #484, reported in play: the mouse became welded to the camera and ran the view to its limit in
# whatever direction it moved. Toggling dev mode mid-enemy-phase rested game_state on _base_state(),
# which unlocked the board while playback_locked stayed true -- opening _update_pointer's gate (it writes
# the hidden 2D camera) at the same time as _mirror_camera's (it reads it).
#
# Drives the REAL door: set_dev_mode, not a game_state poke. The rig assertion is the point -- the
# predicate going false is the rule, but the camera running away is what the dev saw, and a case
# that only read the predicate would pass against a mirror wired straight to game_state.
func test_toggling_dev_mode_during_an_ai_turn_leaves_the_board_locked() -> void:
	_game.game_state = _game.GameState.AI_TURN
	_cam().set_playback_locked(true)
	await _settle()
	var before := _rig.position

	_game.set_dev_mode(true)
	assert_int(_game.game_state).override_failure_message(
			"set_dev_mode no longer rests game_state -- this case is asserting nothing"
			).is_equal(_game.GameState.DEV_MODE)
	assert_bool(_game._board_locked_for_player()).override_failure_message(
			"dev mode unlocked the board mid-AI-turn: game_state moved and the lock followed it"
			).is_true()

	# The runaway itself. A hover would snap the 2D camera and the mirror would drag the rig after it.
	var unit := _player_unit()
	var screen := _screen_of(unit.movement.cell)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _settle()

	assert_that(_rig.position).override_failure_message(
			"the mouse dragged the 3D camera -- the pointer and the mirror both ran in one frame"
			).is_equal(before)
	_game.set_dev_mode(false)
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE


# The second door onto the same pair (#484): clear_board rests game_state through exit_current_mode,
# so a reload mid-enemy-phase reaches it too. Now that the lock READS playback_locked, an interrupted AI
# turn leaving the flag standing would lock the FRESH board for good -- so clear_board drops it,
# beside the ai_factions reset it already does for the same "a new board inherits nothing" reason.
func test_clearing_the_board_during_an_ai_turn_drops_the_ai_camera_lock() -> void:
	_cam().set_playback_locked(true)
	await _settle()

	_game.scenario_manager.clear_board()
	await _settle()

	assert_bool(_cam().playback_locked).override_failure_message(
			"a cleared board kept the last turn's camera lock -- the new board is locked for good"
			).is_false()
	assert_bool(_game._board_locked_for_player()).override_failure_message(
			"the fresh board came up locked").is_false()


func test_a_locked_board_refuses_the_players_camera_but_keeps_the_rig_running() -> void:
	_game.game_state = _game.GameState.AI_TURN
	await _settle()
	assert_bool(_rig.manual_input_enabled).is_false()
	assert_bool(_rig.is_processing()).override_failure_message(
			"the rig was frozen, not merely input-gated — the mirror could not drive it").is_true()

	_game.game_state = _game.GameState.IDLE
	await _settle()
	assert_bool(_rig.manual_input_enabled).is_true()


func test_a_menu_leaves_the_pointer_alone() -> void:
	_game.game_state = _game.GameState.MENU
	# The precondition, stated rather than inherited. It used to arrive for free — nothing picked a
	# cell until the mouse moved — but since #471 the poll re-derives on CAMERA movement too, and
	# framing the loaded mission is exactly that, so before_test now leaves a cell under the cursor.
	# The rule here is that a MENU does not UPDATE the pointer, which is unchanged either way.
	_scene._pointer_cell = BoardSpace.NO_CELL
	var unit := _player_unit()
	var screen := _screen_of(unit.movement.cell)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _settle()
	assert_that(_scene._pointer_cell).override_failure_message(
			"the bracket painted over a board the click handler would refuse").is_equal(BoardSpace.NO_CELL)


# --- Framing a real mission --------------------------------------------------------

func test_both_authored_missions_open_where_they_say() -> void:
	# REPLACES "opens with the whole board in frame" (dev feel-check 2026-08-14: fitting all
	# 64x40 of Prolog was too far out to play from). The board is now what the view is
	# BOUNDED by — see the case below, which keeps that half honest.
	#
	# TWO answers since #234, so this forks on the SEAM and never on which mission it is:
	# a board that authors a camera start opens THERE, one that authors none opens on its own
	# squad. Naming which is which would pin authored content — the dev captured a start on
	# Level_1 the day the feature landed, and *that is the feature working*. The derivation's
	# content-independent pin lives in test_camera_start.gd, so this case going all-authored
	# is correct rather than vacuous.
	for path in [PROLOG, LEVEL_1]:
		_scene.load_mission(path)
		await _settle()
		var start: CameraPose = _game.scenario_manager.current_camera_start
		if start != null:
			_assert_opens_at_the_authored_pose(path, start)
		else:
			_assert_opens_on_the_player_squad(path)


# The authored half. Compared against the pose CLAMPED into the rig's own limits, not against
# the raw authored numbers: #234's ruling is that a stale start is clamped silently with no
# validity predicate, so asserting the raw value would red on exactly the content the dev is
# allowed to edit — and would contradict the rule it is meant to be checking.
func _assert_opens_at_the_authored_pose(path: String, start: CameraPose) -> void:
	var limit: Rect2 = _rig.pan_limit
	assert_float(_rig.position.x).override_failure_message(
			"%s authors a camera start and did not open at its aim" % path
			).is_equal_approx(clampf(start.aim.x, limit.position.x, limit.end.x), 0.01)
	assert_float(_rig.position.z).override_failure_message(
			"%s authors a camera start and did not open at its aim" % path
			).is_equal_approx(clampf(start.aim.z, limit.position.y, limit.end.y), 0.01)
	# Yaw is the one axis nothing clamps, so it is the sharpest single check here.
	assert_float(_rig.rotation_degrees.y).override_failure_message(
			"%s authors a camera start and did not open at its angle" % path
			).is_equal_approx(start.yaw_degrees, 0.01)
	assert_float(_camera3d.position.z).override_failure_message(
			"%s authors a camera start and did not open at its zoom" % path
			).is_equal_approx(minf(start.distance, _rig.max_distance), 0.01)   # no zoom-in floor since 2026-08-23


# The derived half — unchanged, and still the reason the shot/bounds split exists.
func _assert_opens_on_the_player_squad(path: String) -> void:
	var seen := 0
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit == null or unit.get_faction() != Team.Faction.PLAYER:
			continue
		seen += 1
		lo = lo.min(Vector2(unit.movement.cell))
		hi = hi.max(Vector2(unit.movement.cell))
		var point := _stand(unit.movement.cell)
		assert_bool(_camera3d.is_position_in_frustum(point)).override_failure_message(
				"%s: player unit at %s is off-camera at load" % [path, unit.movement.cell]).is_true()
	assert_int(seen).override_failure_message(
			"%s spawns no player units; the case proves nothing" % path).is_greater(0)

	# The rig is AIMED at them, not merely wide enough to contain them. Measured: both
	# authored squads start near enough to the middle that the frustum loop above passes
	# against a window centred on the BOARD — so without this clause the "opens on your
	# squad" claim would be pinned by nothing.
	var board: AABB = _scene._board_volume()
	var focus := (lo + hi + Vector2.ONE) * 0.5
	assert_bool(focus.distance_to(Vector2(board.get_center().x, board.get_center().z)) > 1.0) \
		.override_failure_message(
			"%s starts its squad on the board's centre; aim cannot be told from framing here" % path
			).is_true()
	assert_float(_rig.position.x).override_failure_message(
			"%s: the rig is not aimed at the player squad" % path).is_equal_approx(focus.x, 0.01)
	assert_float(_rig.position.z).override_failure_message(
			"%s: the rig is not aimed at the player squad" % path).is_equal_approx(focus.y, 0.01)
	# Non-vacuous wherever it can be. A board narrower than the opening window legitimately
	# opens at the whole-board distance, so only assert "closer" where closer exists.
	if maxf(board.size.x, board.size.z) > _scene.opening_view_cells + 2.0:
		assert_float(_rig._target_distance).override_failure_message(
				"%s opened at the whole-board distance — the shot/bounds split did nothing" % path
				).is_less(_rig.max_distance)


func test_zooming_fully_out_still_shows_the_whole_board() -> void:
	# The other half, and what still pins the shipped bug: a board span in CELLS went to
	# set_zoom, which wants a camera DISTANCE, and the clamp ate it — Prolog needed ~82 and
	# got 24, so the far corners were unreachable at ANY zoom, not merely unframed at load.
	for path in [PROLOG, LEVEL_1]:
		_scene.load_mission(path)
		await _settle()
		var board: AABB = _scene._board_volume()
		var center := board.get_center()
		_rig.hold_at(Vector3(center.x, _rig.position.y, center.z))
		_rig.set_zoom(_rig.max_distance)
		_camera3d.position.z = _rig._target_distance   # settle the exponential lerp outright
		await _settle()

		var rect: Rect2i = _game.grid.get_used_rect()
		var corners: Array[Vector2i] = [
			rect.position,
			rect.position + Vector2i(rect.size.x - 1, 0),
			rect.position + Vector2i(0, rect.size.y - 1),
			rect.position + rect.size - Vector2i.ONE,
		]
		for corner in corners:
			# The corner's real surface, not an assumed floor — a corner standing on a terrace is
			# HIGHER, i.e. nearer the top of the frustum, which is exactly the case that would fail.
			var point := _stand(corner)
			assert_bool(_camera3d.is_position_in_frustum(point)).override_failure_message(
					"%s: board corner %s is off-camera even zoomed fully out" % [path, corner]).is_true()


func test_an_ai_turn_squares_the_camera_up() -> void:
	# Dev call 2026-08-14: whatever angle the player left the camera at, the enemy phase
	# plays out on an axis-aligned board.
	_rig._target_yaw_degrees = 37.0
	_cam().set_playback_locked(true)
	await _settle()
	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"the AI turn did not square the camera up").is_equal_approx(0.0, 0.001)

	# It is an EDGE, not a per-frame clamp — so a yaw driven mid-turn is left alone. That
	# matters the day free orbit is allowed under an AI turn: a per-frame snap would fight
	# the drag every frame instead of squaring up once.
	_rig._target_yaw_degrees = 200.0
	await _settle()
	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"the realign re-fires every frame, not on entry").is_equal_approx(200.0, 0.001)

	# And on the NEXT turn it takes the nearest detent, not zero. The yaw is re-driven AFTER the
	# release, deliberately: since the view return landed (#534) a release puts back whatever the
	# player was looking at before playback borrowed the camera, so a yaw poked in mid-turn does not
	# survive it. Between turns the player really does own the orbit, so this is the honest setup.
	_cam().set_playback_locked(false)
	await _settle()
	_rig._target_yaw_degrees = 200.0
	await _settle()
	_cam().set_playback_locked(true)
	await _settle()
	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"it squared up to zero rather than to the nearest detent").is_equal_approx(180.0, 0.001)
	_cam().set_playback_locked(false)


func test_space_recentres_the_diorama_on_the_pointer() -> void:
	var unit := _player_unit()
	var cell: Vector2i = unit.movement.cell
	_scene._update_pointer(_screen_of(cell))
	_rig.hold_at(Vector3(_rig.position.x + 12.0, _rig.position.y, _rig.position.z + 12.0))
	var before := _rig.position

	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	# The WHOLE point, height included (2026-08-23). It used to keep `before.y` — which is how the
	# rig came to sit at the board's ceiling for ever on any board with elevation.
	#
	# Read BEFORE the key, not after the flight: SPACE is a PAN since #520, and the pointer poll
	# re-picks on CAMERA movement (#471), so the cell under a motionless cursor legitimately changes
	# while the rig is in the air. What SPACE acted on is the cell it was over when the key arrived.
	var point := BoardSpace.surface_point(BoardSpace.flat(_scene._pointer_cell), _game.board_heights)
	_scene._unhandled_input(space)
	await _settle()   # headless the glide lands on the next frame

	assert_that(_rig.position).is_equal(point)
	assert_bool(_rig.position.distance_to(before) > 1.0).is_true()


# --- Coming back to the acting unit (#471) ------------------------------------------

# The ring does NOT lock the board, so the player can pan the diorama anywhere while choosing --
# and then commit an order that plays out around a unit no longer on screen. Driven at
# game.focus_view_on rather than through a menu pick: the RING's half of this wire is pinned in
# tests/ui/test_radial_menu.gd, and this is the half only the 3D host can see. Kill battle3d's
# connect and this is what reds.
func test_a_committed_order_brings_the_rig_back_to_the_acting_unit() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	# The opening shot sits over the player's squad, i.e. over this very unit, so the rig has to be
	# shoved off first -- to a corner of its own pan limit, which the clamp will leave alone.
	_rig.hold_at(Vector3(_rig.pan_limit.position.x, _rig.position.y, _rig.pan_limit.position.y))
	var before := _rig.position
	# The unit's PROJECTED cell, which is what focus_view_on means by "where this unit is acting
	# from" -- read through the same expression rather than assumed to be movement.cell.
	var target := BoardSpace.standing_point(BoardSpace.of_cell(unit.get_projected_destination(), 0))
	assert_bool(Vector2(before.x, before.z).distance_to(Vector2(target.x, target.z)) > 1.0) \
		.override_failure_message("the rig was already over the unit; the case proves nothing").is_true()

	_game.focus_view_on(unit)
	await _settle()

	assert_float(_rig.position.x).override_failure_message(
			"a committed order did not bring the rig back to the acting unit").is_equal_approx(target.x, 0.01)
	assert_float(_rig.position.z).override_failure_message(
			"a committed order did not bring the rig back to the acting unit").is_equal_approx(target.z, 0.01)


# The pointer poll re-derives on CAMERA movement, not only on mouse movement (#471). Without it the
# hover bracket sits on the cell the pointer LEFT until the mouse moves -- true of WASD and of SPACE
# long before this ticket, and this is what makes it frequent enough to notice.
func test_moving_the_camera_re_picks_the_cell_under_a_still_pointer() -> void:
	_game.game_state = _game.GameState.IDLE
	var unit := _player_unit()
	var cell: Vector2i = unit.movement.cell
	_scene._update_pointer(_screen_of(cell))
	await _settle()
	assert_that(_scene._pointer_cell).override_failure_message(
			"the fixture never got the pointer onto the unit's cell").is_equal(_picked(cell))

	# The mouse does not move; the world does.
	_rig.hold_at(Vector3(_rig.position.x + 6.0, _rig.position.y, _rig.position.z + 6.0))
	await _settle()

	assert_that(_scene._pointer_cell).override_failure_message(
			"panning under a still cursor left the pointer on the cell it had left") \
		.is_not_equal(_picked(cell))


# --- The aim HEIGHT (dev report, 2026-08-23) ----------------------------------------

# THE rule: the rig aims ON the surface it is looking at, never at the board's CEILING.
# CameraRig3D._aim_at lifts the OPENING shot to the top of the whole board volume — right for
# framing a board, wrong for looking at something standing on one — and nothing ever re-derived it,
# because every recentre kept _rig.position.y. On Level_1 (columns to level 4, plus an authored
# start that froze aim.y = 5) that put the look-at point four cells in the air, so the unit rode
# off the top of the frame at close zoom. Prolog is flat, which is why it never showed there.
#
# The absurd height is SET here rather than inherited from a mission, so this is a claim about the
# RULE and not about what any board happens to be painted to (the content razor).
func test_the_return_aims_at_the_surface_not_at_the_board_ceiling() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	_rig.hold_at(Vector3(_rig.position.x, 12.0, _rig.position.z))

	_game.focus_view_on(unit)
	await _settle()

	var wanted := BoardSpace.surface_point(unit.get_projected_destination(), _game.board_heights)
	assert_bool(absf(12.0 - wanted.y) > 1.0).override_failure_message(
			"the parked height IS the surface here; the case proves nothing").is_true()
	assert_float(_rig.position.y).override_failure_message(
			"the rig kept its inherited aim height, so it looks at a point in the air above the unit"
			).is_equal_approx(wanted.y, 0.01)


# The same rule at the OTHER surface that reads it, and the one the dev actually saw it on: an AI
# turn on Level_1. Pre-existing since 4d — the mirror kept _rig.position.y as deliberately as the
# recentre did, so fixing one without the other would have left the enemy phase aiming at the sky.
func test_the_ai_pan_aims_at_the_surface_too() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	_game.game_state = _game.GameState.AI_TURN
	_cam().set_playback_locked(true)
	await _cam().pan_to(unit)
	_rig.hold_at(Vector3(_rig.position.x, 12.0, _rig.position.z))
	await _settle()

	var wanted := _surface_aim(BoardSpace.of_pixels(_cam().global_position, 0.0))
	assert_bool(absf(12.0 - wanted.y) > 1.0).override_failure_message(
			"the parked height IS the surface here; the case proves nothing").is_true()
	assert_float(_rig.position.y).override_failure_message(
			"the AI pan kept the rig's inherited aim height").is_equal_approx(wanted.y, 0.01)
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE


# --- the knockback follow (#520 diff 2b) --------------------------------------------------------
#
# THIS BEHAVIOUR WAS ALREADY BUILT and the ticket lists it as work: pan_to closes with follow(unit),
# _process re-reads follow_unit.global_position every frame, and a shove slides that very position --
# so the camera has ridden launched bodies since #118 without anyone claiming it. What was missing is
# a LAW, and that absence is the same one #103 cost thirteen months: three correct pieces, no case
# over the join, so any of them could be rewritten in good faith and nothing would go red.
#
# It is pinned at the DECISION -- who the camera is following when the pan lands -- rather than by
# watching a body fly, because the slide's own animation is headless-escaped like everything else in
# this file's neighbourhood, so a mid-flight sample reads frame timing rather than the wire.
func test_the_camera_rides_the_body_a_blow_sends_flying() -> void:
	var attacker := _player_unit()
	assert_object(attacker).is_not_null()
	var victim: Unit = null
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit != null and unit.get_faction() == Team.Faction.ENEMY:
			victim = unit
			break
	assert_object(victim).is_not_null()

	_cam().set_playback_locked(true)
	_cam().follow_unit = attacker            # somebody ELSE, so "it ended up there" cannot pass by
	await _cam().pan_to(victim)              # ...the camera never having changed who it watches
	await _settle()

	assert_object(_cam().follow_unit).override_failure_message(
			"the camera stopped following at the pan's end, so a shove would leave the body behind"
	).is_same(victim)

	# ...and the follow is LIVE, not a latched position: move the body and the camera's target must
	# come with it. That is the whole of the knockback follow, since a shove is exactly this write.
	var flew_to := victim.global_position + Vector2(64.0, 0.0)
	victim.global_position = flew_to
	await _settle()
	assert_vector(_cam().target_position).override_failure_message(
			"the camera held its old target while the body moved -- the follow is latched, not tracking"
	).is_equal_approx(flew_to, Vector2(0.01, 0.01))
	_cam().set_playback_locked(false)


# --- the cliff follow (#602) --------------------------------------------------------------------
#
# The knockback follow above is FREE because a shove writes the unit's own position. A FALL does
# not: both fall animations are mirror-side Y offsets, so the board thinks the body has already
# arrived and follow_unit tracks it to the lip and then holds level while the sprite drops out of
# the frame. What is pinned here is the DECISION -- where the rig sits given a published depth --
# never the descent, which is headless-escaped like everything else in this neighbourhood.
#
# The fall itself is set DIRECTLY, and that is forced: plummet() returns before raising its flag
# when DisplayServer is headless, so the real path cannot reach this state in a suite. The depth
# ARITHMETIC has its own cases in tests/presentation/test_shove_fall.gd; these are about the wire.

# Put a body `cells` down a hole, the way the mirror-side animation would.
func _hanging(unit: Unit, cells: float) -> void:
	unit.movement.plummeting = true
	unit.movement.plummet_depth = cells


func test_the_camera_rides_a_body_that_falls_off_the_board() -> void:
	var victim := _player_unit()
	assert_object(victim).is_not_null()
	_cam().set_playback_locked(true)
	await _cam().pan_to(victim)
	await _settle()
	var on_the_lip: Vector3 = _rig.position

	_hanging(victim, 2.0)
	await _settle()

	assert_float(_rig.position.y).override_failure_message(
			"the body fell two cells and the camera stayed up on the lip watching an empty hole"
	).is_equal_approx(on_the_lip.y - 2.0 * BoardSpace.CELL_SIZE, 0.001)
	# ...and it is a VERTICAL channel alone. A fall has one axis, and a drop that also slid the shot
	# sideways would be reading the depth through something that carries a direction.
	assert_float(_rig.position.x).is_equal_approx(on_the_lip.x, 0.001)
	assert_float(_rig.position.z).is_equal_approx(on_the_lip.z, 0.001)
	_cam().set_playback_locked(false)


func test_the_follow_stops_short_rather_than_taking_the_camera_under_the_world() -> void:
	var victim := _player_unit()
	assert_object(victim).is_not_null()
	Pacing.CLIFF_FOLLOW_MAX = 2.0
	_cam().set_playback_locked(true)
	await _cam().pan_to(victim)
	await _settle()
	var on_the_lip: Vector3 = _rig.position

	_hanging(victim, 20.0)   # deeper than any authored plummet, and far past the ceiling
	await _settle()

	assert_float(on_the_lip.y - _rig.position.y).override_failure_message(
			"the camera followed a twenty-cell drop all the way down, ceiling or no ceiling"
	).is_equal_approx(2.0 * BoardSpace.CELL_SIZE, 0.001)
	_cam().set_playback_locked(false)


func test_dialling_the_follow_out_leaves_the_shot_exactly_where_it_was() -> void:
	var victim := _player_unit()
	assert_object(victim).is_not_null()
	Pacing.CLIFF_FOLLOW = 0.0
	_cam().set_playback_locked(true)
	await _cam().pan_to(victim)
	await _settle()
	var on_the_lip: Vector3 = _rig.position

	_hanging(victim, 5.0)
	await _settle()

	assert_that(_rig.position).override_failure_message(
			"the strength is the off switch and it did not switch anything off") \
		.is_equal(on_the_lip)
	_cam().set_playback_locked(false)


func test_a_body_nobody_is_watching_falls_without_moving_the_camera() -> void:
	var watched := _player_unit()
	assert_object(watched).is_not_null()
	var faller := _any_unit_besides(watched)
	assert_object(faller).is_not_null()
	_cam().set_playback_locked(true)
	await _cam().pan_to(watched)
	await _settle()
	var framed: Vector3 = _rig.position

	_hanging(faller, 4.0)
	await _settle()

	assert_that(_rig.position).override_failure_message(
			"a fall somewhere else on the board dragged the shot down -- the channel is reading the "
			+ "wrong unit, or every unit") \
		.is_equal(framed)
	_cam().set_playback_locked(false)


func test_the_camera_comes_back_up_when_the_fall_ends() -> void:
	var victim := _player_unit()
	assert_object(victim).is_not_null()
	_cam().set_playback_locked(true)
	await _cam().pan_to(victim)
	await _settle()
	var on_the_lip: Vector3 = _rig.position

	_hanging(victim, 2.0)
	await _settle()
	assert_bool(_rig.position.y < on_the_lip.y - 0.5).override_failure_message(
			"the camera never went down; the case cannot say anything about coming back").is_true()

	# POLLED, never latched: the fall simply stops publishing a depth, and there is nothing for a
	# caller to remember to undo -- which matters because a void fall ends in die(), so the unit that
	# was publishing it is gone by the time anyone could.
	victim.movement.plummeting = false
	victim.movement.plummet_depth = 0.0
	await _settle()
	assert_float(_rig.position.y).override_failure_message(
			"the camera stayed in the pit after the fall ended -- the drop is latched") \
		.is_equal_approx(on_the_lip.y, 0.001)
	_cam().set_playback_locked(false)


func test_giving_the_camera_back_climbs_it_out_of_whatever_pit_the_pass_left_it_in() -> void:
	# The drop is polled BELOW the playback gate -- unlike the tear-out's lift, which is a fact about
	# the board rather than about a unit. So the release edge has to be the door that ends it, or a
	# pass that finished mid-fall hands the player a rig hanging under the board for ever.
	var victim := _player_unit()
	assert_object(victim).is_not_null()
	_cam().set_playback_locked(true)
	await _cam().pan_to(victim)
	await _settle()
	_hanging(victim, 2.0)
	await _settle()

	_cam().set_playback_locked(false)
	await _settle()

	assert_float(_rig.position.y - _rig._target_aim.y).override_failure_message(
			"playback let go and the camera stayed below the board -- nothing closes the drop") \
		.is_equal_approx(0.0, 0.001)


func test_a_board_swap_mid_fall_puts_the_camera_back_on_the_new_board() -> void:
	# The release edge above is the ORDINARY end of a fall; this is the one that skips it. A swap
	# releases the playback lock and re-frames, and frame() drops the stashed view -- so restore_view
	# early-returns and never runs. With the drop polled below the playback gate, that left nobody at
	# all to close it and the rig sat under the new board for ever.
	#
	# Found by the shared-board fixture rather than by writing this case: EVERY fall case above
	# leaked the same three cells into the next one, which is the fingerprint saying the reset door
	# cannot reach something. It is named here so a future refactor reds on the rule and not on a
	# leak report three cases away.
	var victim := _player_unit()
	assert_object(victim).is_not_null()
	_cam().set_playback_locked(true)
	await _cam().pan_to(victim)
	await _settle()
	_hanging(victim, 2.0)
	await _settle()
	assert_bool(_rig._drop > 0.5).override_failure_message(
			"the camera never went down; the case cannot say anything about the swap").is_true()

	_rig.drop_stashed_view()

	assert_float(_rig._drop).override_failure_message(
			"a board swap left the camera in a pit on a board that no longer exists") \
		.is_equal(0.0)
	assert_float(_rig._target_drop).override_failure_message(
			"the live drop was cut but its target still points into the old board's hole") \
		.is_equal(0.0)
	_cam().set_playback_locked(false)


# --- the tear-out's own height (2026-08-29, found in play) --------------------------------------

# WHILE A FIGHT IS ON STAGE THE CAMERA'S HEIGHT IS THE STAGE'S, not the ground under the camera.
#
# The lift channel has always said this in its own comment; the AIM never applied it. On flat ground
# the two agree by accident, which is why it shipped -- on a fight at the top of a tall column the
# diorama sits at the column's surface plus the lift while the camera sat at the PLAIN's surface plus
# the lift, and the frame was empty. It is also a jerk: a pan crossing the column's edge stepped the
# camera by the column's whole height, mid-transition.
#
# The board is RAISED here rather than found that way -- authored content may not be asserted on, and
# a flat fixture cannot tell the two answers apart. The fixture's reset restores it.
func test_the_camera_takes_the_STAGE_s_height_and_not_the_ground_under_itself() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	var stage_cell: Vector2i = unit.movement.cell
	var heights: BoardHeights = _game.board_heights
	heights.set_cell(stage_cell, 8)
	var raised := BoardSpace.surface_point(stage_cell, heights).y
	# ...and a LOW cell on stage beside it, which is the shape a KNOCKBACK PATH makes: every cell a
	# shoved body crosses is torn out too, and averaging that ground is what dragged the shot down
	# into the pillar's wall with the fight above the frame (dev, 2026-08-29). Nobody stands on it,
	# so it must contribute nothing.
	var low_cell := stage_cell + Vector2i(3, 0)
	heights.set_cell(low_cell, 0)
	var low := BoardSpace.surface_point(low_cell, heights).y
	assert_bool(raised - low > 1.0).override_failure_message(
			"the two staged cells are level; the case cannot tell the answers apart").is_true()
	for child in _game.units_root.get_children():
		var other := child as Unit
		assert_bool(other != null and UnitMirror.cell_under(other) == low_cell) \
			.override_failure_message("fixture: somebody is standing on the low cell").is_false()

	_cam().set_playback_locked(true)
	await _cam().pan_to(unit)
	# ...and then OFF it, which is what any pan across the board does anyway. The follow has to be
	# dropped first or _process hauls the camera straight back onto the unit -- headless it lands
	# exactly, so the park would be undone within the frame.
	_cam().follow_unit = null
	var away: Vector2 = _cam().global_position + Vector2(GridUtils.TILE_SIZE * 5.0, 0.0)
	_cam().global_position = away
	_cam().target_position = away
	await _settle()
	var over_the_plain: float = _rig.position.y
	assert_bool(absf(raised - over_the_plain) > 1.0).override_failure_message(
			"the raised cell is level with the ground under the camera; the case proves nothing"
	).is_true()

	BoardSpace.stage([stage_cell, low_cell], BoardSpace.lift_offset())
	await _settle()

	var wanted := raised + Pacing.STAGE_AIM_LIFT * BoardSpace.CELL_SIZE + BoardSpace.lift_offset().y
	assert_bool(absf(wanted - ((raised + low) * 0.5 + BoardSpace.lift_offset().y)) > 0.5) \
		.override_failure_message(
			"the mean of the staged ground is the same answer here; the case proves nothing").is_true()
	assert_float(_rig.position.y).override_failure_message(
			"the camera did not frame the ground the UNITS are standing on -- it took the plain's "
			+ "surface, or the average of every cell the fight touches") \
		.is_equal_approx(wanted, 0.01)
	BoardSpace.clear_staging()
	_cam().set_playback_locked(false)


# ...and a fall lowers the shot by the FOLLOW and nothing more.
#
# A COMPOSITION check rather than a check on either half: the stage height and the cliff follow both
# move this camera vertically, and what could go wrong is them both answering for the same fall. It
# holds because the height is latched before anyone falls (see the case below, which is what pins
# the latch) -- so read this as "the two channels do not add up wrong", not as evidence for either.
#
# Stated because two mutants had to be run to find it out: swapping the stage height's ground read
# for a stand-height read leaves this GREEN, since at latch time the two agree exactly.
func test_a_fall_lowers_the_shot_by_the_follow_and_nothing_more() -> void:
	var victim := _player_unit()
	assert_object(victim).is_not_null()
	_cam().set_playback_locked(true)
	await _cam().pan_to(victim)
	BoardSpace.stage([victim.movement.cell], BoardSpace.lift_offset())
	await _settle()
	var on_stage: float = _rig.position.y

	_hanging(victim, 2.0)
	await _settle()

	assert_float(on_stage - _rig.position.y).override_failure_message(
			"the fall moved the shot further than the follow itself -- the diorama's height is "
			+ "tracking the faller too, so the dip is counted twice") \
		.is_equal_approx(Pacing.followed_fall(2.0), 0.01)
	BoardSpace.clear_staging()
	_cam().set_playback_locked(false)


# ...and the LATCH is what stops a body being THROWN from walking the whole shot down after it.
#
# This is the case the first draft did not have. Its absence let a mutant that deleted the latch pass
# every case in this file: the fall case above cannot see it, because a falling body's GROUND does
# not move and the height is read off the ground. What does move is a body that lands somewhere
# else -- which is a shove, i.e. the ordinary case, and mid-pass it would drag the diorama's shot
# down to wherever the last person was thrown.
func test_a_body_thrown_onto_lower_ground_does_not_walk_the_shot_down_after_it() -> void:
	var victim := _player_unit()
	assert_object(victim).is_not_null()
	var high_cell: Vector2i = victim.movement.cell
	var heights: BoardHeights = _game.board_heights
	heights.set_cell(high_cell, 8)
	var low_cell := high_cell + Vector2i(3, 0)
	heights.set_cell(low_cell, 0)
	assert_bool(BoardSpace.surface_point(high_cell, heights).y
			- BoardSpace.surface_point(low_cell, heights).y > 1.0).override_failure_message(
			"the two cells are level; the case cannot tell a moved shot from a held one").is_true()

	_cam().set_playback_locked(true)
	await _cam().pan_to(victim)
	BoardSpace.stage([high_cell, low_cell], BoardSpace.lift_offset())
	await _settle()
	var framed: float = _rig.position.y

	# The end state of a shove: the body is standing on the low cell now.
	victim.movement.set_cell(low_cell)
	await _settle()

	assert_float(_rig.position.y).override_failure_message(
			"the diorama's shot followed the thrown body down -- the stage height is being re-solved "
			+ "mid-pass instead of decided when the ground left the board") \
		.is_equal_approx(framed, 0.01)
	BoardSpace.clear_staging()
	_cam().set_playback_locked(false)


# --- the camera comes home BEFORE the tiles do (dev, 2026-08-29) --------------------------------

# A pass whose last blow knocked somebody into a pit ends with the shot still deep below the board,
# and the climb back is EASED -- longer than the aftermath hold -- so the tiles used to start
# dropping while the camera was still on its way up.
#
# The wait reads the fact the RIG publishes rather than a beat of its own, which is what this pins:
# it must still be waiting while the rig is down, and must resume once the rig is back.
#
# The RIG is driven, never the published field -- the mirror rewrites that every frame, so a case
# that poked it would be asserting against its own write and would pass with the publish deleted.
# The whole chain is under test: drop -> mirror -> CameraController.fall_depth -> the wait.
func test_the_tiles_wait_for_the_camera_to_climb_out_before_they_go_home() -> void:
	_rig.drop_to(2.0)
	await _settle()
	assert_float(_cam().fall_depth).override_failure_message(
			"the rig is two cells under the board and playback was never told").is_greater(1.0)

	# The real exit, not the helper: what is at risk is the WIRE, and a case calling the wait
	# directly would pass with its one call site deleted (#103's shape).
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	BoardSpace.stage([unit.movement.cell], BoardSpace.lift_offset())
	var done := [false]
	var exit := func() -> void:
		await _game.order_executor._bring_the_board_home()
		done[0] = true
	exit.call()
	await _settle()
	assert_bool(done[0]).override_failure_message(
			"the tiles went home with the camera still two cells under the board").is_false()
	assert_bool(BoardSpace.staging_active()).override_failure_message(
			"the staging was already dropped while the camera was still climbing").is_true()

	_rig.drop_to(0.0)
	await _settle()
	assert_bool(done[0]).override_failure_message(
			"the camera came home and the exit never resumed -- the wait does not read the rig"
	).is_true()
	assert_bool(BoardSpace.staging_active()).override_failure_message(
			"the exit finished without putting the board back").is_false()
