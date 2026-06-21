# Counter-attack rules C1-C7 from docs/design/squad-system.md.
#
# Counters are DERIVED from the plan (never stored as player orders), so every
# test queues real attacks and asserts what SquadManager.calculate_counterattacks_for_squad
# returns. Weapons are pattern-less => counter reach is Manhattan range 1, so a
# defender at distance 1 from an attacker can counter it and one at distance >= 2
# cannot. Cells are placed by hand to make reach obvious.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# Queue one attack (attacker -> target) into the attacker's squad and return the
# counters the manager derives from that plan.
func _counters_for(attacker: Unit, target: Unit) -> Array[CounterAttackAction]:
	var attack := AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)
	attacker.squad._queue_action(attack)
	return _sm.calculate_counterattacks_for_squad(attacker.squad)

# C1 — every unit in the defending party gets the opportunity to counter (once per
# plan). Two adjacent defenders => two counters off a single attack.
func test_c1_every_defender_gets_a_counter_opportunity() -> void:
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var d1 := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var d2 := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1))
	_sm.join_squad(d2, d1.squad)

	var counters := _counters_for(a, d1)

	assert_int(counters.size()).is_equal(2)
	for c in counters:
		assert_object(c.target).is_same(a)   # lone attacker is the only valid target

# C2 — a counter may target ANY reachable unit in the attacking party, not only
# the unit that attacked (the sacrificial-frontliner rule). A1 strikes from range;
# the defender hits the exposed squadmate A2 instead.
func test_c2_counter_targets_any_reachable_attacker() -> void:
	var a1 := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var a2 := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0))
	_sm.join_squad(a2, a1.squad)
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(3, 0))   # dist 1 from a2, dist 3 from a1

	var counters := _counters_for(a1, d)

	assert_int(counters.size()).is_equal(1)
	assert_object(counters[0].target).is_same(a2)   # a1 is out of reach; a2 takes the hit

# C3 — target choice is deterministic: first valid target in attacking-party member
# order. With both attackers reachable, the leader (member 0) is chosen.
func test_c3_target_is_first_reachable_in_member_order() -> void:
	var a1 := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	var a2 := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1))
	_sm.join_squad(a2, a1.squad)
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))   # adjacent to BOTH

	var counters := _counters_for(a1, d)

	assert_int(counters.size()).is_equal(1)
	assert_object(counters[0].target).is_same(a1)   # first in member order wins

# C4 — a defending party responds at most once per attacking plan, triggered by the
# first attack against it. Two attacks (from two attackers) against the same defender
# squad still yield one counter per defender member, all sourced to the first attack.
func test_c4_defending_party_responds_once_per_plan() -> void:
	var a1 := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var a2 := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0))
	_sm.join_squad(a2, a1.squad)
	var d1 := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))   # adjacent to a1
	var d2 := H.spawn_solo(self, _sm, ENEMY, Vector2i(3, 0))   # adjacent to a2
	_sm.join_squad(d2, d1.squad)

	var atk1 := AttackAction.create(a1, a1.movement.cell, d1, d1.movement.cell)
	var atk2 := AttackAction.create(a2, a2.movement.cell, d2, d2.movement.cell)
	a1.squad._queue_action(atk1)   # different actors => both attacks stay queued
	a1.squad._queue_action(atk2)

	var counters := _sm.calculate_counterattacks_for_squad(a1.squad)

	assert_int(counters.size()).is_equal(2)          # one per defender member, not four
	for c in counters:
		assert_object(c.source_attack).is_same(atk1)  # only the first attack triggers

# C5 — faction gate: friendly-fire victims never counter their own side. A same-faction
# "attack" produces no counter because can_attack (Team.is_enemy) filters it out.
func test_c5_friendly_fire_victims_do_not_counter() -> void:
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var d := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))   # same faction, adjacent

	assert_int(_counters_for(a, d).size()).is_equal(0)

# C6 — weaponless units cannot counter. Paired with an armed positive control in the
# same geometry to show the weapon is the deciding factor.
func test_c6_weaponless_unit_cannot_counter() -> void:
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {}, false)   # no weapon

	assert_int(_counters_for(a, d).size()).is_equal(0)

func test_c6_armed_unit_in_same_geometry_does_counter() -> void:
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {}, true)    # armed control

	assert_int(_counters_for(a, d).size()).is_equal(1)

# C6 (weapon policy) — even armed and in range, a unit whose EQUIPPED WEAPON has
# can_counter = false does not counter. Same geometry as the armed control above, so the
# per-weapon flag is the only difference. Guards #34: SquadManager.can_counter must consult
# the per-WEAPON flag, not only the per-unit Combat component flag.
func test_c6_weapon_can_counter_false_blocks_counter() -> void:
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {}, true)    # armed, adjacent
	d.equipped_weapon.can_counter = false

	assert_int(_counters_for(a, d).size()).is_equal(0)

# C7 — bystander parties never counter: only the attacked party responds. A reachable
# bystander squad is never consulted because no attack targets it.
func test_c7_bystander_parties_never_counter() -> void:
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))   # attacked
	var bystander := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1))   # adjacent to a, not attacked

	var counters := _counters_for(a, d)

	assert_int(counters.size()).is_equal(1)
	assert_object(counters[0].actor).is_same(d)
	for c in counters:
		assert_object(c.actor).is_not_same(bystander)
