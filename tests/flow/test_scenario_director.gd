# ScenarioDirector -- the #182 beat seam: scenario-authored DialogBeats reaching Dialogic.
#
# These run the REAL wire: real TurnManager/SquadManager signal objects into a real director
# into the real Dialogic autoload -- asserting timelines actually start (timeline_started),
# not that a handler was invoked. The managers stay OUT of the tree (their @onready paths
# need a board scene; their signals do not). Timelines are built in-memory via from_text --
# no .dtl files, no rendering asserted: display styling is Dialogic's job and is feel, not law.
extends GdUnitTestSuite

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


class ManagerStub extends RefCounted:
	# Just the two #397 content stores the director reads live; the real ScenarioManager needs a board.
	var current_dialog_beats: Array[DialogBeat] = []
	var current_tutorial_steps: Array[TutorialStep] = []


class GameStub extends Node:
	signal unit_selected(unit: Unit)   # mirrors game.gd's signal; tests emit it directly
	var turn_manager: TurnManager
	var squad_manager: SquadManager
	var scenario_manager: ManagerStub
	var refreshes := 0   # counts refresh_mission_status calls -- the #134 write-point wire

	func refresh_mission_status() -> void:
		refreshes += 1


var _stub: GameStub
var _director: ScenarioDirector
var _starts := 0


func before_test() -> void:
	_stub = auto_free(GameStub.new())
	_stub.turn_manager = auto_free(TurnManager.new())
	_stub.squad_manager = auto_free(SquadManager.new())
	_stub.scenario_manager = ManagerStub.new()   # #397: the content stores the director reads live
	add_child(_stub)
	_director = ScenarioDirector.new()
	_director.game = _stub
	_stub.add_child(_director)   # _ready connects the two manager signals + Dialogic
	_starts = 0
	PlayerSettings.reset_for_test()   # is_on falls through to DISK otherwise (the #350 gotcha)
	Dialogic.timeline_started.connect(_count_start)


func after_test() -> void:
	Dialogic.timeline_started.disconnect(_count_start)
	var active := Dialogic.current_timeline != null
	_director.reset()   # ends any running timeline; pending already cleared so nothing chains
	if active:
		await Dialogic.timeline_ended
	await get_tree().process_frame
	await get_tree().process_frame   # let the layout's queue_free land before orphan accounting


func _count_start() -> void:
	_starts += 1


func _beat(trigger: DialogBeat.Trigger, text: String, turn := 1) -> DialogBeat:
	var beat := DialogBeat.new()
	beat.trigger = trigger
	beat.turn = turn
	beat.timeline = DialogicTimeline.new()
	beat.timeline.from_text(text)
	return beat


func _player_squad() -> Squad:
	return _squad(PLAYER)


func _squad(fac: Team.Faction) -> Squad:
	var leader := auto_free(Unit.new()) as Unit   # never enters the tree: only unit_data.faction is read
	leader.unit_data = UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Leader", fac)
	var squad := auto_free(Squad.new()) as Squad
	squad.set_leader(leader)
	return squad


# start() hands the timeline to the layout's ready callback, so "it started" is a signal await,
# never an immediate assert (the same lesson as Dialogic.Text.text_finished from the spike).
func _await_starts(expected: int) -> void:
	for i in range(120):
		if _starts >= expected:
			break
		await get_tree().process_frame
	assert_int(_starts).is_equal(expected)


# --- MISSION_START ---

func test_mission_start_beat_plays_on_mission_started() -> void:
	_set_beats([_beat(DialogBeat.Trigger.MISSION_START, "Welcome to the academy.")])
	_director.mission_started()
	await _await_starts(1)


func test_mission_start_beat_fires_once_per_battle() -> void:
	_set_beats([_beat(DialogBeat.Trigger.MISSION_START, "Once only.")])
	_director.mission_started()
	_director.mission_started()
	await _await_starts(1)
	await get_tree().process_frame
	assert_int(_starts).is_equal(1)


# --- TURN_START ---

func test_turn_start_beat_waits_for_its_player_turn() -> void:
	_set_beats([_beat(DialogBeat.Trigger.TURN_START, "Turn two tip.", 2)])
	_director.mission_started()   # content is inert until armed
	_stub.turn_manager.turn_started.emit(ENEMY)    # enemy turns never advance the player count
	_stub.turn_manager.turn_started.emit(PLAYER)   # player turn 1: not yet
	await get_tree().process_frame
	assert_int(_starts).is_equal(0)
	_stub.turn_manager.turn_started.emit(PLAYER)   # player turn 2: now
	await _await_starts(1)


# --- SQUAD_FORMED ---

func test_squad_formed_beat_fires_for_player_squad_only() -> void:
	_set_beats([_beat(DialogBeat.Trigger.SQUAD_FORMED, "Squads share a plan.")])
	_director.mission_started()
	_stub.squad_manager.squad_created.emit(_squad(ENEMY))
	await get_tree().process_frame
	assert_int(_starts).is_equal(0)
	_stub.squad_manager.squad_created.emit(_player_squad())
	await _await_starts(1)


# --- one timeline at a time ---

func test_beat_landing_mid_dialog_queues_until_the_timeline_ends() -> void:
	_set_beats([
		_beat(DialogBeat.Trigger.MISSION_START, "Intro talking."),
		_beat(DialogBeat.Trigger.SQUAD_FORMED, "Payoff line."),
	])
	_director.mission_started()
	_stub.squad_manager.squad_created.emit(_player_squad())   # lands the same frame the intro starts
	await _await_starts(1)   # only the intro is playing
	Dialogic.end_timeline(true)
	await _await_starts(2)   # the payoff chained off timeline_ended


# --- resume / teardown ---

func test_disarm_silences_every_trigger() -> void:
	_set_beats([
		_beat(DialogBeat.Trigger.MISSION_START, "Never."),
		_beat(DialogBeat.Trigger.TURN_START, "Never.", 1),
		_beat(DialogBeat.Trigger.SQUAD_FORMED, "Never."),
	])
	_director.disarm()
	# No re-arm: mission_started IS the fresh-start door, so calling it here would legitimately
	# fire (#397 -- disarm silences execution, it no longer destroys content).
	_stub.turn_manager.turn_started.emit(PLAYER)
	_stub.squad_manager.squad_created.emit(_player_squad())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_starts).is_equal(0)


func test_reset_ends_a_running_timeline() -> void:
	_set_beats([_beat(DialogBeat.Trigger.MISSION_START, "Doomed dialog.")])
	_director.mission_started()
	await _await_starts(1)
	_director.reset()
	await Dialogic.timeline_ended
	assert_object(Dialogic.current_timeline).is_null()


# --- tutorial steps (#182 slice 2) ---

func _step(done_when: DialogBeat.Trigger, text: String, unit_name := "", squad_size := 0) -> TutorialStep:
	var step := TutorialStep.new()
	step.done_when = done_when
	step.text = text
	step.unit_name = unit_name
	step.squad_size = squad_size
	return step


func _named_unit(unit_name: String, fac: Team.Faction) -> Unit:
	var unit := auto_free(Unit.new()) as Unit
	unit.unit_data = UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)
	return unit


func test_selection_step_requires_the_named_unit() -> void:
	_set_steps([
		_step(DialogBeat.Trigger.UNIT_SELECTED, "Select Torv.", "Torv"),
		_step(DialogBeat.Trigger.SQUAD_FORMED, "Squad up."),
	])
	_director.mission_started()
	_stub.unit_selected.emit(_named_unit("Isaac", PLAYER))
	assert_str(_director.active_instruction()).is_equal("Select Torv.")
	_stub.unit_selected.emit(_named_unit("Torv", PLAYER))
	assert_str(_director.active_instruction()).is_equal("Squad up.")


func test_member_step_waits_for_the_squad_size() -> void:
	_set_steps([_step(DialogBeat.Trigger.SQUAD_MEMBER_ADDED, "Bring everyone.", "", 3)])
	_director.mission_started()
	var squad := _player_squad()
	squad._add_member(_named_unit("Second", PLAYER))   # 2 members: leader + one
	_stub.squad_manager.squad_member_joined.emit(squad, squad.get_members()[1])
	assert_str(_director.active_instruction()).is_equal("Bring everyone.")
	squad._add_member(_named_unit("Third", PLAYER))    # 3: the step's bar
	_stub.squad_manager.squad_member_joined.emit(squad, squad.get_members()[2])
	assert_str(_director.active_instruction()).is_equal("")


func test_step_and_payoff_beat_share_one_event_step_first() -> void:
	_set_steps([_step(DialogBeat.Trigger.SQUAD_FORMED, "Form a squad.")])
	_set_beats([_beat(DialogBeat.Trigger.SQUAD_FORMED, "Good -- now you move as one.")])
	_director.mission_started()
	_stub.squad_manager.squad_created.emit(_player_squad())
	assert_str(_director.active_instruction()).is_equal("")   # the step advanced...
	await _await_starts(1)                                    # ...and the payoff voice fired


func test_the_lesson_walks_in_authored_order() -> void:
	_set_steps([
		_step(DialogBeat.Trigger.UNIT_SELECTED, "Select Torv.", "Torv"),
		_step(DialogBeat.Trigger.SQUAD_FORMED, "Squad up with someone.", "Torv"),
		_step(DialogBeat.Trigger.SQUAD_MEMBER_ADDED, "Bring the other two.", "", 4),
	])
	_director.mission_started()
	var refreshes_before: int = _stub.refreshes
	# Forming a squad FIRST must not skip the selection step -- only the active step listens.
	_stub.squad_manager.squad_created.emit(_player_squad())
	assert_str(_director.active_instruction()).is_equal("Select Torv.")
	_stub.unit_selected.emit(_named_unit("Torv", PLAYER))
	assert_str(_director.active_instruction()).is_equal("Squad up with someone.")
	var torv_squad := auto_free(Squad.new()) as Squad
	torv_squad.set_leader(_named_unit("Torv", PLAYER))
	_stub.squad_manager.squad_created.emit(torv_squad)
	assert_str(_director.active_instruction()).is_equal("Bring the other two.")
	for extra in range(3):
		torv_squad._add_member(_named_unit("Extra%d" % extra, PLAYER))
	_stub.squad_manager.squad_member_joined.emit(torv_squad, torv_squad.get_members()[3])
	assert_str(_director.active_instruction()).is_equal("")   # lesson done
	# Each advance hit the HUD write point (#134's pattern): 3 advances = 3 refreshes.
	assert_int(_stub.refreshes - refreshes_before).is_equal(3)


func test_disarm_clears_the_instruction() -> void:
	_set_steps([_step(DialogBeat.Trigger.SQUAD_FORMED, "Never seen on resume.")])
	_director.mission_started()
	assert_str(_director.active_instruction()).is_equal("Never seen on resume.")
	_director.disarm()
	assert_str(_director.active_instruction()).is_equal("")


func test_payoff_beat_fires_when_its_step_completes() -> void:
	_set_steps([
		_step(DialogBeat.Trigger.UNIT_SELECTED, "Select Torv.", "Torv"),
		_step(DialogBeat.Trigger.SQUAD_FORMED, "Squad up."),
	])
	var payoff := _beat(DialogBeat.Trigger.STEP_COMPLETED, "Both steps done.")
	payoff.step = 2
	_set_beats([payoff])
	_director.mission_started()
	_stub.unit_selected.emit(_named_unit("Torv", PLAYER))   # completes step 1 -- not the payoff's step
	await get_tree().process_frame
	assert_int(_starts).is_equal(0)
	_stub.squad_manager.squad_created.emit(_player_squad())   # completes step 2 -- the payoff's
	await _await_starts(1)


func test_member_step_ignores_the_wrong_leaders_squad() -> void:
	_set_steps([_step(DialogBeat.Trigger.SQUAD_MEMBER_ADDED, "Grow Torv's squad.", "Torv", 2)])
	_director.mission_started()
	var isaac_squad := auto_free(Squad.new()) as Squad
	isaac_squad.set_leader(_named_unit("Isaac", PLAYER))
	isaac_squad._add_member(_named_unit("Collette", PLAYER))
	_stub.squad_manager.squad_member_joined.emit(isaac_squad, isaac_squad.get_members()[1])
	assert_str(_director.active_instruction()).is_equal("Grow Torv's squad.")
	var torv_squad := auto_free(Squad.new()) as Squad
	torv_squad.set_leader(_named_unit("Torv", PLAYER))
	torv_squad._add_member(_named_unit("Ross", PLAYER))
	_stub.squad_manager.squad_member_joined.emit(torv_squad, torv_squad.get_members()[1])
	assert_str(_director.active_instruction()).is_equal("")


# --- authored content integrity (the Prolog lesson, #182 slice 3) ---

# Not a content pin: empty arrays pass. What it guards is the WIRE from authored data to
# playable dialog -- a renamed or moved .dtl leaves a beat with a null timeline and no error
# until a player reaches that moment of the lesson.
func test_prolog_authored_content_resolves() -> void:
	var scenario: ScenarioData = load("res://Scenarios/missions/Prolog.tres")
	for beat: DialogBeat in scenario.dialog_beats:
		assert_object(beat.timeline).is_not_null()
	for step: TutorialStep in scenario.tutorial_steps:
		assert_str(step.text).is_not_empty()


func test_disarm_also_empties_the_pending_queue() -> void:
	# The resurrection bug: a beat queued behind a running timeline survived disarm, and
	# timeline_ended popped it back to life on a director that had nothing left to say.
	_set_beats([
		_beat(DialogBeat.Trigger.MISSION_START, "First voice."),
		_beat(DialogBeat.Trigger.MISSION_START, "Queued voice."),
	])
	_director.mission_started()   # first starts, second queues
	await _await_starts(1)
	_director.disarm()
	Dialogic.end_timeline(true)   # ended pops the queue -- which must now be empty
	await Dialogic.timeline_ended
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_starts).is_equal(1)


# #397: content lives on the manager; the director reads it live. These write the stub store.
func _set_beats(beats: Array[DialogBeat]) -> void:
	_stub.scenario_manager.current_dialog_beats = beats


func _set_steps(steps: Array[TutorialStep]) -> void:
	_stub.scenario_manager.current_tutorial_steps = steps


# --- the #400 player switch ---

func test_dialog_off_consumes_beats_silently_and_never_replays_them() -> void:
	PlayerSettings.set_on(PlayerSettings.Setting.SHOW_DIALOG, false)
	_set_beats([_beat(DialogBeat.Trigger.MISSION_START, "Skipped entirely.")])
	_director.mission_started()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_starts).is_equal(0)
	# The moment passed: re-enabling mid-battle must not replay it...
	PlayerSettings.set_on(PlayerSettings.Setting.SHOW_DIALOG, true)
	_director.mission_started()   # same battle, fired-set intact
	await get_tree().process_frame
	assert_int(_starts).is_equal(0)


func test_dialog_off_leaves_the_instruction_row_alone() -> void:
	PlayerSettings.set_on(PlayerSettings.Setting.SHOW_DIALOG, false)
	_set_steps([_step(DialogBeat.Trigger.SQUAD_FORMED, "Form a squad.")])
	_director.mission_started()
	assert_str(_director.active_instruction()).is_equal("Form a squad.")
