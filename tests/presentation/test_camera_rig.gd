# The diorama camera rig (#176 stage 4d): framing, orbit, detents, bounds and the
# manual-input gate, pinned in the look-dev scene the rig calls home.
#
# Framing is asserted as a PROPERTY — every corner lands inside the frustum — never as
# a distance number, so fov/pitch/margin stay the dev's knobs (the doctrine
# test_look_dev.gd and test_board_picker.gd already set). What IS pinned numerically is
# arithmetic with one right answer: which detent Q lands on, and where a clamp bites.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/LookDev/LookDev.tscn"

var _scene: Node3D


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)   # a real projection; headless defaults can be tiny
	_scene = (load(SCENE_PATH) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func _rig() -> Node3D:
	return _scene.get_node("CameraRig") as Node3D


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


func test_frame_adopts_the_fit_as_home_so_reset_returns_to_it() -> void:
	var rig := _rig()
	rig.frame(AABB(Vector3(10, 0, 10), Vector3(20, 1, 20)))
	var framed_position: Vector3 = rig.position
	var framed_distance: float = rig._target_distance
	# Non-vacuous: the fit must differ from the scene's authored home, or R proves nothing.
	assert_bool(framed_position.distance_to(Vector3(0, 1, 0)) > 1.0).is_true()

	rig.position = Vector3(999, 1, 999)
	rig.set_zoom(rig.min_distance)
	_key(KEY_R)
	assert_that(rig.position).is_equal(framed_position)
	assert_float(rig._target_distance).is_equal_approx(framed_distance, 0.001)


# --- Orbit and detents -------------------------------------------------------------

func test_dragging_the_orbit_button_rotates_freely() -> void:
	var rig := _rig()
	rig._target_yaw_degrees = 0.0
	_drag(rig.orbit_button, Vector2(40.0, 0.0))
	# Free means free: the resting yaw is not a multiple of the detent step.
	assert_float(rig._target_yaw_degrees).is_not_equal(0.0)
	assert_float(fmod(absf(rig._target_yaw_degrees), rig.yaw_step)).is_not_equal(0.0)


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
	rig.position = Vector3(500, 1, 500)
	rig._process(0.016)
	# Non-vacuous: it moved, and it stopped exactly at the bound rather than anywhere.
	assert_float(rig.position.x).is_less(500.0)
	assert_float(rig.position.x).is_equal_approx(rig.pan_limit.end.x, 0.001)
	assert_float(rig.position.z).is_equal_approx(rig.pan_limit.end.y, 0.001)


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
