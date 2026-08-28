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
#
# HOLD_ATTACK is the LADDER'S FLOOR (dev, 2026-08-27: "I don't see controls for holding the most
# common thing - a regular attack"). Every rung above it is extra time a beat EARNS, so without a
# floor the commonest beat of all -- a hit that just does damage -- earned nothing and took the bare
# base beat, and every other number here was a figure with no zero point to be read against.
# hold_for seeds from it rather than from 0.0; it is not in coda_hold, which answers for side-channel
# VERBS and must go on reporting ATTACK as undeclared.
static var HOLD_ATTACK := 0.25     # a hit that just does damage -- the floor the rest are read against
static var HOLD_DOWN := 0.9        # a unit goes down, is killed, maimed, or removed from the board
static var HOLD_CRISIS := 0.85      # someone stands up surged instead of falling
static var HOLD_IRON_WILL := 0.45  # the cap BIT: that should have killed them and did not
static var HOLD_KNOCKBACK := 0.8   # the hit shoved its target
static var HOLD_TURNOVER := 0.8    # the act break: the defending line raises weapons
static var HOLD_HEAL := 0.8       # HP came back -- the quiet beat this table had no row for

# The side-channel tail (dev, 2026-08-26: "the side channel actions are going to need emphasis as
# well"). PER VERB rather than one shared number, because a rescue and a reload are not the same
# moment. coda_hold() below is the one lookup.
static var HOLD_RESCUE := 0.5
static var HOLD_RALLY := 0.5
static var HOLD_INTIMIDATE := 0.5
static var HOLD_RELOAD := 0.5
static var HOLD_REV := 0.5
static var HOLD_BURROW := 0.5
static var HOLD_CAPTURE := 0.5
static var HOLD_GUARD := 0.5
static var HOLD_OVERWATCH := 0.5

# --- the LINGER: how long the camera stays AFTER an action plays (dev, 2026-08-27) --------------
#
# Every pause above lands BEFORE its action, which was right when a beat had nothing to watch on the
# way out and wrong the moment health readouts gained debris: the cubes burst on UnitMirror's own HP
# poll, fly for HealthBlockDebris.lifetime, and nothing ever waited for them -- so the last counter
# killed someone and the pass cut away mid-explosion. The dev's report: "after the last counter
# attack, we're still not waiting for the cubes to break off, the game just instantly transitions
# back", widened to every verb: "even basic attacks knock away health cubes and we want that focused
# too."
#
# FLAT -- no profile, no is_ai, and deliberately not multiplied by drama_of. A hold is anticipation
# and scales with how dramatic you want the pass to feel; a linger is matched to an ANIMATION that
# runs in real time whichever profile is live. Drama-scaling it would give the plain board none at
# all (BOARD_DRAMA ships at 0.0), which is the instant cut this exists to close. If the board ever
# wants its own pace here, linger_for is the one place that forks.
#
# One per ACTION (the dev's own axis), plus a single OUTCOME rung: a death bursts the whole
# remaining grid at block_death_power rather than chipping a few cubes off it, so it is categorically
# a longer thing to watch. Same largest-wins rule as the holds.
static var LINGER_ATTACK := 0.45
static var LINGER_DOWN := 1.0      # the whole grid goes at once -- the loudest thing to watch
static var LINGER_RESCUE := 0.3
static var LINGER_RALLY := 0.3
static var LINGER_INTIMIDATE := 0.3
static var LINGER_RELOAD := 0.2
static var LINGER_REV := 0.2
static var LINGER_BURROW := 0.3
static var LINGER_CAPTURE := 0.4
static var LINGER_GUARD := 0.3
static var LINGER_OVERWATCH := 0.3

# How much of a hold actually applies, per profile. BOARD ships at 0.0 -- flat, "small pauses
# everywhere" (dev, 2026-08-26) -- so the shape exists but is dialled out rather than absent. That
# is the whole reason the holds are separate from the base: wanting shape on the plain board later
# is one number, not a restructure.
static var BOARD_DRAMA := 0.0
static var CINEMATIC_DRAMA := 0.65

# How far the camera turns toward a beat's SIDE-ON angle, per profile (#520) -- 0 leaves the yaw
# exactly where playback squared it up, 1 takes the full profile shot. DRAMA's shape applied to the
# angle instead of the hold, and for the same reason: at 0.0 the BOARD profile is bit-for-bit the
# square-on enemy phase it has always been, so wanting some angle on the plain board later is one
# number rather than a restructure.
static var BOARD_DIRECTION := 0.0
static var CINEMATIC_DIRECTION := 1.0

# --- the flourish channels: what the camera does BESIDES going somewhere (#520 diff 2b) ---------
#
# Three effects that are not "where the camera looks" but a displacement laid over it. They share
# one gate (the rig only flourishes while playback has BORROWED the view) and split on one axis:
# whether the effect is anticipation, which the profile dials, or a match to an animation that runs
# in real time either way, which it must not.

# How many degrees SHALLOWER than the board's authored pitch a directed beat takes the shot -- the
# camera comes down toward the fight's own eye level so the blow looms, instead of being read from
# the strategist's overhead angle. Its own magnitude, but it shares direction_of's profile fork with
# the yaw: whether the plain board gets directed shots at all is ONE question, and it already has an
# answer. How far each axis swings under that answer is two.
#
# The shallow end is also where a billboard is being looked at from the angle its art IS drawn for,
# so the drama and the HD-2D conceit want the same direction here. Clamped into the same band the
# player's own drag is (min/max_pitch_degrees): that band is an ART limit, so it binds every writer.
static var PITCH_DIVE := 10.0

# The impact jolt, in world units of camera displacement. FLAT across profiles, and that follows the
# LINGER's reasoning rather than the hold's: the health cubes burst on their own real-time clock in
# both profiles, and an impact matched to them must too. Drama-scaling would give the plain board
# none at all (BOARD_DRAMA ships 0.0), which is the same instant-cut hole the linger exists to close.
#
# Two rungs, not a damage curve. A hit and a death are categorically different moments -- and they
# cannot double-fire, because UnitMirror's HP poll never observes a unit at 0 HP (die() emits and
# queue_frees in one frame), so a killing blow reaches the death rung ONLY.
static var SHAKE_HIT := 0.16
static var SHAKE_DOWN := 0.4
static var SHAKE_DECAY := 11.0     # how fast the jolt dies, e-folds per second
static var SHAKE_FREQUENCY := 32.0 # how fast it oscillates, radians per second

# The resting hand-held drift, in world units. ANTICIPATION rather than a match, so unlike the shake
# it forks on profile exactly as drama and direction do -- BOARD ships 0.0 and the plain board is
# bit-for-bit as still as it has always been.
static var SWAY_AMPLITUDE := 0.05
static var SWAY_SPEED := 0.9       # radians per second of the primary bob
static var BOARD_SWAY := 0.0
static var CINEMATIC_SWAY := 1.0

# --- lethality-aware direction (#520 diff 2c) ---------------------------------------------------
#
# The director knows the ending before it shoots the scene: every ResolvedOutcome carries its rung
# before playback starts, so a beat that is about to kill someone can be SHOT differently rather
# than merely held longer. The wind-up was already built -- hold_for's HOLD_DOWN rung is a killing
# blow holding three times as long as a scratch -- so what is here is the push-in and the freeze.

# How far the camera pushes IN on the loudest beat, in world units of camera distance. Subtracted
# from wherever the player has left the zoom, never assigned over it: the wheel stays theirs through
# a pass (#520, dev 2026-08-26) and a per-beat set_zoom is exactly the leash that ruling refuses.
#
# Scaled by direction_of, the same fork the side-on angle and the pitch stoop use -- whether the
# plain board gets DIRECTED shots at all is one question and it already has an answer.
static var DOLLY_IN := 2.5
# ...and the floor the dolly's OWN CONTRIBUTION respects. There is no zoom-in floor on this rig by
# dev ruling (asked twice, "please remove it entirely"), and scrolling past the aim point takes the
# camera through its target to look back -- his call, for HIS hand. A director inheriting that hole
# would fly the camera through a unit on the exact beat it most wants to be looking at one.
#
# So this floors what the DOLLY adds, never the total: a player already closer than this keeps their
# distance untouched and simply gets no push-in, which is why it cannot re-introduce the floor the
# ruling removed.
static var DOLLY_FLOOR := 4.0

# The RUNGS, 0..1, and they are the holds' ladder asked a different question -- how big is this
# moment, rather than how long to wait before it. Their own numbers because the two rankings may
# legitimately disagree: a held breath (iron will) is worth a long PAUSE and not much of a push-in,
# while a death wants both. An ordinary blast earns 0 and is the baseline the rest are read against.
static var EMPHASIS_DOWN := 1.0
static var EMPHASIS_CRISIS := 0.8
static var EMPHASIS_IRON_WILL := 0.5

# How long everything stops when a killing blow lands, in REAL seconds. A freeze creates time rather
# than matching an animation that is already running, so unlike the linger it is DRAMA and forks on
# profile -- BOARD ships 0.0, both because the plain board has never had one and because zoom-off
# pacing is already the standing question from the linger slice; it should not gain a time-freeze
# unasked.
static var HITSTOP_DOWN := 0.09
static var BOARD_HITSTOP := 0.0
static var CINEMATIC_HITSTOP := 1.0


# What mode the player has the zoom in. ONE read of the setting, so nothing else names it.
static func zoom_mode() -> PlayerSettings.BattleZoom:
	return PlayerSettings.choice_of(PlayerSettings.Setting.BATTLE_ZOOM_MODE) as PlayerSettings.BattleZoom


# WHICH PROFILE THIS BEAT RUNS UNDER (#647) -- the one collapse from (mode, beat) to a profile, and
# duration_for's shape one question over: that one collapses a beat's facts to a LENGTH, this one to
# the pacing it is played at.
#
# It replaced `active_profile()`, which answered for the whole pass. Once COMBAT_ONLY exists there is
# no such answer -- a move and the volley after it run under different profiles -- so a global would
# be a seam that quietly mis-answers rather than one that fails (Law #4). Every caller now names the
# beat it is asking about, and the ones with no beat in hand read CameraController.beat_profile,
# which is this answer PUBLISHED (#520's channel, one field further).
static func profile_for(beat: BeatSheet.Beat) -> Profile:
	match zoom_mode():
		PlayerSettings.BattleZoom.OFF:
			return Profile.BOARD
		PlayerSettings.BattleZoom.COMBAT_ONLY:
			return Profile.CINEMATIC if is_combat_beat(beat) else Profile.BOARD
	return Profile.CINEMATIC


# Is a unit dealing or taking damage in this beat (dev, 2026-08-28)? The VOLLEY is the blow itself;
# the TURNOVER is the act break where the defending line raises weapons, and it is cinematic because
# it is punctuation INSIDE a fight -- dropping to plain for it would cut the exchange in half between
# an attack and its counter.
#
# MOVES and CODA are the walk and the side-channel verbs, neither of which is a blow. CELL_EFFECTS is
# the edge the wording could have reached -- a unit standing in fire IS taking damage -- and it stays
# plain rather than reversing a standing call: the environment pass forks on neither profile nor
# faction, because the board acts there and the zoom has no drama to add to bookkeeping.
static func is_combat_beat(beat: BeatSheet.Beat) -> bool:
	if beat == null:
		return false
	return beat.kind == BeatSheet.Kind.VOLLEY or beat.kind == BeatSheet.Kind.TURNOVER


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


# ...and the sway's, the third of the same shape. Shake has no such fork on purpose -- see its rows.
static func sway_of(profile: Profile) -> float:
	return CINEMATIC_SWAY if profile == Profile.CINEMATIC else BOARD_SWAY


# ...and the hitstop's, the fourth of the same shape.
static func hitstop_of(profile: Profile) -> float:
	return CINEMATIC_HITSTOP if profile == Profile.CINEMATIC else BOARD_HITSTOP


# HOW BIG A MOMENT THIS IS, 0..1 (#520 diff 2c) -- hold_for's twin, and deliberately its own answer
# rather than a rescaling of it. That one returns SECONDS, and a number meaning two things is the
# duplicate seam Law #4 refuses; this is the same beat's facts collapsed for the CAMERA instead.
#
# Same structure as the holds: seeded from nothing, LOUDEST SINGLE ONE WINS BY VALUE, so the ranking
# between rungs is tunable rather than written into the code. A beat that only does damage earns
# nothing at all -- an ordinary blast is the baseline the rest are read against, exactly as
# HOLD_ATTACK is the floor over there.
static func emphasis_for(beat: BeatSheet.Beat) -> float:
	if beat == null or beat.kind != BeatSheet.Kind.VOLLEY:
		return 0.0
	var emphasis := 0.0
	if beat.has_removal \
			or beat.has_lethality(ResolvedOutcome.Lethality.DOWNED) \
			or beat.has_lethality(ResolvedOutcome.Lethality.KILLED) \
			or beat.has_lethality(ResolvedOutcome.Lethality.MAIMED):
		emphasis = maxf(emphasis, EMPHASIS_DOWN)
	if beat.has_lethality(ResolvedOutcome.Lethality.CRISIS):
		emphasis = maxf(emphasis, EMPHASIS_CRISIS)
	if beat.iron_will_held:
		emphasis = maxf(emphasis, EMPHASIS_IRON_WILL)
	return emphasis


# The FREEZE (#520 diff 2c), beside beat() because it is a playback pause and this file is the one
# declared table of those -- it just spends its time by stopping the world rather than by waiting.
#
# Engine.time_scale is a GLOBAL, so three things are load-bearing. The unfreeze timer is created with
# ignore_time_scale TRUE, or it would be frozen by the very freeze it exists to end and hang the game
# outright. Re-entry is counted rather than ignored: a volley that kills two fires twice, and without
# the count the first restore would end the second freeze early and the two would race. And the
# restore writes 1.0 literally, which is correct only while nothing else in the project writes
# time_scale -- true today (grepped), and this comment is where to look the day it stops being.
#
# Headless returns immediately, the escape beat() carries and for the same reason: nobody is watching,
# and a real freeze would put wall clock on every suite that resolves a lethal plan.
static var _frozen_count := 0

static func hitstop(host: Node, seconds: float) -> void:
	if seconds <= 0.0 or DisplayServer.get_name() == "headless":
		return
	_frozen_count += 1
	Engine.time_scale = 0.0
	await host.get_tree().create_timer(seconds, true, false, true).timeout
	_frozen_count -= 1
	if _frozen_count <= 0:
		_frozen_count = 0
		Engine.time_scale = 1.0


# Whether the world is stopped right now. Nothing in the game reads it; it exists so a test can ask
# without reaching for Engine.time_scale, which is global state a case must not leave dirty.
static func is_frozen() -> bool:
	return _frozen_count > 0


# The loudest hold this beat earns, by VALUE rather than by rung order (see the holds above).
static func hold_for(beat: BeatSheet.Beat) -> float:
	if beat.kind == BeatSheet.Kind.TURNOVER:
		return HOLD_TURNOVER
	if beat.kind == BeatSheet.Kind.CODA:
		# Floored, so an undeclared verb degrades to no hold rather than a negative beat. The law
		# test is what actually refuses one -- a silent 0 in play is not a signal anybody sees.
		return maxf(0.0, coda_hold(beat.coda_type))
	# Seeded from the FLOOR, not from zero: a volley that only does damage is still a blast, and
	# every rung below is extra time measured against this one (#520, dev 2026-08-27).
	var hold := HOLD_ATTACK
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
		BaseAction.ActionType.OVERWATCH: return HOLD_OVERWATCH
	return -1.0


# hold_for's twin for the other side of the action (#520, dev 2026-08-27): how long to stay AFTER it
# has finished playing. Same shape clause for clause -- a CODA answers per verb, a VOLLEY takes the
# loudest rung by VALUE, punctuation earns nothing -- with two deliberate differences.
#
# It takes no profile and no is_ai, because a linger is flat (see the table above). And its VOLLEY
# branch has one rung rather than five: what makes a beat longer to watch on the way out is how much
# DEBRIS it threw, and only a death empties the grid. A shove's slide and a plummet are already
# awaited inside AttackAction.execute, so they are not waiting this needs to invent.
static func linger_for(beat: BeatSheet.Beat) -> float:
	if beat == null:
		return 0.0
	if beat.kind == BeatSheet.Kind.CODA:
		# Floored exactly as hold_for floors coda_hold: an undeclared verb degrades to no linger
		# rather than a negative one. The law test is what refuses the omission.
		return maxf(0.0, coda_linger(beat.coda_type))
	if beat.kind != BeatSheet.Kind.VOLLEY:
		return 0.0
	var linger := LINGER_ATTACK
	# The SAME clause hold_for uses for HOLD_DOWN -- one spelling of "this beat took someone out",
	# so the two sides of the beat can never disagree about what happened in it.
	if beat.has_removal \
			or beat.has_lethality(ResolvedOutcome.Lethality.DOWNED) \
			or beat.has_lethality(ResolvedOutcome.Lethality.KILLED) \
			or beat.has_lethality(ResolvedOutcome.Lethality.MAIMED):
		linger = maxf(linger, LINGER_DOWN)
	return linger


# coda_hold's twin, and it carries the same -1.0 sentinel for the same reason: an undeclared verb
# must be distinguishable from a deliberate 0, and tests/law/test_action_registry.gd refuses it.
static func coda_linger(type: BaseAction.ActionType) -> float:
	match type:
		BaseAction.ActionType.RESCUE: return LINGER_RESCUE
		BaseAction.ActionType.RALLY: return LINGER_RALLY
		BaseAction.ActionType.INTIMIDATE: return LINGER_INTIMIDATE
		BaseAction.ActionType.RELOAD: return LINGER_RELOAD
		BaseAction.ActionType.REV: return LINGER_REV
		BaseAction.ActionType.BURROW: return LINGER_BURROW
		BaseAction.ActionType.CAPTURE: return LINGER_CAPTURE
		BaseAction.ActionType.GUARD: return LINGER_GUARD
		BaseAction.ActionType.OVERWATCH: return LINGER_OVERWATCH
	return -1.0


static func beat(host: Node, seconds: float) -> void:
	if seconds <= 0.0 or DisplayServer.get_name() == "headless":
		return
	await host.get_tree().create_timer(seconds).timeout
