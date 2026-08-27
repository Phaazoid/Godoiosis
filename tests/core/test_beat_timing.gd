# The beat table (#519, umbrella #410): how a BeatSheet.Beat's facts become a pause length.
#
# NOTHING HERE ASSERTS WHAT A VALUE IS. Every one of these numbers is tuned by feel from the Game
# tab's Playback group, and tuning must never redden the suite -- test_pacing.gd's own law says so
# and this is its sibling. So every case pins a RELATIONSHIP that survives any tuning: which beat
# outlasts which, which profile is the quieter one, whether a fork exists at all.
#
# Pacing's values are static vars that outlive a case, so the whole table is snapshotted and put
# back around each one -- a suite that tuned a knob and walked away would poison every case after
# it, which is exactly the class of bug #449 found in PlayerSettings.
extends GdUnitTestSuite

const BOARD := Pacing.Profile.BOARD
const CINEMATIC := Pacing.Profile.CINEMATIC

var _saved: Dictionary = {}


# DERIVED from the knob table rather than named, since #520 2b slice 2 -- the fix #450 already made
# in test_game_knobs, for this exact shape. A hand-written list of statics is a COPY of "which values
# this suite can move", and it can only go stale in the SILENT direction: a value added without its
# restore poisons every later case in the RUN, not just in this file. The list had already grown to
# eighteen by hand and this ticket would have added twelve more.
#
# Keyed by NAME through read_static/write_static, the same pair the panel uses -- and filtered to the
# PACING rows, since those are the only statics this suite touches. A null host is safe for exactly
# them: every Pacing arm assigns and returns, with no re-apply sweep to reach a scene through.
func before_test() -> void:
	PlayerSettings.reset_for_test()
	_saved = {}
	for knob: Dictionary in GameKnobs.CLASS_KNOBS:
		if not knob.has("static") or knob.get("script", "") != GameKnobs.PACING_SCRIPT:
			continue
		var current: Variant = GameKnobs.read_static(knob["static"])
		if typeof(current) == TYPE_NIL:
			continue   # a missing READ arm is test_every_class_knob_resolves' finding, not ours
		_saved[knob["static"]] = current


func after_test() -> void:
	for name: String in _saved:
		GameKnobs.write_static(null, name, _saved[name])
	PlayerSettings.reset_for_test()


# The guard on the derivation above, and the lesson the hand-list paid twice: a snapshot that
# silently covers NOTHING restores nothing. If the Pacing rows are ever renamed out from under this
# filter, that is the failure to see -- not a suite that quietly stops protecting the run.
func test_the_snapshot_actually_covers_the_table() -> void:
	assert_int(_saved.size()).override_failure_message(
			"the Pacing snapshot is empty -- every case here now leaks its tuning into the whole run") \
		.is_greater(10)
	for name: String in ["HOLD_ATTACK", "HOLD_DOWN", "LINGER_ATTACK", "LINGER_DOWN"]:
		assert_bool(_saved.has(name)).override_failure_message(
				"%s is not covered by the snapshot" % name).is_true()


# --- the profile fork -------------------------------------------------------------------------

# The dev's 2026-08-26 ruling, as a property rather than a number: with the zoom OFF every blast
# holds for the same length, whatever happened in it. Ships as BOARD_DRAMA = 0.
func test_the_board_profile_paces_a_kill_and_a_scratch_alike() -> void:
	assert_float(Pacing.duration_for(_kill(), BOARD, false)) \
		.override_failure_message("BOARD ships FLAT -- a death and a scratch hold the same") \
		.is_equal_approx(Pacing.duration_for(_chip(), BOARD, false), 0.0001)


# ... and the shape is DIALLED OUT, not absent: raising the one multiplier brings it back without
# any other change. That is the whole reason the holds are separate from the base.
func test_raising_board_drama_brings_the_shape_back() -> void:
	Pacing.BOARD_DRAMA = 1.0
	assert_float(Pacing.duration_for(_kill(), BOARD, false)) \
		.is_greater(Pacing.duration_for(_chip(), BOARD, false))


func test_the_cinematic_profile_holds_longer_on_a_kill_than_on_a_scratch() -> void:
	assert_float(Pacing.duration_for(_kill(), CINEMATIC, false)) \
		.is_greater(Pacing.duration_for(_chip(), CINEMATIC, false))


# --- whose pass it is -------------------------------------------------------------------------

# BOARD keeps #118's fork: an AI plan is being read for the first time, a player's was authored by
# the person watching it.
func test_board_still_paces_an_ai_pass_apart_from_the_players_own() -> void:
	assert_float(Pacing.duration_for(_chip(), BOARD, true)) \
		.is_not_equal(Pacing.duration_for(_chip(), BOARD, false))


# CINEMATIC drops it: #410 rules the zoom fires for every combat, enemy assaults included.
func test_the_zoom_does_not_care_whose_pass_it_is() -> void:
	assert_float(Pacing.duration_for(_kill(), CINEMATIC, true)) \
		.is_equal_approx(Pacing.duration_for(_kill(), CINEMATIC, false), 0.0001)


# --- the holds --------------------------------------------------------------------------------

# Holds do NOT stack -- the loudest single one wins -- and "loudest" is read off the NUMBERS, so
# the drama ranking is tunable rather than written into code. Falsifiable both ways: this case
# fails if they sum, and fails again if the ranking is hardcoded by rung.
func test_the_loudest_hold_wins_and_the_ranking_follows_the_knobs() -> void:
	Pacing.HOLD_DOWN = 0.5
	Pacing.HOLD_KNOCKBACK = 0.1
	var both := _kill()
	both.has_knockback = true
	# Not the sum: the death alone decides it.
	assert_float(Pacing.hold_for(both)).is_equal_approx(0.5, 0.0001)

	# Now make a shove the louder thing. Nothing else changes.
	Pacing.HOLD_KNOCKBACK = 0.9
	assert_float(Pacing.hold_for(both)).is_equal_approx(0.9, 0.0001)


func test_the_turnover_beat_earns_the_turnover_hold() -> void:
	Pacing.HOLD_TURNOVER = 0.77
	assert_float(Pacing.hold_for(_turnover())).is_equal_approx(0.77, 0.0001)


# An Iron Will save is its OWN beat, not a quiet one: the cap bit, so something happened. Pinned
# because the beat carries no lethality at all in that case -- the unit is still standing.
func test_an_iron_will_save_outlasts_a_plain_scratch() -> void:
	var held := _chip()
	held.iron_will_held = true
	assert_float(Pacing.duration_for(held, CINEMATIC, false)) \
		.is_greater(Pacing.duration_for(_chip(), CINEMATIC, false))


# A heal is a thing that HAPPENED -- HP came back -- and until 2026-08-26 the table had no clause
# for it, so it earned the bare base beat: the flattest moment a pass could contain, in the profile
# that exists to make moments land. The dev found it in play ("the heal in the counter attack felt
# left out of focus"); the camera was already going there, the beat was not.
func test_a_heal_outlasts_a_plain_scratch() -> void:
	var mended := _chip()
	mended.has_heal = true
	assert_float(Pacing.duration_for(mended, CINEMATIC, false)) \
		.is_greater(Pacing.duration_for(_chip(), CINEMATIC, false))


# ... and it takes part in the same by-VALUE ranking as everything else, rather than sitting
# outside it: a heal that also killed somebody holds for whichever knob is larger.
func test_a_heal_that_also_killed_takes_the_louder_knob() -> void:
	Pacing.HOLD_HEAL = 0.2
	Pacing.HOLD_DOWN = 0.8
	var both := _kill()
	both.has_heal = true
	assert_float(Pacing.hold_for(both)).is_equal_approx(0.8, 0.0001)

	Pacing.HOLD_HEAL = 1.5
	assert_float(Pacing.hold_for(both)).is_equal_approx(1.5, 0.0001)


# --- the side-channel tail --------------------------------------------------------------------

# Each verb holds for its OWN knob, not one shared coda number -- a rescue and a reload are not the
# same moment. Pinned as the relationship rather than the values, and driven from the knobs so a
# hardcoded ranking would fail the second half.
func test_each_side_channel_verb_holds_for_its_own_knob() -> void:
	Pacing.HOLD_RESCUE = 0.9
	Pacing.HOLD_RELOAD = 0.1
	assert_float(Pacing.hold_for(_coda(BaseAction.ActionType.RESCUE))) \
		.is_greater(Pacing.hold_for(_coda(BaseAction.ActionType.RELOAD)))

	# Swap which one is loud. Nothing else changes.
	Pacing.HOLD_RESCUE = 0.1
	Pacing.HOLD_RELOAD = 0.9
	assert_float(Pacing.hold_for(_coda(BaseAction.ActionType.RELOAD))) \
		.is_greater(Pacing.hold_for(_coda(BaseAction.ActionType.RESCUE)))


# hold_for FLOORS coda_hold's -1.0 sentinel, so an undeclared verb degrades to no hold in play
# instead of subtracting from the base beat. The law suite is what refuses the omission; this pins
# that the floor exists, since a negative reaching duration_for would shorten a real pause.
func test_an_undeclared_verb_never_shortens_the_beat() -> void:
	var stray := _coda(BaseAction.ActionType.ATTACK)   # never a side-channel verb
	assert_float(Pacing.coda_hold(BaseAction.ActionType.ATTACK)).is_less(0.0)
	assert_float(Pacing.hold_for(stray)).is_equal_approx(0.0, 0.0001)
	assert_float(Pacing.duration_for(stray, CINEMATIC, false)) \
		.is_equal_approx(Pacing.base_for(CINEMATIC, false), 0.0001)


# --- which profile is live --------------------------------------------------------------------

func test_the_profile_follows_the_battle_zoom_setting() -> void:
	PlayerSettings.set_on(PlayerSettings.Setting.BATTLE_ZOOM, true)
	assert_int(Pacing.active_profile()).is_equal(CINEMATIC)
	PlayerSettings.set_on(PlayerSettings.Setting.BATTLE_ZOOM, false)
	assert_int(Pacing.active_profile()).is_equal(BOARD)


# --- the safety property, on the new path -----------------------------------------------------

# test_pacing.gd pins this for beat() itself; repeated here because duration_for is a NEW way to
# reach it, and a table that can return a big number is exactly what would put wall clock on the
# nine suites that await execute_orders.
func test_a_computed_beat_still_costs_a_headless_run_nothing() -> void:
	assert_str(DisplayServer.get_name()).is_equal("headless")
	Pacing.CINEMATIC_ACTION = 30.0
	Pacing.HOLD_CRISIS = 30.0
	var before := Engine.get_process_frames()
	await Pacing.beat(self, Pacing.duration_for(_crisis(), CINEMATIC, false))
	assert_int(Engine.get_process_frames() - before) \
		.override_failure_message("a computed beat waited headlessly -- every resolve pass now pays wall clock") \
		.is_equal(0)


# --- beat builders ----------------------------------------------------------------------------

# --- the ladder's FLOOR, and the linger (#520 2b slice 2) --------------------------------------

# The dev's finding: "I don't see controls for holding the most common thing - a regular attack."
# A plain hit used to earn hold = 0 and take the bare base beat, which is also why every rung above
# it was a number with no zero point. Asserted as the RELATIONSHIP, never as a value.
func test_a_plain_hit_earns_the_attack_hold_rather_than_nothing() -> void:
	Pacing.HOLD_ATTACK = 0.3
	assert_float(Pacing.hold_for(_chip())).override_failure_message(
			"a blast that only did damage earned no hold at all -- the ladder has no floor") \
		.is_equal_approx(0.3, 0.0001)


func test_the_attack_hold_is_a_floor_and_not_a_ceiling() -> void:
	# Largest-wins, seeded from the floor: a louder rung must still win, and a floor tuned ABOVE one
	# must lift it. Both directions, because "seed from HOLD_ATTACK" and "return HOLD_ATTACK" pass
	# the first half identically.
	Pacing.HOLD_ATTACK = 0.1
	Pacing.HOLD_DOWN = 0.9
	assert_float(Pacing.hold_for(_kill())).override_failure_message(
			"the floor swallowed a death -- it is seeding the ladder, not capping it") \
		.is_equal_approx(0.9, 0.0001)

	Pacing.HOLD_ATTACK = 1.5
	assert_float(Pacing.hold_for(_kill())).override_failure_message(
			"a floor tuned above the death rung did not lift it") \
		.is_equal_approx(1.5, 0.0001)


# A CODA is unaffected by the floor: it answers per verb, and its own rung is the whole answer.
func test_the_attack_floor_does_not_reach_the_side_channel_tail() -> void:
	Pacing.HOLD_ATTACK = 2.0
	Pacing.HOLD_RELOAD = 0.1
	assert_float(Pacing.hold_for(_coda(BaseAction.ActionType.RELOAD))).override_failure_message(
			"the attack floor lifted a reload -- coda_hold is meant to be the whole answer there") \
		.is_equal_approx(0.1, 0.0001)


# The other side of the beat. Same ladder shape, one rung: what makes a beat longer to WATCH is how
# much debris it threw, and only a death empties the grid.
func test_a_death_lingers_longer_than_a_plain_hit() -> void:
	assert_float(Pacing.linger_for(_kill())).override_failure_message(
			"a death left the screen as fast as a scratch -- the whole grid bursts on one and not the other") \
		.is_greater(Pacing.linger_for(_chip()))


func test_a_coda_lingers_for_its_own_verb() -> void:
	Pacing.LINGER_RESCUE = 0.9
	Pacing.LINGER_RELOAD = 0.1
	assert_float(Pacing.linger_for(_coda(BaseAction.ActionType.RESCUE))) \
		.is_greater(Pacing.linger_for(_coda(BaseAction.ActionType.RELOAD)))


# Punctuation has no action to stay after, so it earns no linger -- unlike hold_for, where a
# TURNOVER has a rung of its own. The two sides of the beat are deliberately not symmetric here.
func test_punctuation_earns_no_linger() -> void:
	assert_float(Pacing.linger_for(_turnover())).override_failure_message(
			"the act break lingered -- there is no action there to stay after") \
		.is_equal_approx(0.0, 0.0001)
	assert_float(Pacing.linger_for(null)).is_equal_approx(0.0, 0.0001)


# coda_linger carries coda_hold's sentinel for the same reason, and linger_for floors it for the
# same reason: an undeclared verb must degrade to no wait rather than a negative one.
func test_an_undeclared_verb_never_shortens_the_linger() -> void:
	var stray := _coda(BaseAction.ActionType.ATTACK)   # never a side-channel verb
	assert_float(Pacing.coda_linger(BaseAction.ActionType.ATTACK)).is_less(0.0)
	assert_float(Pacing.linger_for(stray)).is_equal_approx(0.0, 0.0001)


# The linger is FLAT -- the one place it deliberately differs from the hold. A hold is anticipation
# and scales with drama; a linger is matched to an animation that runs in real time either way.
# Falsified against the alternative: multiply it by drama_of and this reds, because BOARD_DRAMA
# ships at 0 and the plain board would get no linger at all.
func test_the_linger_does_not_fork_on_the_profile() -> void:
	Pacing.BOARD_DRAMA = 0.0
	Pacing.CINEMATIC_DRAMA = 3.0
	# linger_for takes no profile at all, which is the property -- so the assertion is that the one
	# answer is non-zero while the two drama values it might have been scaled by differ wildly.
	assert_float(Pacing.linger_for(_kill())).override_failure_message(
			"the board profile lingers for nothing -- it has been scaled by drama, which ships at 0") \
		.is_greater(0.0)


func _chip() -> BeatSheet.Beat:
	var beat := BeatSheet.Beat.new()
	beat.kind = BeatSheet.Kind.VOLLEY
	beat.lethalities.append(ResolvedOutcome.Lethality.NONE)
	return beat


func _kill() -> BeatSheet.Beat:
	var beat := BeatSheet.Beat.new()
	beat.kind = BeatSheet.Kind.VOLLEY
	beat.lethalities.append(ResolvedOutcome.Lethality.KILLED)
	return beat


func _crisis() -> BeatSheet.Beat:
	var beat := BeatSheet.Beat.new()
	beat.kind = BeatSheet.Kind.VOLLEY
	beat.lethalities.append(ResolvedOutcome.Lethality.CRISIS)
	return beat


func _turnover() -> BeatSheet.Beat:
	var beat := BeatSheet.Beat.new()
	beat.kind = BeatSheet.Kind.TURNOVER
	beat.is_counter = true
	return beat


func _coda(type: BaseAction.ActionType) -> BeatSheet.Beat:
	var beat := BeatSheet.Beat.new()
	beat.kind = BeatSheet.Kind.CODA
	beat.coda_type = type
	return beat
