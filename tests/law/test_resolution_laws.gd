# Law-level guards that protect every future resolution feature (elemental, Will).
# See docs/design/resolution-pipeline.md R2 (determinism) and R3 (preview == execution).
#
# These are deliberately thin now; they become the hooks that elemental/Will plug into
# — the moment a new stage can change a counter target or a damage number, these fail
# first if it broke determinism or made the preview lie.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# Law #1 (no randomness) / R2 (pure, deterministic): deriving counters from the same
# plan twice yields identical results — same count, same actor->target pairing, same order.
func test_counter_derivation_is_deterministic() -> void:
	var sm := _sm
	var a1 := H.spawn_solo(self, sm, PLAYER, Vector2i(0, 0))
	var a2 := H.spawn_solo(self, sm, PLAYER, Vector2i(1, 0))
	sm.join_squad(a2, a1.squad)
	var d1 := H.spawn_solo(self, sm, ENEMY, Vector2i(0, 1))
	var d2 := H.spawn_solo(self, sm, ENEMY, Vector2i(1, 1))
	sm.join_squad(d2, d1.squad)
	var attack := H.stamped_attack(a1, d1)
	a1.squad._queue_action(attack)

	var attacks: Array[AttackAction] = [attack]
	var first := sm.calculate_reactions_for_squad(a1.squad, attacks, null)
	var second := sm.calculate_reactions_for_squad(a1.squad, attacks, null)

	assert_int(second.size()).is_equal(first.size())
	assert_int(first.size()).is_greater(0)   # guard against vacuously-equal empties
	for i in first.size():
		assert_object(second[i].actor).is_same(first[i].actor)
		assert_object(second[i].target).is_same(first[i].target)

# Law #2 (the queue never lies) / R3 (preview == execution): the damage previewed at
# plan time is exactly what execution subtracts. Asserted at the damage seam
# (combat.apply_damage) — the point elemental/Will will later modify. We bypass
# AttackAction.execute()'s animation await and target the value contract directly.
func test_previewed_damage_equals_applied_damage() -> void:
	var sm := _sm
	var attacker := H.spawn_solo(self, sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4}, true, 6)
	var target := H.spawn_solo(self, sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})
	var start_hp := target.get_current_hp()

	var attack := H.stamped_attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)
	var previewed := attack.resolved.damage   # main-attack power(6) + effective STR(4), via the resolver

	target.take_damage(previewed)      # the execution seam

	assert_int(previewed).is_equal(10)
	assert_int(target.get_current_hp()).is_equal(start_hp - previewed)

# R3 under a MID-PASS stat change (#112). This pair is why PlanResolver._Hypo does NOT thread stat
# modifiers: everything stat-derived is computed once at plan time and frozen, and the one thing
# execution recomputes reads no stats at all. So an effect that lands mid-pass cannot make the
# preview lie — it simply isn't modelled, identically, by both halves.
#
# If either of these ever fails, that reasoning has stopped holding and the threading is owed.

func test_a_stat_change_after_resolve_cannot_move_executed_damage() -> void:
	# The attacker gets a large STR buff BETWEEN resolve and execute. Execution is pure playback
	# of the frozen outcome (R3), so the buff must not reach the number that lands.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4}, true, 6)
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})
	var start_hp := target.get_current_hp()

	var attack := H.stamped_attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)
	var previewed: int = attack.resolved.damage

	attacker.apply_stat_effect(StatEffect.make("Buff", {Stats.Stat.STR: 20}))
	target.take_damage(previewed)

	assert_int(target.get_current_hp()).is_equal(start_hp - previewed)

func test_the_lethality_ladder_reads_no_stats() -> void:
	# LethalityRules.Situation carries hp/will/lifecycle/limbs and deliberately no effective stat —
	# which is the whole reason a mid-pass buff can't change which RUNG a frozen hit lands on, even
	# though Unit.take_damage re-predicts live. A +CON effect moves max HP; the rung must not move.
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	var lethal: int = target.get_current_hp()
	var before := LethalityRules.predict(LethalityRules.situation_for(target), lethal)

	target.apply_stat_effect(StatEffect.make("Buff", {Stats.Stat.CON: 5}))
	assert_int(target.get_max_hp()).is_equal(22)   # the buff really did move a derived readout

	assert_int(LethalityRules.predict(LethalityRules.situation_for(target), lethal)).is_equal(before)
