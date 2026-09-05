# The roster spawns as off-board units (#738) -- the mechanism that lets every wielder-taking
# predicate serve the pre-mission screen unchanged, and the riskiest ticket in #731.
#
# Two failure modes are the whole point, and both are invisible to a suite that only checks the
# happy path:
#
#   * undeployed units under units_root are LIVING PLAYER UNITS -- the #96 defeat floor never fires,
#     present_factions never drops PLAYER, and the AI weighs nine phantoms standing at (0, 0);
#   * a holding parent outside clear_board's teardown survives a board swap, pointing into a board
#     that has been freed (#107's shape, one node over).
#
# The named mutant for the first is: parent the reserve under units_root and confirm the defeat case
# reds. Note it is DEFEAT and not ROUT -- rout asks about HOSTILE factions, so extra player units do
# not touch it; what they break is the floor that says the last player unit was the last one.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const SCRATCH := "user://__off_board_roster_738.tres"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 8

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController


func before_test() -> void:
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
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _a_roster() -> String:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the off-board half cannot be exercised")
		return ""
	return names[0]


func _roster_size(name: String) -> int:
	var roster: Roster = RosterCatalog.resolve(name)
	return 0 if roster == null else roster.entries.size()


# A board with `cap` deployable cells' worth of roster and, optionally, one authored ENEMY -- which
# is what lets `contested` latch, without which no board can ever report DEFEAT (#96 doctrine 3).
func _author(roster: String, cap: int, with_enemy: bool) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(4):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	if with_enemy:
		assert_object(game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(7, 0))) \
			.override_failure_message("precondition: the enemy would not spawn").is_not_null()
	sm.current_roster = roster
	sm.current_deployment_cap = cap

	var scenario := sm.capture_scenario("off_board_738", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _reserve() -> Array:
	return game.reserve_root.get_children()


func _player_units_on_board() -> Array[Unit]:
	var found: Array[Unit] = []
	for unit: Unit in game.units_root.get_children():
		if unit.get_faction() == Team.Faction.PLAYER:
			found.append(unit)
	return found


# --- the two failure modes ---

# THE case, and the one the named mutant reds. Under it the nine undeployed characters are living
# player units on the board, so the mission can be neither lost nor left: only Quit.
func test_the_defeat_floor_fires_with_the_undeployed_roster_standing_by() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	if _roster_size(roster) < 2:
		push_warning("the shipped roster deploys entirely, so nothing would be left in reserve")
		return
	var path := _author(roster, 1, true)

	mc.begin_mission(path)
	await await_idle_frame()
	assert_array(_reserve()).override_failure_message(
		"precondition: nobody was left undeployed, so the case proves nothing").is_not_empty()

	mc.check()   # both sides up: latches `contested`, without which nothing can be lost
	var deployed: Array[Unit] = _player_units_on_board()
	assert_int(deployed.size()).is_equal(1)
	deployed[0].die()
	mc.check()

	assert_int(mc.outcome).override_failure_message(
		"the last player unit fell and the mission did not end -- the undeployed roster is being "
		+ "counted as a living force on the board").is_equal(MissionRules.Outcome.DEFEAT)


func test_a_board_swap_takes_the_undeployed_units_with_it() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	var path := _author(roster, 1, false)
	mc.begin_mission(path)
	await await_idle_frame()
	assert_array(_reserve()).is_not_empty()

	sm.clear_board()
	await await_idle_frame()

	assert_array(_reserve()).override_failure_message(
		"the reserve outlived its board -- every unit in it now points into a freed one").is_empty()


# --- what is on the board and what is not ---

func test_only_the_cap_stands_on_the_board_and_the_rest_wait_off_it() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	var size := _roster_size(roster)
	if size < 3:
		push_warning("the shipped roster is too small to split")
		return
	var path := _author(roster, 2, false)

	mc.begin_mission(path)
	await await_idle_frame()

	assert_int(_player_units_on_board().size()).is_equal(2)
	assert_int(_reserve().size()).override_failure_message(
		"the roster's undeployed half did not land in the reserve").is_equal(size - 2)


func test_a_save_records_the_board_and_never_the_reserve() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	if _roster_size(roster) < 2:
		return
	var path := _author(roster, 1, false)
	mc.begin_mission(path)
	await await_idle_frame()

	# A FULL capture -- the one that keeps drawn units (#737). Even it must not reach off the board.
	var snapshot := sm.capture_scenario("mid_battle", false)
	assert_int(snapshot.unit_entries.size()).override_failure_message(
		"a save recorded units that are not on the board").is_equal(game.units_root.get_child_count())


# --- what an undeployed unit IS ---

# The whole reason they are real Unit nodes: Unit._ready guards ONLY its grid setup, so an off-board
# unit has run initialize() and _seed_starting_kit() and answers the wielder-taking predicates the
# pre-mission screen is made of. Derived from the seam, never from what Company happens to carry.
func test_an_undeployed_unit_is_a_whole_unit() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	if _roster_size(roster) < 2:
		return
	var path := _author(roster, 1, false)
	mc.begin_mission(path)
	await await_idle_frame()
	var waiting: Unit = _reserve()[0]

	assert_object(waiting.unit_instance).override_failure_message(
		"_ready bailed before initialize(), so this unit can answer nothing").is_not_null()
	assert_int(waiting.inventory.size()).override_failure_message(
		"the inventory was never sized, so every later add_item would fail silently"
	).is_equal(Unit.MAX_INVENTORY_SIZE)
	# The stat chain, off the board: base -> limb -> jobs -> effects, with no grid under it.
	assert_int(waiting.get_effective_stat(Stats.Stat.CON)).is_greater(0)


func test_an_undeployed_unit_belongs_to_no_squad() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	if _roster_size(roster) < 2:
		return
	var path := _author(roster, 1, false)
	mc.begin_mission(path)
	await await_idle_frame()
	var waiting: Unit = _reserve()[0]

	# TYPED read on purpose: a FREED reference compares == null as TRUE, so assert_object(...).is_null()
	# passes against a dangling squad while this line is what dies (#149).
	var squad: Squad = waiting.squad
	assert_object(squad).override_failure_message(
		"an off-board unit is holding a squad").is_null()


# --- the round trip, which is where the two squad bugs live ---

func test_deploying_and_undeploying_puts_a_unit_back_where_it_started() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	if _roster_size(roster) < 2:
		return
	var path := _author(roster, 1, false)
	mc.begin_mission(path)
	await await_idle_frame()
	var waiting: Unit = _reserve()[0]
	var reserve_before: int = _reserve().size()

	assert_bool(game.deploy_unit(waiting, Vector2i(3, 0))).is_true()
	assert_object(waiting.get_parent()).is_same(game.units_root)
	assert_vector(waiting.movement.cell).is_equal(Vector2i(3, 0))
	var on_board_squad: Squad = waiting.squad
	assert_object(on_board_squad).override_failure_message(
		"a deployed unit must be registered, exactly as a spawned one is").is_not_null()

	game.undeploy_unit(waiting)

	assert_object(waiting.get_parent()).is_same(game.reserve_root)
	assert_int(_reserve().size()).is_equal(reserve_before)
	# The typed read again: release() detaches WITHOUT re-soloing, and _erase_member is what has to
	# clear the field -- otherwise this unit names a Squad that destroy_empty_squad just freed.
	var after: Squad = waiting.squad
	assert_object(after).override_failure_message(
		"the undeployed unit still names a squad").is_null()


func test_undeploying_leaves_no_squad_holding_the_unit_that_left() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	if _roster_size(roster) < 2:
		return
	var path := _author(roster, 1, false)
	mc.begin_mission(path)
	await await_idle_frame()
	var waiting: Unit = _reserve()[0]
	assert_bool(game.deploy_unit(waiting, Vector2i(3, 0))).is_true()

	game.undeploy_unit(waiting)

	# leave_squad would have handed it a FRESH solo squad on the way out -- one holding a unit that
	# is no longer on the board, and emitting squad_created while it did.
	for squad: Squad in game.squad_manager.squads:
		assert_bool(squad.get_members().has(waiting)).override_failure_message(
			"a squad is still holding the undeployed unit").is_false()


func test_a_redeployed_unit_is_registered_again() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	if _roster_size(roster) < 2:
		return
	var path := _author(roster, 1, false)
	mc.begin_mission(path)
	await await_idle_frame()
	var waiting: Unit = _reserve()[0]

	assert_bool(game.deploy_unit(waiting, Vector2i(3, 0))).is_true()
	game.undeploy_unit(waiting)
	assert_bool(game.deploy_unit(waiting, Vector2i(5, 0))).is_true()

	var squad: Squad = waiting.squad
	assert_object(squad).is_not_null()
	assert_vector(waiting.movement.cell).is_equal(Vector2i(5, 0))
	assert_object(game.get_unit_at_cell(Vector2i(5, 0))).is_same(waiting)


func test_deploying_onto_an_occupied_cell_leaves_the_unit_in_reserve() -> void:
	var roster := _a_roster()
	if roster == "":
		return
	if _roster_size(roster) < 2:
		return
	var path := _author(roster, 1, false)
	mc.begin_mission(path)
	await await_idle_frame()
	var standing: Array[Unit] = _player_units_on_board()
	var waiting: Unit = _reserve()[0]
	var reserve_before: int = _reserve().size()

	assert_bool(game.deploy_unit(waiting, standing[0].movement.cell)).override_failure_message(
		"deploy_unit stood two units on one cell").is_false()
	assert_object(waiting.get_parent()).is_same(game.reserve_root)
	assert_int(_reserve().size()).is_equal(reserve_before)
