# The pre-mission draw (#737), driven through the REAL doors. A board that names a roster puts that
# roster's units on its deployment zone and then plays; a board that names none boots exactly as it
# did before.
#
# Every case fires the real sequence rather than calling deploy_roster directly, because WHERE the
# draw is called from is the whole design: it sits at the two fresh-start doors, before the director
# arms, and nowhere near apply_scenario -- which every board load crosses, resume included.
#
# The scratch mission is authored IN MEMORY and saved to user://, never into Scenarios/ (which
# Mission Select scans and #9's integrity suite sweeps). save_dir is redirected for the same reason
# test_save_slots.gd redirects it: the suite shares user:// with the dev's own play saves.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH := "user://__pre_mission_737.tres"
const TEST_SAVE_DIR := "user://__test_saves_737/"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const ROW_WIDTH := 8                  # the known-walkable strip every case authors on

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController


func before_test() -> void:
	ScenarioManager.save_dir = TEST_SAVE_DIR
	_wipe_saves()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	mc = game.mission_controller
	sm = game.scenario_manager
	mc._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	_wipe_saves()
	ScenarioManager.save_dir = ScenarioManager.DEFAULT_SAVE_DIR
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


static func _wipe_saves() -> void:
	if not DirAccess.dir_exists_absolute(TEST_SAVE_DIR):
		return
	for file in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute(TEST_SAVE_DIR + file)


# The one roster on disk, or "" -- a content precondition, never an assertion (the content razor:
# what a shipped roster HOLDS is authored, and a suite may not pin it).
func _a_roster() -> String:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the draw cannot be exercised")
		return ""
	return names[0]


func _roster_size(name: String) -> int:
	var roster: Roster = RosterCatalog.resolve(name)
	return 0 if roster == null else roster.entries.size()


# Author a board with `zone_cells` deployment cells and NO authored cast, so its whole player force
# is the draw. Returns the saved path, or "" when there is no roster to name.
func _author(roster: String, cap: int, zone_cells: int, steps: Array[TutorialStep] = []) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(zone_cells):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = roster
	sm.current_deployment_cap = cap
	sm.current_tutorial_steps = steps

	var scenario := sm.capture_scenario("pre_mission_737", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _units() -> Array:
	return game.units_root.get_children()


func _deployed_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for unit: Unit in _units():
		cells.append(unit.movement.cell)
	cells.sort()
	return cells


# --- the draw itself ---

func test_beginning_a_roster_mission_stands_its_units_in_the_deployment_zone() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	var path := _author(roster, 3, 4)

	mc.begin_mission(path)
	await await_idle_frame()

	assert_int(_units().size()).override_failure_message(
		"the draw put nobody on the board").is_equal(3)
	for unit: Unit in _units():
		assert_bool(game.zone_manager.contains("landing", unit.movement.cell)).override_failure_message(
			"%s stood outside the deployment zone at %s" % [unit.get_unit_name(), unit.movement.cell]
		).is_true()
	# ...and the mission is actually under way, which is the other half of "and then plays".
	assert_bool(mc.is_over()).is_false()


func test_a_cap_of_zero_sends_as_many_as_the_zone_holds() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	var room := 3
	if _roster_size(roster) <= room:
		push_warning("the shipped roster is not larger than the zone, so the cap cannot be shown")
		return
	var path := _author(roster, PreMission.NO_CAP, room)

	mc.begin_mission(path)
	await await_idle_frame()

	assert_int(_units().size()).is_equal(room)


func test_a_zone_smaller_than_the_cap_deploys_only_what_fits() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	var path := _author(roster, 6, 2)

	mc.begin_mission(path)
	await await_idle_frame()

	assert_int(_units().size()).is_equal(2)


func test_a_board_that_names_no_roster_boots_exactly_as_it_did_before() -> void:
	var path := _author("", 0, 4)

	mc.begin_mission(path)
	await await_idle_frame()

	assert_array(_units()).override_failure_message(
		"a roster-less board grew units from somewhere").is_empty()


# --- where it is called from, which is the design ---

# THE case nothing else catches, and the reason the draw is not inside apply_scenario: a save slot
# records `roster` like any other field, so a deploy down there fires again on the way back in --
# on top of the units the save just restored. Its mutant is moving the call into apply_scenario.
func test_a_resume_does_not_draw_the_roster_a_second_time() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	var path := _author(roster, 3, 4)
	mc.begin_mission(path)
	await await_idle_frame()
	var deployed: int = _units().size()
	assert_int(deployed).is_greater(0)

	assert_bool(sm.save_to_slot(1)).is_true()
	sm.clear_board()
	await await_idle_frame()
	assert_array(_units()).is_empty()

	mc.resume_from_slot(1)
	await await_idle_frame()

	assert_int(_units().size()).override_failure_message(
		"the resume re-drew the roster on top of the force it restored").is_equal(deployed)


# The draw spawns solo squads, each emitting squad_created, which an ARMED ScenarioDirector answers
# by advancing a SQUAD_FORMED step -- so a three-unit draw completes the lesson before the player
# has touched anything. The mutant is swapping deploy_roster and the arm.
func test_the_draw_lands_before_the_director_arms() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	var step := TutorialStep.new()
	step.text = "Form a squad"
	step.done_when = DialogBeat.Trigger.SQUAD_FORMED   # any player leader
	var steps: Array[TutorialStep] = [step]
	var path := _author(roster, 3, 4, steps)

	mc.begin_mission(path)
	await await_idle_frame()

	assert_int(_units().size()).override_failure_message(
		"precondition: nobody deployed, so the ordering was never exercised").is_greater(0)
	assert_str(game.scenario_director.active_instruction()).override_failure_message(
		"the draw's own squads completed the lesson before the player could act").is_equal(step.text)


# A restart re-runs the same deterministic walk, which is why the phase needs no buffer to preserve.
func test_a_restart_puts_the_same_characters_back_on_the_same_cells() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	var path := _author(roster, 3, 4)
	mc.begin_mission(path)
	await await_idle_frame()
	var first: Array[Vector2i] = _deployed_cells()
	assert_array(first).is_not_empty()

	mc.restart_mission()
	await await_idle_frame()

	assert_array(_deployed_cells()).override_failure_message(
		"a restart drew a different force, or drew onto different cells").is_equal(first)


# --- what a capture records ---

func test_an_authored_capture_leaves_the_drawn_units_out_of_the_mission_file() -> void:
	# The trip this guards: play a roster mission, F1, tweak something, Update. Recording the draw
	# writes it into unit_entries, and the NEXT boot draws a second force on top of it.
	var roster := _a_roster()
	if roster == "":
		return
	var path := _author(roster, 3, 4)
	mc.begin_mission(path)
	await await_idle_frame()
	assert_int(_units().size()).is_greater(0)

	var authored := sm.capture_scenario("re_authored", true)
	assert_array(authored.unit_entries).override_failure_message(
		"an authored save baked the roster's draw into the board").is_empty()


func test_a_full_capture_keeps_them_because_a_resume_has_to_restore_them() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	var path := _author(roster, 3, 4)
	mc.begin_mission(path)
	await await_idle_frame()
	var deployed: int = _units().size()

	var snapshot := sm.capture_scenario("mid_battle", false)
	assert_int(snapshot.unit_entries.size()).override_failure_message(
		"a save slot dropped the drawn force, so a resume would come back short").is_equal(deployed)
