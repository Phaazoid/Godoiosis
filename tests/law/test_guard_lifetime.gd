# Guard's LIFETIME half (#414, docs/design/standing-reactions.md) — the shared standing-reaction
# grammar: a Guard arms when declared, absorbs exactly ONE trigger, and otherwise lapses when its
# owner's faction's next turn begins. Plus the anchor rule, which for Guard is deliberately
# RANGE-shaped rather than cell-shaped: the pair holds while the ward is within the Guard's range of
# the blocker, however either of them got there.
#
# Separated from test_guard_substitution.gd on purpose: that file asks "what does a block DO", this
# one asks "when is there a block at all". They fail for different reasons.
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


# --- one trigger, then spent -----------------------------------------------------------------

func test_a_guard_absorbs_exactly_one_hit() -> void:
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))

	var plan := ResolvedPlan.new()
	plan.guards.append(GuardWard.arm(blocker, ward, 1))
	var first := H.stamped_attack(attacker, ward)
	var second := H.stamped_attack(attacker, ward)
	plan.attacks.append(first)
	plan.attacks.append(second)
	_resolve(plan)

	assert_object(first.target).is_same(blocker)    # blocked
	assert_object(second.target).is_same(ward)      # spent -- the ward eats this one
	assert_object(second.blocked_for).is_null()


func test_an_already_spent_guard_covers_nothing() -> void:
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))

	var plan := ResolvedPlan.new()
	var ward_link := GuardWard.arm(blocker, ward, 1)
	ward_link.spent = true          # e.g. it already caught something on an earlier pass
	plan.guards.append(ward_link)
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_object(atk.target).is_same(ward)


# --- the anchor rule: unit-and-range, not cells ----------------------------------------------

func test_a_pair_separated_beyond_range_stops_covering() -> void:
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(4, 0))   # three cells away -- out of a range-1 Guard

	var plan := ResolvedPlan.new()
	plan.guards.append(GuardWard.arm(blocker, ward, 1))
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_object(atk.target).is_same(ward)
	assert_object(atk.blocked_for).is_null()


func test_an_authored_range_holds_a_wider_pair_together() -> void:
	# Range is authored on the granting content (default 1); the same separation that dropped the
	# Guard above keeps it here. Asserted through the ward's own range so the default can be tuned.
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(4, 0))

	var plan := ResolvedPlan.new()
	plan.guards.append(GuardWard.arm(blocker, ward, 3))
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_object(atk.target).is_same(blocker)


func test_a_downed_blocker_stops_covering() -> void:
	# Liveness is lifecycle as well as range: a body on the floor is not standing in front of you.
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))
	blocker.force_down()

	var plan := ResolvedPlan.new()
	plan.guards.append(GuardWard.arm(blocker, ward, 1))
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_object(atk.target).is_same(ward)


# --- stacking ---------------------------------------------------------------------------------

func test_stacked_guards_absorb_in_arm_order() -> void:
	# Two blockers may ward the same unit; the earlier-armed one absorbs the first hit and the
	# later one is still standing by for the next. No refusal rule -- just an order.
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var first_blocker := _defender(Vector2i(1, 1))
	var second_blocker := _defender(Vector2i(1, -1))

	var plan := ResolvedPlan.new()
	plan.guards.append(GuardWard.arm(first_blocker, ward, 1))
	plan.guards.append(GuardWard.arm(second_blocker, ward, 1))
	var first := H.stamped_attack(attacker, ward)
	var second := H.stamped_attack(attacker, ward)
	plan.attacks.append(first)
	plan.attacks.append(second)
	_resolve(plan)

	assert_object(first.target).is_same(first_blocker)
	assert_object(second.target).is_same(second_blocker)


# --- the live state's four doors ---------------------------------------------------------------

func test_arming_records_the_pair_and_spending_marks_it_used() -> void:
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))

	blocker.arm_guard(ward, blocker.get_guard_range())
	assert_object(blocker.guard).is_not_null()
	assert_object(blocker.guard.blocker).is_same(blocker)
	assert_object(blocker.guard.ward).is_same(ward)
	assert_bool(blocker.guard.spent).is_false()

	blocker.spend_guard()
	assert_bool(blocker.guard.spent).is_true()   # spent, not erased -- "used" and "never had one" differ


func test_lapsing_clears_the_ward() -> void:
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))
	blocker.arm_guard(ward, blocker.get_guard_range())

	blocker.lapse_guard()

	assert_object(blocker.guard).is_null()


func test_a_unit_cannot_guard_itself() -> void:
	var blocker := _defender(Vector2i(2, 0))
	blocker.arm_guard(blocker, blocker.get_guard_range())
	assert_object(blocker.guard).is_null()


func test_a_guard_armed_spent_stays_spent() -> void:
	# GuardAction.execute arms with the resolver's verdict, so this is the shape a Guard that ate
	# its owner's own splash arrives in: live, but already used up.
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))

	blocker.arm_guard(ward, blocker.get_guard_range(), true)

	assert_object(blocker.guard).is_not_null()
	assert_bool(blocker.guard.spent).is_true()
