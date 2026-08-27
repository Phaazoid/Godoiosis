extends Object
class_name Pacing

# How long turn playback PAUSES so a human can read it (#118, widened into a beat table by #519).
# Named beside each other so they can be tuned as a set instead of hunted across four files.
#
# Execution is pure playback of an already-resolved plan (R3), so a beat changes only WHEN frames
# land -- never what the queue claimed or what the resolver computed (Law #2).
#
# Every pause routes through beat(), which is where the headless escape lives. That escape is a
# safety property, not a convenience: OrderExecutor.execute_orders is awaited directly by the
# suite, so a literal timer at an await site would put real wall clock on every case that resolves
# a plan.
#
# STATIC VAR, NOT CONST, since #519: every value here is tuned from the Game tab's Playback group,
# and a const is a slider that moves nothing. Same move ATTACK_MODULATE made for #212.

enum Profile { BOARD, CINEMATIC }

# --- the pass beats (#118) -------------------------------------------------------------------

static var AI_SQUAD_PAN := 0.7     # camera glide from squad to squad -- CameraController.pan_to
static var AI_PLAN_READ := 0.6     # AI squad's plan is drawn; hold before it resolves -- AIController
static var AI_ACTION := 0.45       # BOARD base beat on an AI pass -- an unread plan
static var PLAYER_ACTION := 0.3    # BOARD base beat on the player's own Execute (#519)
static var TURN_HANDOFF := 1.0     # hold at every faction turn start -- game.start_faction_turn

# How long the camera takes to reach the next beat's subject, and therefore how long the action
# WAITS for it (#520). Shorter than AI_SQUAD_PAN because that one crosses the board between squads
# while this hops between units already near each other. Fixed duration, not fixed speed: a short
# hop and a long one read at the same pace, which is what makes it a beat rather than a lurch.
static var PLAYBACK_PAN := 0.5

# The END-OF-TURN EFFECT PASS -- today, units standing in fire (#534). TWO numbers of its own
# rather than one scale over the beats above (dev, 2026-08-26: "I don't see controls for the camera
# speed/linger for this post phase"): the fork is who may disagree about a value, and this phase is
# one he tunes AGAINST the others rather than with them.
#
# Neither forks on profile or on whose turn is ending. The BOARD acts here, not a faction, so an
# enemy's fire and yours are the same event and the battle zoom has no drama to add to bookkeeping.
static var ENVIRONMENT_PAN := 0.3    # camera travel to each affected unit
static var ENVIRONMENT_HOLD := 0.45   # the look AFTER the damage lands -- the whole point of the phase

# PLAYER_ACTION was 0.0 from #118 until #519 -- "deliberately none" (dev, 2026-08-10), reversed on
# 2026-08-26: "small pauses everywhere", because a pass with no gap at all is what made the health
# readouts flash in and out (#475, subsumed) and battles read "way too fast".

# --- the beat shape (#519, umbrella #410) ----------------------------------------------------

# CINEMATIC does not fork on whose plan it is: #410 rules the zoom fires for all combats, AI-vs-AI
# included, because an enemy assault deserves the drama too.
static var CINEMATIC_ACTION := 0.4

# What a beat earns for what it WAS. These do not stack -- the loudest single hold wins -- so the
# drama ranking is whatever these NUMBERS say rather than an order written into code. Tune
# HOLD_KNOCKBACK above HOLD_DOWN and a shove outranks a death, deliberately.
static var HOLD_DOWN := 0.9        # a unit goes down, is killed, maimed, or removed from the board
static var HOLD_CRISIS := 0.85      # someone stands up surged instead of falling
static var HOLD_IRON_WILL := 0.45  # the cap BIT: that should have killed them and did not
static var HOLD_KNOCKBACK := 0.6   # the hit shoved its target
static var HOLD_TURNOVER := 0.7    # the act break: the defending line raises weapons
static var HOLD_HEAL := 0.45       # HP came back -- the quiet beat this table had no row for

# The side-channel tail (dev, 2026-08-26: "the side channel actions are going to need emphasis as
# well"). PER VERB rather than one shared number, because a rescue and a reload are not the same
# moment. coda_hold() below is the one lookup.
static var HOLD_RESCUE := 0.2
static var HOLD_RALLY := 0.4
static var HOLD_INTIMIDATE := 0.35
static var HOLD_RELOAD := 0.2
static var HOLD_REV := 0.15
static var HOLD_BURROW := 0.25
static var HOLD_CAPTURE := 0.5
static var HOLD_GUARD := 0.35

# How much of a hold actually applies, per profile. BOARD ships at 0.0 -- flat, "small pauses
# everywhere" (dev, 2026-08-26) -- so the shape exists but is dialled out rather than absent. That
# is the whole reason the holds are separate from the base: wanting shape on the plain board later
# is one number, not a restructure.
static var BOARD_DRAMA := 0.0
static var CINEMATIC_DRAMA := 0.95

# How far the camera turns toward a beat's SIDE-ON angle, per profile (#520) -- 0 leaves the yaw
# exactly where playback squared it up, 1 takes the full profile shot. DRAMA's shape applied to the
# angle instead of the hold, and for the same reason: at 0.0 the BOARD profile is bit-for-bit the
# square-on enemy phase it has always been, so wanting some angle on the plain board later is one
# number rather than a restructure.
static var BOARD_DIRECTION := 0.0
static var CINEMATIC_DIRECTION := 1.0


# Which profile playback is running under. ONE answer, so a caller never re-reads the setting.
static func active_profile() -> Profile:
	return Profile.CINEMATIC if PlayerSettings.is_on(PlayerSettings.Setting.BATTLE_ZOOM) else Profile.BOARD


# How long to hold before this beat. The one collapse from a beat's FACTS to a length -- BeatSheet
# deliberately carries neither a duration nor a severity ranking, because both are this table's.
static func duration_for(beat: BeatSheet.Beat, profile: Profile, is_ai: bool) -> float:
	if beat == null:
		return 0.0
	return base_for(profile, is_ai) + drama_of(profile) * hold_for(beat)


static func base_for(profile: Profile, is_ai: bool) -> float:
	if profile == Profile.CINEMATIC:
		return CINEMATIC_ACTION
	return AI_ACTION if is_ai else PLAYER_ACTION


static func drama_of(profile: Profile) -> float:
	return CINEMATIC_DRAMA if profile == Profile.CINEMATIC else BOARD_DRAMA


static func direction_of(profile: Profile) -> float:
	return CINEMATIC_DIRECTION if profile == Profile.CINEMATIC else BOARD_DIRECTION


# The loudest hold this beat earns, by VALUE rather than by rung order (see the holds above).
static func hold_for(beat: BeatSheet.Beat) -> float:
	if beat.kind == BeatSheet.Kind.TURNOVER:
		return HOLD_TURNOVER
	if beat.kind == BeatSheet.Kind.CODA:
		# Floored, so an undeclared verb degrades to no hold rather than a negative beat. The law
		# test is what actually refuses one -- a silent 0 in play is not a signal anybody sees.
		return maxf(0.0, coda_hold(beat.coda_type))
	var hold := 0.0
	if beat.has_removal \
			or beat.has_lethality(ResolvedOutcome.Lethality.DOWNED) \
			or beat.has_lethality(ResolvedOutcome.Lethality.KILLED) \
			or beat.has_lethality(ResolvedOutcome.Lethality.MAIMED):
		hold = maxf(hold, HOLD_DOWN)
	if beat.has_lethality(ResolvedOutcome.Lethality.CRISIS):
		hold = maxf(hold, HOLD_CRISIS)
	if beat.iron_will_held:
		hold = maxf(hold, HOLD_IRON_WILL)
	if beat.has_knockback:
		hold = maxf(hold, HOLD_KNOCKBACK)
	if beat.has_heal:
		hold = maxf(hold, HOLD_HEAL)
	return hold


# How long one side-channel verb holds. -1.0 for a verb nobody has declared one for, which is what
# makes the omission VISIBLE: an undeclared verb is indistinguishable from a deliberate 0 otherwise,
# and tests/law/test_action_registry.gd refuses the negative.
static func coda_hold(type: BaseAction.ActionType) -> float:
	match type:
		BaseAction.ActionType.RESCUE: return HOLD_RESCUE
		BaseAction.ActionType.RALLY: return HOLD_RALLY
		BaseAction.ActionType.INTIMIDATE: return HOLD_INTIMIDATE
		BaseAction.ActionType.RELOAD: return HOLD_RELOAD
		BaseAction.ActionType.REV: return HOLD_REV
		BaseAction.ActionType.BURROW: return HOLD_BURROW
		BaseAction.ActionType.CAPTURE: return HOLD_CAPTURE
		BaseAction.ActionType.GUARD: return HOLD_GUARD
	return -1.0


static func beat(host: Node, seconds: float) -> void:
	if seconds <= 0.0 or DisplayServer.get_name() == "headless":
		return
	await host.get_tree().create_timer(seconds).timeout
