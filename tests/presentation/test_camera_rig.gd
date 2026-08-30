# The diorama camera rig (#176 stage 4d): framing, orbit, detents, bounds and the
# manual-input gate, pinned in the look-dev scene the rig calls home.
#
# Framing is asserted as a PROPERTY — every corner lands inside the frustum — never as
# a distance number, so fov/pitch/margin stay the dev's knobs (the doctrine
# test_look_dev.gd and test_board_picker.gd already set). What IS pinned numerically is
# arithmetic with one right answer: which detent Q lands on, and where a clamp bites.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/LookDev/LookDev.tscn")

var _scene: Node3D


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)   # a real projection; headless defaults can be tiny
	_scene = SCENE.instantiate() as Node3D
	get_tree().root.add_child(_scene)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func _rig() -> CameraRig3D:
	return _scene.get_node("CameraRig") as CameraRig3D


func _camera() -> Camera3D:
	return _scene.get_node("CameraRig/Pitch/Camera") as Camera3D


# Drive the rig's own handler: the look-dev scene layers a full-rect vignette over the
# viewport, so a parsed event is not guaranteed to reach it.
func _key(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = keycode
	press.pressed = true
	_rig()._unhandled_input(press)


func _drag(button: MouseButton, pixels: Vector2) -> void:
	_press(button)
	_move(pixels)
	_release(button)


# The halves, split out because the strand cases (#231) need a gesture left LIVE — a drag
# whose release never arrives is the whole failure they pin.
func _press(button: MouseButton) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	_rig()._unhandled_input(down)


func _move(pixels: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = pixels
	_rig()._unhandled_input(motion)


func _release(button: MouseButton) -> void:
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	_rig()._unhandled_input(up)


# --- Framing -----------------------------------------------------------------------

func test_frame_pulls_back_until_the_whole_volume_is_visible() -> void:
	var rig := _rig()
	var camera := _camera()
	var volume := AABB(Vector3(0, 0, 0), Vector3(40, 1, 26))
	rig.frame(volume)
	await await_idle_frame()

	for i in 8:
		assert_bool(camera.is_position_in_frustum(volume.get_endpoint(i))) \
			.override_failure_message("corner %d of the framed volume is off-camera" % i).is_true()


func test_frame_raises_the_zoom_ceiling_so_the_fit_survives_its_own_clamp() -> void:
	# THE shipped bug: a board span was handed to set_zoom and silently clamped to 24,
	# so both authored missions opened showing a fraction of the board.
	var rig := _rig()
	rig.max_distance = 24.0
	rig.frame(AABB(Vector3.ZERO, Vector3(64, 1, 40)))
	assert_float(rig.max_distance).override_failure_message(
			"the ceiling still eats the fit").is_greater(24.0)
	assert_float(_camera().position.z).is_equal_approx(rig._target_distance, 0.001)

# THERE IS NO ZOOM-IN FLOOR (dev, 2026-08-23, asked twice: "please remove it entirely"). It was
# min_distance = 6.0 and it is what "I can't zoom in far enough to see what I'm brushing" meant;
# lowering it to 1.0 first was not what he asked for and did not satisfy him either.
#
# The ceiling is the only bound left, so this is the pair: a tiny distance survives untouched, and
# one past the ceiling is still pulled back. A floor re-added at ANY value reds the first half.
func test_zooming_in_has_no_floor_while_the_ceiling_still_holds() -> void:
	var rig := _rig()
	rig.max_distance = 24.0

	rig.set_zoom(0.05)
	assert_float(rig._target_distance).override_failure_message(
			"a zoom-in floor is back: 0.05 came out as %s" % rig._target_distance) \
		.is_equal_approx(0.05, 0.0001)

	rig.set_zoom(1000.0)
	assert_float(rig._target_distance).override_failure_message(
			"the ceiling stopped holding when the floor went").is_equal_approx(24.0, 0.0001)



func test_framing_a_shot_inside_bounds_leaves_the_ceiling_and_pan_on_the_bounds() -> void:
	# The shot/bounds split (dev feel-check 2026-08-14). Asserted by EQUIVALENCE rather than
	# by numbers: whatever framing the whole board alone would yield for the ceiling and the
	# pan limit, framing a close shot *within* that board must yield identically.
	var rig := _rig()
	var camera := _camera()
	var board := AABB(Vector3.ZERO, Vector3(64, 1, 40))
	var shot := AABB(Vector3(20, 0, 12), Vector3(18, 1, 18))

	rig.frame(shot, board)
	await await_idle_frame()
	for i in 8:
		assert_bool(camera.is_position_in_frustum(shot.get_endpoint(i))) \
			.override_failure_message("corner %d of the shot is off-camera" % i).is_true()
	# Non-vacuous: the shot really is closer than fitting everything.
	assert_float(rig._target_distance).override_failure_message(
			"the shot opened at the whole-board distance — the split did nothing").is_less(rig.max_distance)

	var split_ceiling: float = rig.max_distance
	var split_pan: Rect2 = rig.pan_limit
	rig.frame(board)
	assert_float(split_ceiling).override_failure_message(
			"the ceiling was solved off the shot, not the bounds — the rest of the board is unreachable" \
			).is_equal_approx(rig.max_distance, 0.001)
	assert_that(split_pan).override_failure_message(
			"panning was bounded to the shot, not the board").is_equal(rig.pan_limit)


func test_align_to_detent_snaps_to_the_nearest_one() -> void:
	# What an AI turn calls. Distinct from Q/E, which always travel a whole step.
	var rig := _rig()
	rig._target_yaw_degrees = 37.0
	rig.align_to_detent()
	assert_float(rig._target_yaw_degrees).is_equal_approx(0.0, 0.001)
	rig._target_yaw_degrees = 200.0
	rig.align_to_detent()
	assert_float(rig._target_yaw_degrees).override_failure_message(
			"it snapped to zero rather than to the NEAREST detent").is_equal_approx(180.0, 0.001)
	rig._target_yaw_degrees = 90.0
	rig.align_to_detent()
	assert_float(rig._target_yaw_degrees).override_failure_message(
			"already square, and it moved anyway").is_equal_approx(90.0, 0.001)


func test_frame_snaps_the_camera_rather_than_easing_to_it() -> void:
	# Load-bearing for every screen-space read: a camera still lerping toward the fit
	# unprojects at one distance and picks at another.
	var rig := _rig()
	rig.frame(AABB(Vector3.ZERO, Vector3(50, 1, 50)))
	assert_float(_camera().position.z).is_equal_approx(rig._target_distance, 0.001)
	# ...and the AIM, which is the half this case stopped covering the moment #520 made position an
	# eased channel: the NAME claimed all three axes while the body asserted one, so a frame()
	# routed through glide_to passed the whole suite. FOUND BY MUTATION, not by reasoning.
	# Asserted as "nothing is left to ease" rather than as a coordinate, so the fit stays derived.
	assert_that(rig._aim).override_failure_message(
			"frame() eased toward the fit instead of landing on it -- every screen-space read taken " \
			+ "on the way in unprojects at one place and picks at another") \
		.is_equal(rig._target_aim)


func test_frame_adopts_the_fit_as_home_so_reset_returns_to_it() -> void:
	var rig := _rig()
	rig.frame(AABB(Vector3(10, 0, 10), Vector3(20, 1, 20)))
	var framed_position: Vector3 = rig.position
	var framed_distance: float = rig._target_distance
	# Non-vacuous: the fit must differ from the scene's authored home, or R proves nothing.
	assert_bool(framed_position.distance_to(Vector3(0, 1, 0)) > 1.0).is_true()

	# hold_at, not a raw write: `position` is DERIVED from the rig's two channels since #520, so an
	# assignment to it is overwritten on the next frame and this fixture would shove nothing.
	rig.hold_at(Vector3(999, 1, 999))
	rig.set_zoom(1.0)   # any distance other than the one R must restore
	_key(KEY_R)
	# R is a PAN now, so the aim lands on the next frame rather than inside the keypress. Headless
	# the glide closes in one (CameraRig3D._process's escape), which is what keeps this a decision
	# rather than a reading of frame timing.
	await await_idle_frame()
	assert_that(rig.position).is_equal(framed_position)
	assert_float(rig._target_distance).is_equal_approx(framed_distance, 0.001)


# --- The authored pose (#234) ------------------------------------------------------

const BOARD := AABB(Vector3.ZERO, Vector3(64, 1, 40))


func test_pose_lands_the_camera_exactly_where_it_was_authored() -> void:
	# An authored start is not solved from anything — it is the three numbers you flew to.
	var rig := _rig()
	rig.pose(Vector3(20, 1, 14), 37.0, 16.0, BOARD)
	await await_idle_frame()

	assert_that(rig.position).is_equal(Vector3(20, 1, 14))
	# 37 degrees on purpose: free orbit is the contract (#176 stage 4d), so an off-detent
	# authored yaw must survive rather than being tidied to 0.
	assert_float(rig.rotation_degrees.y).is_equal_approx(37.0, 0.001)
	assert_float(_camera().position.z).is_equal_approx(16.0, 0.001)


# RENAMED for #520 diff 2b: it was "..._both_smoothed_axes_...", and position became a third one.
# A name that undercounts what it covers is the same blind spot the frame() case above had.
func test_pose_snaps_every_smoothed_axis_rather_than_easing_to_them() -> void:
	# frame()'s reason, applied to yaw as well: a rig still lerping unprojects at one basis
	# and picks at another. Deliberately NOT awaiting a frame — the smoothing would hide it.
	var rig := _rig()
	rig.rotation_degrees.y = 0.0
	rig.pose(Vector3(20, 1, 14), 130.0, 16.0, BOARD)

	assert_float(rig.rotation_degrees.y).override_failure_message(
			"yaw is still easing toward the authored pose — screen-space reads desync on the way" \
			).is_equal_approx(130.0, 0.001)
	assert_float(_camera().position.z).is_equal_approx(rig._target_distance, 0.001)
	assert_that(rig._aim).override_failure_message(
			"the aim is still easing toward the authored pose, for the same reason") \
		.is_equal(rig._target_aim)


func test_pose_leaves_the_ceiling_and_pan_on_the_board_exactly_as_framing_does() -> void:
	# "An authored start replaces the SHOT and nothing else moves." Asserted by equivalence
	# against frame(), not by numbers, so the rig's knobs stay the dev's.
	var rig := _rig()
	rig.pose(Vector3(20, 1, 14), 45.0, 16.0, BOARD)
	var posed_ceiling: float = rig.max_distance
	var posed_pan: Rect2 = rig.pan_limit
	# Non-vacuous: the authored shot really is closer than fitting the whole board.
	assert_float(rig._target_distance).is_less(posed_ceiling)

	rig.frame(BOARD)
	assert_float(posed_ceiling).override_failure_message(
			"the ceiling was solved off the authored shot — the rest of the board is unreachable" \
			).is_equal_approx(rig.max_distance, 0.001)
	assert_that(posed_pan).override_failure_message(
			"panning was bounded to the authored shot, not the board").is_equal(rig.pan_limit)


func test_pose_adopts_the_authored_yaw_as_home_unlike_framing() -> void:
	# R means "back to the opening shot", and an authored opening shot INCLUDES its yaw —
	# the one place pose() and frame() deliberately differ.
	var rig := _rig()
	rig.pose(Vector3(20, 1, 14), 135.0, 16.0, BOARD)

	rig.hold_at(Vector3(5, 1, 5))
	rig._target_yaw_degrees = 0.0
	rig.set_zoom(1.0)   # any distance other than the one R must restore
	_key(KEY_R)
	await await_idle_frame()   # R is a pan since #520; headless the glide lands in one frame

	assert_that(rig.position).is_equal(Vector3(20, 1, 14))
	assert_float(rig._target_yaw_degrees).override_failure_message(
			"R dropped the authored yaw and returned to the scene's" \
			).is_equal_approx(135.0, 0.001)
	assert_float(rig._target_distance).is_equal_approx(16.0, 0.001)


func test_an_authored_aim_off_the_board_is_clamped_back_onto_it() -> void:
	# The dev's ruling (2026-08-15): a stale authored start is CLAMPED, silently, and there is
	# deliberately no validity predicate — it rides the pan_limit clamp _process already runs.
	# Asserted as the property (inside the limit), never as the clamped coordinate.
	var rig := _rig()
	rig.pose(Vector3(500, 1, -400), 0.0, 16.0, BOARD)
	# Non-vacuous: the aim really is outside, so a no-op clamp cannot pass this.
	assert_bool(rig.position.x > rig.pan_limit.end.x).is_true()
	await await_idle_frame()

	# Inclusive bounds, not Rect2.has_point — the clamp lands the far axis exactly ON end.x, which
	# has_point (half-open) reports as outside. The rule being pinned is "back onto the board".
	assert_bool(rig.position.x >= rig.pan_limit.position.x and rig.position.x <= rig.pan_limit.end.x) \
		.override_failure_message("an off-board authored aim escaped the pan limit in x").is_true()
	assert_bool(rig.position.z >= rig.pan_limit.position.y and rig.position.z <= rig.pan_limit.end.y) \
		.override_failure_message("an off-board authored aim escaped the pan limit in z").is_true()


# --- Orbit and detents -------------------------------------------------------------

func test_dragging_the_orbit_button_rotates_freely() -> void:
	var rig := _rig()
	rig._target_yaw_degrees = 0.0
	_drag(rig.orbit_button, Vector2(40.0, 0.0))
	# Free means free: the resting yaw is not a multiple of the detent step.
	assert_float(rig._target_yaw_degrees).is_not_equal(0.0)
	assert_float(fmod(absf(rig._target_yaw_degrees), rig.yaw_step)).is_not_equal(0.0)


# --- The tilt (#586) ----------------------------------------------------------------
#
# The same drag's vertical half. Dev, reversing #586's original dev-only scope: "I think it's better
# to just let the player in general tilt the camera up and down too ... I don't see the harm."

func test_dragging_up_and_down_tilts_the_camera() -> void:
	var rig := _rig()
	rig._target_pitch_degrees = -40.0
	_drag(rig.orbit_button, Vector2(0.0, 30.0))
	assert_float(rig._target_pitch_degrees).override_failure_message(
			"the vertical half of the orbit drag went nowhere").is_not_equal(-40.0)


func test_the_tilt_is_clamped_to_its_own_band() -> void:
	# On the TARGET, so a drag past the limit cannot park an angle the ease would keep fighting.
	# The band is a knob, so the case drives PAST whatever it is set to rather than naming a number.
	var rig := _rig()
	var span: float = rig.max_pitch_degrees - rig.min_pitch_degrees
	var pixels: float = (span * 4.0) / rig.orbit_sensitivity

	rig._target_pitch_degrees = rig.max_pitch_degrees
	_drag(rig.orbit_button, Vector2(0.0, -pixels))
	assert_float(rig._target_pitch_degrees).override_failure_message(
			"the shallow end of the tilt is unbounded -- the camera can look along the board") \
		.is_equal_approx(rig.max_pitch_degrees, 0.001)

	rig._target_pitch_degrees = rig.min_pitch_degrees
	_drag(rig.orbit_button, Vector2(0.0, pixels))
	assert_float(rig._target_pitch_degrees).override_failure_message(
			"the steep end of the tilt is unbounded") \
		.is_equal_approx(rig.min_pitch_degrees, 0.001)


func test_r_levels_the_tilt_back_to_the_boards_own_angle() -> void:
	# R is the ONLY leveller, and it returns to what the MOOD authored rather than to a _home_ of
	# pitch's own -- the board already says what the opening angle is, so a second copy could drift.
	var rig := _rig()
	rig.board_pitch_degrees = -35.0
	rig._target_pitch_degrees = -70.0
	_key(KEY_R)
	assert_float(rig._target_pitch_degrees).override_failure_message(
			"R left the camera tilted -- it is the one gesture that puts the board's angle back") \
		.is_equal_approx(-35.0, 0.001)


func test_a_realign_keeps_the_tilt():
	# Dev ruling 2026-08-27: Q/E stays a YAW realign. Tilting to read a pit and then turning to see
	# its other side is the gesture the tilt exists for, and levelling here would cost it.
	var rig := _rig()
	rig.board_pitch_degrees = -40.0
	rig._target_pitch_degrees = -72.0
	_key(KEY_Q)
	assert_float(rig._target_pitch_degrees).override_failure_message(
			"Q levelled the tilt -- a realign is yaw only, or you cannot turn while looking down") \
		.is_equal_approx(-72.0, 0.001)
	_key(KEY_E)
	rig.align_to_detent()
	assert_float(rig._target_pitch_degrees).override_failure_message(
			"squaring up for playback levelled the tilt").is_equal_approx(-72.0, 0.001)


func test_the_authored_pitch_snaps_rather_than_easing_in() -> void:
	# frame()'s reasoning, on the axis frame() does not own: pitch is part of the camera's BASIS, so
	# a rig still lerping toward a newly applied mood unprojects at one angle and picks at another.
	# A mood arriving is a board arriving. Deliberately no awaited frame -- smoothing would hide it.
	var rig := _rig()
	rig.board_pitch_degrees = -55.0
	assert_float(_scene.get_node("CameraRig/Pitch").rotation_degrees.x) \
		.override_failure_message("the applied mood eased in instead of landing") \
		.is_equal_approx(-55.0, 0.001)


func test_the_pitch_node_is_an_output_and_is_never_read_back() -> void:
	# The rig's live angle is its OWN float; the node is where that float is written and nothing
	# more. Pinned because reading it back is what made the channel unable to settle -- the basis
	# round-trip returns -39.999992 for an authored -40, so the ease chased a target it could never
	# reach and rewrote the camera transform every frame for ever.
	var rig := _rig()
	var node: Node3D = _scene.get_node("CameraRig/Pitch")
	rig.board_pitch_degrees = -45.0
	node.rotation_degrees.x = -12.0   # a stale writer, of the kind the old knob was
	_drag(rig.orbit_button, Vector2(0.0, 4.0))
	await await_idle_frame()
	assert_float(node.rotation_degrees.x).override_failure_message(
			"the tilt eased from a value written ONTO the node -- the rig is reading its own output "
			+ "back, which is what stops the channel settling") \
		.is_less(-30.0)


# NB there is deliberately NO "the camera settles" case here or in test_input_bridge: two written for
# it both PASSED against the mutant they were aimed at. The read-back's real guard is the pair of
# health-readout suites named in CameraRig3D._process.


func test_the_camera_return_brings_the_tilt_back_with_the_rest() -> void:
	# A player who tilted to read a pit and then pressed Execute is standing where they were
	# standing; #534's return owes them the pitch exactly as it owes them the yaw.
	var rig := _rig()
	rig._target_pitch_degrees = -68.0
	rig.stash_view()
	rig._target_pitch_degrees = -30.0   # playback points the camera somewhere else
	rig.restore_view()
	assert_float(rig._target_pitch_degrees).override_failure_message(
			"the view came back without the tilt the player left on it") \
		.is_equal_approx(-68.0, 0.001)


func test_q_and_e_land_on_the_next_detent_from_anywhere() -> void:
	var rig := _rig()
	# From off-axis, one press realigns — the whole point of the detents.
	rig._target_yaw_degrees = 37.0
	_key(KEY_Q)
	assert_float(rig._target_yaw_degrees).is_equal_approx(90.0, 0.001)
	rig._target_yaw_degrees = 37.0
	_key(KEY_E)
	assert_float(rig._target_yaw_degrees).is_equal_approx(0.0, 0.001)
	# From an exact detent it still moves a whole step, i.e. the old behaviour survives.
	rig._target_yaw_degrees = 90.0
	_key(KEY_Q)
	assert_float(rig._target_yaw_degrees).is_equal_approx(180.0, 0.001)


# --- The orbit strand (#231) --------------------------------------------------------
#
# A gesture whose release can never match strands _orbiting TRUE for ever. After that every
# motion is yaw and Battle3D's `not is_orbiting()` guard refuses to point at ANY cell —
# permanently, for the rest of the session. #231 arms this on purpose: the tile brush takes
# RIGHT while armed, so the host now rewrites orbit_button at runtime.

func test_rebinding_the_orbit_button_mid_drag_releases_the_gesture() -> void:
	var rig := _rig()
	_press(rig.orbit_button)
	_move(Vector2(30.0, 0.0))
	assert_bool(rig.is_orbiting()).override_failure_message(
			"precondition: the drag never started, so this proves nothing").is_true()
	# Whichever way round the scene authored it — the knob is the dev's, not this test's.
	var other: MouseButton = MOUSE_BUTTON_MIDDLE if rig.orbit_button == MOUSE_BUTTON_RIGHT \
			else MOUSE_BUTTON_RIGHT
	rig.orbit_button = other
	assert_bool(rig.is_orbiting()).override_failure_message(
			"the drag survived the rebind — pointing is now dead for the whole session"
	).is_false()


func test_losing_manual_input_mid_drag_releases_the_gesture() -> void:
	var rig := _rig()
	_press(rig.orbit_button)
	_move(Vector2(30.0, 0.0))
	assert_bool(rig.is_orbiting()).override_failure_message(
			"precondition: the drag never started, so this proves nothing").is_true()
	rig.manual_input_enabled = false
	assert_bool(rig.is_orbiting()).is_false()


# The early-out is not a micro-optimisation, it IS the correctness of the two cases above:
# battle3d._process assigns both of these every frame, so an unguarded release would cancel a
# live orbit sixty times a second and dragging would be impossible in the 3D view.
func test_rewriting_the_same_values_does_not_cancel_a_live_drag() -> void:
	var rig := _rig()
	_press(rig.orbit_button)
	_move(Vector2(30.0, 0.0))
	var unchanged_button: MouseButton = rig.orbit_button
	rig.manual_input_enabled = true      # exactly what _process writes, unchanged
	rig.orbit_button = unchanged_button
	assert_bool(rig.is_orbiting()).override_failure_message(
			"a no-op write killed the drag — orbit is impossible under a per-frame host"
	).is_true()


# release_orbit() must NOT zero the travel. The PHYSICAL release is still coming, and
# _handle_cancel_button reads last_gesture_was_click() on it — so zeroing here would report an
# abandoned long drag as a click and fire a spurious cancel at whatever the cursor had reached.
func test_releasing_the_orbit_keeps_the_gesture_travel() -> void:
	var rig := _rig()
	_press(rig.orbit_button)
	_move(Vector2(rig.orbit_click_slop_px + 50.0, 0.0))
	rig.release_orbit()
	assert_bool(rig.last_gesture_was_click()).override_failure_message(
			"the abandoned drag now reads as a click — a spurious cancel fires on release"
	).is_false()


func test_a_short_drag_still_reads_as_a_click() -> void:
	# What lets orbit_button be a real knob: a host sharing the button with a click verb
	# (Battle3D's right-click cancel) asks the rig which the gesture was.
	var rig := _rig()
	_drag(rig.orbit_button, Vector2(1.0, 0.0))
	assert_bool(rig.last_gesture_was_click()).is_true()
	_drag(rig.orbit_button, Vector2(rig.orbit_click_slop_px + 20.0, 0.0))
	assert_bool(rig.last_gesture_was_click()).is_false()


# --- Bounds and the manual gate ----------------------------------------------------

func test_panning_is_clamped_to_the_framed_board() -> void:
	var rig := _rig()
	rig.frame(AABB(Vector3.ZERO, Vector3(10, 1, 10)))
	# Through the door, for the reason above: a raw `position =` is derived away rather than
	# clamped, and this case would then pass on the rig never having left the board at all.
	rig.hold_at(Vector3(500, 1, 500))
	rig._process(0.016)
	# Non-vacuous: it moved, and it stopped exactly at the bound rather than anywhere.
	assert_float(rig.position.x).is_less(500.0)
	assert_float(rig.position.x).is_equal_approx(rig.pan_limit.end.x, 0.001)
	assert_float(rig.position.z).is_equal_approx(rig.pan_limit.end.y, 0.001)


# --- The pan, and the snaps that stay snaps (#520) ---------------------------------
#
# The EASE ITSELF IS INVISIBLE HEADLESS: _process lands both position channels in one frame (the
# rig's own escape, the fourth in the repo), because a suite sampling an asymptotic lerp reads frame
# timing rather than the rig. So these pin the DECISION -- a pan moves where the camera is HEADING
# and leaves the camera alone, a snap moves both -- which is exactly what separates the four calls
# the dev asked to stop teleporting from the three that must keep cutting.

func test_a_glide_moves_where_the_camera_is_heading_and_not_the_camera() -> void:
	var rig := _rig()
	rig.hold_at(Vector3(4, 1, 4))
	var before: Vector3 = rig.position

	rig.glide_to(Vector3(20, 1, 18))

	# Non-vacuous: there is real distance to travel, so "it has not arrived" cannot pass by the
	# destination already sitting under the camera.
	assert_bool(before.distance_to(Vector3(20, 1, 18)) > 1.0).override_failure_message(
			"the glide had nowhere to go; the case proves nothing").is_true()
	assert_that(rig.position).override_failure_message(
			"the pan teleported -- it wrote the camera's position instead of its target") \
		.is_equal(before)
	assert_that(rig._target_aim).is_equal(Vector3(20, 1, 18))


func test_a_snap_moves_both_so_nothing_is_left_for_the_ease_to_fight() -> void:
	var rig := _rig()
	rig.glide_to(Vector3(4, 1, 4))
	rig.hold_at(Vector3(20, 1, 18))

	assert_that(rig.position).is_equal(Vector3(20, 1, 18))
	# The target too, and that half is the load-bearing one: a snap that moved only the camera
	# would be dragged straight back to wherever the last pan was heading on the very next frame.
	assert_that(rig._target_aim).override_failure_message(
			"the snap left a stale target behind, so the ease pulls the camera off it") \
		.is_equal(Vector3(20, 1, 18))


func test_the_ease_closes_the_gap_a_pan_opened() -> void:
	var rig := _rig()
	rig.frame(AABB(Vector3.ZERO, Vector3(30, 1, 30)))
	rig.hold_at(Vector3(4, 1, 4))
	rig.glide_to(Vector3(20, 1, 18))
	assert_bool(rig.position.distance_to(Vector3(20, 1, 18)) > 1.0).override_failure_message(
			"precondition: the pan left no gap to close").is_true()

	await await_idle_frame()

	assert_that(rig.position).override_failure_message(
			"the target moved and the camera never followed it -- nothing eases the aim") \
		.is_equal(Vector3(20, 1, 18))


# The clamp bites the TARGET as well as the live aim, and this is the consequence that buys those
# two lines. Headless the pair is otherwise indistinguishable — the ease lands in one frame, so a
# surviving off-board target is re-clamped every frame and the camera never visibly moves. What it
# costs is LATER: painting a tile grows the board and widens the limit without moving the view
# (#231's rule), and a destination the clamp had already refused would come back to life there.
func test_a_pan_aimed_off_the_board_does_not_come_back_when_the_board_grows() -> void:
	var rig := _rig()
	rig.frame(AABB(Vector3.ZERO, Vector3(20, 1, 20)))
	rig.glide_to(Vector3(500, 1, 500))
	await await_idle_frame()
	var clamped: Vector3 = rig.position
	# Non-vacuous: the aim really was outside, so a no-op clamp cannot pass this.
	assert_bool(clamped.distance_to(Vector3(500, 1, 500)) > 1.0).override_failure_message(
			"the aim was already inside the limit; the case proves nothing").is_true()

	rig.rebound(AABB(Vector3.ZERO, Vector3(600, 1, 600)))
	await await_idle_frame()

	assert_that(rig.position).override_failure_message(
			"the camera flew off to a destination the clamp had already refused, the moment the " \
			+ "board grew enough to allow it").is_equal(clamped)


func test_the_diorama_lift_carries_the_camera_up_with_it() -> void:
	# #521's half: the fight tears out of the board and the camera has to go with it, or it stays
	# down on the board watching a hole. A SECOND channel rather than part of the aim, because the
	# aim is held every frame by the playback mirror and the lift is the one thing that pans.
	var rig := _rig()
	rig.frame(AABB(Vector3.ZERO, Vector3(30, 1, 30)))
	rig.hold_at(Vector3(12, 1, 12))
	var grounded: Vector3 = rig.position

	rig.lift_to(Vector3(0.0, 9.0, 0.0))
	await await_idle_frame()

	assert_that(rig.position).override_failure_message(
			"the camera stayed down on the board while the diorama rose") \
		.is_equal(grounded + Vector3(0.0, 9.0, 0.0))

	# ...and back down when the tiles thud into their sockets, without anyone remembering to undo it.
	rig.lift_to(Vector3.ZERO)
	await await_idle_frame()
	assert_that(rig.position).override_failure_message(
			"the camera never came back down -- the lift latched instead of being polled") \
		.is_equal(grounded)


# --- Widening to fit a span (#520) --------------------------------------------------
#
# The move phase's half of "instead of just centering on the unit, it should try to show both their
# start and end position in the initial shot" (dev, scratchpad 2026-08-26). Asserted by EQUIVALENCE
# against what framing that span outright solves for, never as a distance number, so fov, pitch and
# the fit margin all stay the dev's knobs.

func test_widening_to_a_span_reaches_the_distance_that_span_needs() -> void:
	var rig := _rig()
	var board := AABB(Vector3.ZERO, Vector3(64, 1, 40))
	var span := AABB(Vector3(6, 0, 5), Vector3.ZERO).expand(Vector3(52, 1, 34))

	rig.frame(span, board)
	var wanted: float = rig._target_distance   # the oracle

	rig.frame(AABB(Vector3(28, 0, 18), Vector3(4, 1, 4)), board)   # ...and a close opening shot
	assert_float(rig._target_distance).override_failure_message(
			"the shot already sat at the span's distance; the widen proves nothing").is_less(wanted)
	var aim: Vector3 = rig.position

	rig.widen_to_fit(span)

	assert_float(rig._target_distance).override_failure_message(
			"the widen did not pull back far enough to hold both ends of the walk") \
		.is_equal_approx(wanted, 0.001)
	assert_that(rig.position).override_failure_message(
			"the widen moved the camera; it may only touch the distance").is_equal(aim)


func test_widening_never_pulls_in_on_a_short_hop() -> void:
	# A hop already has both ends in frame at the distance the pass opened on, so fitting it would
	# mean zooming IN to a two-cell walk -- answering a question nobody asked.
	var rig := _rig()
	var board := AABB(Vector3.ZERO, Vector3(64, 1, 40))
	var hop := AABB(Vector3(30, 0, 20), Vector3.ZERO).expand(Vector3(32, 1, 20))

	rig.frame(hop, board)
	var hop_distance: float = rig._target_distance
	rig.frame(board)
	assert_float(hop_distance).override_failure_message(
			"the hop needs the whole-board distance; the case proves nothing").is_less(rig._target_distance)
	var opened: float = rig._target_distance

	rig.widen_to_fit(hop)

	assert_float(rig._target_distance).override_failure_message(
			"the widen pulled IN to fit a two-cell hop").is_equal_approx(opened, 0.001)


func test_a_span_too_big_to_fit_stops_at_the_boards_own_ceiling() -> void:
	# The ticket's own "should be doable unless super zoomed in": a span that will not fit is not a
	# licence to leave the zoom ceiling the board sets behind.
	var rig := _rig()
	rig.frame(AABB(Vector3.ZERO, Vector3(20, 1, 20)))
	var ceiling: float = rig.max_distance

	rig.widen_to_fit(AABB(Vector3(-400, 0, -400), Vector3(800, 1, 800)))

	assert_float(rig._target_distance).override_failure_message(
			"the widen escaped the board's own zoom ceiling").is_equal_approx(ceiling, 0.001)


func test_disabling_manual_input_refuses_keys_but_keeps_smoothing_alive() -> void:
	# The distinction the whole AI-follow rests on: while something else drives the rig
	# it must ignore the player WITHOUT freezing, or the mirrored motion would not settle.
	var rig := _rig()
	rig.manual_input_enabled = false
	rig._target_yaw_degrees = 0.0
	_key(KEY_Q)
	assert_float(rig._target_yaw_degrees).override_failure_message(
			"Q reached the rig while manual input was off").is_equal_approx(0.0, 0.001)
	_drag(rig.orbit_button, Vector2(40.0, 0.0))
	assert_float(rig._target_yaw_degrees).is_equal_approx(0.0, 0.001)

	# ...and the smoothing still runs, which a set_process(false) implementation would
	# have killed outright. Asserted as "most of the way there" rather than "arrived":
	# the lerp is exponential, so it approaches asymptotically and the exact residual is
	# a function of the smoothing knob, which must stay tunable without reddening this.
	var start: float = _camera().position.z
	rig.set_zoom(start + 5.0)
	for i in 30:
		rig._process(0.016)
	assert_float(_camera().position.z).override_failure_message(
			"the camera never moved — _process is dead, not merely input-gated").is_greater(start + 4.0)
