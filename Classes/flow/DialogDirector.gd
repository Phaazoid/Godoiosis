class_name DialogDirector
extends Node

# Fires a scenario's authored DialogBeats (#182): holds which beats are armed, which already
# fired, and hands timelines to the Dialogic autoload one at a time. Built in
# game._build_collaborators with a back-ref (the DevController pattern).
#
# Seam rules: the board is the only authority on game state -- nothing here mirrors board facts
# into Dialogic's variable store. Triggers arrive as the board's own signals (turn_started,
# squad_created) plus MissionController's fresh-start call. Beats are fresh-start content: a
# resume disarms them -- missing a nudge beats replaying a seen intro, and the mission-status
# HUD (#134) still carries the objective either way.

var game   # the Game coordinator; set by game._build_collaborators()

var _beats: Array[DialogBeat] = []
var _fired: Dictionary = {}   # DialogBeat -> true; battle-scoped, cleared with the board
var _pending: Array[DialogicTimeline] = []   # triggered while another timeline was playing
var _dialog_active := false   # OUR in-flight latch: Dialogic.current_timeline is set a frame late
                              # (start() defers to the layout's ready), so same-frame beats need this
var _player_turn := 0   # counts turn_started(PLAYER); no other system owns this count


func _ready() -> void:
	game.turn_manager.turn_started.connect(_on_turn_started)
	game.squad_manager.squad_created.connect(_on_squad_created)
	Dialogic.timeline_ended.connect(_on_timeline_ended)


# The scenario's beats arrive with the board (apply_scenario). REPLACED, not merged (#150).
func set_beats(beats: Array[DialogBeat]) -> void:
	_beats = beats
	_fired.clear()
	_pending.clear()
	_player_turn = 0


# Fresh mission start (begin_mission / restart_mission -- the #220 door). Not board_loaded:
# that signal also fires on resume and dev rebuilds, which must never replay an intro.
func mission_started() -> void:
	for beat: DialogBeat in _beats:
		if beat.trigger == DialogBeat.Trigger.MISSION_START:
			_fire(beat)


# A resume is not a fresh start; beats are fresh-start content.
func disarm() -> void:
	_beats = []


# Board teardown (clear_board). Ends any running timeline so no dialog outlives its board.
func reset() -> void:
	disarm()
	_fired.clear()
	_pending.clear()
	_player_turn = 0
	_dialog_active = false
	if Dialogic.current_timeline != null:
		Dialogic.end_timeline(true)   # un-awaited: nothing downstream depends on completion


func _on_turn_started(faction: Team.Faction) -> void:
	if faction != Team.Faction.PLAYER:
		return
	_player_turn += 1
	for beat: DialogBeat in _beats:
		if beat.trigger == DialogBeat.Trigger.TURN_START and beat.turn == _player_turn:
			_fire(beat)


func _on_squad_created(squad: Squad) -> void:
	var leader: Unit = squad.get_leader()
	if leader == null or leader.get_faction() != Team.Faction.PLAYER:
		return
	for beat: DialogBeat in _beats:
		if beat.trigger == DialogBeat.Trigger.SQUAD_FORMED:
			_fire(beat)


# Once per beat per battle. Dialogic plays one timeline at a time, so a beat landing mid-dialog
# queues -- the squad-payoff can arrive while the intro is still talking.
func _fire(beat: DialogBeat) -> void:
	if _fired.has(beat) or beat.timeline == null:
		return
	_fired[beat] = true
	if _dialog_active or Dialogic.current_timeline != null:
		_pending.append(beat.timeline)
	else:
		_dialog_active = true
		Dialogic.start(beat.timeline)


func _on_timeline_ended() -> void:
	_dialog_active = false
	if not _pending.is_empty():
		_dialog_active = true
		Dialogic.start(_pending.pop_front())
