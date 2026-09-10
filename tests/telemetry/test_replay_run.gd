# WHAT A RUN FOLDER READS BACK AS (#871), and in particular what happens when the board in it names
# content this build cannot load.
#
# These write real .tres to a scratch folder and load them back, because the fault being pinned lives
# in GODOT'S LOADER: a dangling ext_resource is a hard parse error for the WHOLE file, so there is no
# partial board to be had and nothing built in memory would behave the same way.
# tests/core/test_content_repair.gd pins that premise itself.
#
# A run recorded on SOMEBODY ELSE'S build is what made this matter -- #865 brought those down -- and
# a moved .tres is the shape #596 already produced once for real.
extends GdUnitTestSuite

# Its OWN scratch root. test_replay_driver.gd owns user://__replay_test/, and two suite files sharing
# one folder is two tests fighting over it the first time they land in the same shard.
const SCRATCH_ROOT := "user://__replay_run_test/"
const SD_SCRIPT := "res://Classes/flow/ScenarioData.gd"
const GONE_POSE := "res://Scenarios/__test_no_such_pose.tres"
const GONE_SCRIPT := "res://Classes/flow/__test_no_such_script.gd"
const RUN_ID := "2026-09-10_00-00-00_fixture0"


func before_test() -> void:
	TelemetryStore.reset_for_test()
	TelemetryStore.root = SCRATCH_ROOT
	TelemetryStore.persistence_enabled = true
	_wipe(SCRATCH_ROOT)


func after_test() -> void:
	# The repair registry is static and outlives the case that filled it.
	ContentRepair.forget(_board_path())
	_wipe(SCRATCH_ROOT)
	TelemetryStore.reset_for_test()
	await await_idle_frame()


func _board_path() -> String:
	return TelemetryStore.run_dir(RUN_ID) + ReplayRun.BOARD_FILE


# A ScenarioData the way ResourceSaver writes one, plus whatever header and body lines a case adds.
# Two readable event lines go beside it: without them can_replay() would be answering about an empty
# log rather than about the board, which is what every case here is actually asking.
func _stage_run(extra_refs: Array[String], extra_props: Array[String],
		script_path := SD_SCRIPT) -> void:
	var refs: Array[String] = ['[ext_resource type="Script" path="%s" id="1_sd"]' % script_path]
	refs.append_array(extra_refs)
	var body: Array[String] = ['script = ExtResource("1_sd")', 'scenario_name = "Fixture"']
	body.append_array(extra_props)
	var dir := TelemetryStore.run_dir(RUN_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	var events := FileAccess.open(dir + ReplayRun.EVENTS_FILE, FileAccess.WRITE)
	events.store_line(JSON.stringify({
		"seq": 0, "t_ms": 0, "round": 1, "event": "mission_start",
		"scenario_name": "Fixture", "roster": []}))
	events.store_line(JSON.stringify({
		"seq": 1, "t_ms": 10, "round": 1, "event": "mission_end", "outcome": "VICTORY"}))
	events.close()
	var board := FileAccess.open(dir + ReplayRun.BOARD_FILE, FileAccess.WRITE)
	board.store_string('[gd_resource type="Resource" script_class="ScenarioData" format=3]\n\n'
		+ "\n".join(refs) + "\n\n[resource]\n" + "\n".join(body) + "\n")
	board.close()


# The one dangling reference every degraded case here uses: a CameraPose that is not on disk, held by
# a single property, so the repair's strip has a clean edge to cut on.
func _stage_degraded_run() -> void:
	_stage_run(['[ext_resource type="Resource" path="%s" id="2_gone"]' % GONE_POSE],
		['camera_start = ExtResource("2_gone")'])


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir + sub + "/")
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + file)
	DirAccess.remove_absolute(dir)


# ==============================================================================
#  The board that lost a reference
# ==============================================================================

func test_a_board_that_lost_a_reference_still_loads_and_names_what_it_lost() -> void:
	_stage_degraded_run()
	var run := ReplayRun.load_run(RUN_ID)
	assert_object(run.board).override_failure_message(
		"a board whose only damage is one dangling reference must still load").is_not_null()
	# Everything that did not depend on the missing file came back untouched.
	assert_str(run.board.scenario_name).is_equal("Fixture")
	assert_array(run.degraded).is_not_empty()
	assert_str("\n".join(run.degraded)).override_failure_message(
		"the degradation must NAME the reference: %s" % str(run.degraded)).contains(GONE_POSE)
	# And it is not a refusal. The dev's 2026-09-09 ruling: seed it, mark it untrusted.
	assert_array(run.problems).is_empty()
	assert_bool(run.can_replay()).is_true()


# THE NON-VACUITY GUARD for every case above: if a clean board reported degradation too, they would
# all pass while the field meant nothing.
func test_a_clean_board_reports_no_degradation() -> void:
	var none: Array[String] = []
	_stage_run(none, none)
	var run := ReplayRun.load_run(RUN_ID)
	assert_object(run.board).is_not_null()
	assert_array(run.degraded).override_failure_message(
		"a board with nothing missing must not be called degraded").is_empty()
	assert_bool(run.can_replay()).is_true()


# ContentRepair REFUSES to strip a missing Script, deliberately -- stripping it would change what the
# resource IS. So this branch still fails, and what this ticket asks of it is that it fail with the
# reference NAMED. A board carries ~15 script references out of ~56, so this is a third of the ways a
# run from another build can arrive broken, and the only one the repair cannot help with.
#
# The board's OWN script is the one taken away, because that is both the realistic shape (rename
# ScenarioData.gd and every recorded board on earth says this) and the only one that bites: a
# dangling ext_resource NOTHING USES does not fail the file -- see test_content_repair.gd.
func test_a_board_whose_missing_reference_is_a_script_refuses_and_names_it() -> void:
	var none: Array[String] = []
	_stage_run(none, none, GONE_SCRIPT)
	var run := ReplayRun.load_run(RUN_ID)
	assert_object(run.board).is_null()
	assert_bool(run.can_replay()).is_false()
	assert_str("\n".join(run.problems)).override_failure_message(
		"a refused board must name what it could not load: %s" % str(run.problems)).contains(GONE_SCRIPT)


# THE REPORT MUST NOT BE READ OFF ContentRepair'S REGISTRY, and this is the case that proves it.
# load_tolerant erases its own repair record whenever a load comes back clean -- and the SECOND look
# at one run is a clean load, because the repaired board took over that path in the resource cache.
# ReplayTool holds the previous ReplayRun while it builds the next one, so that cache entry is alive
# at exactly the moment this happens for real.
func test_looking_at_one_degraded_run_twice_reports_the_same_both_times() -> void:
	_stage_degraded_run()
	var first := ReplayRun.load_run(RUN_ID)
	var second := ReplayRun.load_run(RUN_ID)
	assert_array(first.degraded).is_not_empty()
	assert_array(second.degraded).override_failure_message(
		"the second look said %s where the first said %s"
		% [str(second.degraded), str(first.degraded)]).is_equal(first.degraded)
	# HELD TO THE END ON PURPOSE: dropping `first` would free the repaired board and its cache entry
	# with it, and the second load would miss the cache -- passing this case vacuously.
	assert_object(first.board).is_not_null()


# A run's board is a frozen snapshot of a mission somebody else played. Left in the registry it would
# appear in every later BoardLint report as authored content the dev is told to go and restore.
func test_a_runs_board_is_not_left_in_the_repair_registry() -> void:
	_stage_degraded_run()
	var run := ReplayRun.load_run(RUN_ID)
	assert_array(run.degraded).is_not_empty()   # the repair DID happen, else this is vacuous
	assert_array(ContentRepair.repaired_paths()).not_contains([_board_path()])
