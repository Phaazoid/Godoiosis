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


func before_test() -> void:
	PlayerSettings.reset_for_test()
	_saved = {
		"player": Pacing.PLAYER_ACTION, "ai": Pacing.AI_ACTION, "cine": Pacing.CINEMATIC_ACTION,
		"bd": Pacing.BOARD_DRAMA, "cd": Pacing.CINEMATIC_DRAMA,
		"down": Pacing.HOLD_DOWN, "crisis": Pacing.HOLD_CRISIS, "iron": Pacing.HOLD_IRON_WILL,
		"knock": Pacing.HOLD_KNOCKBACK, "turn": Pacing.HOLD_TURNOVER, "heal": Pacing.HOLD_HEAL, "post": Pacing.POST_TURN_SCALE,
		"rescue": Pacing.HOLD_RESCUE, "rally": Pacing.HOLD_RALLY, "intim": Pacing.HOLD_INTIMIDATE,
		"reload": Pacing.HOLD_RELOAD, "rev": Pacing.HOLD_REV, "burrow": Pacing.HOLD_BURROW,
		"capture": Pacing.HOLD_CAPTURE, "guard": Pacing.HOLD_GUARD,
	}


func after_test() -> void:
	Pacing.PLAYER_ACTION = _saved["player"]
	Pacing.AI_ACTION = _saved["ai"]
	Pacing.CINEMATIC_ACTION = _saved["cine"]
	Pacing.BOARD_DRAMA = _saved["bd"]
	Pacing.CINEMATIC_DRAMA = _saved["cd"]
	Pacing.HOLD_DOWN = _saved["down"]
	Pacing.HOLD_CRISIS = _saved["crisis"]
	Pacing.HOLD_IRON_WILL = _saved["iron"]
	Pacing.HOLD_KNOCKBACK = _saved["knock"]
	Pacing.HOLD_TURNOVER = _saved["turn"]
	Pacing.POST_TURN_SCALE = _saved["post"]
	Pacing.HOLD_HEAL = _saved["heal"]
	Pacing.HOLD_RESCUE = _saved["rescue"]
	Pacing.HOLD_RALLY = _saved["rally"]
	Pacing.HOLD_INTIMIDATE = _saved["intim"]
	Pacing.HOLD_RELOAD = _saved["reload"]
	Pacing.HOLD_REV = _saved["rev"]
	Pacing.HOLD_BURROW = _saved["burrow"]
	Pacing.HOLD_CAPTURE = _saved["capture"]
	Pacing.HOLD_GUARD = _saved["guard"]
	PlayerSettings.reset_for_test()


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


# --- the post-turn pass (#534) ------------------------------------------------------------------

# The end-of-turn effect pass runs QUICKER than a blast -- the dev's "double speed" -- and it says
# so as a RELATIONSHIP to the beats he tunes rather than as a second set of numbers. Both halves
# scale together (the camera travel and the pause), which is the whole reason it is one knob.
func test_the_post_turn_pass_runs_quicker_than_a_blast() -> void:
	Pacing.POST_TURN_SCALE = 0.5
	assert_float(Pacing.PLAYBACK_PAN * Pacing.POST_TURN_SCALE) \
		.override_failure_message("the post-turn camera travel is no quicker than a blast's") \
		.is_less(Pacing.PLAYBACK_PAN)
	assert_float(Pacing.base_for(CINEMATIC, false) * Pacing.POST_TURN_SCALE) \
		.override_failure_message("the post-turn pause is no shorter than a blast's") \
		.is_less(Pacing.base_for(CINEMATIC, false))

	# ...and the knob really is the dial: above 1 the phase is the slower one.
	Pacing.POST_TURN_SCALE = 2.0
	assert_float(Pacing.PLAYBACK_PAN * Pacing.POST_TURN_SCALE).is_greater(Pacing.PLAYBACK_PAN)


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
