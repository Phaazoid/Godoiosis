# The flourish channel (#520 diff 2b): the impact jolt, the resting sway, and the pitch a directed
# beat stoops to. Three effects that are not WHERE the camera looks but a displacement laid over it.
#
# What is pinned here is DECISIONS and CURVE SHAPE, never a rendered frame. The clocks do not
# advance headless (see CameraRig3D._process), which is deliberate and is what keeps `position`
# bit-identical to a run without this channel -- so every case that wants to watch a curve supplies
# the elapsed time itself and reads flourish(), rather than waiting for frames that spend none.
#
# The curve functions are STATIC and pure, which is the whole reason they are worth having as their
# own seam: a damped oscillation can be pinned as a property (it decays, it starts at rest, it does
# not repeat) with no scene, no host and no frame timing anywhere near it.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/LookDev/LookDev.tscn")

var _scene: Node3D
# Pacing's rows are `static var` so a tuning panel can reach them, which means they OUTLIVE a suite
# (#449). Saved and restored around every case rather than at the end of each body: a failing case
# aborts before its own restore line, and would then hand its tuning to every case after it.
var _saved: Dictionary = {}


func before_test() -> void:
	_saved = {
		"pitch_dive": Pacing.PITCH_DIVE,
		"board_direction": Pacing.BOARD_DIRECTION,
		"cinematic_direction": Pacing.CINEMATIC_DIRECTION,
	}
	PlayerSettings.reset_for_test()
	get_tree().root.size = Vector2i(1280, 720)
	_scene = SCENE.instantiate() as Node3D
	get_tree().root.add_child(_scene)
	await await_idle_frame()


func after_test() -> void:
	Pacing.PITCH_DIVE = _saved["pitch_dive"]
	Pacing.BOARD_DIRECTION = _saved["board_direction"]
	Pacing.CINEMATIC_DIRECTION = _saved["cinematic_direction"]
	PlayerSettings.reset_for_test()
	get_tree().root.remove_child(_scene)
	_scene.free()
	# The #93/#473 orphan workaround: gdUnit4's own teardown, not ours.
	await await_idle_frame()


func _rig() -> CameraRig3D:
	return _scene.get_node("CameraRig") as CameraRig3D


# --- the curves, as properties -----------------------------------------------------------------

func test_a_jolt_starts_at_rest_so_it_pushes_off_from_where_the_camera_already_was() -> void:
	# Not decoration: it is what lets the headless clock stay at zero and still leave `position`
	# untouched, which is the escape the whole channel is built on.
	assert_float(CameraRig3D.shake_offset(1.0, 0.0)).is_equal_approx(0.0, 0.0001)


func test_a_jolt_decays_rather_than_ringing_forever() -> void:
	# The ENVELOPE, sampled at successive peaks of the sine rather than at arbitrary times -- the
	# raw offset crosses zero twice a cycle, so comparing two instants proves nothing about decay.
	var quarter := (PI / 2.0) / Pacing.SHAKE_FREQUENCY
	var first := absf(CameraRig3D.shake_offset(1.0, quarter))
	var later := absf(CameraRig3D.shake_offset(1.0, quarter + 4.0 * TAU / Pacing.SHAKE_FREQUENCY))
	assert_float(first).is_greater(0.0)
	assert_float(later).is_less(first)


func test_a_jolt_is_deterministic_in_its_arguments() -> void:
	# Law #1 at the smallest scale it can be asked: the same blow reads the same on every replay,
	# which a noise roll could not promise however good it looked.
	var once := CameraRig3D.shake_offset(0.4, 0.07)
	var twice := CameraRig3D.shake_offset(0.4, 0.07)
	assert_float(once).is_equal(twice)


func test_a_silent_jolt_and_a_dialled_out_sway_both_move_nothing() -> void:
	assert_float(CameraRig3D.shake_offset(0.0, 0.13)).is_equal(0.0)
	assert_float(CameraRig3D.sway_offset(0.0, 0.13)).is_equal(0.0)


func test_the_sway_does_not_repeat_on_its_own_period() -> void:
	# The two-sine shape, asserted as the thing it BUYS rather than by counting sines: at one full
	# period of the primary wave a single sine would be exactly back where it started, so a mutant
	# dropping the second term lands on equality here.
	var period := TAU / Pacing.SWAY_SPEED
	var start := CameraRig3D.sway_offset(1.0, 0.0)
	var one_period_later := CameraRig3D.sway_offset(1.0, period)
	assert_float(absf(one_period_later - start)).override_failure_message(
			"the sway returned to its starting value after one primary period, i.e. it is a single sine"
	).is_greater(0.001)


# --- the gate ----------------------------------------------------------------------------------

func test_the_camera_only_flourishes_while_playback_has_borrowed_the_view() -> void:
	# The gate is _view_borrowed rather than a flag of its own, so this is also what pins that
	# choice: a jolt armed with the player holding the camera must move nothing at all.
	var rig := _rig()
	rig.shake(0.5)
	rig._shake_elapsed = (PI / 2.0) / Pacing.SHAKE_FREQUENCY   # headless spends no time; supply it
	assert_that(rig.flourish()).override_failure_message(
			"the camera flourished while the player owned it -- a sway under your own hand is motion sickness"
	).is_equal(Vector3.ZERO)

	rig.stash_view()
	rig.shake(0.5)
	rig._shake_elapsed = (PI / 2.0) / Pacing.SHAKE_FREQUENCY
	assert_float(absf(rig.flourish().y)).is_greater(0.0)


func test_giving_the_camera_back_ends_the_flourish_in_the_same_frame() -> void:
	# A jolt outliving the release would ride into the view the player was just handed, which is the
	# one place this channel could leak into something they authored.
	var rig := _rig()
	rig.stash_view()
	rig.shake(0.5)
	rig._shake_elapsed = (PI / 2.0) / Pacing.SHAKE_FREQUENCY
	assert_float(absf(rig.flourish().y)).is_greater(0.0)

	rig.restore_view()
	assert_that(rig.flourish()).is_equal(Vector3.ZERO)


func test_a_pass_opens_still_however_hard_the_last_one_ended() -> void:
	var rig := _rig()
	rig.stash_view()
	rig.shake(1.0)
	rig.restore_view()

	rig.stash_view()   # the next claim
	rig._shake_elapsed = (PI / 2.0) / Pacing.SHAKE_FREQUENCY
	assert_that(rig.flourish()).override_failure_message(
			"a new pass inherited the tail of the previous pass's jolt"
	).is_equal(Vector3.ZERO)


# --- strongest wins ----------------------------------------------------------------------------

func test_a_scratch_during_a_heavy_blow_does_not_restart_the_jolt() -> void:
	# The holds' own rule -- the loudest single one wins, by value -- applied to an impulse. Summing
	# would make a three-victim volley hit three times as hard as a duel.
	var rig := _rig()
	rig.stash_view()
	rig.shake(1.0)
	rig._shake_elapsed = 0.02
	rig.shake(0.1)
	assert_float(rig._shake_amplitude).is_equal_approx(1.0, 0.0001)
	assert_float(rig._shake_elapsed).override_failure_message(
			"a weaker blow restarted the clock, so a volley's later hits would stretch the first one"
	).is_equal_approx(0.02, 0.0001)


func test_a_heavier_blow_takes_the_jolt_over() -> void:
	var rig := _rig()
	rig.stash_view()
	rig.shake(0.2)
	rig._shake_elapsed = 0.02
	rig.shake(1.0)
	assert_float(rig._shake_amplitude).is_equal_approx(1.0, 0.0001)
	assert_float(rig._shake_elapsed).is_equal_approx(0.0, 0.0001)


func test_the_comparison_is_against_what_is_LEFT_of_a_jolt_not_what_it_started_at() -> void:
	# The envelope, not the instantaneous offset -- which crosses zero twice a cycle, so a naive
	# compare would let any scratch win at a crossing. Sampled at exactly such a crossing.
	var rig := _rig()
	rig.stash_view()
	rig.shake(1.0)
	rig._shake_elapsed = PI / Pacing.SHAKE_FREQUENCY   # sin() == 0 here; the envelope is still high
	rig.shake(0.1)
	assert_float(rig._shake_amplitude).override_failure_message(
			"a scratch won at a zero crossing, so the comparison is reading the offset not the envelope"
	).is_equal_approx(1.0, 0.0001)


# --- the pitch dive ----------------------------------------------------------------------------

func _line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var line: Array[Vector2i] = [from, to]
	return line


func test_a_directed_beat_stoops_the_camera_toward_the_fight() -> void:
	var rig := _rig()
	Pacing.CINEMATIC_DIRECTION = 1.0
	Pacing.PITCH_DIVE = 10.0
	rig.board_pitch_degrees = -40.0
	rig.align_to_detent()
	rig.aim_along(_line(Vector2i(2, 2), Vector2i(5, 4)))
	# SHALLOWER than the board's own angle: the camera comes down toward eye level so the blow
	# looms, which is also the end of the band a billboard is actually drawn for.
	assert_float(rig._target_pitch_degrees).is_equal_approx(-30.0, 0.001)


func test_the_stoop_is_measured_from_the_boards_own_angle_so_re_solving_lands_in_one_place() -> void:
	# 2a's mutant, one axis over: the mirror calls aim_along EVERY FRAME, so measuring from the LIVE
	# pitch closes a fraction of the remaining gap per frame and creeps to the full angle -- at which
	# point the strength knob stops meaning anything. Only a PARTIAL strength can separate the two
	# implementations; at 0 and at 1 they agree exactly, which is why both endpoints are useless here.
	var rig := _rig()
	Pacing.CINEMATIC_DIRECTION = 0.5
	Pacing.PITCH_DIVE = 10.0
	rig.board_pitch_degrees = -40.0
	rig.align_to_detent()

	var line := _line(Vector2i(2, 2), Vector2i(5, 4))
	rig.aim_along(line)
	var first := rig._target_pitch_degrees
	rig.aim_along(line)
	rig.aim_along(line)
	assert_float(rig._target_pitch_degrees).override_failure_message(
			"the stoop crept between identical calls, so it is measured from the live pitch"
	).is_equal_approx(first, 0.0001)
	# ...and non-vacuity: a stoop that never happened is trivially idempotent.
	assert_float(absf(first - rig.board_pitch_degrees)).is_greater(0.1)


func test_the_stoop_stays_inside_the_band_the_players_own_drag_is_held_to() -> void:
	# That band is where the HD-2D conceit gives out, i.e. an ART limit -- so it binds every writer,
	# not just the hand that set it.
	var rig := _rig()
	Pacing.CINEMATIC_DIRECTION = 1.0
	Pacing.PITCH_DIVE = 400.0        # absurd on purpose
	rig.board_pitch_degrees = -40.0
	rig.align_to_detent()
	rig.aim_along(_line(Vector2i(2, 2), Vector2i(5, 4)))
	assert_float(rig._target_pitch_degrees).is_equal_approx(rig.max_pitch_degrees, 0.001)


func test_the_plain_board_is_never_stooped() -> void:
	# Shares direction_of's fork with the yaw: whether the plain board gets DIRECTED shots at all is
	# one question and already has an answer. How far each axis swings under it is two.
	var rig := _rig()
	Pacing.BOARD_DIRECTION = 0.0
	Pacing.PITCH_DIVE = 10.0
	rig.board_pitch_degrees = -40.0
	rig.align_to_detent()
	PlayerSettings.set_on(PlayerSettings.Setting.BATTLE_ZOOM, false)
	rig.aim_along(_line(Vector2i(2, 2), Vector2i(5, 4)))
	assert_float(rig._target_pitch_degrees).is_equal_approx(-40.0, 0.001)


func test_the_stoop_lands_in_the_same_place_however_the_player_had_tilted() -> void:
	# The claim edge does NOT square the tilt up -- #586's rule is that a tilt survives everything
	# but R, and test_camera_rig's own test_a_realign_keeps_the_tilt pins that over align_to_detent.
	# Squaring up was in this slice for one run, on the theory that a player parked at the shallow
	# end leaves the stoop nowhere to go. This is the case that says it does not: the stoop is
	# ABSOLUTE off the board's authored angle, so where the hand left the camera cannot reach it.
	var rig := _rig()
	Pacing.CINEMATIC_DIRECTION = 1.0
	Pacing.PITCH_DIVE = 10.0
	rig.board_pitch_degrees = -40.0
	var line := _line(Vector2i(2, 2), Vector2i(5, 4))

	rig._target_pitch_degrees = -75.0       # a player who had tilted steeply down
	rig.align_to_detent()
	rig.aim_along(line)
	var from_steep := rig._target_pitch_degrees

	rig._target_pitch_degrees = -21.0       # ...and one parked near the shallow end
	rig.align_to_detent()
	rig.aim_along(line)
	assert_float(rig._target_pitch_degrees).override_failure_message(
			"the stoop depended on where the player had left the tilt, so it is not absolute"
	).is_equal_approx(from_steep, 0.001)
	assert_float(from_steep).is_equal_approx(-30.0, 0.001)


func test_a_beat_with_no_direction_leaves_the_players_tilt_alone() -> void:
	# Absence means "the camera does not move" -- aim_along's own idiom for the yaw, and the reason
	# the claim edge may safely leave the tilt exactly where it found it.
	var rig := _rig()
	rig.board_pitch_degrees = -40.0
	rig._target_pitch_degrees = -66.0
	rig.stash_view()
	rig.align_to_detent()
	rig.aim_along([] as Array[Vector2i])
	assert_float(rig._target_pitch_degrees).override_failure_message(
			"a beat with nobody to frame levelled the camera the player had tilted"
	).is_equal_approx(-66.0, 0.001)
