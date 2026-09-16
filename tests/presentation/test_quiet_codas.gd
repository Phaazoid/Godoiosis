# A side-channel verb that earns no beat costs NO CAMERA (#931) -- the wire, on the real game scene.
#
# WHY THIS SUITE EXISTS SEPARATELY from tests/squad/test_beat_sheet.gd, which pins the same rule one
# layer up. That one proves the sheet has no coda and no cells; this one proves the consequence the
# dev actually reported, which is that the view stops going anywhere. Between the two sits the whole
# of execute_orders -- the tear-out, the tail loop, the board coming home -- and a sheet that reads
# right while some other phase still pans is exactly the failure #103's law is about.
#
# IT MEASURES POSITION, NOT TIME, and that is forced rather than preferred: Pacing.beat returns
# without awaiting in a headless run, so every duration in the pass collapses to zero and a case
# asserting "this took less time" would pass against any implementation at all. Where the camera
# ENDS UP survives the escape, so it is the unit the property is measured in.
#
# Fixture is tests/ui/test_radial_menu.gd's -- see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(40):
		for y in range(20):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	game.camera_controller.refresh_bounds(game.grid)
	# THE SHIPPED DEFAULT, set explicitly so the case does not inherit whatever ran before it --
	# and it is the worst case as well as the usual one: under ALWAYS every beat is CINEMATIC, so
	# one cell on the sheet is the difference between a silent pass and the full diorama.
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.ALWAYS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# --- the cases ----------------------------------------------------------------------------------

# An AI chainsword that cannot reach anybody revs, every turn, as its fallback. Before #931 that
# bought a pan across the board, a hold, a linger, AND -- because a coda contributes stage cells
# like any other main action -- the whole tear-out, for an order with no animation, no particle, no
# icon and no sound. The view must not move at all.
func test_an_ai_rev_never_moves_the_camera() -> void:
	var rever := _a_chainsword_unit(Vector2i(20, 10))
	game.ai_controller.set_faction_ai_enabled(Team.Faction.PLAYER, true)
	assert_bool(game.ai_controller.is_ai_faction(rever.get_faction())).override_failure_message(
			"the fixture never made this an AI pass -- the case would run the player path and prove nothing") \
		.is_true()
	var away := _park_the_camera_away_from(rever)

	rever.squad._queue_action(_rev(rever))
	await game.order_executor.execute_orders(rever)
	await await_idle_frame()

	# THE ORDER STILL HAPPENED. Without this the case passes just as well against a pass that
	# refused the plan and conceded, which is a real path in execute_orders and would move no
	# camera either -- a precondition that is never established is not a precondition.
	assert_bool(_saw_of(rever).is_revved()).override_failure_message(
			"the rev never executed, so the still camera proves nothing -- the pass conceded instead") \
		.is_true()
	assert_vector(game.camera_controller.global_position).override_failure_message(
			"an AI's rev moved the camera anyway -- it is flying to a unit standing perfectly still") \
		.is_equal(away)


# ...and the player's own tail is untouched, which is the fork's whole point (dev, 2026-09-16): an
# AI plan is being read for the first time, a player's was authored by the person watching it. Same
# unit, same order, same board -- the only thing that differs is whose pass it is.
func test_the_players_own_rev_still_gets_its_camera() -> void:
	var rever := _a_chainsword_unit(Vector2i(20, 10))
	assert_bool(game.ai_controller.is_ai_faction(rever.get_faction())).override_failure_message(
			"the fixture left AI on for the player faction; this case is the human path") \
		.is_false()
	var away := _park_the_camera_away_from(rever)

	rever.squad._queue_action(_rev(rever))
	await game.order_executor.execute_orders(rever)
	await await_idle_frame()

	assert_bool(_saw_of(rever).is_revved()).override_failure_message(
			"the rev never executed; the case proves nothing either way").is_true()
	assert_vector(game.camera_controller.global_position).override_failure_message(
			"the player's own rev left the camera parked where it was -- #931 is an AI-pass rule and this half must not change") \
		.is_not_equal(away)


# --- helpers ------------------------------------------------------------------------------------

# A unit whose weapon can actually rev. Explicit rather than relying on the fixture default: if the
# equipped weapon had no rev verb, RevAction.actor_can_perform() answers false, the plan is invalid,
# and an AI squad CONCEDES the turn before the tail is ever reached.
func _a_chainsword_unit(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	unit.equipped_weapon = H.make_weapon()
	assert_bool(unit.can_rev_weapon()).override_failure_message(
			"fixture drifted: this unit cannot rev, so the order would be refused").is_true()
	return unit


func _saw_of(unit: Unit) -> ChainswordWeaponInstance:
	return unit.get_equipped_weapon() as ChainswordWeaponInstance


func _rev(rever: Unit) -> RevAction:
	var action := RevAction.new()
	action.init(rever)
	return action


# Park the view somewhere the pass would have to travel from, and PROVE it is somewhere -- the
# clamp can quietly pull a requested position back onto the unit on a small board, which would make
# "the camera did not move" true for a reason that has nothing to do with this ticket.
#
# snap_to_position rather than writing the field: it sets target_position too, and _process glides
# toward THAT, so a hand-parked global_position drifts back on the very next frame.
func _park_the_camera_away_from(unit: Unit) -> Vector2:
	var camera: CameraController = game.camera_controller
	camera.snap_to_position(GridUtils.cell_world(game.grid, Vector2i(36, 17)))
	var away: Vector2 = camera.global_position
	var home := GridUtils.cell_world(game.grid, unit.get_projected_destination())
	assert_bool(away.distance_to(home) > 1.0).override_failure_message(
			"the camera clamp parked the view on the unit anyway; the case proves nothing").is_true()
	return away
