# DialogDirector -- the #182 beat seam: scenario-authored DialogBeats reaching Dialogic.
#
# These run the REAL wire: real TurnManager/SquadManager signal objects into a real director
# into the real Dialogic autoload -- asserting timelines actually start (timeline_started),
# not that a handler was invoked. The managers stay OUT of the tree (their @onready paths
# need a board scene; their signals do not). Timelines are built in-memory via from_text --
# no .dtl files, no rendering asserted: display styling is Dialogic's job and is feel, not law.
extends GdUnitTestSuite

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


class GameStub extends Node:
	var turn_manager: TurnManager
	var squad_manager: SquadManager


var _stub: GameStub
var _director: DialogDirector
var _starts := 0


func before_test() -> void:
	_stub = auto_free(GameStub.new())
	_stub.turn_manager = auto_free(TurnManager.new())
	_stub.squad_manager = auto_free(SquadManager.new())
	add_child(_stub)
	_director = DialogDirector.new()
	_director.game = _stub
	_stub.add_child(_director)   # _ready connects the two manager signals + Dialogic
	_starts = 0
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
	_director.set_beats([_beat(DialogBeat.Trigger.MISSION_START, "Welcome to the academy.")])
	_director.mission_started()
	await _await_starts(1)


func test_mission_start_beat_fires_once_per_battle() -> void:
	_director.set_beats([_beat(DialogBeat.Trigger.MISSION_START, "Once only.")])
	_director.mission_started()
	_director.mission_started()
	await _await_starts(1)
	await get_tree().process_frame
	assert_int(_starts).is_equal(1)


# --- TURN_START ---

func test_turn_start_beat_waits_for_its_player_turn() -> void:
	_director.set_beats([_beat(DialogBeat.Trigger.TURN_START, "Turn two tip.", 2)])
	_stub.turn_manager.turn_started.emit(ENEMY)    # enemy turns never advance the player count
	_stub.turn_manager.turn_started.emit(PLAYER)   # player turn 1: not yet
	await get_tree().process_frame
	assert_int(_starts).is_equal(0)
	_stub.turn_manager.turn_started.emit(PLAYER)   # player turn 2: now
	await _await_starts(1)


# --- SQUAD_FORMED ---

func test_squad_formed_beat_fires_for_player_squad_only() -> void:
	_director.set_beats([_beat(DialogBeat.Trigger.SQUAD_FORMED, "Squads share a plan.")])
	_stub.squad_manager.squad_created.emit(_squad(ENEMY))
	await get_tree().process_frame
	assert_int(_starts).is_equal(0)
	_stub.squad_manager.squad_created.emit(_player_squad())
	await _await_starts(1)


# --- one timeline at a time ---

func test_beat_landing_mid_dialog_queues_until_the_timeline_ends() -> void:
	_director.set_beats([
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
	_director.set_beats([
		_beat(DialogBeat.Trigger.MISSION_START, "Never."),
		_beat(DialogBeat.Trigger.TURN_START, "Never.", 1),
		_beat(DialogBeat.Trigger.SQUAD_FORMED, "Never."),
	])
	_director.disarm()
	_director.mission_started()
	_stub.turn_manager.turn_started.emit(PLAYER)
	_stub.squad_manager.squad_created.emit(_player_squad())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_starts).is_equal(0)


func test_reset_ends_a_running_timeline() -> void:
	_director.set_beats([_beat(DialogBeat.Trigger.MISSION_START, "Doomed dialog.")])
	_director.mission_started()
	await _await_starts(1)
	_director.reset()
	await Dialogic.timeline_ended
	assert_object(Dialogic.current_timeline).is_null()
