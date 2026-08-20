class_name ScenarioDirector
extends Node

# Runs a scenario's authored script (#182): DialogBeats (independent "when X, say Y" moments over
# Dialogic timelines) and TutorialSteps (a sequential lesson whose active step renders as the
# mission HUD's instruction row). Built in game._build_collaborators with a back-ref (the
# DevController pattern).
#
# Seam rules: the board is the only authority on game state -- nothing here mirrors board facts
# into Dialogic's variable store. Triggers arrive as the board's own signals plus
# MissionController's fresh-start call. CONTENT lives on ScenarioManager
# (current_dialog_beats/current_tutorial_steps, the current_look_preset seam) and is read LIVE
# here, never copied (#397) -- so capture_scenario always sees the lesson, and disarming silences
# EXECUTION without destroying what Update needs to save. This node owns only execution state:
# armed, fired, pending, the step cursor, the turn count.
#
# One node runs both beats and steps ON PURPOSE: a step and a beat can answer the same event, so
# the order is pinned here -- step advances (HUD refreshes) then beats fire -- instead of racing
# between two listeners.

var game   # the Game coordinator; set by game._build_collaborators()

var _fired: Dictionary = {}   # DialogBeat -> true; battle-scoped, cleared with the board
var _pending: Array[DialogicTimeline] = []   # triggered while another timeline was playing
var _dialog_active := false   # OUR in-flight latch: Dialogic.current_timeline is set a frame late
                              # (start() defers to the layout's ready), so same-frame beats need this
var _player_turn := 0   # counts turn_started(PLAYER); no other system owns this count
var _step_idx := 0      # index of the ACTIVE step; past the end = lesson done

# Content loads INERT and mission_started() arms it: apply_scenario's own spawn loop fires
# squad_created once per unit (spawn_unit's solo-squad invariant), and a loading board must
# never trip a lesson or a beat. A resume or watch-only boot simply never arms (#375).
var _armed := false


func _ready() -> void:
	game.turn_manager.turn_started.connect(_on_turn_started)
	game.squad_manager.squad_created.connect(_on_squad_created)
	game.squad_manager.squad_member_joined.connect(_on_squad_member_joined)
	game.unit_selected.connect(_on_unit_selected)
	Dialogic.timeline_ended.connect(_on_timeline_ended)


# What the HUD's instruction row shows; empty = no row. game.refresh_mission_status() reads
# this on every refresh -- the panel never reads the director directly (#134's contract).
func active_instruction() -> String:
	if not _armed or _step_idx >= _steps().size():
		return ""
	return _steps()[_step_idx].text


# BoardLint's gate for the authored-time checks (#397): true only once an ARMED battle has moved
# past its opening turn. Deliberately false on un-armed boards -- the dev-tools Load path never
# arms, and that is exactly the authoring session the lint exists for.
func past_opening_turn() -> bool:
	return _armed and _player_turn > 1


# Fresh mission start (begin_mission / restart_mission -- the #220 door). Not board_loaded:
# that signal also fires on resume and dev rebuilds, which must never replay an intro.
func mission_started() -> void:
	_armed = true
	game.refresh_mission_status()   # the lesson's first instruction is up before anyone talks
	for beat: DialogBeat in _beats():
		if beat.trigger == DialogBeat.Trigger.MISSION_START:
			_fire(beat)


# A resume (or watch-only boot) is not a fresh start. Silences EXECUTION only: the content stays
# on ScenarioManager, so a later capture_scenario still saves the lesson (#397).
func disarm() -> void:
	_armed = false
	# Pending is queued EXECUTION: a beat surviving here resurrects the moment the current
	# timeline ends (timeline_ended pops the queue) -- disarmed means nothing left to say.
	_pending.clear()
	game.refresh_mission_status()


# Board teardown (clear_board). Ends any running timeline so no dialog outlives its board.
func reset() -> void:
	_armed = false
	_fired.clear()
	_pending.clear()
	_player_turn = 0
	_step_idx = 0
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
	for beat: DialogBeat in _beats():
		if beat.trigger == DialogBeat.Trigger.TURN_START and beat.turn == _player_turn:
			_fire(beat)


func _on_unit_selected(unit: Unit) -> void:
	if not _armed:
		return
	var step := _active_step()
	if step != null and step.done_when == DialogBeat.Trigger.UNIT_SELECTED \
			and _name_matches(step.unit_name, unit):
		_advance_step()
	for beat: DialogBeat in _beats():
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
	for beat: DialogBeat in _beats():
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
	for beat: DialogBeat in _beats():
		if beat.trigger == DialogBeat.Trigger.SQUAD_MEMBER_ADDED:
			_fire(beat)


# --- content: ScenarioManager's stores, read live (#397) ---

func _beats() -> Array[DialogBeat]:
	return game.scenario_manager.current_dialog_beats


func _steps() -> Array[TutorialStep]:
	return game.scenario_manager.current_tutorial_steps


# --- steps ---

func _active_step() -> TutorialStep:
	if _step_idx >= _steps().size():
		return null
	return _steps()[_step_idx]


func _advance_step() -> void:
	_step_idx += 1
	game.refresh_mission_status()   # the write-point pattern (#134), not a signal
	# THEN the payoff voice (the pinned order: HUD first). _step_idx is also how many steps
	# are complete, which is exactly the 1-based index STEP_COMPLETED beats author against.
	for beat: DialogBeat in _beats():
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
