# A limb lost by a unit that is still STANDING, in the middle of its own pass (#1174).
#
# Before #1174 a limb only ever went with a down, and a downed unit acts no further (#1005), so a
# maim could never land between a unit's orders. Now a big enough watch shot takes an arm off a
# walker that then goes on to swing. Execution plays back resolved damage and the lost limb's stat
# settle runs mid-pass, which stats.md declares un-modelled by preview and execution alike. This
# suite drives that real sequence on the real game scene: the walk, the shot, the settle, the swing.
#
# Fixture is tests/flow/test_watch_shot_interrupts_the_walk.gd's -- see tests/README.md -> Testing
# the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const CROSSING := Vector2i(2, 0)
const WALK_END := Vector2i(4, 0)

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
	for x in range(8):
		for y in range(5):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i, power := 4, mhp := 80) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: mhp}, faction), cell)
	assert_object(unit).override_failure_message("fixture failed to spawn at %s" % str(cell)).is_not_null()
	unit.equipped_weapon = H.make_weapon(power)
	return unit


# The walker's own shot in the resolved plan: the one watch shot that struck it.
func _shot_on(plan: ResolvedPlan, walker: Unit) -> AttackAction:
	for shot in plan.watch_shots:
		if shot.target == walker:
			return shot
	return null


func _swing_by(plan: ResolvedPlan, walker: Unit) -> AttackAction:
	for atk in plan.attacks:
		if atk.actor == walker and atk.target != null:
			return atk
	return null


# THE wire case. A watch shot big enough to take a limb, but nowhere near enough to down the walker,
# lands mid-walk; the walker then plays its queued swing. Preview and execution must agree on the
# rung, on the limb, and on the swing's damage -- with the limb's stat settle in between.
func test_a_limb_lost_mid_walk_leaves_the_rest_of_the_pass_as_previewed() -> void:
	var watcher := _spawn(ENEMY, Vector2i(2, 3), LethalityRules.LIMB_LOSS_DAMAGE + 4)
	var walker := _spawn(PLAYER, Vector2i(0, 0))
	var victim := _spawn(ENEMY, Vector2i(5, 0))
	await await_idle_frame()
	var footprint: Array[Vector2i] = [CROSSING]
	watcher.arm_watch(watcher.movement.cell, CROSSING, footprint, watcher.get_default_attack())

	var path: Array[Vector2i] = []
	for x in range(0, WALK_END.x + 1):
		path.append(Vector2i(x, 0))
	var move := MoveAction.new()
	move.init(walker, path, null)
	assert_bool(game.squad_manager.queue_action(walker.squad, move)) \
		.override_failure_message("fixture failed to queue the walk").is_true()
	assert_bool(game.squad_manager.queue_action(walker.squad,
			AttackAction.declare(walker, WALK_END, victim.movement.cell))) \
		.override_failure_message("fixture failed to queue the swing").is_true()

	var plan: ResolvedPlan = game.squad_manager.resolved_plan_for(walker.squad)
	assert_object(plan).override_failure_message("queueing left no resolved plan").is_not_null()
	var shot := _shot_on(plan, walker)
	var swing := _swing_by(plan, walker)
	assert_object(shot).override_failure_message("the walk never tripped the watch").is_not_null()
	assert_object(swing).override_failure_message("the walker's swing never resolved").is_not_null()
	if shot == null or swing == null:
		return
	# Non-vacuity, read off the knob rather than pinned: the shot is a limb-sized blow on a unit it
	# leaves standing, which is the one state this suite exists for.
	assert_int(shot.resolved.severed_limb) \
		.override_failure_message("fixture shot (%d) takes no limb -- the case is not exercising the rule"
			% shot.resolved.damage).is_not_equal(-1)
	assert_int(shot.resolved.lethality) \
		.override_failure_message("fixture shot did not leave the walker standing") \
		.is_equal(ResolvedOutcome.Lethality.NONE)
	var previewed_slot: int = shot.resolved.severed_limb
	var previewed_victim_hp: int = swing.resolved.target_hp_after
	assert_bool(swing.resolved.skipped) \
		.override_failure_message("a standing walker's swing was skipped").is_false()

	await game.order_executor.execute_orders(walker.squad.get_leader())

	assert_bool(walker.is_active()) \
		.override_failure_message("execution felled a walker the preview left standing").is_true()
	assert_int(walker.unit_instance.limbs[previewed_slot].state) \
		.override_failure_message("execution did not take the limb the preview named") \
		.is_equal(UnitInstance.LimbState.EMPTY)
	assert_int(walker.unit_instance.maim_order().size()) \
		.override_failure_message("execution took a different number of limbs than the preview") \
		.is_equal(UnitInstance.LimbSlot.size() - 1)
	assert_int(victim.get_current_hp()) \
		.override_failure_message("the swing after the lost limb landed a different number than previewed") \
		.is_equal(previewed_victim_hp)
