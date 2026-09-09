# A STANDING WATCH IS YOUR REACTION, SPENT (#810, dev 2026-09-09, docs/design/standing-reactions.md).
# Overwatch is strong enough that without a cost the player never engages -- they hold back and try
# to draw the enemy onto the line. So taking Overwatch spends the round's reaction: no counter, no
# reactive heal.
#
# Two reaction gates read the rule and each gets its own case, because they do NOT share the
# predicate -- can_counter and can_reaction_heal both call attack_source_can_counter, and a fix
# applied to one is invisible from the other.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

# The watched cells. Nothing in this suite ever walks into them -- the rule is about the watch
# EXISTING, not about it firing.
const WATCHED: Array[Vector2i] = [Vector2i(5, 5)]

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _main_of(unit: Unit) -> WeaponAttackData:
	return (unit.get_equipped_weapon() as WeaponInstance).template.main_attack


func _arm(unit: Unit) -> void:
	unit.arm_watch(unit.movement.cell, WATCHED[0], WATCHED, _main_of(unit))


# One attack, queued for real, and the reactions the manager derives from that plan -- the shape
# test_counters.gd uses, because counters are DERIVED and a hand-built plan cannot see the gate.
func _counters_for(attacker: Unit, target: Unit) -> Array[CounterAttackAction]:
	var attack := AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)
	attacker.squad._queue_action(attack)
	var attacks: Array[AttackAction] = [attack]
	return _sm.calculate_reactions_for_squad(attacker.squad, attacks, null)


# --- Gate 1: the counter ------------------------------------------------------------------------

func test_a_watching_defender_does_not_counter() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var defender := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))

	assert_int(_counters_for(attacker, defender).size()).is_equal(1)   # the baseline it loses

	defender.squad.action_queue.clear()
	_arm(defender)

	assert_array(_counters_for(attacker, defender)).is_empty()


# The ignore-`spent` decision, pinned. A watch that already fired still cost the action.
func test_a_watch_that_already_fired_still_costs_the_counter() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var defender := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	_arm(defender)
	defender.spend_watch()

	assert_bool(defender.watch.spent).is_true()
	assert_array(_counters_for(attacker, defender)).is_empty()


# The negative case, and the suite is worthless without it: the predicate must be "is watching",
# not "never counters". lapse_watch is the turn-start door, so this is the next round.
func test_a_lapsed_watch_gives_the_counter_back() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var defender := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	_arm(defender)
	defender.lapse_watch()

	assert_int(_counters_for(attacker, defender).size()).is_equal(1)


# The watcher drops out of the member loop; it does not eat the squad's whole reaction. Without
# this half, suppressing every counter in the squad would pass every other case here.
func test_a_watching_member_costs_only_its_own_counter() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var watcher := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var squadmate := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1))
	_sm.join_squad(squadmate, watcher.squad)
	_arm(watcher)

	var counters := _counters_for(attacker, watcher)

	assert_int(counters.size()).is_equal(1)
	assert_object(counters[0].actor).is_same(squadmate)


# --- Gate 2: the reactive heal ------------------------------------------------------------------

func test_a_watching_medic_does_not_reactively_heal() -> void:
	var healer := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var hurt := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 1))
	_sm.join_squad(hurt, healer.squad)
	# A reactive heal needs BOTH flags: is_attack_victim falls through to hits_allies for a non-enemy,
	# so heals alone reaches nobody. Caught by the baseline assertion below, which is why it is here.
	_main_of(healer).heals = true
	_main_of(healer).hits_allies = true
	hurt.take_damage(3)

	assert_bool(_sm.can_reaction_heal(healer, hurt, null)).is_true()   # the baseline it loses

	_arm(healer)

	assert_bool(_sm.can_reaction_heal(healer, hurt, null)).is_false()
