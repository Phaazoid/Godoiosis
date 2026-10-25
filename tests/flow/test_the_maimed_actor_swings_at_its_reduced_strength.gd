# A unit that loses a limb earlier in its own pass ACTS on the body it is left with (#1480 stage 4).
#
# Stage 3 threaded the target's body through the pass; the actor's own numbers still came from the
# live unit, which execution has not hit yet. So a counter-er maimed by the blow it answers, or a
# walker maimed by a watch shot before its swing, struck at its whole STR in preview and execution
# alike. Both now read the pass's copy: the expectation is derived from a copy of the live body put
# through the same sever (UnitState.lose_next_limb), never pinned.
#
# Fixture is tests/flow/test_limb_loss_mid_pass.gd's: the real game scene, so execution lands what the
# preview said through the real executor.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const CROSSING := Vector2i(2, 0)
const WALK_END := Vector2i(4, 0)
# Lopsided on purpose: a lost arm halves the arm average, so the maimed swing cannot coincide with
# the whole one.
const STRENGTH := 8

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


func _spawn(faction: Team.Faction, cell: Vector2i, power := 4) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 80, Stats.Stat.STR: STRENGTH}, faction), cell)
	assert_object(unit).override_failure_message("fixture failed to spawn at %s" % str(cell)).is_not_null()
	unit.equipped_weapon = H.make_weapon(power)
	return unit


# A weapon whose main scales off STR alone, so a lost arm moves its number.
func _strong(unit: Unit) -> void:
	var weapon := H.make_weapon(4)
	var blend: Dictionary[Stats.Stat, int] = {Stats.Stat.STR: Stats.BLEND_TOTAL}
	weapon.template.main_attack.scaling_blend = blend
	unit.equipped_weapon = weapon


# What `attack` deals from `unit`'s body once the next limb in the rotation is gone, and whole. Both
# are read off copies, so the live unit is never touched.
func _maimed_and_whole(unit: Unit, attack: AttackData) -> Array[int]:
	var maimed := unit.state.copy()
	assert_int(maimed.lose_next_limb()).override_failure_message("fixture: the unit has no limb to lose") \
		.is_not_equal(-1)
	var whole := unit.state.copy()
	var out: Array[int] = [
		(maimed.equipped_weapon as WeaponInstance).base_damage(maimed, attack as WeaponAttackData),
		(whole.equipped_weapon as WeaponInstance).base_damage(whole, attack as WeaponAttackData),
	]
	assert_int(out[0]).override_failure_message(
			"fixture: the lost limb moves nothing (%d both ways), so the case measures nothing" % out[0]) \
		.is_not_equal(out[1])
	return out


func _hit_on(list: Array[AttackAction], target: Unit) -> AttackAction:
	for atk in list:
		if atk.target == target:
			return atk
	return null


func _swing_by(list: Array, actor: Unit) -> AttackAction:
	for atk: AttackAction in list:
		if atk.actor == actor and atk.target != null:
			return atk
	return null


# The blow takes the defender's arm and leaves it standing; its counter swings at the STR it has left.
func test_a_counter_after_the_blow_that_maimed_it_swings_at_the_reduced_strength() -> void:
	var attacker := _spawn(PLAYER, Vector2i(2, 1), LethalityRules.LIMB_LOSS_DAMAGE + 4)
	var defender := _spawn(ENEMY, Vector2i(1, 1))
	_strong(defender)
	await await_idle_frame()
	assert_bool(game.squad_manager.queue_action(attacker.squad,
			AttackAction.declare(attacker, attacker.movement.cell, defender.movement.cell))) \
		.override_failure_message("fixture failed to queue the blow").is_true()

	var plan: ResolvedPlan = game.squad_manager.resolved_plan_for(attacker.squad)
	var blow := _hit_on(plan.attacks, defender)
	var counter := _swing_by(plan.counters, defender)
	assert_object(blow).override_failure_message("the blow never resolved").is_not_null()
	assert_object(counter).override_failure_message("the defender drew no counter").is_not_null()
	if blow == null or counter == null:
		return
	assert_int(blow.resolved.severed_limb) \
		.override_failure_message("fixture blow (%d) takes no limb" % blow.resolved.damage).is_not_equal(-1)
	assert_int(blow.resolved.lethality) \
		.override_failure_message("fixture blow did not leave the defender standing") \
		.is_equal(ResolvedOutcome.Lethality.NONE)

	var expected := _maimed_and_whole(defender, counter.fired_attack)
	assert_int(counter.resolved.base_damage) \
		.override_failure_message("the counter swung at %d, the whole body's number; the maimed body deals %d"
			% [counter.resolved.base_damage, expected[0]]) \
		.is_equal(expected[0])

	var previewed_hp: int = counter.resolved.target_hp_after
	await game.order_executor.execute_orders(attacker.squad.get_leader())
	assert_int(attacker.get_current_hp()) \
		.override_failure_message("the counter landed a different number than previewed") \
		.is_equal(previewed_hp)


# A watch shot takes the walker's arm mid-walk; its queued swing then lands at the STR it has left.
func test_a_swing_after_a_watch_shot_maimed_its_walker_lands_at_the_reduced_strength() -> void:
	var watcher := _spawn(ENEMY, Vector2i(2, 3), LethalityRules.LIMB_LOSS_DAMAGE + 4)
	var walker := _spawn(PLAYER, Vector2i(0, 0))
	_strong(walker)
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
	var shot := _hit_on(plan.watch_shots, walker)
	var swing := _swing_by(plan.attacks, walker)
	assert_object(shot).override_failure_message("the walk never tripped the watch").is_not_null()
	assert_object(swing).override_failure_message("the walker's swing never resolved").is_not_null()
	if shot == null or swing == null:
		return
	assert_int(shot.resolved.severed_limb) \
		.override_failure_message("fixture shot (%d) takes no limb" % shot.resolved.damage).is_not_equal(-1)
	assert_int(shot.resolved.lethality) \
		.override_failure_message("fixture shot did not leave the walker standing") \
		.is_equal(ResolvedOutcome.Lethality.NONE)

	var expected := _maimed_and_whole(walker, swing.fired_attack)
	assert_int(swing.resolved.base_damage) \
		.override_failure_message("the swing struck at %d, the whole body's number; the maimed body deals %d"
			% [swing.resolved.base_damage, expected[0]]) \
		.is_equal(expected[0])

	var previewed_hp: int = swing.resolved.target_hp_after
	await game.order_executor.execute_orders(walker.squad.get_leader())
	assert_int(victim.get_current_hp()) \
		.override_failure_message("the swing after the lost limb landed a different number than previewed") \
		.is_equal(previewed_hp)
