# The Pre-mission screen box (#46, dev 2026-10-05: "a standard checkbox ... whether or not a mission
# allows the pre missions screen"). Ticked, a roster board opens the phase as it always has.
# Unticked, the roster is still drawn but its authored placement stands and the battle begins, armed,
# at both fresh-start doors; a loadout committed while the box was ticked does not replay; and the
# box rides a save while a clear puts it back TICKED.
#
# Every case drives the real doors (begin_mission, restart_mission, commit_deployment) on the real
# game scene, test_pre_mission_restart.gd's fixture. The scratch missions are authored in memory and
# saved to user://, never into Scenarios/.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH := "user://__pre_mission_offered.tres"
const TEST_SAVE_DIR := "user://__test_saves_offered/"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const ROW_WIDTH := 10
const ZONE_CELLS := 5
const CAP := 2
# Inside the zone and past anything the cap can reach, so a unit standing here was put here by hand.
const FAR_CELL := Vector2i(ZONE_CELLS - 1, 0)

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController


func before_test() -> void:
	ScenarioManager.save_dir = TEST_SAVE_DIR
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
	ScenarioManager.save_dir = ScenarioManager.DEFAULT_SAVE_DIR
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# The shipped roster offering the most characters -- loaded, never asserted about (the content razor).
static func _largest_roster() -> String:
	var best := ""
	var most := -1
	for name: String in RosterCatalog.saved_rosters():
		var roster: Roster = RosterCatalog.resolve(name)
		var count := 0 if roster == null else roster.offered_entries().size()
		if count > most:
			best = name
			most = count
	return best


# A board whose whole player force is the roster's, with the box set as asked, saved to SCRATCH.
func _author(offered: bool) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = _largest_roster()
	sm.current_deployment_cap = CAP
	sm.current_offers_pre_mission = offered
	# Claimed before it is written (CLAUDE.md, the load() cache), so a board saved by an earlier case
	# can never load back in this one's place.
	var scenario := sm.capture_scenario("pre_mission_offered", true)
	scenario.take_over_path(SCRATCH)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _drawn_standing() -> int:
	var count := 0
	for unit: Unit in mc.roster_units():
		if game.is_deployed(unit):
			count += 1
	return count


# The battle is on: no phase, the turn begun, and the dialog ARMED -- an unticked box is a fresh start
# like any other, not the watch-only boot, whose disarm would silence the mission's opening lines.
func _assert_battle_began(when: String) -> void:
	assert_bool(mc.is_deploying()).override_failure_message(
		"%s: an unticked board opened the pre-mission phase" % when).is_false()
	assert_bool(mc._battle_begun).override_failure_message(
		"%s: the battle never began" % when).is_true()
	assert_bool(game.scenario_director._armed).override_failure_message(
		"%s: the battle began with the mission's dialog disarmed" % when).is_true()


func test_an_unticked_board_begins_the_battle_on_the_authored_draw() -> void:
	mc.begin_mission(_author(false))
	await await_idle_frame()

	_assert_battle_began("begin_mission")
	assert_int(_drawn_standing()).override_failure_message(
		"the roster's authored draw did not stand: nobody to play with").is_greater(0)


# The control: the same board with the box ticked still opens the phase, so the case above is not
# passing on a board that could never open one.
func test_a_ticked_board_still_opens_the_phase() -> void:
	mc.begin_mission(_author(true))
	await await_idle_frame()

	assert_bool(mc.is_deploying()).override_failure_message(
		"a ticked roster board did not open the phase").is_true()


func test_a_restart_of_an_unticked_board_does_not_open_the_phase_either() -> void:
	mc.begin_mission(_author(false))
	await await_idle_frame()

	mc.restart_mission()
	await await_idle_frame()

	_assert_battle_began("restart_mission")


# A loadout committed while the box was ticked must not stand again once it is unticked: the player
# could no longer see or change it.
func test_a_loadout_committed_while_ticked_does_not_replay_once_unticked() -> void:
	mc.begin_mission(_author(true))
	await await_idle_frame()
	var mover: Unit = null
	for unit: Unit in mc.roster_units():
		if game.is_deployed(unit):
			mover = unit
			break
	assert_bool(mover != null and mc.reposition(mover, FAR_CELL)).override_failure_message(
		"precondition: the hand placement this case is about was refused").is_true()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()
	var data: ScenarioData = load(SCRATCH)
	data.offers_pre_mission = false
	assert_int(ResourceSaver.save(data, SCRATCH)).is_equal(OK)

	mc.restart_mission()
	await await_idle_frame()

	_assert_battle_began("restart after unticking")
	assert_object(game.get_unit_at_cell(FAR_CELL)).override_failure_message(
		"the loadout committed while the box was ticked stood again on an unticked board").is_null()


# The box rides a capture and an apply, and a clear puts it back TICKED -- the field's own default, so
# a board authored after a clear opens its phase as every board did before the box existed.
func test_the_box_rides_a_save_and_a_clear_ticks_it_again() -> void:
	sm.current_offers_pre_mission = false
	var saved := sm.capture_scenario("box_round_trip", true)
	assert_bool(saved.offers_pre_mission).override_failure_message("the capture dropped the box").is_false()

	sm.clear_board()
	assert_bool(sm.current_offers_pre_mission).override_failure_message(
		"a clear left the box unticked for the next board").is_true()

	sm.apply_scenario(saved, "")
	assert_bool(sm.current_offers_pre_mission).override_failure_message("the apply dropped the box").is_false()
