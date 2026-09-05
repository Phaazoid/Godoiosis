# The pre-mission phase becomes a place the player STANDS (#739): it waits instead of falling
# through to turn 1, the board takes placement clicks, squads are built with the flow that already
# exists, and an explicit commit starts the mission.
#
# Every case that can drives the REAL sequence -- game._on_left_click, then the ring's own dispatch
# through MainActionMenu.on_pressed -- rather than calling deploy_unit/join_squad directly. The
# issue says so for the squad half specifically, and the reason generalises: the gates being tested
# live in populate() and _click_pre_mission, which nothing but a real click consults.
#
# The scratch mission is authored IN MEMORY and saved to user://, never into Scenarios/ (which
# Mission Select scans and #9's integrity suite sweeps) -- test_pre_mission_draw.gd's setup, for
# its reasons, including the save_dir redirect that keeps the slot cases off the dev's own saves.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const SCRATCH := "user://__pre_mission_739.tres"
const TEST_SAVE_DIR := "user://__test_saves_739/"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const ROW_WIDTH := 10
const ZONE_CELLS := 5
const FREE_CELL := Vector2i(ZONE_CELLS - 1, 0)   # past any cap this suite authors, inside the zone

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


# A board whose whole player force is the roster's, optionally with an authored ENEMY off in a
# corner -- the additive case ruling 2c describes, and the only way to get a unit onto the board
# that the phase must NOT offer to lift off it.
func _author(roster: String, cap: int, with_enemy := false) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	if with_enemy:
		assert_object(game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(ROW_WIDTH - 1, 0))) \
			.override_failure_message("precondition: the authored enemy would not spawn").is_not_null()
	sm.current_roster = roster
	sm.current_deployment_cap = cap

	var scenario := sm.capture_scenario("pre_mission_739", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


# Boot a roster board and stop in the phase. Returns false when the shipped content cannot carry
# the case, so a caller returns rather than asserting about what a roster HOLDS.
func _enter_phase(cap := 2, with_enemy := false) -> bool:
	var roster := _a_roster()
	if roster == "" or _roster_size(roster) <= cap:
		push_warning("the shipped roster is not larger than the cap, so the phase has no reserve")
		return false
	mc.begin_mission(_author(roster, cap, with_enemy))
	await await_idle_frame()
	return true


func _drawn() -> Array[Unit]:
	var found: Array[Unit] = []
	for unit: Unit in game.units_root.get_children():
		if unit.drawn_from_roster:
			found.append(unit)
	return found


func _ring_names(unit: Unit) -> Array[String]:
	var names: Array[String] = []
	for id: int in game.main_action_menu.populate(unit):
		names.append(String(MainActionMenu.ACTION_DATA[id]["name"]))
	return names


# Did the last click open a ring? The controller is built per open and parented to game.
func _ring_open() -> bool:
	for child in game.get_children():
		if child is ActionMenuController and not child.is_queued_for_deletion():
			return true
	return false


# The widget frees its controller on the way out, and these cases reach past the widget straight
# into on_pressed -- so the node is still standing afterwards. Clear it, or the NEXT click's
# _ring_open answer is the previous open's.
func _close_rings() -> void:
	for child in game.get_children():
		if child is ActionMenuController:
			child.free()


# --- the phase waits, and commit is what ends it ---

func test_a_roster_mission_stops_in_the_phase_instead_of_starting() -> void:
	if not await _enter_phase():
		return

	assert_bool(mc.is_deploying()).override_failure_message(
		"the mission fell straight through to turn 1").is_true()
	assert_int(game.game_state).is_equal(game.GameState.PRE_MISSION)
	# Nobody's turn has begun, which is what the deployment zone's own visibility rule reads -- so
	# the player can still see where they may place (#736).
	assert_array(mc.hidden_zone_names()).override_failure_message(
		"the deployment zone stopped being drawn before the player could use it").is_empty()


func test_committing_starts_the_mission_and_closes_the_phase() -> void:
	if not await _enter_phase():
		return

	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()

	assert_bool(mc.is_deploying()).is_false()
	assert_int(game.game_state).override_failure_message(
		"turn 1 came to rest inside the phase it just left").is_not_equal(game.GameState.PRE_MISSION)
	assert_array(mc.hidden_zone_names()).override_failure_message(
		"the deployment zone is still drawn after the battle started").is_not_empty()


func test_commit_is_refused_with_nobody_on_the_board() -> void:
	if not await _enter_phase():
		return
	for unit: Unit in _drawn():
		game.undeploy_unit(unit)
	await await_idle_frame()
	assert_int(mc.deployed_roster_count()).is_equal(0)

	assert_bool(mc.commit_deployment()).override_failure_message(
		"a mission started with no force to command").is_false()
	assert_bool(mc.is_deploying()).override_failure_message(
		"a refused commit still closed the phase").is_true()


func test_a_second_commit_does_nothing() -> void:
	if not await _enter_phase():
		return
	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()

	assert_bool(mc.commit_deployment()).override_failure_message(
		"the phase could be committed twice, so turn 1 could fire twice").is_false()


# --- the ring, and the verbs that must NOT be in it ---

# The testable form of "a click on a deployed unit must not open the action menu": the ring is the
# same widget, and what changes is that it can no longer say anything about a turn.
func test_the_phase_ring_offers_no_turn_verb() -> void:
	if not await _enter_phase(3):
		return
	var standing: Array[Unit] = _drawn()
	assert_array(standing).is_not_empty()

	var names := _ring_names(standing[0])
	for forbidden: String in ["Move", "Group Move", "Wait", "Guard", "Rescue", "Rally", "Capture Point"]:
		assert_bool(names.has(forbidden)).override_failure_message(
			"the phase ring offered '%s', which is a turn verb: %s" % [forbidden, str(names)]).is_false()
	assert_bool(names.has("Undeploy")).override_failure_message(
		"a drawn unit could not be taken off the board: %s" % str(names)).is_true()
	assert_bool(names.has("Inspect")).is_true()


# Ruling 2c: authored units are additive and belong to the BOARD, so they are not the player's to
# lift off it -- and enemies are units_root children too, which is what an ungated arm would offer.
func test_a_unit_the_board_authored_is_not_undeployable() -> void:
	if not await _enter_phase(2, true):
		return
	var authored: Unit = null
	for unit: Unit in game.units_root.get_children():
		if not unit.drawn_from_roster:
			authored = unit
	assert_object(authored).override_failure_message(
		"precondition: the authored unit did not survive the load").is_not_null()

	assert_bool(_ring_names(authored).has("Undeploy")).override_failure_message(
		"the phase offered to lift a unit the board authored off it").is_false()


# --- placement, through the real clicks ---

func test_clicking_a_deployed_unit_and_picking_undeploy_takes_it_off_the_board() -> void:
	if not await _enter_phase():
		return
	var victim: Unit = _drawn()[0]
	var waiting: int = game.reserve_root.get_child_count()

	game._on_left_click(victim.movement.cell)
	assert_bool(_ring_open()).override_failure_message(
		"clicking a deployed unit opened no ring at all").is_true()
	game.main_action_menu.on_pressed(MainActionMenu.UNDEPLOY, victim)
	await await_idle_frame()

	assert_object(victim.get_parent()).override_failure_message(
		"the unit is still on the board").is_same(game.reserve_root)
	assert_int(game.reserve_root.get_child_count()).is_equal(waiting + 1)


# The round trip, and the only way to reach an empty cell with room under the cap: the draw fills
# the cap by construction, so a player who wants somebody else has to take somebody off first.
func test_clicking_an_empty_deployment_cell_brings_in_a_unit_that_was_waiting() -> void:
	if not await _enter_phase(2):
		return
	var lifted: Unit = _drawn()[0]
	game._on_left_click(lifted.movement.cell)
	game.main_action_menu.on_pressed(MainActionMenu.UNDEPLOY, lifted)
	await await_idle_frame()
	_close_rings()

	assert_object(game.get_unit_at_cell(FREE_CELL)).override_failure_message(
		"precondition: the cell the case clicks was not free").is_null()
	var on_board: int = _drawn().size()
	var waiting: int = game.reserve_root.get_child_count()
	assert_int(waiting).is_greater(0)

	game._on_left_click(FREE_CELL)
	assert_bool(_ring_open()).override_failure_message(
		"an empty deployment cell offered nothing").is_true()
	# -1 is the first synthetic leaf of the open the click just built -- MainActionMenu's own id
	# scheme for a non-verb row, and exactly what the ring hands back when that row is picked.
	game.main_action_menu.on_pressed(-1, null)
	await await_idle_frame()

	assert_int(_drawn().size()).override_failure_message(
		"nobody came in from the reserve").is_equal(on_board + 1)
	assert_object(game.get_unit_at_cell(FREE_CELL)).is_not_null()
	assert_int(game.reserve_root.get_child_count()).is_equal(waiting - 1)


func test_the_cap_refuses_one_more_than_it_allows() -> void:
	if not await _enter_phase(2):
		return
	assert_int(_drawn().size()).override_failure_message(
		"precondition: the cap did not fill, so there is no cap to test").is_equal(2)

	game._on_left_click(FREE_CELL)   # the third, over a cap of two

	assert_bool(_ring_open()).override_failure_message(
		"the cap was full and the cell still offered to bring someone in").is_false()
	assert_int(_drawn().size()).is_equal(2)
	assert_object(game.get_unit_at_cell(FREE_CELL)).is_null()


# The cell has to be a DEPLOYMENT cell, not merely empty ground.
func test_clicking_empty_ground_outside_the_zone_offers_nothing() -> void:
	if not await _enter_phase(2):
		return
	var outside := Vector2i(ROW_WIDTH - 1, 0)
	assert_bool(game.zone_manager.contains("landing", outside)).is_false()

	game._on_left_click(outside)

	assert_bool(_ring_open()).override_failure_message(
		"a cell outside the deployment zone offered to place a unit").is_false()
	assert_object(game.get_unit_at_cell(outside)).is_null()


# --- the one nothing else would catch ---

# A squad pick sets game_state to PICKING_TARGET, and leaving that mode rests the board on
# _base_state(). If that reads IDLE rather than the phase, the player silently drops out of
# deployment the first time they build a squad -- and every click after it goes to the battle ring.
func test_a_squad_pick_returns_into_the_phase() -> void:
	if not await _enter_phase(3):
		return
	var standing: Array[Unit] = _drawn()
	assert_int(standing.size()).is_equal(3)

	game._on_left_click(standing[0].movement.cell)
	game.main_action_menu.on_pressed(MainActionMenu.SQUADUP, standing[0])
	assert_int(game.game_state).override_failure_message(
		"Squad Up did not open a pick").is_equal(game.GameState.PICKING_TARGET)

	game._on_left_click(standing[1].movement.cell)   # the pick itself
	await await_idle_frame()

	assert_int(game.game_state).override_failure_message(
		"the board dropped out of the phase after a squad pick -- every click after this one would "
		+ "reach the battle ring").is_equal(game.GameState.PRE_MISSION)
	assert_bool(mc.is_deploying()).is_true()


func test_a_squad_forms_through_the_real_click_sequence() -> void:
	if not await _enter_phase(3):
		return
	var standing: Array[Unit] = _drawn()
	assert_int(standing.size()).is_equal(3)
	var leader: Unit = standing[0]
	var recruit: Unit = standing[1]

	game._on_left_click(leader.movement.cell)
	game.main_action_menu.on_pressed(MainActionMenu.SQUADUP, leader)
	game._on_left_click(recruit.movement.cell)
	await await_idle_frame()

	assert_bool(leader.has_squad()).override_failure_message(
		"the squad never formed").is_true()
	assert_bool(leader.squad.get_members().has(recruit)).is_true()


# --- the surfaces that must stand down, and come back ---

func test_saving_is_refused_while_deploying() -> void:
	if not await _enter_phase():
		return

	assert_bool(sm.save_to_slot(1)).override_failure_message(
		"a save during deployment would keep only the units already placed, and the resume would "
		+ "drop the rest of the roster").is_false()

	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()
	assert_bool(sm.save_to_slot(1)).override_failure_message(
		"saving is still refused after the mission started").is_true()


func test_the_turn_hud_stands_down_for_the_phase_and_comes_back_on_commit() -> void:
	if not await _enter_phase():
		return
	assert_bool(game.end_turn_button.visible).override_failure_message(
		"End Turn is live during deployment -- its press does not gate on the phase, so it would "
		+ "run a turn that never started").is_false()

	assert_bool(mc.commit_deployment()).is_true()
	await await_idle_frame()

	assert_bool(game.end_turn_button.visible).override_failure_message(
		"End Turn never came back").is_true()


# Abandon never passes through commit, which is why the hide rides the flag's SETTER: the flag is
# cleared by reset(), from the next board's clear_board, and that is what puts the HUD back. A hide
# written at commit instead strands the next mission with no End Turn button at all.
func test_abandoning_the_phase_leaves_the_next_mission_with_its_turn_hud() -> void:
	if not await _enter_phase():
		return
	assert_bool(game.end_turn_button.visible).is_false()

	mc.abandon_mission()
	await await_idle_frame()
	mc._close_mission_select()

	# ...and now an ordinary roster-less board, which never enters the phase at all.
	sm.clear_board()
	var plain := _author("", 0)
	mc.begin_mission(plain)
	await await_idle_frame()

	assert_bool(mc.is_deploying()).is_false()
	assert_bool(game.end_turn_button.visible).override_failure_message(
		"the End Turn button never came back after abandoning mid-deployment, so this mission has "
		+ "no way to end a turn").is_true()


# The watch-only boot has no player to answer the phase (#375, #731 ruling 8), so it must not wait.
func test_a_watch_only_boot_does_not_stop_in_the_phase() -> void:
	var roster := _a_roster()
	if roster == "" or _roster_size(roster) <= 2:
		return
	var path := _author(roster, 2)

	mc.begin_mission(path, false)   # demo mode's own call
	await await_idle_frame()

	assert_bool(mc.is_deploying()).override_failure_message(
		"demo mode is waiting for a commit nobody can give it").is_false()
	assert_array(_drawn()).override_failure_message(
		"the watch-only boot did not deploy at all").is_not_empty()
	assert_int(game.game_state).is_not_equal(game.GameState.PRE_MISSION)
