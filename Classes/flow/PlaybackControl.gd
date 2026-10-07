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
var _holding := false   # Shift was down at the last tick
var _last_msec := -1

# What the player sees of this, owned here as MusicDirector owns its players and pushed every tick.
# Both live in the HUD layer: the fade at UiLayers.PLAYBACK_FADE, under the dialogue, the wheel and
# every card, so a pause menu opened mid-skip draws over the black rather than under it.
var _fade_rect: ColorRect
var _hint: PlaybackHint


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var hud: CanvasLayer = game.ui_layer
	var status: MissionStatusPanel = game.mission_status_panel
	_fade_rect = ColorRect.new()
	_fade_rect.name = "SkipFade"
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.z_index = UiLayers.PLAYBACK_FADE
	_fade_rect.visible = false
	hud.add_child(_fade_rect)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint = PlaybackHint.new(status.panel_style())
	hud.add_child(_hint)


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
	_holding = holding
	Pacing.set_playback_speed(speed_for(owned, holding))
	_draw_views(owned)


# Whether the key hint is up: while the keys work and nothing covers them. The last clause is one
# slot, one occupant -- End Turn stays up through your own end-of-turn burn, so the hint yields.
func hint_shown(owned: bool) -> bool:
	if not owned or game.menu_is_up() or ModalLock.any_open(get_tree()) or phase != Phase.IDLE:
		return false
	var end_turn: EndTurnButton = game.end_turn_button
	return not end_turn.visible


func holding() -> bool:
	return _holding


func hint() -> PlaybackHint:
	return _hint


func fade_rect() -> ColorRect:
	return _fade_rect


func _draw_views(owned: bool) -> void:
	_fade_rect.color = Color(0, 0, 0, _fade)
	_fade_rect.visible = _fade > 0.001
	_hint.visible = hint_shown(owned)
	_hint.set_held(_holding and _hint.visible)


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


# How dark the skip fade is, 0..1.
func fade_level() -> float:
	return _fade


# Back to idle and clear, unskipped at 1x. A suite's teardown.
func reset() -> void:
	phase = Phase.IDLE
	_fade = 0.0
	_talked = false
	_holding = false
	Pacing.reset_playback()
	_draw_views(false)


static func _faded(level: float, toward: float, real_dt: float) -> float:
	if Pacing.SKIP_FADE <= 0.0:
		return toward
	return move_toward(level, toward, real_dt / Pacing.SKIP_FADE)
