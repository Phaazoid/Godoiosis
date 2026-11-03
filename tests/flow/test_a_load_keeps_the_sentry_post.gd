# A mid-battle load keeps a Sentry's POST (#1564). The post is Squad.home_cell, set at a board's load
# to the leader's spawn cell; a Sentry with nobody to fight walks back to it. A full capture used to
# save only the leader's CURRENT cell, and apply_placement made that the post, so a Sentry lured off
# its post and then saved and loaded had its post moved to where it stood, and never walked home.
#
# The post reaches the board through the real doors here: a load sets it (apply_placement), a real MOVE
# order walks the Sentry off it, and the round trip is the game's own capture_scenario/apply_scenario,
# read back on the game host and on the headless BoardBuilder, which shares the placement door.
#
# The control is the authored rule, which must not move: an authored save writes no post, so the post
# is the spawn cell it writes (#177's board-as-authored reading, and no new line in a committed file).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const WIDTH := 10
const HEIGHT := 5
const ZONE := "Post"
const POST := Vector2i(1, 2)
const OFF_POST := Vector2i(3, 2)

var _main: Node
var game: Node2D
var sm: ScenarioManager


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	sm = game.scenario_manager
	game.mission_controller._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _paint() -> void:
	for x in range(WIDTH):
		for y in range(HEIGHT):
			game.grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(0, 6):
		for y in range(HEIGHT):
			game.zone_manager.paint_cell(ZONE, ZoneManager.Kind.PATROL, Vector2i(x, y))


func _units() -> Array[Unit]:
	var units: Array[Unit] = []
	for child in game.units_root.get_children():
		if child is Unit and not child.is_queued_for_deletion():
			units.append(child)
	return units


static func _unit_at(units: Array[Unit], cell: Vector2i) -> Unit:
	for unit: Unit in units:
		if unit.movement.cell == cell:
			return unit
	return null


# A Sentry whose post came from a LOAD, which is where every authored post comes from: authored, then
# loaded, so apply_placement sets the post to the spawn cell.
func _loaded_sentry() -> Unit:
	_paint()
	var sentry: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), POST)
	assert_object(sentry).override_failure_message("precondition: the Sentry would not spawn").is_not_null()
	sentry.squad.archetype = AIArchetype.Type.SENTRY
	sentry.squad.zone_name = ZONE
	sm.apply_scenario(sm.capture_scenario("sentry_post_seed", true))
	await await_idle_frame()
	var loaded := _unit_at(_units(), POST)
	assert_object(loaded).override_failure_message("precondition: the seed load lost the Sentry").is_not_null()
	assert_that(loaded.squad.home_cell).override_failure_message(
		"precondition: a load did not set the post to the spawn cell").is_equal(POST)
	return loaded


# Off the post through a real MOVE order and a real pass.
func _walk_off_post(sentry: Unit) -> void:
	var reach := RulesService.compute_move_range(sentry, game._board())
	var move := MoveAction.new()
	move.init(sentry, game.route_to(sentry, reach, OFF_POST),
		GridUtils.get_terrain_icon_at_cell(game.grid, OFF_POST))
	assert_bool(game.squad_manager.queue_action(sentry.squad, move)) \
		.override_failure_message("precondition: the move off the post was refused").is_true()
	await game.order_executor.execute_orders(sentry)
	assert_that(sentry.movement.cell).override_failure_message(
		"precondition: the Sentry did not leave its post").is_equal(OFF_POST)
	assert_that(sentry.squad.home_cell).override_failure_message(
		"precondition: walking moved the post itself").is_equal(POST)


# The same captured board onto a fresh headless board, through the Play API's loader.
func _headless_load(scenario: ScenarioData) -> Array[Unit]:
	var board := BoardBuilder.build(self, "SentryPostHeadless")
	auto_free(board.root)
	return await BoardBuilder.apply_scenario(board, scenario)


# ==============================================================================

func test_a_sentry_off_its_post_keeps_its_post_across_a_load() -> void:
	var sentry := await _loaded_sentry()
	await _walk_off_post(sentry)

	var snapshot: ScenarioData = sm.capture_scenario("sentry_post_full")
	sm.apply_scenario(snapshot)
	await await_idle_frame()

	var reloaded := _unit_at(_units(), OFF_POST)
	assert_object(reloaded).override_failure_message("the load lost the Sentry").is_not_null()
	assert_that(reloaded.squad.home_cell).override_failure_message(
		"the game's load moved the post to where the Sentry stood when it was saved").is_equal(POST)

	var headless_units: Array[Unit] = await _headless_load(snapshot)
	var headless := _unit_at(headless_units, OFF_POST)
	assert_object(headless).override_failure_message("the headless load lost the Sentry").is_not_null()
	assert_that(headless.squad.home_cell).override_failure_message(
		"the headless load moved the post to where the Sentry stood when it was saved").is_equal(POST)


func test_a_squad_with_no_post_yet_reloads_with_none() -> void:
	# A squad born mid-battle (a spawn, an eject) has no post until its first Sentry turn fixes one, and
	# that turn fixes the cell it stands on THEN. A load that invented one would fix it early.
	_paint()
	var fresh: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), OFF_POST)
	assert_object(fresh).override_failure_message("precondition: the unit would not spawn").is_not_null()
	assert_that(fresh.squad.home_cell).override_failure_message(
		"precondition: a fresh squad already has a post").is_equal(Squad.NO_HOME)

	sm.apply_scenario(sm.capture_scenario("sentry_post_none"))
	await await_idle_frame()

	var reloaded := _unit_at(_units(), OFF_POST)
	assert_object(reloaded).override_failure_message("the load lost the unit").is_not_null()
	assert_that(reloaded.squad.home_cell).override_failure_message(
		"the load gave a squad with no post one").is_equal(Squad.NO_HOME)


func test_an_authored_save_keeps_the_spawn_cell_rule() -> void:
	var sentry := await _loaded_sentry()
	await _walk_off_post(sentry)

	var authored: ScenarioData = sm.capture_scenario("sentry_post_authored", true)
	for entry: ScenarioUnitEntry in authored.unit_entries:
		assert_bool(entry.squad_home_saved).override_failure_message(
			"an authored save wrote a post, so an Update writes a line no board had").is_false()
	sm.apply_scenario(authored)
	await await_idle_frame()

	var reloaded := _unit_at(_units(), OFF_POST)
	assert_object(reloaded).override_failure_message("the load lost the Sentry").is_not_null()
	assert_that(reloaded.squad.home_cell).override_failure_message(
		"an authored board's post is no longer the leader's spawn cell").is_equal(OFF_POST)
