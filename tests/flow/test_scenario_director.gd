# ScenarioDirector -- the #182 beat seam: scenario-authored DialogBeats reaching Dialogic.
#
# These run the REAL wire: real TurnManager/SquadManager signal objects into a real director
# into the real Dialogic autoload -- asserting timelines actually start (timeline_started),
# not that a handler was invoked. The managers stay OUT of the tree (their @onready paths
# need a board scene; their signals do not). Timelines are built in-memory via from_text --
# no .dtl files, no rendering asserted: display styling is Dialogic's job and is feel, not law.
#
# The TURN_START cases boot the real game instead (#1361): the opening turn emits no turn_started,
# so only the real mission doors can show which turn a mission opens on.
extends GdUnitTestSuite

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const SCRATCH := "user://__director_turns_1361.tres"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const ROW_WIDTH := 8


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
var _quiets := 0
var _main: Node = null    # the real game, booted only by the cases that need its mission doors
var _game: Node2D = null


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
	_quiets = 0
	_director.went_quiet.connect(_count_quiet)   # dies with the director, which _stub owns
	PlayerSettings.reset_for_test()   # is_on falls through to DISK otherwise (the #350 gotcha)
	Dialogic.timeline_started.connect(_count_start)


func after_test() -> void:
	Dialogic.timeline_started.disconnect(_count_start)
	if _main != null:
		await _free_game()
	var active := Dialogic.current_timeline != null
	_director.reset()   # ends any running timeline; pending already cleared so nothing chains
	if active:
		await Dialogic.timeline_ended
	await get_tree().process_frame
	await get_tree().process_frame   # let the layout's queue_free land before orphan accounting


func _count_start() -> void:
	_starts += 1


func _count_quiet() -> void:
	_quiets += 1


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


# --- TURN_START (#1361: the opening turn is turn 1) ---

func _boot() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	_game = _main.get_node("GameContainer/GameView/Game")
	_game.mission_controller._close_mission_select()
	_game.scenario_manager.clear_board()
	_game.game_state = _game.GameState.IDLE
	await await_idle_frame()


func _free_game() -> void:
	_game.scenario_director.disarm()   # its queue must not chain a beat off the end below
	await DialogFixtures.end_all_dialog(self)
	_game.scenario_manager.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	_main = null
	_game = null
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# A player and an enemy on one grass row, nobody AI-controlled, opening on the PLAYER's turn. With a
# roster the player force is the draw instead, onto a deployment zone, so the phase opens.
func _author(beats: Array[DialogBeat], steps: Array[TutorialStep] = [], roster := "") -> String:
	var sm: ScenarioManager = _game.scenario_manager
	for x in range(ROW_WIDTH):
		_game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	if roster == "":
		assert_object(_game.spawn_unit(H.make_unit_data({}, PLAYER), Vector2i(0, 0))).is_not_null()
	else:
		for x in range(2):
			_game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
		sm.current_roster = roster
		sm.current_deployment_cap = 1
	assert_object(_game.spawn_unit(H.make_unit_data({}, ENEMY), Vector2i(ROW_WIDTH - 1, 0))).is_not_null()
	var nobody: Array[Team.Faction] = []
	_game.ai_controller.set_ai_factions(nobody)
	_game.turn_manager.set_active_faction(PLAYER)
	sm.current_dialog_beats = beats
	sm.current_tutorial_steps = steps
	var scenario := sm.capture_scenario("director_turns_1361", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


# THE defect: turn_started never fires for the turn a mission opens on, so a turn-1 beat played on
# turn 2 and every count after it ran one late. Reached through begin_mission and two real end_turns,
# never an emitted signal -- the old case emitted a "turn 1" the game never sends.
func test_turn_beats_and_steps_count_the_turn_a_mission_opens_on() -> void:
	await _boot()
	var step := TutorialStep.new()
	step.done_when = DialogBeat.Trigger.TURN_START
	step.turn = 2
	step.text = "End your turn."
	var steps: Array[TutorialStep] = [step]
	var path := _author([
		_beat(DialogBeat.Trigger.TURN_START, "Turn one tip.", 1),
		_beat(DialogBeat.Trigger.TURN_START, "Turn two tip.", 2),
	], steps)
	var director: ScenarioDirector = _game.scenario_director

	_game.mission_controller.begin_mission(path)
	await _await_starts(1)
	# Drained before asking: a turn-two beat fired now would QUEUE behind turn one's, and the end
	# pops it. is_talking() rather than a start count, which lags the pop by the layout's frames.
	await DialogFixtures.end_all_dialog(self)
	assert_bool(director.is_talking()).override_failure_message(
		"the turn-two beat fired on the opening turn").is_false()
	assert_str(director.active_instruction()).override_failure_message(
		"the turn-two step completed on the opening turn").is_equal("End your turn.")
	assert_bool(director.past_opening_turn()).is_false()

	await _game.end_turn()   # PLAYER -> ENEMY, which nobody plays and nothing counts
	assert_bool(director.is_talking()).override_failure_message(
		"the enemy's turn was counted as the player's").is_false()
	await _game.end_turn()   # ENEMY -> PLAYER: the player's SECOND turn
	await _await_starts(2)
	assert_str(director.active_instruction()).override_failure_message(
		"the turn-two step did not complete on turn two").is_empty()
	assert_bool(director.past_opening_turn()).is_true()


func test_a_restart_counts_its_opening_turn_again() -> void:
	await _boot()
	var path := _author([_beat(DialogBeat.Trigger.TURN_START, "Turn one tip.", 1)])
	_game.mission_controller.begin_mission(path)
	await _await_starts(1)
	await DialogFixtures.end_all_dialog(self)
	_game.mission_controller.restart_mission()
	await _await_starts(2)


# The third arming door. The phase itself is no turn: the beat waits for the commit.
func test_a_committed_deployment_counts_its_opening_turn() -> void:
	await _boot()
	var rosters: Array[String] = RosterCatalog.saved_rosters()
	if rosters.is_empty():
		push_warning("no rosters are shipped, so the commit door cannot be exercised")
		return
	var path := _author([_beat(DialogBeat.Trigger.TURN_START, "Turn one tip.", 1)], [], rosters[0])
	_game.mission_controller.begin_mission(path)
	await await_idle_frame()
	assert_bool(_game.mission_controller.is_deploying()).override_failure_message(
		"precondition: the pre-mission phase did not open, so the commit door was never reached").is_true()
	assert_bool(_game.scenario_director.is_talking()).override_failure_message(
		"a turn beat played inside the pre-mission phase").is_false()
	assert_bool(_game.mission_controller.commit_deployment()).is_true()
	await _await_starts(1)


# The other half of the rule: a board opening on the enemy's turn gives the player turn 1 at the
# hand-off. Driven through the real TurnManager.end_turn, the only emitter of turn_started.
func test_a_mission_opening_on_the_enemy_turn_counts_the_player_from_the_hand_off() -> void:
	_set_beats([_beat(DialogBeat.Trigger.TURN_START, "Turn one tip.", 1)])
	_stub.turn_manager.set_active_faction(ENEMY)
	_director.mission_started()
	assert_bool(_director.is_talking()).override_failure_message(
		"the enemy's opening turn was counted as the player's").is_false()
	var present: Array[Team.Faction] = [PLAYER, ENEMY]
	_stub.turn_manager.end_turn(present)   # ENEMY -> PLAYER
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


# --- the pre-mission briefing (#882) ---
#
# A MISSION_START beat fires at the COMMIT, so a line telling you what the map wants arrives after
# the roster, the loadout and the placement are already final. PRE_MISSION_START is the slot before
# any of that -- the phase opens on the bare board, the briefing plays, and the loadout screen waits
# for went_quiet. What is asserted here is the DIRECTOR's half; the screen's half is in
# tests/flow/test_pre_mission_draw.gd, which drives the real begin_mission.

func test_the_briefing_plays_and_the_mission_start_beat_still_waits_for_the_commit() -> void:
	_set_beats([
		_beat(DialogBeat.Trigger.PRE_MISSION_START, "A rifleman sits on the only ford."),
		_beat(DialogBeat.Trigger.MISSION_START, "Now we begin."),
	])
	assert_bool(_director.pre_mission_started()).override_failure_message(
		"the phase was told nothing would play").is_true()
	await _await_starts(1)

	# The briefing has to be the ONLY thing the phase queued, and a frame-count assert cannot see
	# that: a MISSION_START beat fired here would QUEUE behind the briefing rather than play, so
	# _starts reads 1 either way until the first timeline ends. Drain it and ask again.
	Dialogic.end_timeline(true)
	await Dialogic.timeline_ended
	await get_tree().process_frame
	assert_int(_starts).override_failure_message(
		"the MISSION_START beat was queued by the briefing").is_equal(1)
	assert_int(_quiets).override_failure_message(
		"something was still queued when the briefing ended").is_equal(1)

	# ...and it was not merely queued-and-dropped: the commit still plays it, so the beat is intact
	# in the fired-once-per-battle set rather than consumed by the phase.
	_director.mission_started()
	await _await_starts(2)


func test_the_briefing_does_not_arm_the_director() -> void:
	# The phase itself spawns and squads the whole roster, so an armed director would answer every
	# one of those squad_created emissions -- the same reason deploy_roster runs before the arm.
	_set_beats([
		_beat(DialogBeat.Trigger.PRE_MISSION_START, "Briefing."),
		_beat(DialogBeat.Trigger.SQUAD_FORMED, "Not yet."),
	])
	_set_steps([_step(DialogBeat.Trigger.SQUAD_FORMED, "Form a squad.")])
	_director.pre_mission_started()
	# Asked BEFORE the squad lands, because an armed director would ADVANCE past this one step and
	# answer "" again from the far end of the lesson -- the same reading for opposite reasons.
	assert_str(_director.active_instruction()).override_failure_message(
		"the lesson's first instruction was up before the battle").is_empty()
	await _await_starts(1)

	_stub.squad_manager.squad_created.emit(_player_squad())
	# Drained, not counted in place: a beat fired here QUEUES behind the briefing instead of
	# playing, so _starts reads 1 whether or not the director answered that squad.
	Dialogic.end_timeline(true)
	await Dialogic.timeline_ended
	await get_tree().process_frame
	assert_int(_starts).override_failure_message(
		"the briefing armed the director, so the draw tripped a beat").is_equal(1)


func test_went_quiet_waits_for_the_LAST_timeline_rather_than_the_first() -> void:
	_set_beats([
		_beat(DialogBeat.Trigger.PRE_MISSION_START, "First line."),
		_beat(DialogBeat.Trigger.PRE_MISSION_START, "Second line."),
	])
	_director.pre_mission_started()   # the first starts, the second queues behind it
	await _await_starts(1)
	Dialogic.end_timeline(true)
	await _await_starts(2)   # the second chained off timeline_ended
	assert_int(_quiets).override_failure_message(
		"the screen would have opened over the second line").is_equal(0)
	Dialogic.end_timeline(true)
	await Dialogic.timeline_ended
	await get_tree().process_frame
	assert_int(_quiets).is_equal(1)


func test_dialog_off_reports_nothing_to_say_so_the_screen_opens_at_once() -> void:
	# _fire CONSUMES the beat without playing it (#400), so there is no timeline to wait on and the
	# phase must not sit on a hidden screen forever waiting for a went_quiet that cannot come.
	PlayerSettings.set_on(PlayerSettings.Setting.SHOW_DIALOG, false)
	_set_beats([_beat(DialogBeat.Trigger.PRE_MISSION_START, "Unheard.")])
	assert_bool(_director.pre_mission_started()).is_false()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_starts).is_equal(0)


func test_a_restart_taken_mid_dialog_still_reports_that_the_briefing_will_play() -> void:
	# reset() ends the outgoing timeline WITHOUT awaiting it, so the retry's briefing is fired while
	# Dialogic still has one in hand: _fire QUEUES it rather than starting it, and _dialog_active is
	# already false. Reading that flag alone would report silence, reveal the loadout screen, and
	# then play the briefing over the top of it.
	_set_beats([_beat(DialogBeat.Trigger.MISSION_START, "The attempt that just ended.")])
	_director.mission_started()
	await _await_starts(1)
	_director.reset()
	_set_beats([_beat(DialogBeat.Trigger.PRE_MISSION_START, "The retry's briefing.")])
	assert_bool(_director.pre_mission_started()).override_failure_message(
		"a queued briefing was reported as nothing to say").is_true()
	await _await_starts(2)


# --- the #982 preview door ---

func _timeline(text: String) -> DialogicTimeline:
	var timeline := DialogicTimeline.new()
	timeline.from_text(text)
	return timeline


func test_preview_plays_a_timeline_over_an_unarmed_board() -> void:
	assert_bool(_director.preview(_timeline("torv: A previewed line."))).is_true()
	await _await_starts(1)


# The preview is for hearing a line, not for spending a beat: an author who previews the timeline
# a MISSION_START beat names must still get that beat when the mission starts.
func test_preview_does_not_spend_the_beat_that_shares_its_timeline() -> void:
	var beat := _beat(DialogBeat.Trigger.MISSION_START, "torv: The briefing.")
	_stub.scenario_manager.current_dialog_beats.append(beat)

	assert_bool(_director.preview(beat.timeline)).is_true()
	await _await_starts(1)
	Dialogic.end_timeline(true)
	await Dialogic.timeline_ended

	_director.mission_started()
	await _await_starts(2)


# Refuses rather than queues -- see the door's own header.
func test_preview_is_refused_while_something_is_already_talking() -> void:
	assert_bool(_director.preview(_timeline("torv: First."))).is_true()
	await _await_starts(1)

	assert_bool(_director.preview(_timeline("torv: Second."))).is_false()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_starts).is_equal(1)


func test_preview_refuses_a_null_timeline() -> void:
	assert_bool(_director.preview(null)).is_false()


# The latch has to come back down, or the NEXT preview is refused forever and so is every beat.
func test_a_finished_preview_goes_quiet_and_leaves_the_door_open() -> void:
	_director.went_quiet.connect(_count_quiet)
	assert_bool(_director.preview(_timeline("torv: A line."))).is_true()
	await _await_starts(1)
	Dialogic.end_timeline(true)
	await Dialogic.timeline_ended
	await get_tree().process_frame

	assert_int(_quiets).is_equal(1)   # the same signal the pre-mission screen waits on
	assert_bool(_director.preview(_timeline("torv: Another."))).is_true()
	await _await_starts(2)


# WHY preview sets _dialog_active rather than leaning on Dialogic.current_timeline: start() defers
# to the layout's ready, so current_timeline is a frame late, and a beat triggered in the SAME
# frame reads "nothing is talking".
#
# MEASURED, because the obvious guess is wrong: without the latch the beat does not play OVER the
# preview -- Dialogic absorbs the second start -- it is marked fired and SILENTLY SWALLOWED, and
# _pending stays empty. So the property is not "only one plays" (true either way, which is why a
# case asserting that passes against the bug); it is that the beat is still there afterwards.
func test_a_beat_triggered_in_the_same_frame_as_a_preview_queues_behind_it() -> void:
	_stub.scenario_manager.current_dialog_beats.append(
		_beat(DialogBeat.Trigger.MISSION_START, "torv: The briefing."))

	assert_bool(_director.preview(_timeline("torv: A previewed line."))).is_true()
	_director.mission_started()   # same frame, before the layout is ready

	await _await_starts(1)        # the preview alone; the beat is queued behind it
	Dialogic.end_timeline(true)
	await _await_starts(2)        # ...and the beat plays when the preview ends
