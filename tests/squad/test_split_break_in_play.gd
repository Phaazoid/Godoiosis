# The tether BREAK plays at the BLOW (#367 part 2B). On the real game scene, through the real
# OrderExecutor.execute_orders: a shove that carries a member out of its leader's range breaks that
# tether BEFORE the pass settles -- it is already playing when the settle ejects the member -- and
# exactly once. Then the two decisions around it that a headless pass cannot show as motion: the
# stage lifts the far end (the dev's Z2), and after_the_blow lets the camera go to the stage and
# waits out the break.
#
# Sampling the store per frame cannot see "during the pass": headless, everything after the shove's
# slide runs to the settle without another frame. So the ORDER is read at the one moment that decides
# it -- the settle's own ejection signal.
#
# The break's two times are SET long here and restored, so a moment cannot expire mid-case and nothing
# pins the dev's tuning. Fixture is test_split_forecast.gd's.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _main: Node
var game: Node2D
var _saved := {}
var _leader: Unit
var _watched: Unit
# How many breaks of the watched link were in the store when the settle ejected it; -1 until it did.
var _playing_at_settle := -1


func before_test() -> void:
	_saved = {"strain": SquadLines2D.BREAK_STRAIN_SECONDS, "shatter": SquadLines2D.BREAK_SHATTER_SECONDS,
			"zoom": PlayerSettings.choice_of(PlayerSettings.Setting.BATTLE_ZOOM_MODE)}
	SquadLines2D.BREAK_STRAIN_SECONDS = 30.0
	SquadLines2D.BREAK_SHATTER_SECONDS = 30.0
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(10):
		for y in range(5):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	_playing_at_settle = -1
	await await_idle_frame()


func after_test() -> void:
	SquadLines2D.BREAK_STRAIN_SECONDS = _saved["strain"]
	SquadLines2D.BREAK_SHATTER_SECONDS = _saved["shatter"]
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, _saved["zoom"])
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# --- fixture -------------------------------------------------------------------------------------

func _spawn(faction: Team.Faction, cell: Vector2i, stats: Dictionary = {}, power := 3,
		knockback := 0) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data(stats, faction), cell)
	assert_object(unit).is_not_null()
	var weapon := H.make_weapon(power)
	(weapon.template.main_attack as WeaponAttackData).knockback = knockback
	unit.equipped_weapon = weapon
	return unit


# A two-strong enemy squad, and a hero whose queued shove carries its member out of the leader's
# range -- test_split_forecast's first case. The board is armed after, so only the pass plays.
func _shove_out_of_range() -> Unit:
	_leader = _spawn(ENEMY, Vector2i(1, 2), {Stats.Stat.LDR: 10})
	_watched = _spawn(ENEMY, Vector2i(4, 2))
	game.squad_manager.join_squad(_watched, _leader.squad)
	var hero := _spawn(PLAYER, Vector2i(3, 2), {}, 3, 2)
	game.squad_manager.active_squad = hero.squad
	var aim := AttackAction.declare(hero, hero.movement.cell, _watched.movement.cell)
	assert_bool(game.squad_manager.queue_action(hero.squad, aim)).override_failure_message(
			"fixture: the shove never queued").is_true()
	game.refresh_action_queue(hero.squad)
	var presenter: SquadTetherPresenter = game.squad_tether_presenter
	presenter.arm()
	var squads: SquadManager = game.squad_manager
	squads.squad_member_left.connect(_on_left)
	return hero


func _on_left(_squad: Squad, unit: Unit, _cause: SquadManager.LeaveCause) -> void:
	if unit == _watched and _playing_at_settle < 0:
		_playing_at_settle = _breaks().size()


# The breaks in the store toward the watched pair's leader.
func _breaks() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var overlays: OverlayManager = game.overlay_manager
	for entry: Dictionary in overlays.squad_tether_moments:
		if entry["moment"] == SquadLines2D.Moment.BREAK and entry["to"] == _leader.movement.cell:
			found.append(entry)
	return found


func _the_shove(hero: Unit) -> AttackAction:
	var plan: ResolvedPlan = game.squad_manager.resolve_plan(hero.squad, game._board())
	for blow in SplitForecast.playback(plan):
		if blow.target == _watched:
			return blow
	return null


# --- cases ---------------------------------------------------------------------------------------

func test_a_shove_out_of_range_breaks_its_tether_at_the_blow_and_only_once() -> void:
	var hero := _shove_out_of_range()
	var blow := _the_shove(hero)
	assert_int(blow.resolved_outcome().relinks.size()).override_failure_message(
			"fixture: the forecast foretells no break").is_equal(1)
	var link: ResolvedOutcome.Relink = blow.resolved_outcome().relinks[0]
	var staged_before := BoardSpace.staging_version
	var executor: OrderExecutor = game.order_executor
	await executor.execute_orders(hero)
	await await_idle_frame()
	await await_idle_frame()

	assert_int(BoardSpace.staging_version).override_failure_message(
			"fixture: the pass never tore the fight out, so this is not the zoom's case").is_greater(staged_before)
	assert_int(_playing_at_settle).override_failure_message(
			"fixture: the settle never ejected the member").is_greater_equal(0)
	assert_int(_playing_at_settle).override_failure_message(
			"the break was not playing when the pass settled -- it waited for the settle, not the blow") \
		.is_equal(1)
	var breaks := _breaks()
	assert_int(breaks.size()).override_failure_message(
			"the tether broke %d times across the pass" % breaks.size()).is_equal(1)
	# The plan's riskiest assumption, measured: the break is strung between the cells the stage lifts.
	assert_that(breaks[0]["from"]).override_failure_message(
			"the break's member end is not where the forecast staged it").is_equal(link.member_cell)
	assert_that(breaks[0]["to"]).override_failure_message(
			"the break's leader end is not where the forecast staged it").is_equal(link.leader_cell)


# The dev's ruling: with battle zooms off the break plays on the BOARD -- still at the blow, with
# nothing torn out.
func test_with_battle_zoom_off_the_break_still_plays_at_the_blow_and_nothing_stages() -> void:
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.OFF)
	var hero := _shove_out_of_range()
	var staged_before := BoardSpace.staging_version
	var executor: OrderExecutor = game.order_executor
	await executor.execute_orders(hero)
	await await_idle_frame()

	assert_int(BoardSpace.staging_version).override_failure_message(
			"a pass with the zoom off tore the board out").is_equal(staged_before)
	assert_int(_playing_at_settle).override_failure_message(
			"with the zoom off the break waited for the settle instead of playing at the blow").is_equal(1)


# Z2: the leader at the far end of a foretold break goes up with the fight. Its cell is nowhere in the
# fight itself -- no origin, aim, footprint or flight -- so only the break can have put it on stage.
func test_the_stage_lifts_the_far_end_of_a_foretold_break() -> void:
	var hero := _shove_out_of_range()
	var blow := _the_shove(hero)
	var fight: Array[Vector2i] = [blow.origin_cell, blow.target_cell]
	fight.append_array(blow.footprint)
	fight.append_array(blow.resolved_outcome().knockback_path)
	assert_bool(fight.has(_leader.movement.cell)).override_failure_message(
			"fixture: the leader stands in the fight, so the stage would take it anyway").is_false()
	var plan: ResolvedPlan = game.squad_manager.resolve_plan(hero.squad, game._board())
	var sheet := BeatSheet.read(hero.squad, plan)
	assert_bool(sheet.cells.has(_leader.movement.cell)).override_failure_message(
			"the far end of the breaking tether was left on the board, under the diorama").is_true()


# The dev's "pull back to the stage": while a fight is staged, a blow that breaks a tether lets go of
# the victim so the stage shot frames the whole diorama -- and the pass waits the break out. With no
# stage up (the zoom off) the camera keeps the victim.
func test_after_the_blow_pulls_the_camera_back_to_the_stage_and_waits_out_the_break() -> void:
	var hero := _shove_out_of_range()
	var blow := _the_shove(hero)
	var executor: OrderExecutor = game.order_executor
	var camera: CameraController = game.camera_controller
	var stage: Array[Vector2i] = [blow.target_cell]
	camera.shot_cells = stage
	camera.follow(_watched)
	var linger := executor.after_the_blow(blow, 0.1)
	var released := camera.follow_unit == null
	var no_stage: Array[Vector2i] = []
	camera.shot_cells = no_stage
	camera.follow(_watched)
	executor.after_the_blow(blow, 0.1)
	var kept := camera.follow_unit == _watched
	camera.follow(null)

	assert_bool(released).override_failure_message(
			"a breaking blow on stage kept the camera on the victim").is_true()
	assert_float(linger).override_failure_message("the pass did not wait out the break") \
			.is_greater_equal(SquadLines2D.shown_seconds(SquadLines2D.Moment.BREAK))
	assert_bool(kept).override_failure_message(
			"with no stage up the camera let go of the victim anyway").is_true()
