# #1599: an authored save (the dev header's Update and Save As) writes the board as authored, never what
# play did to the battle. The mission's latches -- the round count, `contested`, the captured zones --
# are what play did and nothing authors them, so an authored save writes none of them. The turn is
# written as the board was LOADED with (ScenarioManager.current_opening_faction), never the turn the
# save was made on. A full capture (a save slot, a bug report) still writes every one of them live.
#
# What it cannot see: the dev header itself. Its Update reaches capture_scenario with authored true
# (ScenarioHeader._save), the door both cases call.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const SCRATCH := "user://__authored_save_writes_no_battle_state.tres"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const WIDTH := 6
const HEIGHT := 3

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


# Two sides and two capture zones on a field of grass. No AI faction: each side's turn waits for its
# End Turn, the hotseat shape.
func _board() -> void:
	for x in range(WIDTH):
		for y in range(HEIGHT):
			game.grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	game.zone_manager.paint_cell("North", ZoneManager.Kind.CAPTURE, Vector2i(2, 0))
	game.zone_manager.paint_cell("South", ZoneManager.Kind.CAPTURE, Vector2i(2, HEIGHT - 1))
	assert_object(game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(0, 1))).is_not_null()
	assert_object(game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(WIDTH - 1, 1))).is_not_null()


# One End Turn through the real door, and the hand-off it starts.
func _end_turn() -> void:
	await game.end_turn()
	await await_idle_frame()
	await await_idle_frame()


func test_an_authored_save_writes_no_latch_and_the_turn_the_board_opened_on() -> void:
	_board()
	assert_int(game.turn_manager.active_faction()).override_failure_message(
			"precondition: a cleared board opens on the player").is_equal(Team.Faction.PLAYER)
	await _end_turn()   # the player's
	await _end_turn()   # the enemy's: a round is done
	await _end_turn()   # the player's again, so the saves below are made on the enemy's turn
	mc.capture("North")
	var rounds: int = mc.rounds_elapsed()
	assert_int(rounds).override_failure_message("precondition: the clock counted no round").is_greater(0)
	assert_bool(mc.is_contested()).override_failure_message(
			"precondition: the turn ends did not latch contested").is_true()
	assert_array(mc.captured_zone_names()).override_failure_message(
			"precondition: North was not claimed").contains_exactly(["North"])
	assert_int(game.turn_manager.active_faction()).override_failure_message(
			"precondition: the live turn is not the enemy's").is_equal(Team.Faction.ENEMY)

	var authored: ScenarioData = sm.capture_scenario("authored", true)
	assert_int(authored.rounds_elapsed).override_failure_message(
			"an authored save wrote the round count").is_equal(0)
	assert_bool(authored.contested).override_failure_message(
			"an authored save wrote the contested latch").is_false()
	assert_array(authored.captured_zones).override_failure_message(
			"an authored save wrote the captured zones").is_empty()
	assert_int(authored.active_faction).override_failure_message(
			"an authored save wrote the turn it was made on, not the one the board opened on").is_equal(
			Team.Faction.PLAYER)

	var full: ScenarioData = sm.capture_scenario("full")
	assert_int(full.rounds_elapsed).override_failure_message("a full capture lost the round count").is_equal(rounds)
	assert_bool(full.contested).override_failure_message("a full capture lost the contested latch").is_true()
	assert_array(full.captured_zones).override_failure_message(
			"a full capture lost the captured zones").contains_exactly(["North"])
	assert_int(full.active_faction).override_failure_message("a full capture lost the live turn").is_equal(
			Team.Faction.ENEMY)


# A board authored to open on the enemy keeps that opening under Update, whoever's turn it is when the
# Update is made, and a cleared board goes back to opening on the player.
func test_an_update_keeps_the_turn_a_board_opens_on() -> void:
	_board()
	var opening: ScenarioData = sm.capture_scenario("opens_on_the_enemy", true)
	opening.active_faction = Team.Faction.ENEMY   # the authored opening; no dev control writes one yet
	assert_int(ResourceSaver.save(opening, SCRATCH)).is_equal(OK)
	sm.load_scenario(SCRATCH)
	await await_idle_frame()
	assert_int(game.turn_manager.active_faction()).override_failure_message(
			"precondition: the board did not open on the enemy").is_equal(Team.Faction.ENEMY)
	await _end_turn()   # the enemy's
	assert_int(game.turn_manager.active_faction()).override_failure_message(
			"precondition: the live turn is not the player's").is_equal(Team.Faction.PLAYER)

	assert_int(sm.capture_scenario("update", true).active_faction).override_failure_message(
			"an Update moved the turn the board opens on").is_equal(Team.Faction.ENEMY)
	assert_int(sm.capture_scenario("full").active_faction).override_failure_message(
			"a full capture did not write the live turn").is_equal(Team.Faction.PLAYER)

	sm.clear_board()
	assert_int(sm.capture_scenario("sandbox", true).active_faction).override_failure_message(
			"a cleared board kept the last board's opening").is_equal(Team.Faction.PLAYER)
