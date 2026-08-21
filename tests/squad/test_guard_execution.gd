# Guard's EXECUTION wires (#414). The resolver decides everything; execution only has to (a) apply
# the already-substituted outcome to the blocker and spend that blocker's LIVE ward, and (b) arm the
# ward at the end of the pass carrying the resolver's own spent verdict.
#
# Both are the "test the wire" class: each end can be perfectly correct while nothing connects them,
# and neither is visible from a resolver-only test — the resolver deliberately never touches live
# state, so a missing spend_guard() leaves every plan-level assertion green and hands the player a
# bodyguard that blocks forever.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _attacker(cell: Vector2i) -> Unit:
	return H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.STR: 4}, true, 6)


func _defender(cell: Vector2i, hp := 40) -> Unit:
	return H.spawn_solo(self, _sm, PLAYER, cell, {Stats.Stat.MHP: hp}, false)


func _resolve(plan: ResolvedPlan) -> void:
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)


# The whole round trip, played out: resolve a blocked hit, then run the real execute() — awaited,
# because it plays the attacker's lunge and the blocker's block lunge.
func test_executing_a_blocked_hit_hurts_the_blocker_spares_the_ward_and_spends_the_guard() -> void:
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))
	blocker.arm_guard(ward, blocker.get_guard_range())
	var ward_hp := ward.get_current_hp()
	var blocker_hp := blocker.get_current_hp()

	var plan := ResolvedPlan.new()
	plan.guards.append(blocker.guard.copy())
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)
	assert_object(atk.blocked_for).override_failure_message("fixture failed to block the hit").is_same(ward)

	await atk.execute()

	assert_int(ward.get_current_hp()).is_equal(ward_hp)
	assert_int(blocker.get_current_hp()).is_equal(blocker_hp - atk.resolved.damage)
	assert_bool(blocker.guard.spent) \
		.override_failure_message("the live Guard was never spent -- it will block again next pass") \
		.is_true()


func test_executing_an_ordinary_hit_leaves_a_bystanders_guard_alone() -> void:
	# The control: without it the case above passes against a version that spends every Guard on the
	# board whenever anything resolves.
	var attacker := _attacker(Vector2i(0, 0))
	var victim := _defender(Vector2i(1, 0))
	var ward := _defender(Vector2i(5, 0))
	var blocker := _defender(Vector2i(6, 0))
	blocker.arm_guard(ward, blocker.get_guard_range())

	var plan := ResolvedPlan.new()
	plan.guards.append(blocker.guard.copy())
	var atk := H.stamped_attack(attacker, victim)
	plan.attacks.append(atk)
	_resolve(plan)

	await atk.execute()

	assert_bool(blocker.guard.spent).is_false()


func test_the_guard_order_arms_the_ward_on_execute() -> void:
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))

	var order := GuardAction.new()
	order.init(blocker, ward)
	assert_object(blocker.guard).override_failure_message("declaring must not arm -- executing does").is_null()

	order.execute()

	assert_object(blocker.guard).is_not_null()
	assert_object(blocker.guard.ward).is_same(ward)
	assert_int(blocker.guard.guard_range).is_equal(blocker.get_guard_range())
	assert_bool(blocker.guard.spent).is_false()


func test_a_guard_the_pass_already_consumed_arms_spent() -> void:
	# The side channel runs AFTER the attack phase, so a Guard that absorbed this pass's own splash
	# would otherwise arm fresh and hand the player back a block the queue said was gone.
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))

	var order := GuardAction.new()
	order.init(blocker, ward)
	order.resolved_spent = true     # what SquadManager.resolve_plan stamps
	order.execute()

	assert_object(blocker.guard).is_not_null()
	assert_bool(blocker.guard.spent).is_true()
