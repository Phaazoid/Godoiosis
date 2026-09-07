# A restart returns to the phase with what the player CHOSE, not with the walk the author wrote
# (#763). The choices are five things now, not one -- who stands and where, squads, gear, jobs and
# fitted mods -- and every one of them was made again by hand after a retry.
#
# Each case drives the REAL sequence: enter the phase, change something through the door the phase
# itself uses, commit, restart, and ask the board. The buffer is only ever observed through what
# came back standing and carrying, never read off MissionController directly -- a test that
# asserted on the snapshot object would pass just as happily if nothing replayed it.
#
# The scratch missions are authored IN MEMORY and saved to user://, never into Scenarios/ (which
# Mission Select scans and #9's integrity suite sweeps) -- test_pre_mission_draw.gd's setup, for its
# reasons, including the save_dir redirect that keeps this off the dev's own play saves.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH := "user://__pre_mission_763.tres"
const OTHER_SCRATCH := "user://__pre_mission_763_other.tres"   # a SECOND mission, for the leak case
const TEST_SAVE_DIR := "user://__test_saves_763/"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const ROW_WIDTH := 10
const ZONE_CELLS := 5
const CAP := 2
# Inside the zone and past anything the cap can reach, so a unit standing here can only have been
# put here by hand -- which is the whole of what these cases are asking about.
const FAR_CELL := Vector2i(ZONE_CELLS - 1, 0)
const SPARE_CELL := Vector2i(ZONE_CELLS - 2, 0)

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
	for path: String in [SCRATCH, OTHER_SCRATCH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _wipe_saves() -> void:
	if not DirAccess.dir_exists_absolute(TEST_SAVE_DIR):
		return
	for file in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute(TEST_SAVE_DIR + file)


# The one roster on disk, or "" -- a content precondition, never an assertion (the content razor).
func _a_roster() -> String:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the phase cannot be exercised")
		return ""
	return names[0]


func _roster_size(name: String) -> int:
	var roster: Roster = RosterCatalog.resolve(name)
	return 0 if roster == null else roster.entries.size()


# A board whose whole player force is the roster's: one walkable row, a deployment zone across the
# left of it, and nothing authored standing on it.
func _author(roster: String, path: String) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = roster
	sm.current_deployment_cap = CAP

	var scenario := sm.capture_scenario("pre_mission_763", true)
	assert_int(ResourceSaver.save(scenario, path)).is_equal(OK)
	return path


# Boot a roster board and stop in the phase. False when the shipped content cannot carry the case,
# so a caller returns rather than asserting about what a roster HOLDS.
#
# It also refuses on repeated character names: every case here identifies a character by name across
# a board teardown, since the Unit nodes themselves are freed and respawned by the restart.
func _enter_phase(path := SCRATCH) -> bool:
	var roster := _a_roster()
	if roster == "" or _roster_size(roster) <= CAP:
		push_warning("the shipped roster is not larger than the cap, so the phase has no reserve")
		return false
	mc.begin_mission(_author(roster, path))
	await await_idle_frame()
	var seen: Dictionary = {}
	for unit: Unit in mc.roster_units():
		if seen.has(unit.get_unit_name()):
			push_warning("the shipped roster draws two characters of one name; identity by name cannot serve")
			return false
		seen[unit.get_unit_name()] = true
	return true


func _deployed_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for unit: Unit in game.units_root.get_children():
		cells.append(unit.movement.cell)
	cells.sort()
	return cells


# WHO is standing where, by character name -- the handle that survives the restart's teardown.
func _standing_names() -> Dictionary:
	var where: Dictionary = {}
	for unit: Unit in game.units_root.get_children():
		where[unit.get_unit_name()] = unit.movement.cell
	return where


func _reserve_names() -> Array[String]:
	var names: Array[String] = []
	for unit: Unit in game.reserve_root.get_children():
		names.append(unit.get_unit_name())
	return names


func _named(name: String) -> Unit:
	for unit: Unit in mc.roster_units():
		if unit.get_unit_name() == name:
			return unit
	return null


func _first_standing() -> Unit:
	for unit: Unit in mc.roster_units():
		if game.is_deployed(unit):
			return unit
	return null


func _first_waiting() -> Unit:
	for unit: Unit in mc.roster_units():
		if not game.is_deployed(unit):
			return unit
	return null


func _carried_names(unit: Unit) -> Array[String]:
	var names: Array[String] = []
	for item: Item in unit.inventory:
		if item != null:
			names.append(item.display_name)
	return names


# Hand `unit` the first stash item it will actually take, through the phase's own judge. Returns the
# item's name, or "" when nothing in the stash can move -- a content precondition, not a failure.
func _give_from_stash(unit: Unit) -> String:
	var loadout: Loadout = mc.loadout()
	for item: Item in loadout.stash.duplicate():
		if loadout.move(item, null, unit) == "":
			return item.display_name
	return ""


# --- placement ---

func test_a_unit_the_player_moved_comes_back_where_they_put_it() -> void:
	if not await _enter_phase():
		return
	var mover: Unit = _first_standing()
	var moved_name: String = mover.get_unit_name()
	assert_bool(mc.reposition(mover, FAR_CELL)).override_failure_message(
		"precondition: the hand placement this case is about was refused").is_true()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()

	mc.restart_mission()
	await await_idle_frame()

	assert_bool(mc.is_deploying()).override_failure_message(
		"the restart did not return to the phase at all").is_true()
	assert_dict(_standing_names()).override_failure_message(
		"the restart redrew the author's opening position over the player's").contains_key_value(
			moved_name, FAR_CELL)


func test_who_the_player_left_behind_stays_behind() -> void:
	if not await _enter_phase():
		return
	# BOTH picked before either moves: _first_waiting() asks the live board, so asked after the
	# undeploy below it would hand back the very unit that was just benched.
	var benched: Unit = _first_standing()
	var called_up: Unit = _first_waiting()
	var benched_name: String = benched.get_unit_name()
	var called_name: String = called_up.get_unit_name()
	game.undeploy_unit(benched)
	assert_bool(game.deploy_unit(called_up, SPARE_CELL)).override_failure_message(
		"precondition: the substitute this case is about could not be placed").is_true()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()

	mc.restart_mission()
	await await_idle_frame()

	assert_array(_reserve_names()).override_failure_message(
		"a unit the player benched was drawn back onto the board").contains([benched_name])
	assert_dict(_standing_names()).override_failure_message(
		"the substitute the player called up was sent back to the reserve").contains_key_value(
			called_name, SPARE_CELL)


# --- gear ---

# BOTH SIDES OF THE ROSTER, in one case on purpose: the replay applies its rows to every drawn unit
# rather than only the standing ones, and a reserve unit's kit is exactly as much the player's
# choice as a deployed one's.
func test_gear_taken_out_of_the_stash_is_still_carried_after_a_restart() -> void:
	if not await _enter_phase():
		return
	var standing: Unit = _first_standing()
	var waiting: Unit = _first_waiting()
	var standing_name: String = standing.get_unit_name()
	var waiting_name: String = waiting.get_unit_name()
	var to_standing: String = _give_from_stash(standing)
	var to_waiting: String = _give_from_stash(waiting)
	if to_standing == "" or to_waiting == "":
		push_warning("the shipped stash holds nothing these two characters will take")
		return
	var stash_left: int = mc.loadout().stash.size()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()

	mc.restart_mission()
	await await_idle_frame()

	assert_array(_carried_names(_named(standing_name))).override_failure_message(
		"a deployed unit lost the gear the player gave it").contains([to_standing])
	assert_array(_carried_names(_named(waiting_name))).override_failure_message(
		"a RESERVE unit lost the gear the player gave it").contains([to_waiting])
	assert_int(mc.loadout().stash.size()).override_failure_message(
		"the stash refilled itself with gear the player had already taken out").is_equal(stash_left)


# --- squads ---

func test_a_squad_built_in_the_phase_is_a_squad_again() -> void:
	if not await _enter_phase():
		return
	var leader: Unit = _first_standing()
	var follower: Unit = null
	for unit: Unit in mc.roster_units():
		if unit != leader and game.is_deployed(unit):
			follower = unit
			break
	if follower == null:
		push_warning("the cap stands only one unit, so there is no second to squad with")
		return
	var leader_name: String = leader.get_unit_name()
	var follower_name: String = follower.get_unit_name()
	game.squad_manager.join_squad(follower, leader.squad)
	assert_int(leader.squad.get_members().size()).override_failure_message(
		"precondition: the squad this case is about was never formed").is_equal(2)
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()

	mc.restart_mission()
	await await_idle_frame()

	var rebuilt: Unit = _named(leader_name)
	assert_object(rebuilt.squad).is_not_null()
	var names: Array[String] = []
	for member: Unit in rebuilt.squad.get_members():
		names.append(member.get_unit_name())
	assert_array(names).override_failure_message(
		"the squad the player built came back as solos").contains([leader_name, follower_name])


# --- what the buffer belongs to ---

# The dev's ruling (2026-09-07): the buffer belongs to the MISSION, not to the button that got you
# there, so coming back through Mission Select restores it the same way a Retry does.
func test_re_entering_the_same_mission_from_the_title_restores_it_too() -> void:
	if not await _enter_phase():
		return
	var mover: Unit = _first_standing()
	var moved_name: String = mover.get_unit_name()
	assert_bool(mc.reposition(mover, FAR_CELL)).is_true()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()

	mc.begin_mission(SCRATCH)
	await await_idle_frame()

	assert_dict(_standing_names()).override_failure_message(
		"a mission re-entered from the title forgot the force the player took into it"
		).contains_key_value(moved_name, FAR_CELL)


func test_a_different_mission_does_not_inherit_the_buffer() -> void:
	if not await _enter_phase():
		return
	assert_bool(mc.reposition(_first_standing(), FAR_CELL)).is_true()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()
	var carried_over: Array[Vector2i] = _deployed_cells()

	sm.clear_board()
	await await_idle_frame()
	mc.begin_mission(_author(_a_roster(), OTHER_SCRATCH))
	await await_idle_frame()

	assert_array(_deployed_cells()).override_failure_message(
		"another mission opened on the force staged for the last one").is_not_equal(carried_over)
	assert_array(_deployed_cells()).override_failure_message(
		"the second mission did not open on its own authored walk").is_equal(
			[Vector2i(0, 0), Vector2i(1, 0)])


# --- the way back to the author's own opening position ---

# THE ORDERING CASE. restart_mission reads _deploying to decide whether to drop the buffer, and
# reload_current -> clear_board -> reset() clears that flag -- so the read has to be the function's
# first act. Asked one line lower it answers "no" every time, this ruling silently inverts, and the
# player has no door back to the draw the author wrote.
func test_a_restart_taken_inside_the_phase_puts_the_authors_own_force_back() -> void:
	if not await _enter_phase():
		return
	assert_bool(mc.reposition(_first_standing(), FAR_CELL)).is_true()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()

	mc.restart_mission()   # back into the phase, standing where the player left them
	await await_idle_frame()
	assert_array(_deployed_cells()).override_failure_message(
		"precondition: the buffer never replayed, so dropping it cannot be observed").contains(
			[FAR_CELL])

	mc.restart_mission()   # ...and again, from INSIDE the phase
	await await_idle_frame()

	assert_bool(mc.is_deploying()).is_true()
	assert_array(_deployed_cells()).override_failure_message(
		"a restart taken inside the phase replayed the buffer instead of dropping it").is_equal(
			[Vector2i(0, 0), Vector2i(1, 0)])


# A BUFFER THE BOARD CAN NO LONGER HOLD must not start a battle with nobody in it. Both fresh-start
# doors gate the phase on a non-zero draw, so a replay that stands nobody has to fall through to the
# authored walk rather than returning 0 -- otherwise the mission opens with the whole roster in the
# reserve and the defeat floor waiting for a turn to end.
#
# Reached by rewriting the buffer's own cells rather than by repainting the board, because it takes
# the dev tools between two attempts to reach honestly and the branch is worth a case either way.
func test_a_buffer_whose_cells_the_board_no_longer_has_redraws_instead_of_starting_empty() -> void:
	if not await _enter_phase():
		return
	assert_bool(mc.reposition(_first_standing(), FAR_CELL)).is_true()
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()
	for entry: ScenarioUnitEntry in mc._staged.entries:
		entry.cell = Vector2i(-5, -5)   # off the map entirely: can_spawn_at refuses every one

	mc.restart_mission()
	await await_idle_frame()

	assert_bool(mc.is_deploying()).override_failure_message(
		"the mission started with nobody on the board instead of redrawing").is_true()
	assert_array(_deployed_cells()).override_failure_message(
		"an unusable buffer left the board half-staged rather than falling back").is_equal(
			[Vector2i(0, 0), Vector2i(1, 0)])


# NOT TESTED, deliberately: the pause row's rename inside the phase. It is one conditional over two
# literals with no state to get wrong, and a case for it would pin the wording of a button -- which
# is authored content, and the razor says a suite may not hold it still. Checked by hand instead.
