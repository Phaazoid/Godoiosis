# Who takes a reaction, and what may trigger one -- squad-system.md C1-C5, C5's trigger half (#767),
# and the repeal of the reactive heal (#148, dev 2026-09-28: "too strong and doesn't make logical
# sense").
#
# This file was test_reaction_heal.gd. Everything it pinned about HOW a reaction heal chose its
# target went with the feature; what survives is what a reaction is ALLOWED to answer, and the one
# case the repeal adds: a healer answers nothing.
#
# The #767 gate (a reaction answers a HOSTILE hit) lost its only observable witness in the repeal --
# a healer's reaction turned inward and never asked who it was answering, and nothing else does. The
# two cases below survive because each can still fail: the friendly-fire case under any reactor that
# ignores hostility, and the heal-at-an-enemy case under the rejected "a heal never triggers" route.
#
# Base damage is power + STR (WeaponData's default scaling_blend is 100% STR), so the fixture's
# power-3 weapon on STR 5 lands 8.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

# LDR 9 buys capacity for four members (leader + floor(eLDR / 2)) so join_squad doesn't
# push_warning, and MHP 30 means an incoming 8 leaves the unit HURT AND STANDING.
const TOUGH_LEADER := {Stats.Stat.LDR: 9, Stats.Stat.MHP: 30}

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _make_healer(unit: Unit) -> void:
	var weapon := H.make_weapon(4)
	weapon.template.main_attack.heals = true
	weapon.template.main_attack.hits_allies = true
	unit.equipped_weapon = weapon

# Queue one real attack and resolve the attacker's whole plan — the production path, so victim
# gathering, the shared hypo and the reaction derivation all run exactly as they do in game.
func _resolve_attack_on(attacker: Unit, target: Unit, units: Array[Unit]) -> ResolvedPlan:
	attacker.squad._queue_action(H.stamped_attack(attacker, target))
	return _sm.resolve_plan(attacker.squad, BoardContext.new(_sm.grid, units, _sm))

func _reactions_by_actor(plan: ResolvedPlan, actor: Unit) -> Array[CounterAttackAction]:
	var found: Array[CounterAttackAction] = []
	for reaction in plan.counters:
		if reaction.actor == actor:
			found.append(reaction)
	return found


# --- The repeal: a healer answers nothing ---

# The original #148 bug is the reason this is its own case: before reactive heals existed, a healer
# COUNTERED, and a heal aimed back at the attacker restored the attacker's HP. The repeal must not
# bring that back, so the healer stands adjacent to a WOUNDED attacker -- in reach of a counter, with
# someone to top up -- and a damaging squadmate beside it proves the squad's reaction still happens.
func test_a_healer_takes_no_reaction_and_never_tops_up_the_attacker() -> void:
	var attacker := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), TOUGH_LEADER)
	var defender := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), TOUGH_LEADER)
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1))
	_sm.join_squad(healer, defender.squad)
	_make_healer(healer)
	attacker.set_current_hp(10)
	defender.set_current_hp(20)

	var plan := _resolve_attack_on(attacker, defender, [attacker, defender, healer] as Array[Unit])

	assert_bool(_sm.can_counter(healer, attacker, null)) \
		.override_failure_message("a healing main answers no hit").is_false()
	assert_array(_reactions_by_actor(plan, healer)).is_empty()
	var answered := _reactions_by_actor(plan, defender)
	assert_int(answered.size()).override_failure_message(
			"fixture: the damaging squadmate must still counter, or the squad simply never reacted").is_equal(1)
	assert_object(answered[0].target).is_same(attacker)
	for reaction in plan.counters:
		assert_int(reaction.resolved.heal_amount).is_equal(0)
	_break_volleys(plan)


# --- C5 trigger half: a reaction answers a HOSTILE hit (#767) --------------------------------

# The dev's own example of the nonsense the gate stops: "being able to blow your own unit a tile to
# double their output." An attack aimed at a squadmate, deliberately with NO enemy on the board, so
# `counters` empty is exact rather than a claim about which reactions survived.
func test_a_friendly_fire_hit_draws_no_reaction_from_the_attackers_own_squad() -> void:
	var splasher := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), TOUGH_LEADER)
	var victim := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), TOUGH_LEADER)
	_sm.join_squad(victim, splasher.squad)
	(splasher.get_equipped_weapon() as WeaponInstance).template.main_attack.hits_allies = true

	var plan := _resolve_attack_on(splasher, victim, [splasher, victim] as Array[Unit])

	# MHP 30 taking base 8 leaves the victim HURT AND STANDING, so it was able to answer.
	assert_int(plan.attacks[0].resolved.damage).is_greater(0)
	assert_int(PlanResolver.projected_hp(victim, plan.hypo)).is_between(1, 29)
	assert_int(plan.counters.size()).is_equal(0)
	_break_volleys(plan)

# THE FORK THE DEV PICKED, pinned (ruling 2026-09-05): the gate is "actor and target are enemies",
# NOT "a heal never triggers". Healing an enemy is authored canon (a player-AIMED heal keeps its
# enemy splash), and being healed by an enemy is still being acted upon by one -- so the enemy's own
# reaction survives. Under the rejected route this case reads zero.
func test_a_heal_aimed_at_an_enemy_still_draws_their_reaction() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), TOUGH_LEADER)
	_make_healer(healer)
	foe.set_current_hp(10)

	var plan := _resolve_attack_on(healer, foe, [healer, foe] as Array[Unit])

	assert_object(plan.attacks[0].target).is_same(foe)
	assert_int(plan.attacks[0].resolved.heal_amount).is_greater(0)
	assert_int(plan.counters.size()).is_equal(1)
	assert_object(plan.counters[0].actor).is_same(foe)
	assert_object(plan.counters[0].target).is_same(healer)
	_break_volleys(plan)


# Volley siblings link into a shared self-referential array (a RefCounted cycle, #35) — break both
# lists so the derived plan doesn't leak after the test.
func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty
