# THE SPLIT FORECAST AGREES WITH THE PASS (#367, Law #2).
#
# SplitForecast replays, at plan time, the settle that runs after a pass: a death hands over at once,
# downed units leave in the order they went down, then the contact sweep. The rules inside each step
# are shared code; the ORDER is the one thing it spells itself -- so every case here runs the REAL
# pass through OrderExecutor.execute_orders and requires the forecast to name exactly the units that
# squad_member_left then reports as FORCED or DOWNED out of a squad of two or more. Where a case is
# about WHICH blow owns a split, it says so as well. Every case also checks the forecast's LINKS
# (#367 part 2B): applied blow by blow to the board before the pass, they must give the board after.
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
var _links_before: Dictionary = {}
var _foretold: Array[Dictionary] = []


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


# Every row that can own a split: the pass's blows, its sinkings (#922), then its END OF TURN burns.
func _rows(squad: Squad) -> Array[BaseAction]:
	var plan := _plan(squad)
	var rows: Array[BaseAction] = []
	rows.append_array(SplitForecast.playback(plan))
	rows.append_array(plan.sinks)
	rows.append_array(plan.tile_hits)
	return rows


# unit id -> the row the forecast says knocks it out.
func _forecast(squad: Squad) -> Dictionary:
	var owners: Dictionary = {}
	for blow in _rows(squad):
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


# The pass, and with `then_burn` the END OF TURN burn after it (game.end_turn's own first step).
func _execute(actor: Unit, then_burn := false) -> void:
	_left.clear()
	_links_before = _links()
	_foretold = []
	var faction := actor.get_faction()
	for blow in _rows(actor.squad):
		var outcome := blow.resolved_outcome()
		if outcome == null:
			continue
		for link in outcome.relinks:
			_foretold.append({"member": link.member.get_instance_id(),
					"leader": link.leader.get_instance_id(), "ends": link.ends})
	await game.order_executor.execute_orders(actor)
	if then_burn:
		await game.order_executor.apply_burning_tile_damage(faction)


# Every member -> leader link on the board, by instance id.
func _links() -> Dictionary:
	var links: Dictionary = {}
	for squad: Squad in game.squad_manager.squads:
		if not is_instance_valid(squad) or not squad.has_squadmates():
			continue
		var leader := squad.get_leader()
		for member: Unit in squad.get_members():
			if member != leader:
				links[member.get_instance_id()] = leader.get_instance_id()
	return links


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
	_assert_links_foretold()


# The links the forecast says end and begin, applied blow by blow to the board before the pass, are
# the board's links after it -- what the tether break plays at the blow is what the settle leaves.
func _assert_links_foretold() -> void:
	var links := _links_before.duplicate()
	for change: Dictionary in _foretold:
		var member: int = change["member"]
		if change["ends"]:
			if links.get(member, 0) == change["leader"]:
				links.erase(member)
		else:
			links[member] = change["leader"]
	assert_dict(links).override_failure_message(
			"the forecast's links come to %s but the pass left %s" % [links, _links()]) \
		.is_equal(_links())


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


# A downed leader's links all end on the downing blow, and the member its successor can hold draws
# in to the successor on that SAME blow -- the handover the tether plays at the blow (#367 part 2B).
func test_a_downed_leaders_handover_relinks_on_the_downing_blow() -> void:
	var lead := _spawn(ENEMY, Vector2i(4, 2), {Stats.Stat.LDR: 10})
	var heir := _spawn(ENEMY, Vector2i(5, 2), {Stats.Stat.LDR: 4})
	var other := _spawn(ENEMY, Vector2i(6, 2))
	_squad(lead, [heir, other])
	assert_int(Squad.capacity_of(heir)).override_failure_message(
			"fixture: the successor must be able to hold the one left behind").is_greater_equal(2)
	var hero := _spawn(PLAYER, Vector2i(4, 3))
	_queue(hero, lead.movement.cell)
	_make_it_a_down(hero.squad, lead)

	var said: Array[String] = []
	for link in _blow_on(hero.squad, lead).resolved_outcome().relinks:
		said.append(_spell(link))
	assert_array(said).contains_exactly_in_any_order([
			"%s>%s ends" % [heir.get_instance_id(), lead.get_instance_id()],
			"%s>%s ends" % [other.get_instance_id(), lead.get_instance_id()],
			"%s>%s begins" % [other.get_instance_id(), heir.get_instance_id()]])
	var owners := _forecast(hero.squad)
	await _execute(hero)
	_assert_agrees(owners)


func _spell(link: ResolvedOutcome.Relink) -> String:
	return "%s>%s %s" % [link.member.get_instance_id(), link.leader.get_instance_id(),
			"ends" if link.ends else "begins"]


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


# --- walks and watches (2A's leftovers) ----------------------------------------------------------

# A watch over `cells`, anchored where the watcher stands -- test_overwatch_trigger's fixture.
func _watch(watcher: Unit, cells: Array[Vector2i]) -> void:
	var attack: WeaponAttackData = (watcher.get_equipped_weapon() as WeaponInstance).template.main_attack
	watcher.arm_watch(watcher.movement.cell, cells[0], cells, attack)


func _walk(unit: Unit, to: Vector2i) -> void:
	var path: Array[Vector2i] = []
	var at := unit.movement.cell
	path.append(at)
	while at != to:
		at += Vector2i(signi(to.x - at.x), 0) if at.x != to.x else Vector2i(0, signi(to.y - at.y))
		path.append(at)
	var move := MoveAction.new()
	move.init(unit, path, null)
	game.squad_manager.active_squad = unit.squad
	assert_bool(game.squad_manager.queue_action(unit.squad, move)).override_failure_message(
			"fixture: the walk to %s never queued (%s)" % [to, ", ".join(move.validation_errors)]).is_true()
	game.refresh_action_queue(unit.squad)


# A watch shot kills the leader at its first step while a member is still walking in. Live, the
# successor's reach waits for the walk to end -- where the forecast judges it -- so the member stays;
# judged at the frame of the kill, it would be stranded mid-stride.
func test_a_leader_killed_mid_walk_judges_reach_where_the_walks_end() -> void:
	var lead := _spawn(PLAYER, Vector2i(7, 0), {Stats.Stat.LDR: 10, Stats.Stat.MHP: 10})
	var heir := _spawn(PLAYER, Vector2i(6, 2), {Stats.Stat.LDR: 4, Stats.Stat.COH: 1})
	var walker := _spawn(PLAYER, Vector2i(1, 2))
	_squad(lead, [heir, walker])
	var watcher := _spawn(ENEMY, Vector2i(9, 4), {}, 200)
	_watch(watcher, [Vector2i(6, 0)])
	_walk(walker, Vector2i(5, 2))
	_walk(lead, Vector2i(5, 0))

	var shots := _plan(lead.squad).mid_walk_shots()
	assert_int(shots.size()).override_failure_message("fixture: the watch never fired").is_equal(1)
	assert_object(shots[0].target).is_same(lead)
	assert_int(LethalityRules.lifecycle_for(shots[0].resolved_outcome().lethality)).override_failure_message(
			"fixture: the watch shot does not kill the leader").is_equal(Unit.LifecycleState.DEAD)

	var owners := _forecast(lead.squad)
	assert_bool(owners.is_empty()).override_failure_message(
			"the walker ends beside the successor, yet the forecast strands it").is_true()
	await _execute(lead)
	_assert_ran(walker, Vector2i(5, 2))
	_assert_agrees(owners)
	assert_object(walker.squad).override_failure_message(
			"the walker was judged mid-stride and left the squad").is_same(heir.squad)


# 2A declared "a watch shot that halts a walk short strands a member with no blow to own it". That
# pass cannot run: the validator judges a halted walk where the shot CATCHES it, so a catch out of
# range reds the walk and the plan is refused. A catch in range makes the shove an ordinary break
# the forecast already owns (test_a_shove_out_of_range_is_a_split_on_the_shove's shape).
func test_a_walk_a_watch_would_halt_out_of_range_is_refused_rather_than_stranded() -> void:
	var lead := _spawn(PLAYER, Vector2i(6, 2), {Stats.Stat.LDR: 10})
	var walker := _spawn(PLAYER, Vector2i(0, 2), {Stats.Stat.MHP: 30})
	_squad(lead, [walker])
	var watcher := _spawn(ENEMY, Vector2i(1, 4), {}, 1, 1)
	_watch(watcher, [Vector2i(1, 2)])
	_walk(walker, Vector2i(3, 2))

	var shots := _plan(lead.squad).mid_walk_shots()
	assert_int(shots.size()).override_failure_message("fixture: the watch never fired").is_equal(1)
	var shot := shots[0].resolved_outcome()
	assert_bool(shot.knockback_applied and LethalityRules.lifecycle_for(shot.lethality) \
			== Unit.LifecycleState.ACTIVE).override_failure_message(
			"fixture: the watch shot must shove the walker and leave it standing").is_true()
	var board: BoardContext = game._board()
	assert_bool(SquadCohesion.in_range_of(lead, lead.movement.cell, walker, shot.knockback_from, board)) \
		.override_failure_message("fixture: the shot must catch the walker out of range").is_false()

	game.refresh_action_queue(lead.squad)
	assert_bool(walker.get_move_action().is_valid).override_failure_message(
			"a walk the watch halts out of range is legal, so the pass could strand the walker").is_false()
	await _execute(lead)
	assert_object(walker.squad).is_same(lead.squad)
	assert_array(_left).is_empty()


# --- the END OF TURN burn ------------------------------------------------------------------------

func _ignite(cell: Vector2i) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BURNING])
	game.terrain_states.apply(effect)


func _burn_on(squad: Squad, victim: Unit) -> TileHitAction:
	for burn in _plan(squad).tile_hits:
		if burn.actor == victim:
			return burn
	return null


# Exactly what the burn deals, so the ladder lands on a down -- _make_it_a_down's reason.
func _burn_down(squad: Squad, victim: Unit) -> void:
	var burn := _burn_on(squad, victim)
	assert_object(burn).override_failure_message("fixture: the fire forecasts no burn").is_not_null()
	victim.set_current_hp(burn.resolved_outcome().damage)
	game.refresh_action_queue(squad)
	assert_int(LethalityRules.lifecycle_for(_burn_on(squad, victim).resolved_outcome().lethality)) \
		.override_failure_message("fixture: the burn does not down the victim").is_equal(
			Unit.LifecycleState.DOWNED)


func test_a_member_the_burn_downs_splits_on_its_end_of_turn_row() -> void:
	var lead := _spawn(PLAYER, Vector2i(1, 2), {Stats.Stat.LDR: 10})
	var member := _spawn(PLAYER, Vector2i(3, 2))
	_squad(lead, [member])
	_ignite(member.movement.cell)
	_burn_down(lead.squad, member)

	var owners := _forecast(lead.squad)
	assert_bool(owners.has(member.get_instance_id())).override_failure_message(
			"a member the burn downs has no Split").is_true()
	assert_object(owners[member.get_instance_id()]).override_failure_message(
			"the burn's Split is not on the END OF TURN row").is_instanceof(TileHitAction)
	await _execute(lead, true)
	_assert_agrees(owners)


# The burned-down leader hands over at end of turn, and the member its successor cannot reach leaves
# on the same END OF TURN row.
func test_a_leader_the_burn_downs_hands_over_on_its_end_of_turn_row() -> void:
	var lead := _spawn(PLAYER, Vector2i(4, 2), {Stats.Stat.LDR: 10})
	var heir := _spawn(PLAYER, Vector2i(6, 2), {Stats.Stat.LDR: 4})
	var far := _spawn(PLAYER, Vector2i(1, 2))
	_squad(lead, [heir, far])
	_ignite(lead.movement.cell)
	_burn_down(lead.squad, lead)

	var owners := _forecast(lead.squad)
	assert_array(_ids(owners)).override_failure_message(
			"the burned leader and the member its successor cannot reach are one row's Split") \
		.is_equal(_sorted([lead.get_instance_id(), far.get_instance_id()]))
	assert_object((owners[far.get_instance_id()] as TileHitAction).actor).is_same(lead)
	await _execute(lead, true)
	_assert_agrees(owners)


# --- the ground this pass changes ----------------------------------------------------------------

const WATER_ATLAS := Vector2i(5, 6)   # play/board_builder.gd's: deep water, walkable only frozen


# A river along `row` that nobody crosses except on `frozen`.
func _river(row: int, frozen: Array[Vector2i]) -> void:
	var grid: BoardGrid = game.grid
	for x in range(10):
		grid.paint(Vector2i(x, row), GRASS_SOURCE, WATER_ATLAS)
	for cell in frozen:
		var ice := ResolvedCellEffect.new()
		ice.cell = cell
		ice.states_added.assign([Terrain.TileState.FROZEN])
		game.terrain_states.apply(ice)


# The unit's main attack carries `element` and lands on the ground as well as on units.
func _imbue(unit: Unit, element: Elemental.Element) -> void:
	var attack: WeaponAttackData = (unit.get_equipped_weapon() as WeaponInstance).template.main_attack
	attack.elemental_damage_type = element
	attack.targets = EquippableData.TargetMode.BOTH


func _deposits_at(squad: Squad, cell: Vector2i) -> Array[ResolvedCellEffect]:
	var found: Array[ResolvedCellEffect] = []
	for effect in _plan(squad).cell_effects:
		if effect.cell == cell:
			found.append(effect)
	return found


# The fire melts the one crossing between leader and member. Nobody is hit, and the member is out of
# range once the pass's ground lands -- on the fire's own row.
func test_a_fire_that_melts_the_ice_between_them_splits_on_the_fire() -> void:
	_river(2, [Vector2i(1, 2)])
	var lead := _spawn(ENEMY, Vector2i(2, 1), {Stats.Stat.LDR: 10, Stats.Stat.COH: 3})
	var member := _spawn(ENEMY, Vector2i(1, 3))
	_squad(lead, [member])
	var hero := _spawn(PLAYER, Vector2i(1, 1))
	_imbue(hero, Elemental.Element.FIRE)
	_queue(hero, Vector2i(1, 2))
	var melt := _deposits_at(hero.squad, Vector2i(1, 2))
	assert_bool(melt.size() == 1 and melt[0].states_removed.has(Terrain.TileState.FROZEN)) \
		.override_failure_message("fixture: the fire does not melt the crossing").is_true()

	var owners := _forecast(hero.squad)
	assert_bool(owners.has(member.get_instance_id())).override_failure_message(
			"a member stranded by melting ice has no Split").is_true()
	assert_object((owners[member.get_instance_id()] as AttackAction).actor).override_failure_message(
			"the Split is not on the fire that melted the crossing").is_same(hero)
	await _execute(hero)
	_assert_agrees(owners)


# A member standing ON the ice the fire melts goes under (#922) -- a down, so a split, and on the
# sinking's own row: the fire's blow does not down it, the water does.
func test_a_member_the_melt_sinks_splits_on_its_sinking() -> void:
	_river(2, [Vector2i(1, 2)])
	var lead := _spawn(ENEMY, Vector2i(1, 1), {Stats.Stat.LDR: 10, Stats.Stat.COH: 3})
	var member := _spawn(ENEMY, Vector2i(1, 2), {Stats.Stat.MHP: 30})
	_squad(lead, [member])
	var hero := _spawn(PLAYER, Vector2i(1, 3))
	_imbue(hero, Elemental.Element.FIRE)
	_queue(hero, Vector2i(1, 2))
	var blow := _blow_on(hero.squad, member, hero)
	assert_that(LethalityRules.lifecycle_for(blow.resolved_outcome().lethality)).override_failure_message(
			"fixture: the fire alone must leave the member standing").is_equal(Unit.LifecycleState.ACTIVE)
	assert_int(_plan(hero.squad).sinks.size()).override_failure_message(
			"fixture: the member must go under").is_equal(1)

	var owners := _forecast(hero.squad)
	assert_bool(owners.has(member.get_instance_id())).override_failure_message(
			"a member the melt sank has no Split").is_true()
	assert_bool(owners[member.get_instance_id()] is SinkAction).override_failure_message(
			"the Split is not on the sinking").is_true()
	await _execute(hero)
	_assert_agrees(owners)


# A shove sends a member the long way round the river, out of range -- and the same pass freezes a
# crossing right beside it. The pass keeps the member, so no Split (and no break played for it).
func test_an_ice_that_freezes_a_way_back_keeps_the_member_the_shove_would_have_lost() -> void:
	_river(2, [Vector2i(1, 2)])
	var lead := _spawn(ENEMY, Vector2i(2, 1), {Stats.Stat.LDR: 10, Stats.Stat.COH: 3})
	var member := _spawn(ENEMY, Vector2i(1, 3), {Stats.Stat.MHP: 30})
	_squad(lead, [member])
	var shover := _spawn(PLAYER, Vector2i(0, 3), {}, 1, 1)
	var froster := _spawn(PLAYER, Vector2i(1, 2))
	_squad(shover, [froster])
	_imbue(froster, Elemental.Element.ICE)
	_queue(shover, member.movement.cell)
	_queue(froster, Vector2i(2, 2))
	var ice := _deposits_at(shover.squad, Vector2i(2, 2))
	assert_bool(ice.size() == 1 and ice[0].states_added.has(Terrain.TileState.FROZEN)) \
		.override_failure_message("fixture: the ice does not freeze the new crossing").is_true()
	var board: BoardContext = game._board()
	assert_bool(SquadCohesion.in_range_of(lead, lead.movement.cell, member, Vector2i(2, 3), board)) \
		.override_failure_message("fixture: without the ice, the shove must strand the member").is_false()

	var owners := _forecast(shover.squad)
	assert_bool(owners.is_empty()).override_failure_message(
			"a member the pass's own ice keeps in range forecasts a Split").is_true()
	await _execute(shover)
	_assert_ran(member, Vector2i(2, 3))
	_assert_agrees(owners)


# A leader killed by one mid-walk shot, then a member thrown INTO the successor's reach by a later
# one: the handover is judged where the walk ends, after the throw, so the member stays.
func test_a_mid_walk_handover_is_judged_after_a_later_mid_walk_shove() -> void:
	var lead := _spawn(PLAYER, Vector2i(7, 0), {Stats.Stat.LDR: 10, Stats.Stat.MHP: 10})
	var heir := _spawn(PLAYER, Vector2i(6, 1), {Stats.Stat.LDR: 4, Stats.Stat.COH: 1})
	var walker := _spawn(PLAYER, Vector2i(2, 1), {Stats.Stat.MHP: 30})
	_squad(lead, [heir, walker])
	var killer := _spawn(ENEMY, Vector2i(9, 4), {}, 200)
	_watch(killer, [Vector2i(6, 0)])
	var thrower := _spawn(ENEMY, Vector2i(0, 1), {}, 1, 2)
	_watch(thrower, [Vector2i(3, 1)])
	_walk(lead, Vector2i(5, 0))
	_walk(walker, Vector2i(4, 1))

	var shots := _plan(lead.squad).mid_walk_shots()
	assert_int(shots.size()).override_failure_message("fixture: both watches must fire").is_equal(2)
	assert_bool(shots[0].target == lead and LethalityRules.lifecycle_for(
			shots[0].resolved_outcome().lethality) == Unit.LifecycleState.DEAD).override_failure_message(
			"fixture: the first shot must kill the leader").is_true()
	assert_bool(shots[1].target == walker and shots[1].resolved_outcome().knockback_to == Vector2i(5, 1)) \
		.override_failure_message("fixture: the second shot must throw the walker beside the heir").is_true()

	var owners := _forecast(lead.squad)
	assert_bool(owners.is_empty()).override_failure_message(
			"the handover was judged before the throw that brings the walker into reach").is_true()
	await _execute(lead)
	_assert_ran(walker, Vector2i(5, 1))
	_assert_agrees(owners)
	assert_object(walker.squad).is_same(heir.squad)


# A case whose point is that the pass KEEPS someone passes vacuously on a plan that never ran.
func _assert_ran(unit: Unit, cell: Vector2i) -> void:
	assert_that(unit.movement.cell).override_failure_message(
			"fixture: the pass never ran (%s is not at %s)" % [unit.get_unit_name(), cell]).is_equal(cell)
