# Guard's ORDERING half (#414) — driven through SquadManager.resolve_plan with a real queue, because
# every claim here is about SEQUENCE and a test that hands the resolver a pre-built plan cannot see
# any of it.
#
#   * "Arms at its queue slot": an attack queued BEFORE a Guard is not blocked by it, one queued
#     after is. That is what makes friendly-fire coverage player agency rather than a foot-gun —
#     sequence your own splash ahead of your own bodyguard.
#   * "One blast, one moment": liveness reads at the volley's start, so a blast covering blocker and
#     ward DOUBLE-BILLS the blocker and the outcome never hinges on volley gather order.
#   * The range check reads THREADED positions, so a shove earlier in the pass really does move who
#     is still covered.
#   * A Guard armed in an EARLIER pass covers during someone else's — the enemy-phase case, which is
#     the entire point of the mechanic.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)



func _attacker(faction: Team.Faction, cell: Vector2i) -> Unit:
	return H.spawn_solo(self, _sm, faction, cell, {Stats.Stat.STR: 4}, true, 6)


func _defender(faction: Team.Faction, cell: Vector2i, hp := 40) -> Unit:
	return H.spawn_solo(self, _sm, faction, cell, {Stats.Stat.MHP: hp}, false)


func _main_of(unit: Unit) -> WeaponAttackData:
	return (unit.get_equipped_weapon() as WeaponInstance).template.main_attack


func _board_with(units_in: Array) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm)


# Volley siblings link into a shared self-referential array (#35) — break them so the derived plan
# doesn't leak after the test.
func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty


func _guard_order(blocker: Unit, ward: Unit) -> GuardAction:
	var order := GuardAction.new()
	order.init(blocker, ward)
	return order


# One squad: a splasher, the unit it is about to splash, and that unit's bodyguard. The attack
# has friendly fire on, so the splash really does reach an ally.
class FriendlyFireBoard:
	var splasher: Unit
	var ward: Unit
	var blocker: Unit
	var board: BoardContext


# Since #767 this is also the one existing fixture that exercises the reaction TRIGGER's skip
# branch: a PLAYER squad splashing its own ward derives no reaction at all now. Nothing here
# observes that (no member carries a healing source, and a damaging squadmate could never counter
# its own side anyway), so the cases below are unchanged — noted so the next reader doesn't take
# their silence about `plan.counters` for coverage of it.
func _friendly_fire_board() -> FriendlyFireBoard:
	var s := FriendlyFireBoard.new()
	s.splasher = _attacker(PLAYER, Vector2i(0, 0))
	s.ward = _defender(PLAYER, Vector2i(2, 0))
	s.blocker = _defender(PLAYER, Vector2i(3, 0))
	_sm.join_squad(s.ward, s.splasher.squad)
	_sm.join_squad(s.blocker, s.splasher.squad)
	_main_of(s.splasher).hits_allies = true
	s.board = _board_with([s.splasher, s.ward, s.blocker])
	return s


# --- arms at its queue slot --------------------------------------------------------------------

func test_a_splash_queued_before_the_guard_is_not_blocked() -> void:
	var s := _friendly_fire_board()
	s.splasher.squad._queue_action(AttackAction.declare(s.splasher, s.splasher.movement.cell, s.ward.movement.cell))
	var guard := _guard_order(s.blocker, s.ward)
	s.splasher.squad._queue_action(guard)

	var plan := _sm.resolve_plan(s.splasher.squad, s.board)

	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].target).is_same(s.ward)   # the Guard had not armed yet
	assert_object(plan.attacks[0].blocked_for).is_null()
	assert_bool(guard.resolved_spent).is_false()
	_break_volleys(plan)


func test_a_splash_queued_after_the_guard_is_blocked() -> void:
	var s := _friendly_fire_board()
	var guard := _guard_order(s.blocker, s.ward)
	s.splasher.squad._queue_action(guard)
	s.splasher.squad._queue_action(AttackAction.declare(s.splasher, s.splasher.movement.cell, s.ward.movement.cell))

	var plan := _sm.resolve_plan(s.splasher.squad, s.board)

	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].target).is_same(s.blocker)
	assert_object(plan.attacks[0].blocked_for).is_same(s.ward)
	# And the order KNOWS it was spent, so execution arms an already-used Guard rather than a fresh
	# one — the side channel runs after the attack phase, so nothing else could carry this.
	assert_bool(guard.resolved_spent).is_true()
	_break_volleys(plan)


func test_the_spent_verdict_is_rewritten_every_resolve() -> void:
	# Cancel the splash and re-resolve: the Guard must come back unspent, or a plan edit would leave
	# execution arming a Guard that nothing consumed (Law #2 — the queue is idempotent).
	var s := _friendly_fire_board()
	var guard := _guard_order(s.blocker, s.ward)
	s.splasher.squad._queue_action(guard)
	var aim := AttackAction.declare(s.splasher, s.splasher.movement.cell, s.ward.movement.cell)
	s.splasher.squad._queue_action(aim)

	var first := _sm.resolve_plan(s.splasher.squad, s.board)
	assert_bool(guard.resolved_spent).is_true()
	_break_volleys(first)

	s.splasher.squad._remove_action(aim)
	var second := _sm.resolve_plan(s.splasher.squad, s.board)

	assert_bool(guard.resolved_spent).is_false()
	_break_volleys(second)


# --- one blast, one moment ---------------------------------------------------------------------

func test_a_blast_covering_both_double_bills_the_blocker() -> void:
	# Blocker AND ward in one footprint: the blocker takes his own share at normal mitigation plus
	# the ward's on top. Two hits, one victim.
	var s := _friendly_fire_board()
	# The aimed cell plus the one beyond it, along the aim -- a two-cell blast, so the test exercises
	# the volley and not the geometry. A stamp turns with the aim, which on this axis-aligned board is
	# exactly what the retired hand-rolled pattern spelled as a fixed world direction.
	var blast: Array[Vector2i] = [Vector2i.ZERO, Vector2i(0, -1)]
	P.stamped(_main_of(s.splasher), 6, blast)   # covers (2,0) and (3,0)
	var guard := _guard_order(s.blocker, s.ward)
	s.splasher.squad._queue_action(guard)
	s.splasher.squad._queue_action(AttackAction.declare(s.splasher, s.splasher.movement.cell, s.ward.movement.cell))

	var plan := _sm.resolve_plan(s.splasher.squad, s.board)

	assert_int(plan.attacks.size()).is_equal(2)
	var blocked := 0
	for atk in plan.attacks:
		assert_object(atk.target).is_same(s.blocker)   # both hits land on him
		if atk.blocked_for != null:
			blocked += 1
	assert_int(blocked).is_equal(1)                    # exactly one of them was the absorbed one
	# He really is billed twice: the threaded HP carries both.
	var total: int = plan.attacks[0].resolved.damage + plan.attacks[1].resolved.damage
	assert_int(PlanResolver.projected_hp(s.blocker, plan.hypo)) \
		.is_equal(s.blocker.get_current_hp() - total)
	_break_volleys(plan)


func test_a_blocker_felled_by_his_own_share_still_blocks_the_wards() -> void:
	# THE case that makes "one blast, one moment" observable. The blast is gathered blocker-first,
	# and his own share downs him -- so a liveness read taken per HIT would find a body on the floor
	# and hand the ward's share straight back to the ward. Read at the volley's START, he goes down
	# HAVING blocked, and the outcome does not hinge on an order the player never sees.
	var splasher := _attacker(ENEMY, Vector2i(0, 0))
	var blocker := _defender(PLAYER, Vector2i(2, 0), 10)   # base damage is 10: one share fells him
	var ward := _defender(PLAYER, Vector2i(3, 0))
	# The aimed cell plus the one beyond it, along the aim -- a two-cell blast, so the test exercises
	# the volley and not the geometry. A stamp turns with the aim, which on this axis-aligned board is
	# exactly what the retired hand-rolled pattern spelled as a fixed world direction.
	var blast: Array[Vector2i] = [Vector2i.ZERO, Vector2i(0, -1)]
	P.stamped(_main_of(splasher), 6, blast)   # gathers (2,0) then (3,0)
	blocker.arm_guard(ward, blocker.get_guard_range())

	splasher.squad._queue_action(AttackAction.declare(splasher, splasher.movement.cell, blocker.movement.cell))
	var plan := _sm.resolve_plan(splasher.squad, _board_with([splasher, blocker, ward]))

	assert_int(plan.attacks.size()).is_equal(2)
	assert_object(plan.attacks[0].target).is_same(blocker)          # his own share, gathered first
	assert_object(plan.attacks[0].blocked_for).is_null()
	assert_that(plan.attacks[0].resolved.lethality) \
		.override_failure_message("fixture failed to fell the blocker on his own share") \
		.is_not_equal(ResolvedOutcome.Lethality.NONE)
	assert_object(plan.attacks[1].target).is_same(blocker)          # and the ward's, absorbed anyway
	assert_object(plan.attacks[1].blocked_for).is_same(ward)
	assert_bool(plan.hypo.has(ward)).is_false()
	_break_volleys(plan)


# --- the enemy-phase case, and the threaded range read ------------------------------------------

func test_a_guard_armed_in_an_earlier_pass_covers_during_the_enemy_phase() -> void:
	var attacker := _attacker(ENEMY, Vector2i(0, 0))
	var ward := _defender(PLAYER, Vector2i(1, 0))
	var blocker := _defender(PLAYER, Vector2i(1, 1))
	blocker.arm_guard(ward, blocker.get_guard_range())   # armed last turn; still live

	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, ward.movement.cell))
	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker, ward, blocker]))

	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].target).is_same(blocker)
	assert_object(plan.attacks[0].blocked_for).is_same(ward)
	# The LIVE ward is untouched by the resolve -- only execution spends it (R2).
	assert_bool(blocker.guard.spent).is_false()
	_break_volleys(plan)


func test_a_shove_earlier_in_the_pass_moves_who_is_still_covered() -> void:
	# Attack 1 PIERCES (so it does not consume the Guard) and shoves the ward two cells clear of its
	# bodyguard; attack 2, aimed at the landing cell, then finds nobody covering it. Range is read
	# per volley against threaded positions, not against where the pair started the turn.
	var piercer := _attacker(ENEMY, Vector2i(0, 0))
	var second := _attacker(ENEMY, Vector2i(6, 0))
	var ward := _defender(PLAYER, Vector2i(1, 0))
	var blocker := _defender(PLAYER, Vector2i(1, 1))
	_sm.join_squad(second, piercer.squad)
	blocker.arm_guard(ward, blocker.get_guard_range())
	_main_of(piercer).pierces_guard = true
	_main_of(piercer).knockback = 2

	piercer.squad._queue_action(AttackAction.declare(piercer, piercer.movement.cell, ward.movement.cell))
	piercer.squad._queue_action(AttackAction.declare(second, second.movement.cell, Vector2i(3, 0)))
	var plan := _sm.resolve_plan(piercer.squad, _board_with([piercer, second, ward, blocker]))

	assert_int(plan.attacks.size()).is_equal(2)
	assert_that(plan.attacks[0].resolved.knockback_to).is_equal(Vector2i(3, 0))   # premise: it really moved
	assert_object(plan.attacks[1].target).is_same(ward)        # out of range now
	assert_object(plan.attacks[1].blocked_for).is_null()
	_break_volleys(plan)


func test_without_the_shove_the_same_second_hit_is_blocked() -> void:
	# The control for the case above: identical board, knockback 0, so the pair never separates.
	var piercer := _attacker(ENEMY, Vector2i(0, 0))
	var second := _attacker(ENEMY, Vector2i(6, 0))
	var ward := _defender(PLAYER, Vector2i(1, 0))
	var blocker := _defender(PLAYER, Vector2i(1, 1))
	_sm.join_squad(second, piercer.squad)
	blocker.arm_guard(ward, blocker.get_guard_range())
	_main_of(piercer).pierces_guard = true

	piercer.squad._queue_action(AttackAction.declare(piercer, piercer.movement.cell, ward.movement.cell))
	piercer.squad._queue_action(AttackAction.declare(second, second.movement.cell, ward.movement.cell))
	var plan := _sm.resolve_plan(piercer.squad, _board_with([piercer, second, ward, blocker]))

	assert_int(plan.attacks.size()).is_equal(2)
	assert_object(plan.attacks[0].target).is_same(ward)        # pierced
	assert_object(plan.attacks[1].target).is_same(blocker)     # blocked
	_break_volleys(plan)
