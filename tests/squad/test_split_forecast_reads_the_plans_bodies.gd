# THE SPLIT FORECAST JUDGES THE BODIES THE PASS LEAVES (#1499, #1504).
#
# SplitForecast hands the shared cohesion rules a body for each unit: the live one until the blow that
# moves its stats, the pass's copy (PlanResolver.state_of) after it, and the copy throughout for a unit
# no blow changes but the pass already has (a carried weapon held for the preview). Each case here makes
# the live body and the pass's copy disagree about the rule it is about, so a forecast handed the wrong
# body names the wrong split, and then runs the real pass (or the real round) and requires agreement:
#   - the round's red tether judges a member's traversal on the copy (round_leavers);
#   - a handover judges the successor's reach and capacity on the copy (_hand_over);
#   - a unit with no stat-changing blow starts on the copy (_start_bodies).
#
# Fixture and helpers are tests/squad/test_split_forecast.gd's.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const WATER_ATLAS := Vector2i(5, 6)   # play/board_builder.gd's: deep water, walkable only frozen
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
	get_tree().root.remove_child(_main)
	_main.free()


# A unit knocked out of a squad that still has members after the erase.
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


# Every row that can own a split.
func _rows_of(plan: ResolvedPlan) -> Array[BaseAction]:
	var rows: Array[BaseAction] = []
	rows.append_array(SplitForecast.playback(plan))
	rows.append_array(plan.sinks)
	rows.append_array(plan.tile_hits)
	return rows


# unit id -> the row `plan` says knocks it out.
func _owners_in(plan: ResolvedPlan) -> Dictionary:
	var owners: Dictionary = {}
	for row in _rows_of(plan):
		var outcome := row.resolved_outcome()
		if outcome == null:
			continue
		for unit in outcome.splits:
			owners[unit.get_instance_id()] = row
	return owners


func _forecast(squad: Squad) -> Dictionary:
	return _owners_in(_plan(squad))


func _blow_on(squad: Squad, victim: Unit, actor: Unit) -> AttackAction:
	for blow in SplitForecast.playback(_plan(squad)):
		if blow.target == victim and blow.actor == actor:
			return blow
	return null


# Exactly what the queued blow deals, so the ladder lands on a down (overkill 0).
func _make_it_a_down(squad: Squad, victim: Unit, actor: Unit) -> void:
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
	_links_before = _links()
	_foretold = []
	for row in _rows_of(_plan(actor.squad)):
		var outcome := row.resolved_outcome()
		if outcome == null:
			continue
		for link in outcome.relinks:
			_foretold.append({"member": link.member.get_instance_id(),
					"leader": link.leader.get_instance_id(), "ends": link.ends})
	await game.order_executor.execute_orders(actor)


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


func _ids_of(units: Array[Unit]) -> Array[int]:
	var ids: Array[int] = []
	for unit in units:
		ids.append(unit.get_instance_id())
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


# --- a worn piece the pass strips ----------------------------------------------------------------

# Hard to fell, with both limb stats high enough that one lost limb moves one of them.
func _tough(stats: Dictionary = {}) -> Dictionary:
	var out := {Stats.Stat.MHP: 4 * LethalityRules.LIMB_LOSS_DAMAGE, Stats.Stat.STR: 6, Stats.Stat.DEX: 6}
	out.merge(stats, true)
	return out


# The stat `unit`'s next lost limb takes down -- the sever asked of a copy, never named here.
func _sever_moves(unit: Unit) -> Stats.Stat:
	var after := unit.state.copy()
	assert_int(after.lose_next_limb()).override_failure_message("fixture: no limb left to lose").is_not_equal(-1)
	for stat: Stats.Stat in Stats.STAT_DEFAULTS:
		if after.get_body_stat(stat) < unit.state.get_body_stat(stat):
			return stat
	fail("fixture: the next limb this unit loses moves no stat")
	return Stats.Stat.STR


# A worn piece giving `mods` (and `abilities`) that stays on only while `gate` holds where it is now.
func _wear_gated(unit: Unit, gate: Stats.Stat, mods: Dictionary[Stats.Stat, int],
		abilities: Array[Abilities.Id] = []) -> void:
	var armor := ArmorData.new()
	armor.display_name = "Gated Piece"
	armor.stat_minimums[gate] = unit.state.get_body_stat(gate)
	armor.stat_modifiers = mods
	for id in abilities:
		var ability := AbilityData.new()
		ability.id = id
		ability.kind = AbilityData.AbilityKind.PASSIVE
		armor.granted_abilities.append(ability)
	assert_bool(unit.add_item(armor)).is_true()
	assert_bool(unit.wear_armor(unit.inventory.find(armor))).override_failure_message(
			"fixture: the gated piece will not go on").is_true()


# An attacker whose one blow takes `target`'s next limb.
func _severer(cell: Vector2i, target: Unit) -> Unit:
	return _spawn(PLAYER, cell, {}, LethalityRules.limb_threshold(target.state))


func _assert_severs(squad: Squad, victim: Unit, actor: Unit) -> void:
	var blow := _blow_on(squad, victim, actor)
	assert_object(blow).override_failure_message("fixture: no blow reaches the victim").is_not_null()
	assert_int(blow.resolved_outcome().severed_limb).override_failure_message(
			"fixture: the blow takes no limb").is_not_equal(-1)
	assert_int(LethalityRules.lifecycle_for(blow.resolved_outcome().lethality)).override_failure_message(
			"fixture: the blow must leave its victim standing").is_equal(Unit.LifecycleState.ACTIVE)


# --- the round's smoke judges a member's traversal on the pass's copy (round_leavers) -------------

const ROUND_COH := 4
const LEAD_AT := Vector2i(2, 2)
const UPWIND := Vector2i(1, 2)   # beside the leader: thick smoke here spills onto it next round


# What standing in smoke takes off the leash, off the authored smoke rules.
func _round_drop() -> int:
	var rules := GasRules.for_kind(Gas.Kind.SMOKE)
	assert_bool(rules != null and rules.while_standing).override_failure_message(
			"fixture: smoke no longer blinds whoever stands in it").is_true()
	assert_int(Gas.Level.THICK - 1).override_failure_message(
			"fixture: a thick cloud's spill no longer blinds").is_greater_equal(rules.state_from)
	var drop := int(Elemental.paired_stat_mods(rules.state).get(Stats.Stat.COH, 0))
	assert_int(drop).override_failure_message("fixture: the blind state no longer shortens COH").is_less(0)
	return drop


# The members whose tether the squad's lines draw red.
func _red_tethers(squad: Squad) -> Array[Unit]:
	game.draw_squad_cohesion(squad, squad.leader.get_projected_destination())
	var red: Array[Unit] = []
	for chord: Dictionary in (game.overlay_manager as OverlayManager).squad_tether_chords:
		if chord["state"] != SquadLines2D.Strain.STRAIN:
			continue
		for member: Unit in squad.members:
			if member != squad.leader and member.get_projected_destination() == chord["from"]:
				red.append(member)
	return red


# One water cell lies between leader and member. Waterwalk from a worn piece carries the member's bubble
# straight over it; the queued sever takes the piece, and the way round is two hops longer. That longer
# way is inside the leash now and outside it once the round's smoke docks it, so the red tether must
# judge the member the pass leaves, and the round must split it.
func test_the_rounds_tether_judges_the_traversal_the_previewed_pass_leaves() -> void:
	var drop := _round_drop()
	var now := maxi(ROUND_COH, 2 - drop)
	var then := now + drop
	var straight := mini(then, now - 2)   # inside the smoked leash; the way round is not, but is inside now
	assert_int(straight).override_failure_message(
			"fixture: no room for a water cell between leader and member").is_greater_equal(2)
	var water := LEAD_AT + Vector2i.RIGHT
	game.grid.paint(water, GRASS_SOURCE, WATER_ATLAS)
	var lead := _spawn(ENEMY, LEAD_AT, {Stats.Stat.LDR: 8 * Squad.MEMBER_LDR_COST, Stats.Stat.COH: now})
	var walker := _spawn(ENEMY, LEAD_AT + Vector2i(straight, 0), _tough())
	_wear_gated(walker, _sever_moves(walker), {}, [Abilities.Id.WATERWALK])
	_squad(lead, [walker])
	assert_bool(game.grid.get_used_rect().has_point(walker.movement.cell + Vector2i.RIGHT)) \
		.override_failure_message("fixture: the board is too narrow for the leash the smoke rules make").is_true()
	game.gas_field.set_level(UPWIND, Gas.Kind.SMOKE, Gas.Level.THICK)
	var hero := _severer(walker.movement.cell + Vector2i.RIGHT, walker)
	_queue(hero, walker.movement.cell)
	_assert_severs(hero.squad, walker, hero)

	assert_array(_red_tethers(lead.squad)).override_failure_message(
			"the member whose Waterwalk the queued pass strips has no red tether: the round's forecast judged its live body") \
		.contains_exactly([walker])

	_left = []
	await game.order_executor.execute_orders(hero)
	assert_array(_left).override_failure_message(
			"fixture: the pass's own sweep took the member, so the round has nothing to split").is_empty()
	await game.end_turn()   # into their turn: the round has not come yet
	await await_idle_frame()
	assert_array(_left).override_failure_message("fixture: the split came before the round did").is_empty()
	await game.end_turn()   # the round, then your turn start
	await await_idle_frame()
	assert_array(_sorted(_left)).override_failure_message(
			"the round split someone other than the red tether named").is_equal(_ids_of([walker]))


# --- a handover judges the successor the pass leaves (_hand_over) --------------------------------

# The downed leader hands over at pass end to an heir whose leash came from a piece the pass takes. The
# member out of the stripped leash leaves on the downing blow, with the leader.
func test_a_successor_the_pass_strips_of_its_leash_drops_who_it_no_longer_reaches() -> void:
	var lead := _spawn(ENEMY, Vector2i(4, 2), {Stats.Stat.LDR: 10, Stats.Stat.COH: 4})
	var heir := _spawn(ENEMY, Vector2i(5, 2), _tough({Stats.Stat.LDR: 6, Stats.Stat.COH: 2}))
	_wear_gated(heir, _sever_moves(heir), {Stats.Stat.COH: 3})
	var far := _spawn(ENEMY, Vector2i(1, 2), {Stats.Stat.LDR: 0})
	_squad(lead, [heir, far])
	var downer := _spawn(PLAYER, Vector2i(4, 3))
	var striker := _severer(Vector2i(6, 2), heir)
	_squad(downer, [striker])
	_queue(downer, lead.movement.cell)
	_make_it_a_down(downer.squad, lead, downer)
	_queue(striker, heir.movement.cell)
	_assert_severs(downer.squad, heir, striker)
	_assert_lifecycle(downer.squad, lead, downer, Unit.LifecycleState.DOWNED)
	var gap := 4   # heir to far, along the row
	var left_with := PlanResolver.state_of(heir, _plan(downer.squad).hypo)
	assert_bool(Squad.range_of(heir.state) >= gap and Squad.range_of(left_with) < gap) \
		.override_failure_message("fixture: the pass must strip the leash that reaches the far member").is_true()

	var owners := _forecast(downer.squad)
	assert_bool(owners.has(far.get_instance_id())).override_failure_message(
			"the member the stripped successor cannot reach has no Split").is_true()
	assert_object(owners.get(far.get_instance_id())).override_failure_message(
			"the member the stripped successor cannot reach is not split on the downing blow") \
		.is_same(owners.get(lead.get_instance_id()))
	await _execute(downer)
	_assert_agrees(owners)


# The same handover, its heir's command from the piece: stripped, it commands fewer than are left, so
# the newest member goes on the downing blow.
func test_a_successor_the_pass_strips_of_its_command_drops_the_newest() -> void:
	var lead := _spawn(ENEMY, Vector2i(4, 2), {Stats.Stat.LDR: 10, Stats.Stat.COH: 4})
	var heir := _spawn(ENEMY, Vector2i(5, 2), _tough({Stats.Stat.LDR: Squad.MEMBER_LDR_COST, Stats.Stat.COH: 4}))
	_wear_gated(heir, _sever_moves(heir), {Stats.Stat.LDR: 2 * Squad.MEMBER_LDR_COST})
	var first := _spawn(ENEMY, Vector2i(3, 2), {Stats.Stat.LDR: 0})
	var newest := _spawn(ENEMY, Vector2i(4, 1), {Stats.Stat.LDR: 0})
	_squad(lead, [heir, first, newest])
	var downer := _spawn(PLAYER, Vector2i(4, 3))
	var striker := _severer(Vector2i(6, 2), heir)
	_squad(downer, [striker])
	_queue(downer, lead.movement.cell)
	_make_it_a_down(downer.squad, lead, downer)
	_queue(striker, heir.movement.cell)
	_assert_severs(downer.squad, heir, striker)
	_assert_lifecycle(downer.squad, lead, downer, Unit.LifecycleState.DOWNED)
	var left_with := PlanResolver.state_of(heir, _plan(downer.squad).hypo)
	assert_bool(Squad.capacity_of(heir.state) >= 3 and Squad.capacity_of(left_with) < 3) \
		.override_failure_message("fixture: the pass must strip the command that holds all three").is_true()

	var owners := _forecast(downer.squad)
	assert_bool(owners.has(newest.get_instance_id())).override_failure_message(
			"the newest member the stripped successor cannot command has no Split").is_true()
	assert_object(owners.get(newest.get_instance_id())).is_same(owners.get(lead.get_instance_id()))
	await _execute(downer)
	_assert_agrees(owners)


# --- a unit no blow changes starts on the pass's copy (_start_bodies) ----------------------------

func _aim_from(hero: Unit, weapon: WeaponInstance, foe: Unit) -> AttackAction:
	return hero.with_weapon_in_hand(weapon, func() -> AttackAction:
		hero.active_attack = weapon.template.main_attack
		var aim := AttackAction.declare(hero, hero.movement.cell, foe.movement.cell)
		hero.active_attack = null
		return aim)


func _counter_on(plan: ResolvedPlan, victim: Unit) -> CounterAttackAction:
	for counter in plan.counters:
		if counter.target == victim:
			return counter
	return null


# The leader's leash comes from a mod on the weapon in hand. Previewed from a plain weapon it carries,
# the pass holds that one, so the leash is the bare one from the start: the foe's counter shoves the
# leader one cell out of the member's reach, and the counter's row owns the Split. Then the same aim,
# the weapon really in hand, runs.
func test_a_preview_from_a_carried_weapon_judges_the_leash_that_weapon_leaves() -> void:
	var hero := _spawn(PLAYER, Vector2i(3, 1), {Stats.Stat.LDR: 4, Stats.Stat.COH: 2, Stats.Stat.MHP: 60}, 1)
	hero.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var in_hand := H.make_weapon(1)
	var mod := WeaponModData.new()
	mod.stat_modifiers[Stats.Stat.COH] = 1
	assert_bool(in_hand.fit(0, mod)).override_failure_message("fixture: the mod must fit").is_true()
	var carried := H.make_weapon(1)
	hero.inventory.clear()
	hero.inventory.append(in_hand)
	hero.inventory.append(carried)
	hero.equipped_weapon = in_hand
	var member := _spawn(PLAYER, Vector2i(3, 3))
	_squad(hero, [member])
	var foe := _spawn(ENEMY, Vector2i(2, 1), {Stats.Stat.MHP: 60}, 1, 1)
	var shoved_to := hero.movement.cell + Vector2i.RIGHT
	var reach := RulesService.path_hops(shoved_to, game._board(), member.state, 8, {}).get(member.movement.cell, -1) as int
	assert_bool(Squad.range_of(hero.state) >= reach
			and hero.with_weapon_in_hand(carried, func() -> int: return Squad.range_of(hero.state)) < reach) \
		.override_failure_message("fixture: only the mod in hand may reach the member from the shoved cell") \
		.is_true()

	game.squad_manager.active_squad = hero.squad
	var preview: ResolvedPlan = game.squad_manager.preview_aim(hero.squad, _aim_from(hero, carried, foe),
			game._board(), carried)
	assert_object(preview).override_failure_message("the preview refused the carried weapon").is_not_null()
	var counter := _counter_on(preview, hero)
	assert_object(counter).override_failure_message("fixture: the foe does not counter").is_not_null()
	assert_that(counter.resolved_outcome().knockback_to).override_failure_message(
			"fixture: the counter does not shove the leader one cell").is_equal(shoved_to)
	assert_bool(counter.resolved_outcome().splits.has(member)).override_failure_message(
			"the preview from the carried weapon forecasts no Split: it judged the leash of the weapon in hand") \
		.is_true()

	assert_bool(hero.set_equipped_weapon(carried)).override_failure_message(
			"fixture: the carried weapon must be equippable").is_true()
	_queue(hero, foe.movement.cell)
	var owners := _forecast(hero.squad)
	assert_object(owners.get(member.get_instance_id())).is_instanceof(CounterAttackAction)
	await _execute(hero)
	_assert_agrees(owners)
