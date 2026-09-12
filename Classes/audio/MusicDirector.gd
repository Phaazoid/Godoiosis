extends Node
class_name MusicDirector

# WHAT IS PLAYING RIGHT NOW, AND WHAT DECIDES IT (#136 slice 3). A game collaborator with a
# back-ref, built last in game._build_collaborators -- the DevController/MissionLog pattern.
#
# A SIBLING OF AudioDirector, NOT AN EXTENSION OF IT. That file answers a different question -- what
# this blow sounded like -- and its header is explicit that it OWNS NO RULE: one cue, fired and
# forgotten, no state. A score is the opposite shape. One at a time, looping, persisting across a
# whole mission, and it DOES own a rule: which track belongs to which phase. Folding that in would
# make the other file's own central claim false. Two doors, two questions.
#
# A RECONCILE, NOT AN EVENT. It asks every frame what SHOULD be playing and swaps if that differs
# from what is, which is the project's own idiom -- PlayerSettings has no changed signal by design,
# UnitMirror is a per-frame reconcile, AudioDirector._process already polls the volume row. So
# TurnManager.turn_started needs no listener here and there is no wiring to keep in step: the state
# cannot drift from the truth, because it IS a read of the truth.
#
# PROCESS_MODE_ALWAYS, for AudioDirector's two measured reasons: ModalLock sets
# game.process_mode = DISABLED, a DISABLED parent STOPS an AudioStreamPlayer's stream, and the
# settings page lives behind that same lock -- so a frozen director would cut the music the moment
# the pause menu opened and could not move the volume while the slider was being dragged.
#
# IT NEVER TOUCHES AudioServer. How loud the Music bus is belongs to AudioDirector's one
# setting-to-bus table; this owns only which track.

# WHOSE SIDE, NEVER WHO IS IN CONTROL (dev, 2026-09-11). The ask was "swap to the enemy approaches
# during AI turns", and in this game today the enemy IS the computer, so the two spellings coincide
# -- which is exactly what makes the wrong one easy to write. They part in both directions:
#
#   * HOTSEAT (ENEMY with AI off) is how the dev tests. BoardLint._check_ai_factions exists for that
#     state and ScenarioManager.clear_board sets AI off for the sandbox, so a control read plays the
#     PLAYER's track through the enemy's whole turn on every such board.
#   * ALLY is a real Team.Faction member, so an AI-controlled ally would announce itself as the enemy.
#
# Team.is_enemy is the project's one answer to whose side a faction is on -- twenty callers, and
# is_enemy(PLAYER, ALLY) false by design. NOT game_state == AI_TURN either: that is the input lock,
# set only while the AI is actually acting, so it is false during the hand-off beat and the mission
# banner -- precisely when the music should already be crossing.
enum Track {
	TITLE,
	BATTLE,
	ENEMY,
}

# NAMED FOR THE WORK, NOT THE ROLE -- the opposite of the SFX convention next door, deliberately. A
# sound effect IS its role (impact, chainsword); a music track is a composition with a title that
# CREDITS.md has to name, so the role lives here and the file keeps the name Simeon gave it. Three of
# the five recovered tracks: Journey and Boss Battle 1 arrive with the per-mission field.
#
# `resumes` IS PER TRACK BECAUSE THE TURNS ARE NOT SYMMETRIC. A player turn is minutes and a
# computer turn is seconds. Picking Battlefield up where it left off is what stops a 1:09 loop being
# the same first fifteen seconds all mission; resuming Enemy Approaching in ten-second fragments
# would mean never hearing a phrase of it, where restarting plays the hook every time -- which is
# what an "approaching" cue is for. Feel, so it is one word to flip.
const TRACKS := {
	Track.TITLE: {"stream": preload("res://Audio/Music/splendor_of_adventure.mp3"), "resumes": true},
	Track.BATTLE: {"stream": preload("res://Audio/Music/battlefield.mp3"), "resumes": true},
	Track.ENEMY: {"stream": preload("res://Audio/Music/enemy_approaching.mp3"), "resumes": false},
}

const BUS_NAME := "Music"

# How long one track takes to replace another. NOT optional and not polish: the swap fires twice a
# round, and a hard cut forty times a mission is the thing that would make a score read as worse
# than silence. A static var rather than a const because it is a GameKnobs row (Audio tab).
static var CROSSFADE_SECONDS := 0.8

var game: Node

# ONE PLAYER PER TRACK, never a pool of two. A pool cannot survive a swap arriving MID-FADE -- a
# computer turn can end inside the fade, and with two players the only free one is the one still
# sounding the track being faded out, so recycling it cuts that track dead at half volume. Per
# track, a swap is only ever "this one's level rises, the others' fall", from wherever they ARE, so
# a reversed fade is the ordinary case rather than a special one and nothing is ever cut.
var _players: Dictionary[Track, AudioStreamPlayer] = {}
# Where each track's mix sits, 0..1. The thing the fade moves; the players' volume_linear follows it.
var _levels: Dictionary[Track, float] = {}
# Where a track was when it last went silent, so a resuming one picks up instead of restarting.
var _positions: Dictionary[Track, float] = {}

# Which Track is wanted, or -1 for silence. A sentinel rather than a Track member: a NONE member
# would have to carry a null stream through TRACKS and every walk of the table would need to skip
# it. Silence is only ever the state before the first reconcile.
var _current := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var bus := AudioServer.get_bus_index(BUS_NAME)
	if bus == -1:
		push_warning("MusicDirector: no '%s' bus -- falling back to Master." % BUS_NAME)
		bus = 0

	for track: Track in TRACKS:
		var player := AudioStreamPlayer.new()
		player.stream = TRACKS[track]["stream"]
		player.bus = AudioServer.get_bus_name(bus)
		player.volume_linear = 0.0
		add_child(player)
		_players[track] = player
		_levels[track] = 0.0


func _process(delta: float) -> void:
	var wanted := wanted_track()
	if wanted != _current:
		_begin(wanted)
	_advance(delta)


# THE RULE, and the whole of it. Two reads, neither re-derived here.
#
# Any phase neither read sees gets the battle track, which is deliberate rather than overlooked: the
# pre-mission deployment screen and the mission-end banner are both that case today.
func wanted_track() -> Track:
	var controller: MissionController = game.mission_controller
	if controller.mission_select_is_up():
		return Track.TITLE
	var turns: TurnManager = game.turn_manager
	if Team.is_enemy(Team.Faction.PLAYER, turns.active_faction()):
		return Track.ENEMY
	return Track.BATTLE


# Start wanting a different track. Nothing is stopped here and no level is written: the incoming
# player only has to be SOUNDING, and _advance is the one place a level moves.
func _begin(track: Track) -> void:
	_current = track
	var player := _players[track]
	if not player.playing:
		player.play(_resume_position(track))


# Walk every track one step toward its target level -- 1 for the wanted one, 0 for the rest.
func _advance(delta: float) -> void:
	# A zero-length fade is INSTANT, never a division. The suite leans on this value, and a knob
	# the dev can drag to 0 would otherwise be a crash rather than a hard cut.
	var step := 1.0 if CROSSFADE_SECONDS <= 0.0 else delta / CROSSFADE_SECONDS
	for track: Track in _players:
		var target := 1.0 if track == _current else 0.0
		var level := move_toward(_levels[track], target, step)
		_levels[track] = level
		var player := _players[track]
		player.volume_linear = level
		# Remember where it got to BEFORE stopping, or the position is gone -- stop() rewinds.
		if level <= 0.0 and player.playing:
			_positions[track] = player.get_playback_position()
			player.stop()


func _resume_position(track: Track) -> float:
	if not TRACKS[track]["resumes"]:
		return 0.0
	return _positions.get(track, 0.0)


# --- read seams, for tests and for anything that wants to know without reaching into the players ---

# Which Track the rule has settled on, or -1 for silence.
func current_track() -> int:
	return _current


# Where this track sits in the mix, 0..1. Mid-fade two of these are non-zero, which is the point.
func level_of(track: Track) -> float:
	return _levels.get(track, 0.0)


# How far into a track its player has got. Zero for one that is not sounding -- where a STOPPED one
# would resume from is _resume_position's question, not this one's.
func position_of(track: Track) -> float:
	var player: AudioStreamPlayer = _players.get(track)
	if player == null or not player.playing:
		return 0.0
	return player.get_playback_position()


# Which tracks are actually sounding. Two of them mid-fade, one settled, none before the first
# reconcile.
func tracks_playing() -> Array[Track]:
	var live: Array[Track] = []
	for track: Track in _players:
		if _players[track].playing:
			live.append(track)
	return live


# PUT THE SCORE DOWN ON THE WAY OUT. A stream still sounding at process teardown leaves its
# AudioStreamPlaybackMP3 alive holding the AudioStreamMP3, and Godot's resource sweep reports the
# pair as `1 resources still in use at exit` -- an ERROR line, which reds the exported-build boot
# smoke (#868).
func _exit_tree() -> void:
	for track: Track in _players:
		var player: AudioStreamPlayer = _players[track]
		player.stop()
		player.stream = null
