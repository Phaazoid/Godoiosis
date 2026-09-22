# R7 liveness past counters (#1005): a unit the pass has already felled is not an AGENT in it.
#
# The reported bug was one shape of this -- a priest downed by an overwatch shot during the MOVE
# phase went on to execute its own queued self-heal, ending up DOWNED with restored HP. The rule
# is wider than that pass: an authored attack, a walk, an arming verb and a side-channel verb all
# ask the same question, and until this ticket only COUNTERS did (PlanResolver._counter_actor_live).
#
# Every case here fells its actor through a REAL watch shot fired mid-walk rather than by calling
# force_down(), because the ORDERING is the bug: a gate that reads the live board instead of the
# threaded hypo passes a hand-downed unit and still misses the one the pass itself put down.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

# The watcher's spread covers the crossing cell AND the cell the bystander stands on -- which is
# the board the bug was found on: a watch shot sweeps its whole footprint, so the unit standing
# in it eats the shot somebody else triggered (standing-reactions.md, "the shot IS the attack").
const CROSSING := Vector2i(3, 0)
const BYSTANDER_CELL := Vector2i(4, 0)
const FOOTPRINT: Array[Vector2i] = [CROSSING, BYSTANDER_CELL]

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _board() -> BoardContext:
	return _sm.board_source.call()


# The enemy standing watch over both cells. Anchored where it stands, or _watch_triggered_by
# refuses it before anything else in this suite can happen.
func _watcher() -> Unit:
	var unit := H.spawn_solo(self, _sm, ENEMY, Vector2i(8, 8), {Stats.Stat.STR: 5})
	var attack: WeaponAttackData = (unit.get_equipped_weapon() as WeaponInstance).template.main_attack
	# Two one-tile paths, so the shot takes the crosser AND the bystander (#1054 ruling 7). As ONE path
	# it would stop at the crosser, the nearer of the two (#1040), and fell nobody the fixture needs.
	var one_tile_each: Array[int] = [1, 1]
	unit.arm_watch(unit.movement.cell, CROSSING, FOOTPRINT, attack, false, false, one_tile_each)
	return unit


# A player squad whose LEADER walks into the watch and whose BYSTANDER is standing in the spread,
# one hit from going down. Returns [leader, bystander]; the caller queues whatever the bystander
# is going to fail to do. The move is queued FIRST so the walk resolves before anything else --
# that ordering is the whole point.
func _squad_walking_into_the_watch() -> Array[Unit]:
	var leader := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), {Stats.Stat.LDR: 10})
	var bystander := H.spawn_solo(self, _sm, PLAYER, BYSTANDER_CELL)
	_sm.join_squad(bystander, leader.squad)

	bystander.take_damage(bystander.get_current_hp() - 1)
	assert_bool(bystander.is_active()) \
		.override_failure_message("fixture bloodied the bystander all the way down").is_true()

	var walk: Array[Vector2i] = [leader.movement.cell, CROSSING]
	var move := MoveAction.new()
	move.init(leader, walk, null)
	leader.squad._queue_action(move)
	return [leader, bystander]


# The shot really did fell the bystander -- asserted in every case, because a fixture that stopped
# felling would make each of them pass for the wrong reason.
func _assert_felled(plan: ResolvedPlan, bystander: Unit) -> void:
	assert_int(plan.watch_shots.size()) \
		.override_failure_message("the walk never tripped the watch").is_greater(0)
	assert_int(PlanResolver.projected_lifecycle(bystander, plan.hypo)) \
		.override_failure_message("the watch shot did not fell the bystander") \
		.is_not_equal(Unit.LifecycleState.ACTIVE)


# ==============================================================================
#  The authored attack: EXPANDED, then skipped
# ==============================================================================

# The heart of the reported bug. The volley must still be DERIVED -- see the next case for why --
# and every member of it marked skipped, which is where R7 has always written this.
func test_a_felled_actors_attack_is_expanded_and_then_skipped() -> void:
	var _w := _watcher()
	var pair := _squad_walking_into_the_watch()
	var bystander: Unit = pair[1]
	var victim := H.spawn_solo(self, _sm, ENEMY, Vector2i(5, 0))
	bystander.squad._queue_action(H.stamped_attack(bystander, victim))

	var plan := _sm.resolve_plan(bystander.squad, _board())
	_assert_felled(plan, bystander)

	var own: Array[AttackAction] = []
	for atk in plan.attacks:
		if atk.actor == bystander:
			own.append(atk)
	assert_int(own.size()) \
		.override_failure_message("the felled actor's volley was DROPPED, not skipped (#1005)") \
		.is_greater(0)
	for atk in own:
		assert_bool(atk.resolved != null and atk.resolved.skipped) \
			.override_failure_message("a felled actor's swing still resolved").is_true()
	assert_int(victim.get_current_hp()) \
		.override_failure_message("a felled actor dealt damage").is_equal(victim.get_max_hp())


# WHY the expansion has to survive. SquadPlanValidator._plan_found_a_target looks for a derived
# attack carrying a target, so an unexpanded aim reads as a whiff and the WHOLE PLAN goes invalid
# -- which refuses Execute for a human and, worse, trips execute_orders' concede branch for an AI
# squad, costing it its entire turn because one member was knocked down mid-walk.
func test_a_felled_actors_attack_does_not_redden_the_plan() -> void:
	var _w := _watcher()
	var pair := _squad_walking_into_the_watch()
	var bystander: Unit = pair[1]
	var victim := H.spawn_solo(self, _sm, ENEMY, Vector2i(5, 0))
	var aim := H.stamped_attack(bystander, victim)
	bystander.squad._queue_action(aim)

	var plan := _sm.resolve_plan(bystander.squad, _board())
	_assert_felled(plan, bystander)
	_sm.validate_squad_plan(bystander.squad, plan)

	assert_bool(aim.is_valid) \
		.override_failure_message("the felled actor's aim whiffed itself red: %s" % str(aim.validation_errors)) \
		.is_true()
	assert_bool(_sm.squad_has_invalid_actions(bystander.squad)) \
		.override_failure_message("one felled member invalidated the squad's whole plan").is_false()


# A swing that never happened provokes nothing. Until liveness generalised past counters, `skipped`
# only ever sat on a counter -- and a counter is never counter-bait -- so this list had never met
# one; without the clause the defender retaliates against a blow nobody threw.
func test_a_skipped_attack_draws_no_counter() -> void:
	var _w := _watcher()
	var pair := _squad_walking_into_the_watch()
	var bystander: Unit = pair[1]
	var victim := H.spawn_solo(self, _sm, ENEMY, Vector2i(5, 0))
	bystander.squad._queue_action(H.stamped_attack(bystander, victim))

	var plan := _sm.resolve_plan(bystander.squad, _board())
	_assert_felled(plan, bystander)

	for ctr in plan.counters:
		assert_object(ctr.actor) \
			.override_failure_message("the victim countered a swing that was never thrown (#1005)") \
			.is_not_same(victim)


# ==============================================================================
#  The walk
# ==============================================================================

# A body does not walk. Without the gate at the top of resolve_move the loop takes its first step
# before the existing post-step lifecycle check halts it, so a felled unit slid one cell. The halt
# is stamped at index 0 so walked_path()/get_destination() report it through the seam they already
# use for a shot-halted walk, rather than needing a new concept.
func test_a_body_does_not_walk() -> void:
	var _w := _watcher()
	var pair := _squad_walking_into_the_watch()
	var bystander: Unit = pair[1]
	var stood_on := bystander.movement.cell
	var own_walk: Array[Vector2i] = [stood_on, Vector2i(5, 0), Vector2i(6, 0)]
	var move := MoveAction.new()
	move.init(bystander, own_walk, null)
	bystander.squad._queue_action(move)   # AFTER the leader's, so the watch fires first

	var plan := _sm.resolve_plan(bystander.squad, _board())
	_assert_felled(plan, bystander)

	assert_int(move.resolved_stop_index) \
		.override_failure_message("a felled mover was not halted where it stood").is_equal(0)
	assert_vector(move.get_destination()) \
		.override_failure_message("the body walked").is_equal(stood_on)
	assert_vector(PlanResolver.projected_position(bystander, plan.hypo)) \
		.override_failure_message("the body's threaded position left its cell").is_equal(stood_on)


# ==============================================================================
#  The side-channel tail
# ==============================================================================

# The tail's verdict is a STAMP on the order (BaseAction.resolved_actor_felled), not a filter in
# OrderExecutor -- six surfaces ask whether a queued rescue happens, and a filter at the executor
# answers one of them while the preview lies and play_session's twin diverges.
func test_a_felled_rescuer_is_stamped_and_hauls_nobody() -> void:
	var _w := _watcher()
	var pair := _squad_walking_into_the_watch()
	var bystander: Unit = pair[1]
	var body := H.spawn_solo(self, _sm, PLAYER, Vector2i(5, 0))
	body.force_down()

	var rescue := RescueAction.new()
	rescue.init(bystander, body, body.movement.cell)
	bystander.squad._queue_action(rescue)

	var plan := _sm.resolve_plan(bystander.squad, _board())
	_assert_felled(plan, bystander)

	assert_bool(rescue.resolved_actor_felled) \
		.override_failure_message("the felled rescuer's order was not stamped (#1005)").is_true()
	assert_bool(rescue.is_inert()) \
		.override_failure_message("the queue row does not read as inert").is_true()
	assert_bool(rescue.is_valid) \
		.override_failure_message("an inert order must stay LEGAL -- reddening it refuses Execute") \
		.is_true()


# The stamp is written AFTER resolve_counters, and that is the whole reason it is not written at
# each order's queue slot: the tail runs last, so the pass can still fell a rescuer with a COUNTER
# after every queue slot has gone by. The leader here is out of the defender's reach, so the
# counter's first legal target (member order, C3) is the rescuer standing next to it.
func test_a_rescuer_felled_by_a_COUNTER_is_stamped_too() -> void:
	var leader := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 10})
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0))
	_sm.join_squad(rescuer, leader.squad)
	var defender := H.spawn_solo(self, _sm, ENEMY, Vector2i(3, 0), {Stats.Stat.STR: 5})
	var body := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	body.force_down()

	# Bare fists reach 1, so the defender can answer the rescuer beside it and never the leader
	# three cells away -- which is what puts the rescuer in the counter's sights.
	rescuer.take_damage(rescuer.get_current_hp() - 1)
	leader.squad._queue_action(H.stamped_attack(leader, defender))
	var rescue := RescueAction.new()
	rescue.init(rescuer, body, body.movement.cell)
	leader.squad._queue_action(rescue)

	var plan := _sm.resolve_plan(leader.squad, _board())

	assert_int(plan.counters.size()) \
		.override_failure_message("no counter was derived at all").is_greater(0)
	assert_object(plan.counters[0].target) \
		.override_failure_message("the counter did not aim at the rescuer -- fixture drifted") \
		.is_same(rescuer)
	assert_int(PlanResolver.projected_lifecycle(rescuer, plan.hypo)) \
		.override_failure_message("the counter did not fell the rescuer") \
		.is_not_equal(Unit.LifecycleState.ACTIVE)
	assert_bool(rescue.resolved_actor_felled) \
		.override_failure_message("a rescuer felled by a COUNTER was not stamped -- the stamp is being written before the counters resolve (#1005)") \
		.is_true()
