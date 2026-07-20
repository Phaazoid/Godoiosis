# Taunt (Reaction, #61, jobs.md "The ability chassis"): a standing policy redirecting counters
# onto the taunter where legal, ahead of the C3 default (first-reachable-in-member-order)
# policy — never a mid-pass prompt. Mirrors test_counters.gd's fixture/geometry conventions.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const F := preload("res://tests/support/job_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager
var _tank: JobData
var _tank_snap: Dictionary

func before_test() -> void:
	_sm = H.make_manager(self)
	_tank = JobCatalog.get_job("tank")
	_tank_snap = F.snapshot(_tank)

func after_test() -> void:
	F.restore(_tank, _tank_snap)

func _give_taunt(unit: Unit) -> void:
	var ability := AbilityData.new()
	ability.id = Abilities.Id.TAUNT
	_tank.ability_pool = [ability]
	unit.unit_instance.add_job("tank")

func _counters_for(attacker: Unit, target: Unit) -> Array[CounterAttackAction]:
	var attack := AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)
	attacker.squad._queue_action(attack)
	var attacks: Array[AttackAction] = [attack]
	return _sm.calculate_counterattacks_for_squad(attacker.squad, attacks)

func test_taunt_holder_attracts_the_counter_over_the_default_policy() -> void:
	# Same geometry as test_c3 (both attackers reachable) — without Taunt this would pick a1
	# (first in member order); a2 holding Taunt must win instead.
	var a1 := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	var a2 := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1))
	_sm.join_squad(a2, a1.squad)
	_give_taunt(a2)
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))   # adjacent to both

	var counters := _counters_for(a1, d)

	assert_int(counters.size()).is_equal(1)
	assert_object(counters[0].target).is_same(a2)

func test_taunt_falls_through_when_the_taunter_is_unreachable() -> void:
	var a1 := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	var a2 := H.spawn_solo(self, _sm, PLAYER, Vector2i(9, 9))   # taunter, out of counter reach
	_sm.join_squad(a2, a1.squad)
	_give_taunt(a2)
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))   # adjacent only to a1

	var counters := _counters_for(a1, d)

	assert_int(counters.size()).is_equal(1)
	assert_object(counters[0].target).is_same(a1)   # falls through to the default policy

func test_no_taunt_holder_uses_the_default_policy() -> void:
	var a1 := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	var a2 := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1))
	_sm.join_squad(a2, a1.squad)
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))

	var counters := _counters_for(a1, d)

	assert_int(counters.size()).is_equal(1)
	assert_object(counters[0].target).is_same(a1)   # first in member order, unchanged from #58
