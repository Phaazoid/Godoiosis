# The #397 store move: lesson content lives on ScenarioManager and SURVIVES capture.
#
# The bug this pins: capture_scenario carried every authored field except dialog_beats and
# tutorial_steps, so the Scenario tool's Update button silently erased a mission's lesson.
# Real Main scene, real capture/apply -- the wire, not the two ends.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func test_capture_carries_the_lesson_and_apply_round_trips_it() -> void:
	var beat := DialogBeat.new()
	beat.trigger = DialogBeat.Trigger.STEP_COMPLETED
	beat.step = 2
	beat.timeline = DialogicTimeline.new()
	var step := TutorialStep.new()
	step.text = "Select Torv."
	step.unit_name = "Torv"
	game.scenario_manager.current_dialog_beats.append(beat)
	game.scenario_manager.current_tutorial_steps.append(step)

	var captured: ScenarioData = game.scenario_manager.capture_scenario("roundtrip")
	assert_int(captured.dialog_beats.size()).is_equal(1)
	assert_int(captured.tutorial_steps.size()).is_equal(1)
	assert_str(captured.tutorial_steps[0].text).is_equal("Select Torv.")

	game.scenario_manager.apply_scenario(captured)   # routes through clear_board -> empty stores
	assert_int(game.scenario_manager.current_dialog_beats.size()).is_equal(1)
	assert_int(game.scenario_manager.current_tutorial_steps.size()).is_equal(1)


func test_clear_board_empties_the_lesson_stores() -> void:
	game.scenario_manager.current_dialog_beats.append(DialogBeat.new())
	game.scenario_manager.current_tutorial_steps.append(TutorialStep.new())
	game.scenario_manager.clear_board()
	assert_bool(game.scenario_manager.current_dialog_beats.is_empty()).is_true()
	assert_bool(game.scenario_manager.current_tutorial_steps.is_empty()).is_true()


func test_a_disarmed_director_does_not_lose_the_content_a_capture_needs() -> void:
	# The old shape's failure: disarm() destroyed the director's COPY of the content, so a
	# resume-then-Update wiped the lesson. Content and execution are separate now.
	game.scenario_manager.current_tutorial_steps.append(TutorialStep.new())
	game.scenario_director.disarm()
	assert_int(game.scenario_manager.capture_scenario("after-disarm").tutorial_steps.size()).is_equal(1)


# --- #982: the beat must hold the FILE-BACKED timeline ---
#
# DialogicTimeline.events is not an @export. A timeline with no resource_path therefore serializes
# INLINE into the mission .tres and comes back with nothing in it, so the beat fires silence -- the
# #177 embed trap, one resource along. The page writes the file and hands the beat what load()
# returns, and this is the case that says so: it round-trips through a real save.
func test_a_beat_holding_a_loaded_timeline_survives_a_save_where_an_in_memory_one_would_not() -> void:
	var dtl := "user://test_dialog_capture/scratch.dtl"
	var saved := "user://test_dialog_capture/board.tres"
	assert_bool(DialogicSource.write(dtl, "torv: A line that has to survive.")).is_true()

	var beat := DialogBeat.new()
	beat.trigger = DialogBeat.Trigger.PRE_MISSION_START
	beat.timeline = load(dtl) as DialogicTimeline   # the file-backed object, not a fresh one
	game.scenario_manager.current_dialog_beats.append(beat)

	var captured: ScenarioData = game.scenario_manager.capture_scenario("embed_probe")
	assert_int(ResourceSaver.save(captured, saved)).is_equal(OK)
	var reloaded := ResourceLoader.load(saved, "", ResourceLoader.CACHE_MODE_IGNORE) as ScenarioData

	assert_int(reloaded.dialog_beats.size()).is_equal(1)
	var timeline: DialogicTimeline = reloaded.dialog_beats[0].timeline
	assert_object(timeline).is_not_null()
	timeline.process()
	assert_int(timeline.events.size()).override_failure_message(
		"the timeline came back empty -- it was embedded rather than referenced").is_greater(0)

	for path: String in [dtl, dtl + ".uid", saved]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
