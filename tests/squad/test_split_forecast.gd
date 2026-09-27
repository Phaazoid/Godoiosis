# THE SPLIT FORECAST AGREES WITH THE PASS (#367, Law #2).
#
# SplitForecast replays, at plan time, the settle that runs after a pass: a death hands over at once,
# downed units leave in the order they went down, then the contact sweep. The rules inside each step
# are shared code; the ORDER is the one thing it spells itself -- so every case here runs the REAL
# pass through OrderExecutor.execute_orders and requires the forecast to name exactly the units that
# squad_member_left then reports as FORCED or DOWNED out of a squad of two or more. Where a case is
# about WHICH blow owns a split, it says so as well.
#
# No case pins a tuned number. A down is made by setting the victim's HP to exactly what the queued
# blow deals (test_downed_ejection's reason), a kill by a blow far past the overkill ceiling, and
# ranges are laid out against the COH each case sets itself. Each fixture checks its own lethality.
#
# Fixture is tests/ui/test_game_scene_smoke.gd's -- see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _main: Node
var game: Node2D
var _left: Array[int] = []


func before_test() -> void:
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
	_left = []
	var manager: SquadManager = game.squad_manager
	manager.squad_member_left.connect(_on_left)
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# What the pass actually did: a unit knocked out of a squad that still has members after the erase.
# A squad of one is not a split, and a death is #1104's.
func _on_left(squad: Squad, unit: Unit, cause: SquadManager.LeaveCause) -> void:
	if cause != SquadManager.LeaveCause.FORCED and cause != SquadManager.LeaveCause.DOWNED:
		return
	if squad.members.is_empty():
		return
	_left.append(unit.get_instance_id())


# --- fixture -------------------------------------------------------------------------------------

func _spawn(faction: Team.Faction, cell: Vector2i, stats: Dictionary = {}, power := 3,
		knockback := 0) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data(stats, faction), cell)
	assert_object(unit).is_not_null()
	var weapon := H.make_weapon(power)
	(weapon.template.main_attack as WeaponAttackData).knockback = knockback
	unit.equipped_weapon = weapon
	return unit


func _squad(leader: Unit, members: Array[Unit]) -> void:
	for member in members:
		game.squad_manager.join_squad(member, leader.squad)
	assert_int(leader.squad.members.size()).override_failure_message(
			"fixture: the squad did not form").is_equal(members.size() + 1)


func _queue(attacker: Unit, cell: Vector2i) -> void:
	game.squad_manager.active_squad = attacker.squad
	var action := AttackAction.declare(attacker, attacker.movement.cell, cell)
	assert_bool(game.squad_manager.queue_action(attacker.squad, action)).override_failure_message(
			"fixture: the attack at %s never queued (%s)" % [cell, ", ".join(action.validation_errors)]) \
		.is_true()
	game.refresh_action_queue(attacker.squad)


func _plan(squad: Squad) -> ResolvedPlan:
	return game.squad_manager.resolve_plan(squad, game._board())


# unit id -> the blow the forecast says knocks it out.
func _forecast(squad: Squad) -> Dictionary:
	var owners: Dictionary = {}
	for blow in SplitForecast.playback(_plan(squad)):
		var outcome := blow.resolved_outcome()
		if outcome == null:
			continue
		for unit in outcome.splits:
			owners[unit.get_instance_id()] = blow
	return owners


func _blow_on(squad: Squad, victim: Unit, actor: Unit = null) -> AttackAction:
	for blow in SplitForecast.playback(_plan(squad)):
		if blow.target == victim and (actor == null or blow.actor == actor):
			return blow
	return null


# Exactly what the queued blow deals, so the ladder lands on a down (overkill 0).
func _make_it_a_down(squad: Squad, victim: Unit, actor: Unit = null) -> void:
	var blow := _blow_on(squad, victim, actor)
	assert_object(blow).override_failure_message("fixture: no blow reaches the victim").is_not_null()
	assert_int(blow.resolved_outcome().damage).override_failure_message(
			"fixture: the blow deals nothing, so it cannot be tuned into a down").is_greater(0)
	victim.set_current_hp(blow.resolved_outcome().damage)
	game.refresh_action_queue(squad)
	_assert_lifecycle(squad, victim, actor, Unit.LifecycleState.DOWNED)


func _assert_lifecycle(squad: Squad, victim: Unit, actor: Unit, expected: Unit.LifecycleState) -> void:
	var blow := _blow_on(squad, victim, actor)
	assert_int(LethalityRules.lifecycle_for(blow.resolved_outcome().lethality)).override_failure_message(
			"fixture: the blow does not land the rung this case is about").is_equal(expected)


func _execute(actor: Unit) -> void:
	_left.clear()
	await game.order_executor.execute_orders(actor)


func _ids(owners: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for id: int in owners:
		ids.append(id)
	ids.sort()
	return ids


func _sorted(ids: Array[int]) -> Array[int]:
	var out := ids.duplicate()
	out.sort()
	return out


func _assert_agrees(owners: Dictionary) -> void:
	assert_array(_ids(owners)).override_failure_message(
			"the queue forecast %s but the pass knocked out %s" % [_ids(owners), _sorted(_left)]) \
		.is_equal(_sorted(_left))


# --- cases ---------------------------------------------------------------------------------------

func test_a_shove_out_of_range_is_a_split_on_the_shove() -> void:
	var lead := _spawn(ENEMY, Vector2i(1, 2), {Stats.Stat.LDR: 10})
	var stray := _spawn(ENEMY, Vector2i(4, 2))
	_squad(lead, [stray])
	var hero := _spawn(PLAYER, Vector2i(3, 2), {}, 3, 2)
	_queue(hero, stray.movement.cell)

	var owners := _forecast(hero.squad)
	assert_bool(owners.has(stray.get_instance_id())).override_failure_message(
			"a shove that carries a member out of range forecasts no Split").is_true()
	assert_object((owners[stray.get_instance_id()] as AttackAction).actor).is_same(hero)
	await _execute(hero)
	_assert_agrees(owners)


func test_a_shove_that_stays_in_range_is_no_split() -> void:
	var lead := _spawn(ENEMY, Vector2i(1, 2), {Stats.Stat.LDR: 10})
	var member := _spawn(ENEMY, Vector2i(4, 2))
	_squad(lead, [member])
	var hero := _spawn(PLAYER, Vector2i(3, 2), {}, 3, 1)
	_queue(hero, member.movement.cell)

	var owners := _forecast(hero.squad)
	assert_bool(owners.is_empty()).override_failure_message(
			"a shove inside the leader's range forecasts a Split").is_true()
	await _execute(hero)
	_assert_agrees(owners)


func test_a_downed_member_is_a_split_on_the_downing_blow() -> void:
	var lead := _spawn(ENEMY, Vector2i(1, 2), {Stats.Stat.LDR: 10})
	var member := _spawn(ENEMY, Vector2i(3, 2))
	_squad(lead, [member])
	var hero := _spawn(PLAYER, Vector2i(4, 2))
	_queue(hero, member.movement.cell)
	_make_it_a_down(hero.squad, member)

	var owners := _forecast(hero.squad)
	assert_array(_ids(owners)).contains_exactly([member.get_instance_id()])
	await _execute(hero)
	_assert_agrees(owners)


# The successor (highest LDR) cannot reach the far member, so the one blow splits two.
func test_a_downed_leader_whose_successor_cannot_reach_a_member_splits_two() -> void:
	var lead := _spawn(ENEMY, Vector2i(4, 2), {Stats.Stat.LDR: 10})
	var heir := _spawn(ENEMY, Vector2i(6, 2), {Stats.Stat.LDR: 4})
	var far := _spawn(ENEMY, Vector2i(1, 2))
	_squad(lead, [heir, far])
	var hero := _spawn(PLAYER, Vector2i(4, 3))
	_queue(hero, lead.movement.cell)
	_make_it_a_down(hero.squad, lead)

	var owners := _forecast(hero.squad)
	assert_array(_ids(owners)).override_failure_message(
			"the downed leader and the member its successor cannot reach are one blow's Split") \
		.is_equal(_sorted([lead.get_instance_id(), far.get_instance_id()]))
	assert_object(owners[far.get_instance_id()]).is_same(owners[lead.get_instance_id()])
	await _execute(hero)
	_assert_agrees(owners)


# The successor commands fewer than are left, so the newest member goes too -- on the same blow.
func test_a_downed_leader_whose_successor_has_less_capacity_drops_the_newest() -> void:
	var lead := _spawn(ENEMY, Vector2i(4, 2), {Stats.Stat.LDR: 10})
	var first := _spawn(ENEMY, Vector2i(5, 2))
	var second := _spawn(ENEMY, Vector2i(6, 2))
	var newest := _spawn(ENEMY, Vector2i(5, 1))
	_squad(lead, [first, second, newest])
	assert_int(Squad.capacity_of(first)).override_failure_message(
			"fixture: the successor must command fewer than the three left behind").is_less(3)
	var hero := _spawn(PLAYER, Vector2i(4, 3))
	_queue(hero, lead.movement.cell)
	_make_it_a_down(hero.squad, lead)

	var owners := _forecast(hero.squad)
	assert_bool(owners.has(newest.get_instance_id())).override_failure_message(
			"the newest member the successor cannot command forecasts no Split").is_true()
	await _execute(hero)
	_assert_agrees(owners)


# A death settles AT ONCE, mid-pass: the successor is judged there, the dead leader is not counted.
func test_a_killed_leader_hands_over_on_the_killing_blow() -> void:
	var lead := _spawn(ENEMY, Vector2i(4, 2), {Stats.Stat.LDR: 10})
	var heir := _spawn(ENEMY, Vector2i(6, 2), {Stats.Stat.LDR: 4})
	var far := _spawn(ENEMY, Vector2i(1, 2))
	_squad(lead, [heir, far])
	var hero := _spawn(PLAYER, Vector2i(4, 3), {}, 200)
	_queue(hero, lead.movement.cell)
	_assert_lifecycle(hero.squad, lead, null, Unit.LifecycleState.DEAD)

	var owners := _forecast(hero.squad)
	assert_array(_ids(owners)).override_failure_message(
			"a kill counts the stranded member and never the dead leader").contains_exactly([far.get_instance_id()])
	assert_object((owners[far.get_instance_id()] as AttackAction).target).is_same(lead)
	await _execute(hero)
	_assert_agrees(owners)


# Downed, then finished off in the same pass: the down's own Split drops (a finished-off body is
# never ejected), and the handover belongs to the kill.
func test_a_leader_downed_then_finished_off_hands_over_on_the_kill() -> void:
	var lead := _spawn(ENEMY, Vector2i(4, 2), {Stats.Stat.LDR: 10})
	var heir := _spawn(ENEMY, Vector2i(6, 2), {Stats.Stat.LDR: 4})
	var far := _spawn(ENEMY, Vector2i(1, 2))
	_squad(lead, [heir, far])
	var first := _spawn(PLAYER, Vector2i(4, 3))
	var second := _spawn(PLAYER, Vector2i(3, 2))
	_squad(first, [second])
	_queue(first, lead.movement.cell)
	_make_it_a_down(first.squad, lead, first)
	_queue(second, lead.movement.cell)
	_assert_lifecycle(first.squad, lead, second, Unit.LifecycleState.DEAD)

	var owners := _forecast(first.squad)
	assert_array(_ids(owners)).contains_exactly([far.get_instance_id()])
	assert_object((owners[far.get_instance_id()] as AttackAction).actor).override_failure_message(
			"the handover is the KILL's, not the down's").is_same(second)
	await _execute(first)
	_assert_agrees(owners)


func test_a_second_shove_back_into_range_is_no_split() -> void:
	var lead := _spawn(ENEMY, Vector2i(1, 2), {Stats.Stat.LDR: 10})
	var member := _spawn(ENEMY, Vector2i(4, 2), {Stats.Stat.MHP: 30})
	_squad(lead, [member])
	var out := _spawn(PLAYER, Vector2i(3, 2), {}, 1, 2)
	var back := _spawn(PLAYER, Vector2i(7, 2), {}, 1, 2)
	_squad(out, [back])
	_queue(out, member.movement.cell)
	_queue(back, Vector2i(6, 2))
	_assert_lifecycle(out.squad, member, back, Unit.LifecycleState.ACTIVE)

	var owners := _forecast(out.squad)
	assert_bool(owners.is_empty()).override_failure_message(
			"a member shoved out and then back into range forecasts a Split").is_true()
	await _execute(out)
	_assert_agrees(owners)


# The pair left range at the FIRST shove and never came back, so the first shove owns the Split --
# the second only moved it further away.
func test_the_blow_that_broke_the_link_owns_the_split_not_the_last_to_move_it() -> void:
	var lead := _spawn(ENEMY, Vector2i(1, 2), {Stats.Stat.LDR: 10})
	var member := _spawn(ENEMY, Vector2i(4, 2), {Stats.Stat.MHP: 30})
	_squad(lead, [member])
	var breaker := _spawn(PLAYER, Vector2i(3, 2), {}, 1, 2)
	var follower := _spawn(PLAYER, Vector2i(6, 1), {}, 1, 1)
	_squad(breaker, [follower])
	_queue(breaker, member.movement.cell)
	_queue(follower, Vector2i(6, 2))
	_assert_lifecycle(breaker.squad, member, follower, Unit.LifecycleState.ACTIVE)

	var owners := _forecast(breaker.squad)
	assert_bool(owners.has(member.get_instance_id())).is_true()
	assert_object((owners[member.get_instance_id()] as AttackAction).actor).override_failure_message(
			"the Split went on the last blow to move the member, not the one that broke the link") \
		.is_same(breaker)
	await _execute(breaker)
	_assert_agrees(owners)


# An enemy's counter shoves one of YOUR members out of your leader's reach: the REACTION owns it.
func test_a_counter_that_shoves_your_member_out_is_a_split_on_the_counter() -> void:
	var lead := _spawn(PLAYER, Vector2i(1, 3), {Stats.Stat.LDR: 10})
	var member := _spawn(PLAYER, Vector2i(4, 2), {}, 1)
	_squad(lead, [member])
	_spawn(ENEMY, Vector2i(3, 2), {}, 1, 2)
	_queue(member, Vector2i(3, 2))

	var owners := _forecast(member.squad)
	assert_bool(owners.has(member.get_instance_id())).override_failure_message(
			"a counter's shove out of range forecasts no Split").is_true()
	assert_object(owners[member.get_instance_id()]).is_instanceof(CounterAttackAction)
	await _execute(member)
	_assert_agrees(owners)
