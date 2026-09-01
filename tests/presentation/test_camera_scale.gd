# The player's camera-handling steps (#394): three choice rows that SCALE what the dev authored
# rather than replacing it, so nothing leaves GameKnobs and no slider is ever inert.
#
# The scale itself is a pure static, so most of this needs no scene -- but the DIAGONAL case does,
# because what it is about is the rig applying one rate to two axes of one drag.
#
# NO CASE SAYS WHAT ANY FACTOR IS. Every expectation is a RATIO taken from scale_of, so the dev may
# retune all three bases and all six factors without reddening a line here.
extends GdUnitTestSuite

const SCENE: PackedScene = preload("res://Scenes/LookDev/LookDev.tscn")

const PAN := PlayerSettings.Setting.CAMERA_PAN_SPEED
const MOUSE := PlayerSettings.Setting.MOUSE_SENSITIVITY
const SMOOTH := PlayerSettings.Setting.CAMERA_SMOOTHING

var _scene: Node3D
var _rig: CameraRig3D

func before_test() -> void:
	PlayerSettings.reset_for_test()
	_scene = SCENE.instantiate() as Node3D
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_rig = _scene.find_child("CameraRig", true, false) as CameraRig3D
	assert_object(_rig).override_failure_message("the look-dev scene has no CameraRig").is_not_null()

func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()
	PlayerSettings.reset_for_test()


func test_normal_is_the_authored_value_untouched() -> void:
	# The fall-through, and the reason NORMAL is absent from SCALE_FACTORS: a player who never opens
	# the page gets exactly what the Game tab's sliders say, with no factor in the way.
	for setting: PlayerSettings.Setting in [PAN, MOUSE, SMOOTH]:
		assert_float(CameraRig3D.scale_of(setting)).override_failure_message(
				"%s does not fall through to 1.0 at NORMAL" % PlayerSettings.Setting.keys()[setting]
				).is_equal_approx(1.0, 0.0001)
	assert_float(_rig.effective_pan_speed()).is_equal_approx(_rig.pan_speed, 0.0001)
	assert_float(_rig.effective_orbit_sensitivity()).is_equal_approx(_rig.orbit_sensitivity, 0.0001)
	assert_float(_rig.effective_zoom_step()).is_equal_approx(_rig.zoom_step, 0.0001)
	assert_float(_rig.effective_smoothing()).is_equal_approx(_rig.smoothing, 0.0001)

func test_normal_is_not_a_row_in_the_factor_table() -> void:
	# Stated directly, because it is the rule the case above depends on. A factor of 1.0 written down
	# is a second answer to what "unchanged" means, and it goes stale the day someone edits it.
	for setting: PlayerSettings.Setting in CameraRig3D.SCALE_FACTORS:
		var row: Dictionary = CameraRig3D.SCALE_FACTORS[setting]
		assert_bool(row.has(PlayerSettings.Scale.NORMAL)).override_failure_message(
				"%s writes NORMAL down as a factor -- it must fall through instead"
				% PlayerSettings.Setting.keys()[setting]).is_false()

func test_every_step_of_every_row_has_a_factor() -> void:
	# A table that has fallen behind its enum scales by 1.0 through a push_error, so the camera still
	# answers the hand -- legible, and silently not what the player picked.
	for setting: PlayerSettings.Setting in [PAN, MOUSE, SMOOTH]:
		var name: String = PlayerSettings.Setting.keys()[setting]
		assert_bool(CameraRig3D.SCALE_FACTORS.has(setting)).override_failure_message(
				"%s is a camera scale row with no factors at all" % name).is_true()
		if not CameraRig3D.SCALE_FACTORS.has(setting):
			continue
		var row: Dictionary = CameraRig3D.SCALE_FACTORS[setting]
		for step: int in PlayerSettings.Scale.values():
			if step == PlayerSettings.Scale.NORMAL:
				continue
			assert_bool(row.has(step)).override_failure_message(
					"%s has no factor for %s" % [name, PlayerSettings.Scale.keys()[step]]).is_true()

func test_a_step_scales_the_value_it_names() -> void:
	# The fork, as a RATIO against scale_of rather than against a number typed here.
	PlayerSettings.set_choice(PAN, PlayerSettings.Scale.FASTER)
	assert_float(_rig.effective_pan_speed()).override_failure_message(
			"the pan-speed step did not reach the value it names").is_equal_approx(
			_rig.pan_speed * CameraRig3D.scale_of(PAN), 0.0001)
	assert_float(CameraRig3D.scale_of(PAN)).override_failure_message(
			"FASTER left the pan speed unscaled").is_not_equal(1.0)

func test_the_mouse_row_drives_the_drag_and_the_wheel_together() -> void:
	# One hand, one setting: the declaration says turning and zooming are the same gesture, so a step
	# that moved only one of them would be the surprise.
	PlayerSettings.set_choice(MOUSE, PlayerSettings.Scale.SLOWER)
	var factor := CameraRig3D.scale_of(MOUSE)
	assert_float(_rig.effective_orbit_sensitivity()).is_equal_approx(
			_rig.orbit_sensitivity * factor, 0.0001)
	assert_float(_rig.effective_zoom_step()).override_failure_message(
			"the wheel was left behind by the mouse-sensitivity step").is_equal_approx(
			_rig.zoom_step * factor, 0.0001)

func test_each_row_moves_only_its_own_values() -> void:
	# Three preferences sharing one enum must not share an EFFECT. Asserted per row so a factor table
	# keyed wrongly names which row leaked.
	PlayerSettings.set_choice(MOUSE, PlayerSettings.Scale.FASTER)
	assert_float(_rig.effective_pan_speed()).override_failure_message(
			"the mouse row moved the pan speed").is_equal_approx(_rig.pan_speed, 0.0001)
	assert_float(_rig.effective_smoothing()).override_failure_message(
			"the mouse row moved the smoothing").is_equal_approx(_rig.smoothing, 0.0001)

	PlayerSettings.reset_for_test()
	PlayerSettings.set_choice(SMOOTH, PlayerSettings.Scale.SLOWER)
	assert_float(_rig.effective_orbit_sensitivity()).override_failure_message(
			"the smoothing row moved the orbit sensitivity").is_equal_approx(
			_rig.orbit_sensitivity, 0.0001)

func test_the_playback_glide_is_outside_the_players_reach() -> void:
	# SCOPE, pinned. glide_smoothing answers how a shot TRAVELS when playback moves the camera --
	# direction rather than comfort, and its own declaration keeps it separate from the input rate.
	# Welding it to the smoothing row would put a dial on the end of every Execute. If it ever joins,
	# this is the case to delete on purpose.
	var authored := _rig.glide_smoothing
	for step: int in PlayerSettings.Scale.values():
		PlayerSettings.set_choice(SMOOTH, step)
		assert_float(_rig.glide_smoothing).override_failure_message(
				"a player's smoothing step reached the playback glide").is_equal_approx(
				authored, 0.0001)

func test_a_diagonal_drag_stays_straight_at_any_sensitivity() -> void:
	# THE case worth the scene. Turning and tilting are two halves of one drag and the rig reads its
	# rate ONCE for both -- scale only one axis and a diagonal drag curves, which no straight-line
	# case can see. Stated as the RATIO between the axes, so it holds at every step.
	var equal_drag := Vector2(40.0, -40.0)   # equal magnitude on both axes
	var moved: Array[Vector2] = []
	for step: int in PlayerSettings.Scale.values():
		PlayerSettings.set_choice(MOUSE, step)
		_rig._target_yaw_degrees = 0.0
		_rig._target_pitch_degrees = (_rig.min_pitch_degrees + _rig.max_pitch_degrees) * 0.5
		var pitch_before := _rig._target_pitch_degrees
		_drag(equal_drag)
		moved.append(Vector2(absf(_rig._target_yaw_degrees),
				absf(_rig._target_pitch_degrees - pitch_before)))

	for i in moved.size():
		var step_name: String = PlayerSettings.Scale.keys()[i]
		assert_float(moved[i].x).override_failure_message(
				"the %s step turned the view without tilting it -- one axis is unscaled" % step_name
				).is_greater(0.0)
		assert_float(moved[i].y / moved[i].x).override_failure_message(
				"a diagonal drag CURVES at the %s step: the two axes took different rates"
				% step_name).is_equal_approx(1.0, 0.001)


# An orbit drag of `travel`, through the rig's real input path.
func _drag(travel: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = _rig.orbit_button
	press.pressed = true
	_rig._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = travel
	_rig._unhandled_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = _rig.orbit_button
	release.pressed = false
	_rig._unhandled_input(release)
