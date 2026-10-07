extends Node
class_name PlaybackControl

# HOW FAST PLAYBACK RUNS, AND WHETHER ANYONE SEES IT (#545). A game collaborator with a back-ref,
# built in game._build_collaborators -- the DevController/MusicDirector pattern. The one place input
# becomes a playback speed; Pacing owns the write to Engine.time_scale.
#
# Three asks, one rule: they change how fast playback runs, never which code runs.
#   - The SETTING (PlayerSettings.PLAYBACK_SPEED) is the base speed for all playback.
#   - HOLDING fast_forward goes to Pacing.FAST_FORWARD, or the setting if that is faster. No stacking.
#   - TAPPING skip_playback fades to black, turns on Pacing.unwatched() -- the headless escape every
#     beat, pan, ease and fall already has -- and runs what is left at Pacing.SKIP_SPEED, until
#     playback lets go of the board. Then it fades back in on the settled board, camera home.
#
# Nothing returns early, so a skipped pass still reaches _end_squad_turn and still releases the
# playback lock that brings the view home. That is the whole of what a skip must not break.
#
# A RECONCILE, NOT AN EVENT: every frame asks what the speed should be, MusicDirector's idiom. Both
# keys are read off the global Input state rather than one window's event stream, so they work from
# either OS window (the two-window trap). PROCESS_MODE_ALWAYS because ModalLock disables the Game
# node, and a card opened mid-fast-forward must drop the speed rather than freeze it in place.

enum Phase { IDLE, FADING_OUT, SKIPPING, FADING_IN }

var game   # the Game coordinator; set by game._build_collaborators()

var phase := Phase.IDLE
var _fade := 0.0   # 0 clear .. 1 black
var _talked := false   # a dialog was up at the last tick (see request_skip)
var _last_msec := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	Pacing.reset_playback()


func _process(_delta: float) -> void:
	# REAL time: _delta is scaled by the very speed this sets, and a hitstop zeroes it.
	var now := Time.get_ticks_msec()
	var real := 0.0 if _last_msec < 0 else (now - _last_msec) / 1000.0
	_last_msec = now
	if Input.is_action_just_pressed("skip_playback"):
		request_skip()
	tick(real, Input.is_action_pressed("fast_forward"))


# The one entry for a skip, true if it took. Refused while the board is the player's, under a card or
# a menu, and while a dialog is playing OR was at the last tick: Space advances dialog too, and the
# press that ends a timeline's last line has already ended it by the time this frame asks.
func request_skip() -> bool:
	if phase != Phase.IDLE or not game.playback_owns_board() or game.menu_is_up():
		return false
	if ModalLock.any_open(get_tree()) or _talked or game.scenario_director.is_talking():
		return false
	phase = Phase.FADING_OUT
	return true


# One frame of the reconcile, on real seconds. Public so a case can drive exact timings.
func tick(real_dt: float, holding: bool) -> void:
	_talked = game.scenario_director.is_talking()
	var owned: bool = game.playback_owns_board()
	match phase:
		Phase.FADING_OUT:
			if not owned:
				phase = Phase.FADING_IN
			else:
				_fade = _faded(_fade, 1.0, real_dt)
				if _fade >= 1.0:
					phase = Phase.SKIPPING
					Pacing.set_skipping(true)
		Phase.SKIPPING:
			if not owned:
				phase = Phase.FADING_IN
				Pacing.set_skipping(false)
		Phase.FADING_IN:
			_fade = _faded(_fade, 0.0, real_dt)
			if _fade <= 0.0:
				phase = Phase.IDLE
	Pacing.set_playback_speed(speed_for(owned, holding))


# What playback should run at this frame.
func speed_for(owned: bool, holding: bool) -> float:
	if not owned or game.menu_is_up() or ModalLock.any_open(get_tree()):
		return 1.0
	if phase == Phase.SKIPPING:
		return Pacing.SKIP_SPEED
	var speed := Pacing.setting_speed()
	if holding:
		speed = maxf(speed, Pacing.FAST_FORWARD)
	return speed


# How dark the skip fade is, 0..1. battle3d draws it.
func fade_level() -> float:
	return _fade


# Back to idle and clear, unskipped at 1x. A suite's teardown.
func reset() -> void:
	phase = Phase.IDLE
	_fade = 0.0
	_talked = false
	Pacing.reset_playback()


static func _faded(level: float, toward: float, real_dt: float) -> float:
	if Pacing.SKIP_FADE <= 0.0:
		return toward
	return move_toward(level, toward, real_dt / Pacing.SKIP_FADE)
