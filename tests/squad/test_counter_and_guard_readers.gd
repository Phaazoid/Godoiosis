# Who a counter may answer, and whether a Guard arms in range, judged on the PASS (#1354). Both used to
# read the live board or the published projection while the resolve had already moved on: a counter
# was spent on a leader the pass had felled, and a Guard went red over a shove queued after it while one
# queued before it slipped through. Each case queues for real and resolves; where the claim is about
# execution, it executes. A stored order the gate would never admit is placed with Squad._queue_action
# -- the queue POSITION is the precondition, never a hand-set shove.
#
# What it cannot see: the AI's exchange scoring end to end (can_counter is asked directly instead).
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func _board(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	return b


func _spawn(b: Dictionary, unit_name: String, fac: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = BoardBuilder.spawn(b, _data(unit_name, fac), cell)
	unit.unit_instance.stats[Stats.Stat.MHP] = 200
	unit.set_current_hp(200)
	return unit


# A range-1 attack that may be aimed at a squadmate, with whatever power and shove the case wants.
# `utility` is a pure shove, the Gust shape: it deals nothing, so a standing Guard lets it through to
# the ward rather than stepping in front of it (PlanResolver._guard_for).
func _arm(unit: Unit, power: int, knockback := 0, utility := false) -> void:
	var hit := WeaponAttackData.new()
	hit.display_name = "Hit"
	hit.power = power
	hit.knockback = knockback
	hit.hits_allies = true
	hit.deals_no_damage = utility
	P.point(hit, 1, 1)
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = hit
	unit.add_item(WeaponInstance.make(t))


func _plan(sess) -> ResolvedPlan:
	return sess.squad_manager.resolve_plan(sess.squad_manager.active_squad, sess._board())


func _hit_on(plan: ResolvedPlan, unit: Unit) -> AttackAction:
	for atk in plan.attacks:
		if atk.target == unit and atk.resolved != null:
			return atk
	return null


# ==============================================================================
#  Counters
# ==============================================================================

# Leader L is felled by a squadmate's own blow, then member N strikes enemy E. E's counter goes to the
# first LEGAL member of the party, and a member the pass has felled is not one (dev, 2026-10-21:
# downed as well as killed) -- so it answers N, in the preview and at execution.
func _leader_felled_then_member_strikes(hp_for_leader: Callable) -> Dictionary:
	var b := _board("FelledLeaderRoot")
	var leader := _spawn(b, "Leader", PLAYER, Vector2i(1, 1))
	var mate := _spawn(b, "Mate", PLAYER, Vector2i(0, 1))
	var striker := _spawn(b, "Striker", PLAYER, Vector2i(1, 3))
	var foe := _spawn(b, "Foe", ENEMY, Vector2i(1, 2))   # beside the leader AND the striker
	_arm(mate, 60)
	_arm(striker, 1)
	_arm(foe, 1)
	b.squad_manager.join_squad(mate, leader.squad)
	b.squad_manager.join_squad(striker, leader.squad)
	var sess = PlaySession.new(b)
	assert_bool(sess.queue_attack(sess.handle_for(mate), leader.movement.cell).ok).override_failure_message(
			"fixture: the friendly blow was refused").is_true()
	hp_for_leader.call(leader, _hit_on(_plan(sess), leader).resolved.damage)
	assert_bool(sess.queue_attack(sess.handle_for(striker), foe.movement.cell).ok).override_failure_message(
			"fixture: the strike was refused").is_true()
	return {"sess": sess, "leader": leader, "striker": striker, "foe": foe}


func _assert_counter_answers_the_striker(ran: Dictionary, rung: ResolvedOutcome.Lethality) -> void:
	var sess = ran.sess
	var leader: Unit = ran.leader
	var striker: Unit = ran.striker
	var plan := _plan(sess)
	assert_int(_hit_on(plan, leader).resolved.lethality).override_failure_message(
			"fixture: the friendly blow does not fell the leader the way this case needs").is_equal(rung)
	var answer: CounterAttackAction = null
	for ctr in plan.counters:
		assert_object(ctr.target).override_failure_message(
				"the counter was spent on a leader the pass had already felled").is_not_same(leader)
		if ctr.target == striker:
			answer = ctr
	assert_object(answer).override_failure_message("nobody standing took the counter").is_not_null()
	var expected_hp: int = answer.resolved.target_hp_after
	assert_bool(sess.execute().ok).is_true()
	assert_int(striker.get_current_hp()).override_failure_message(
			"execution did not land the counter the preview showed on the striker").is_equal(expected_hp)


func test_a_counter_skips_a_leader_the_pass_killed() -> void:
	var ran := _leader_felled_then_member_strikes(func(leader: Unit, _damage: int) -> void:
		leader.set_current_hp(1))   # the 60-power blow overkills a 1 HP leader past the down
	_assert_counter_answers_the_striker(ran, ResolvedOutcome.Lethality.KILLED)


func test_a_counter_skips_a_leader_the_pass_downed() -> void:
	var ran := _leader_felled_then_member_strikes(func(leader: Unit, damage: int) -> void:
		leader.set_current_hp(damage))   # exactly lethal, no overkill: a down
	_assert_counter_answers_the_striker(ran, ResolvedOutcome.Lethality.DOWNED)


# ==============================================================================
#  Guard
# ==============================================================================

# Guard G beside ward W; squadmate P can shove either of them out of G's reach.
func _guard_board(root_name: String, pusher_cell: Vector2i) -> Dictionary:
	var b := _board(root_name)
	var guard := _spawn(b, "Guard", PLAYER, Vector2i(1, 1))
	var ward := _spawn(b, "Ward", PLAYER, Vector2i(2, 1))
	var pusher := _spawn(b, "Pusher", PLAYER, pusher_cell)
	_arm(pusher, 1, 1, true)
	b.squad_manager.join_squad(ward, guard.squad)
	b.squad_manager.join_squad(pusher, guard.squad)
	return {"b": b, "guard": guard, "ward": ward, "pusher": pusher, "sess": PlaySession.new(b)}


func _guard_order(blocker: Unit, ward: Unit) -> GuardAction:
	var order := GuardAction.new()
	order.init(blocker, ward)
	return order


# A shove queued AFTER the Guard is drift the ward has already armed through: the authored
# counterplay, so the order stays green and the ward arms.
func test_a_shove_queued_after_the_guard_leaves_it_green() -> void:
	var g := _guard_board("ShoveAfterGuardRoot", Vector2i(2, 2))   # shoves the ward north, out of reach
	var sess = g.sess
	var guard: Unit = g.guard
	var ward: Unit = g.ward
	assert_bool(sess.guard(sess.handle_for(guard), sess.handle_for(ward)).ok).is_true()
	assert_bool(sess.queue_attack(sess.handle_for(g.pusher), ward.movement.cell).ok).override_failure_message(
			"fixture: the shove was refused").is_true()
	var shove := _hit_on(_plan(sess), ward)
	assert_bool(GuardWard.in_range(guard.movement.cell, shove.resolved.knockback_to, guard.get_guard_range())) \
			.override_failure_message("fixture: the shove leaves the ward in reach anyway").is_false()

	var res: Dictionary = sess.preview()
	assert_bool(res.ok).override_failure_message(
			"a Guard went red over a shove queued after it: %s" % str(res)).is_true()
	assert_bool(sess.execute().ok).is_true()
	assert_object(guard.guard).override_failure_message("the ward never armed").is_not_null()


# ...but one queued BEFORE it parts the pair before the ward arms.
func test_a_shove_of_the_ward_queued_before_the_guard_reds_it() -> void:
	var g := _guard_board("ShoveWardBeforeGuardRoot", Vector2i(2, 2))
	var sess = g.sess
	assert_bool(sess.queue_attack(sess.handle_for(g.pusher), (g.ward as Unit).movement.cell).ok).is_true()
	var order := _guard_order(g.guard, g.ward)
	(g.guard as Unit).squad._queue_action(order)   # slotted after the shove: its arming moment

	var res: Dictionary = sess.preview()
	assert_bool(res.ok).override_failure_message("a Guard the pass has parted before it arms stayed green").is_false()
	assert_bool(order.resolved_in_range).is_false()


# ...and the same for a shove of the GUARD -- which the old clause, reading the guard by its moves
# alone, never saw.
func test_a_shove_of_the_guard_queued_before_it_reds_it() -> void:
	var g := _guard_board("ShoveGuardBeforeGuardRoot", Vector2i(1, 2))   # shoves the guard north
	var sess = g.sess
	assert_bool(sess.queue_attack(sess.handle_for(g.pusher), (g.guard as Unit).movement.cell).ok).is_true()
	var order := _guard_order(g.guard, g.ward)
	(g.guard as Unit).squad._queue_action(order)

	var res: Dictionary = sess.preview()
	assert_bool(res.ok).override_failure_message("a Guard shoved out of reach before it arms stayed green").is_false()
	assert_bool(order.resolved_in_range).is_false()


# A CANDIDATE Guard arms at the end of the queue, after every queued shove: the gate judges it on the
# published projection, the menu's own reading, and refuses a pair a queued aim has already parted.
func test_the_gate_refuses_a_candidate_guard_a_queued_shove_has_parted() -> void:
	var g := _guard_board("CandidateGuardRoot", Vector2i(2, 2))
	var sess = g.sess
	assert_bool(sess.queue_attack(sess.handle_for(g.pusher), (g.ward as Unit).movement.cell).ok).is_true()
	_plan(sess)   # publishes the shove, as every queue change does in the game
	var refusal: String = sess.squad_manager.try_queue_action((g.guard as Unit).squad, _guard_order(g.guard, g.ward))
	assert_str(refusal).override_failure_message("the gate admitted a Guard whose ward a queued shove has parted") \
			.contains("Too far")
