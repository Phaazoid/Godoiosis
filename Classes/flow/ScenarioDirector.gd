class_name ScenarioDirector
extends Node

# Runs a scenario's authored script (#182): DialogBeats (independent "when X, say Y" moments)
# and TutorialSteps (a sequential lesson whose active step shows on the mission-status HUD).
# Built in game._build_collaborators with a back-ref (the DevController pattern).
#
# Seam rules: the board is the only authority on game state -- nothing here mirrors board facts
# into Dialogic's variable store. Triggers arrive as the board's own signals plus
# MissionController's fresh-start call. Both beats and steps are fresh-start content: a resume
# disarms them -- missing a nudge beats replaying a seen intro, and the objectives half of the
# HUD (#134) restores either way.
#
# One node runs both ON PURPOSE: a step and a beat can answer the same event (forming the squad
# completes the step AND fires the payoff line), so the order is pinned here -- step advances
# first (the HUD shows what's next), then beats fire (the voice reacts) -- instead of racing
# between two listeners.

var game   # the Game coordinator; set by game._build_collaborators()

var _beats: Array[DialogBeat] = []
var _fired: Dictionary = {}   # DialogBeat -> true; battle-scoped, cleared with the board
var _pending: Array[DialogicTimeline] = []   # triggered while another timeline was playing
var _dialog_active := false   # OUR in-flight latch: Dialogic.current_timeline is set a frame late
                              # (start() defers to the layout's ready), so same-frame beats need this
var _player_turn := 0   # counts turn_started(PLAYER); no other system owns this count

var _steps: Array[TutorialStep] = []
var _step_idx := 0   # index of the ACTIVE step; past the end = lesson done

# Content loads INERT and mission_started() arms it: apply_scenario's own spawn loop fires
# squad_created once per unit (spawn_unit's solo-squad invariant), and a loading board must
# never trip a lesson or a beat. A resume loads content and simply never arms.
var _armed := false


func _ready() -> void:
	game.turn_manager.turn_started.connect(_on_turn_started)
	game.squad_manager.squad_created.connect(_on_squad_created)
	game.squad_manager.squad_member_joined.connect(_on_squad_member_joined)
	game.unit_selected.connect(_on_unit_selected)
	Dialogic.timeline_ended.connect(_on_timeline_ended)


# The scenario's script arrives with the board (apply_scenario). REPLACED, not merged (#150).
func set_beats(beats: Array[DialogBeat]) -> void:
	_beats = beats
	_fired.clear()
	_pending.clear()
	_player_turn = 0


func set_steps(steps: Array[TutorialStep]) -> void:
	_steps = steps
	_step_idx = 0


# What the HUD's instruction row shows; empty = no row. game.refresh_mission_status() reads
# this on every refresh -- the panel never reads the director directly (#134's contract).
func active_instruction() -> String:
	if not _armed or _step_idx >= _steps.size():
		return ""
	return _steps[_step_idx].text


# Fresh mission start (begin_mission / restart_mission -- the #220 door). Not board_loaded:
# that signal also fires on resume and dev rebuilds, which must never replay an intro.
func mission_started() -> void:
	_armed = true
	game.refresh_mission_status()   # the lesson's first instruction is up before anyone talks
	for beat: DialogBeat in _beats:
		if beat.trigger == DialogBeat.Trigger.MISSION_START:
			_fire(beat)


# A resume is not a fresh start; beats and steps are fresh-start content.
func disarm() -> void:
	_armed = false
	_beats = []
	_steps = []
	game.refresh_mission_status()


# Board teardown (clear_board). Ends any running timeline so no dialog outlives its board.
func reset() -> void:
	_armed = false
	_beats = []
	_steps = []
	_step_idx = 0
	_fired.clear()
	_pending.clear()
	_player_turn = 0
	_dialog_active = false
	if Dialogic.current_timeline != null:
		Dialogic.end_timeline(true)   # un-awaited: nothing downstream depends on completion


# --- board events: the step advances FIRST, then beats fire (see header) ---

func _on_turn_started(faction: Team.Faction) -> void:
	if not _armed or faction != Team.Faction.PLAYER:
		return
	_player_turn += 1
	var step := _active_step()
	if step != null and step.done_when == DialogBeat.Trigger.TURN_START \
			and step.turn == _player_turn:
		_advance_step()
	for beat: DialogBeat in _beats:
		if beat.trigger == DialogBeat.Trigger.TURN_START and beat.turn == _player_turn:
			_fire(beat)


func _on_unit_selected(unit: Unit) -> void:
	if not _armed:
		return
	var step := _active_step()
	if step != null and step.done_when == DialogBeat.Trigger.UNIT_SELECTED \
			and _name_matches(step.unit_name, unit):
		_advance_step()
	for beat: DialogBeat in _beats:
		if beat.trigger == DialogBeat.Trigger.UNIT_SELECTED:
			_fire(beat)


func _on_squad_created(squad: Squad) -> void:
	if not _armed:
		return
	var leader: Unit = squad.get_leader()
	if leader == null or leader.get_faction() != Team.Faction.PLAYER:
		return
	var step := _active_step()
	if step != null and step.done_when == DialogBeat.Trigger.SQUAD_FORMED \
			and _name_matches(step.unit_name, leader):
		_advance_step()
	for beat: DialogBeat in _beats:
		if beat.trigger == DialogBeat.Trigger.SQUAD_FORMED:
			_fire(beat)


func _on_squad_member_joined(squad: Squad, _unit: Unit) -> void:
	if not _armed:
		return
	var leader: Unit = squad.get_leader()
	if leader == null or leader.get_faction() != Team.Faction.PLAYER:
		return
	var step := _active_step()
	if step != null and step.done_when == DialogBeat.Trigger.SQUAD_MEMBER_ADDED \
			and _name_matches(step.unit_name, leader) \
			and squad.get_members().size() >= step.squad_size:
		_advance_step()
	for beat: DialogBeat in _beats:
		if beat.trigger == DialogBeat.Trigger.SQUAD_MEMBER_ADDED:
			_fire(beat)


# --- steps ---

func _active_step() -> TutorialStep:
	if _step_idx >= _steps.size():
		return null
	return _steps[_step_idx]


func _advance_step() -> void:
	_step_idx += 1
	game.refresh_mission_status()   # the write-point pattern (#134), not a signal
	# THEN the payoff voice (the pinned order: HUD first). _step_idx is also how many steps
	# are complete, which is exactly the 1-based index STEP_COMPLETED beats author against.
	for beat: DialogBeat in _beats:
		if beat.trigger == DialogBeat.Trigger.STEP_COMPLETED and beat.step == _step_idx:
			_fire(beat)


func _name_matches(wanted: String, unit: Unit) -> bool:
	if wanted == "":
		return true
	if unit.unit_data == null:
		return false
	return unit.unit_data.display_name == wanted


# --- beats ---

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
