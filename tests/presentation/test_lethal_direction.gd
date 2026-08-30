# Lethality-aware direction (#520 diff 2c): the director knows the ending before it shoots the
# scene, so a killing blow is SHOT differently rather than merely held longer.
#
# The wind-up is not here -- it was already built, and Pacing.hold_for is where it lives. What this
# pins is the push-in and the freeze.
#
# THE CASE THAT MATTERS MOST is the zoom-floor one. This rig has no zoom-in floor by dev ruling
# (asked twice, "please remove it entirely"), so scrolling past the aim point takes the camera
# through its target to look back. That is his call for HIS hand -- and a director subtracting a
# dolly from an already-close player would inherit the hole and fly the camera through a unit on the
# exact beat it most wants to be looking at one.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/LookDev/LookDev.tscn")

var _scene: Node3D
# Pacing's rows are `static var` and outlive a suite (#449). Saved around every case, not at the end
# of each body: a failing case aborts before its own restore and would tune every case after it.
var _saved: Dictionary = {}


func before_test() -> void:
	_saved = {
		"dolly_in": Pacing.DOLLY_IN,
		"dolly_floor": Pacing.DOLLY_FLOOR,
		"down": Pacing.EMPHASIS_DOWN,
		"crisis": Pacing.EMPHASIS_CRISIS,
		"iron": Pacing.EMPHASIS_IRON_WILL,
		"board_direction": Pacing.BOARD_DIRECTION,
		"cinematic_direction": Pacing.CINEMATIC_DIRECTION,
	}
	PlayerSettings.reset_for_test()
	get_tree().root.size = Vector2i(1280, 720)
	_scene = SCENE.instantiate() as Node3D
	get_tree().root.add_child(_scene)
	await await_idle_frame()


func after_test() -> void:
	Pacing.DOLLY_IN = _saved["dolly_in"]
	Pacing.DOLLY_FLOOR = _saved["dolly_floor"]
	Pacing.EMPHASIS_DOWN = _saved["down"]
	Pacing.EMPHASIS_CRISIS = _saved["crisis"]
	Pacing.EMPHASIS_IRON_WILL = _saved["iron"]
	Pacing.BOARD_DIRECTION = _saved["board_direction"]
	Pacing.CINEMATIC_DIRECTION = _saved["cinematic_direction"]
	PlayerSettings.reset_for_test()
	get_tree().root.remove_child(_scene)
	_scene.free()
	await await_idle_frame()


func _rig() -> CameraRig3D:
	# UNDER THE CINEMATIC unless a case says otherwise (#647). Before the profile was published per
	# beat, PlayerSettings shipped the zoom ON, so every case here ran cinematic by default -- the
	# rig now rests at BOARD, and without this each of them would quietly assert against a channel
	# scaled to zero rather than against the shape it is about.
	var rig := _scene.get_node("CameraRig") as CameraRig3D
	rig.beat_profile = Pacing.Profile.CINEMATIC
	return rig


# A beat carrying one lethality rung. Built by hand rather than resolved off a board: this file is
# about the COLLAPSE from rungs to a weight, and a real plan would drag content in to say it.
func _volley(lethality: int, iron_will := false) -> BeatSheet.Beat:
	var beat := BeatSheet.Beat.new()
	beat.kind = BeatSheet.Kind.VOLLEY
	beat.lethalities = [lethality] as Array[ResolvedOutcome.Lethality]
	beat.iron_will_held = iron_will
	return beat


# --- the emphasis ladder -------------------------------------------------------------------------

func test_an_ordinary_hit_earns_no_emphasis_at_all() -> void:
	# The baseline the rest are read against, and the reason the ladder seeds from nothing rather
	# than from a floor the way the HOLDS do: every blast deserves a pause, not every blast deserves
	# the camera leaning in.
	assert_float(Pacing.emphasis_for(_volley(ResolvedOutcome.Lethality.NONE))).is_equal(0.0)


func test_a_death_is_the_loudest_rung() -> void:
	assert_float(Pacing.emphasis_for(_volley(ResolvedOutcome.Lethality.KILLED))) \
		.is_equal_approx(Pacing.EMPHASIS_DOWN, 0.0001)
	assert_float(Pacing.emphasis_for(_volley(ResolvedOutcome.Lethality.DOWNED))) \
		.is_equal_approx(Pacing.EMPHASIS_DOWN, 0.0001)


func test_the_ranking_between_rungs_is_TUNABLE_rather_than_written_into_the_code() -> void:
	# The holds' own law, one table over: loudest single one wins BY VALUE, so which rung outranks
	# which is a number the dev can move. Flipped with a knob rather than asserted as an order --
	# a case that hardcoded "a death beats a Crisis" would pin taste.
	var crisis := _volley(ResolvedOutcome.Lethality.CRISIS)
	Pacing.EMPHASIS_CRISIS = 0.2
	Pacing.EMPHASIS_DOWN = 0.9
	var quiet_crisis := Pacing.emphasis_for(crisis)

	Pacing.EMPHASIS_CRISIS = 1.0
	var loud_crisis := Pacing.emphasis_for(crisis)
	assert_float(loud_crisis).override_failure_message(
			"moving the Crisis rung did not move what a Crisis beat is worth"
	).is_greater(quiet_crisis)


func test_a_beat_takes_its_LOUDEST_rung_not_the_sum() -> void:
	# One blast is one moment, so a hit that both kills and was a held breath is a death -- not a
	# death plus a held breath. Same rule the holds state, and the reason both use maxf.
	Pacing.EMPHASIS_DOWN = 0.6
	Pacing.EMPHASIS_IRON_WILL = 0.3
	var both := _volley(ResolvedOutcome.Lethality.KILLED, true)
	assert_float(Pacing.emphasis_for(both)).override_failure_message(
			"the rungs stacked -- a beat with two facts read as bigger than either"
	).is_equal_approx(0.6, 0.0001)


func test_only_a_VOLLEY_carries_emphasis() -> void:
	# A coda or the turnover has no lethality to read, and asking would answer off an empty array.
	var coda := BeatSheet.Beat.new()
	coda.kind = BeatSheet.Kind.CODA
	assert_float(Pacing.emphasis_for(coda)).is_equal(0.0)
	assert_float(Pacing.emphasis_for(null)).is_equal(0.0)


# --- the push-in ---------------------------------------------------------------------------------

func test_the_push_in_leans_on_the_players_zoom_without_moving_it() -> void:
	# The whole shape of the dolly: the wheel stays the player's through a pass (#520), so the
	# director may lean on their distance and must never assign over it.
	var rig := _rig()
	Pacing.CINEMATIC_DIRECTION = 1.0
	Pacing.DOLLY_IN = 3.0
	Pacing.DOLLY_FLOOR = 2.0
	rig.stash_view()
	rig.set_zoom(14.0)
	rig.dolly_to(1.0)

	assert_float(rig._target_distance).override_failure_message(
			"the push-in wrote the player's own zoom -- that is the leash #520 refused"
	).is_equal_approx(14.0, 0.0001)
	assert_float(rig._dollied_distance()).is_equal_approx(11.0, 0.0001)


func test_a_quiet_beat_lets_the_camera_back_out() -> void:
	# Publishing 0 is what makes the pass breathe between kills, so the dolly must RE-SOLVE rather
	# than accumulate. A latched push-in would leave the camera leaning in for the rest of the pass.
	var rig := _rig()
	Pacing.CINEMATIC_DIRECTION = 1.0
	Pacing.DOLLY_IN = 3.0
	rig.stash_view()
	rig.set_zoom(14.0)
	rig.dolly_to(1.0)
	rig.dolly_to(0.0)
	assert_float(rig._dollied_distance()).override_failure_message(
			"a beat worth nothing left the camera pushed in"
	).is_equal_approx(14.0, 0.0001)


func test_re_solving_the_same_beat_lands_in_one_place() -> void:
	# The mirror polls this EVERY FRAME, so an accumulating dolly would creep to the board and the
	# knob would stop meaning anything. 2a's mutant, a third axis over -- and at a PARTIAL emphasis,
	# because at 0 and 1 an accumulating and a re-solving implementation are hard to tell apart.
	var rig := _rig()
	Pacing.CINEMATIC_DIRECTION = 1.0
	Pacing.DOLLY_IN = 3.0
	Pacing.DOLLY_FLOOR = 1.0
	rig.stash_view()
	rig.set_zoom(14.0)
	rig.dolly_to(0.5)
	var first := rig._dollied_distance()
	rig.dolly_to(0.5)
	rig.dolly_to(0.5)
	assert_float(rig._dollied_distance()).override_failure_message(
			"the push-in crept between identical calls -- it accumulates instead of re-solving"
	).is_equal_approx(first, 0.0001)
	assert_float(absf(14.0 - first)).is_greater(0.1)   # non-vacuity: it actually pushed in


func test_the_push_in_never_takes_the_camera_through_the_board() -> void:
	# THE FLOOR CASE. There is no zoom-in floor on this rig, deliberately, so an unfloored dolly on
	# a close player takes the distance toward zero and the camera looks back through the unit.
	var rig := _rig()
	Pacing.CINEMATIC_DIRECTION = 1.0
	Pacing.DOLLY_IN = 12.0        # far more than the distance below
	Pacing.DOLLY_FLOOR = 4.0
	rig.stash_view()
	rig.set_zoom(6.0)
	rig.dolly_to(1.0)
	assert_float(rig._dollied_distance()).override_failure_message(
			"the push-in went through the floor -- at worst the camera ends up behind its own subject"
	).is_equal_approx(4.0, 0.0001)


# RENAMED in #602 round 4 (was "a player already closer..."): the base is the DIRECTOR's own now
# -- the wheel is dead under playback -- but the arithmetic stands on its own reason, and this
# case is what proved that when the round briefly deleted the arm and it went red.
func test_a_base_already_closer_than_the_floor_is_not_pulled_out_to_it() -> void:
	# The floor is on the DOLLY'S CONTRIBUTION, never on the total. A trained distance tuned
	# tighter than the floor gets no push-in; the push-in must not shove the shot back OUT to the
	# floor, which would be the effect doing the opposite of its name on the tightest shots.
	var rig := _rig()
	Pacing.CINEMATIC_DIRECTION = 1.0
	Pacing.DOLLY_IN = 3.0
	Pacing.DOLLY_FLOOR = 4.0
	rig.stash_view()
	rig.set_zoom(2.0)             # the director's base sits well past the floor
	rig.dolly_to(1.0)
	assert_float(rig._dollied_distance()).override_failure_message(
			"the push-in pulled the shot back OUT to the floor -- the contribution cap is gone"
	).is_equal_approx(2.0, 0.0001)


func test_the_plain_board_is_never_pushed_in() -> void:
	# Shares direction_of's fork with the angle and the stoop: whether the plain board gets DIRECTED
	# shots at all is one question with one answer.
	var rig := _rig()
	Pacing.BOARD_DIRECTION = 0.0
	Pacing.CINEMATIC_DIRECTION = 1.0
	Pacing.DOLLY_IN = 3.0
	rig.stash_view()
	rig.set_zoom(14.0)
	# THE PUBLISHED PROFILE, not the setting (#647): the rig mirrors what playback published. Written
	# as a FORK rather than one side, or the BOARD half passes against a rig that reads no profile at
	# all -- which is what a case writing the setting here would silently have become.
	rig.beat_profile = Pacing.Profile.BOARD
	rig.dolly_to(1.0)
	assert_float(rig._dollied_distance()).is_equal_approx(14.0, 0.0001)

	rig.beat_profile = Pacing.Profile.CINEMATIC
	rig.dolly_to(1.0)
	# CLOSER than the player's own zoom, which is the direction a push-in goes -- a relationship
	# rather than a number, so DOLLY_IN stays tunable.
	assert_float(rig._dollied_distance()).override_failure_message(
			"the push-in is identical under both profiles -- the published profile reaches nothing") \
		.is_less(14.0)


func test_the_push_in_dies_with_the_borrowed_view() -> void:
	# The flourish channel's gate, on the zoom axis. The mirror stops polling the moment playback
	# releases, so without this the last beat's push-in would ride into the player's own view.
	var rig := _rig()
	Pacing.CINEMATIC_DIRECTION = 1.0
	Pacing.DOLLY_IN = 3.0
	Pacing.DOLLY_FLOOR = 1.0
	rig.stash_view()
	rig.set_zoom(14.0)
	rig.dolly_to(1.0)
	assert_float(rig._dollied_distance()).is_less(14.0)

	rig.restore_view()
	assert_float(rig._dollied_distance()).override_failure_message(
			"the push-in outlived the pass and followed the player home"
	).is_equal_approx(14.0, 0.0001)


# --- the freeze ----------------------------------------------------------------------------------

func test_a_headless_run_never_freezes() -> void:
	# Pacing.beat's escape, on the one pause that stops the world rather than waiting. Without it a
	# lethal plan would put real wall clock on every suite that resolves one -- and worse, a global
	# time_scale left at 0 by an aborted case would stall every case after it.
	await Pacing.hitstop(self, 0.5)
	assert_bool(Pacing.is_frozen()).override_failure_message(
			"a headless run froze the world -- the suite now pays real seconds per death"
	).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.0001)


func test_a_freeze_of_no_length_is_not_a_freeze() -> void:
	await Pacing.hitstop(self, 0.0)
	assert_bool(Pacing.is_frozen()).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.0001)
