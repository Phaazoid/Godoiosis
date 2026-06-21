# AoE / volley semantics from docs/design/squad-system.md.
#
# One AoE order resolves into one AttackAction per victim, all sharing the `volley`
# array; the first is primary (plays the lunge), the rest are secondary hits. Squad's
# one-order-per-type rule exempts volley siblings so they coexist in the queue.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager
var _volleys: Array = []   # track volleys so we can break their cycles in after_test

func before_test() -> void:
	_sm = H.make_manager(self)

# AttackAction.volley is self-referential (every sibling points at the shared array,
# which contains itself), so a volley is a RefCounted cycle that never frees on its
# own — a real quirk of the volley design (flagged as a finding). Break the cycle
# here so the test process doesn't leak it at exit.
func after_test() -> void:
	var empty: Array[AttackAction] = []   # typed; volley is Array[AttackAction]
	for volley in _volleys:
		for attack in volley:
			attack.volley = empty   # repoint off the shared self-referential array
	_volleys.clear()

# Make a tracked volley (so after_test can release its cycle).
func _make_volley(attacker: Unit, aim: Vector2i, victims: Array[Unit]) -> Array[AttackAction]:
	var volley := AttackAction.create_volley(attacker, attacker.movement.cell, aim, victims)
	_volleys.append(volley)
	return volley

func _three_victim_volley() -> Array[AttackAction]:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var v1 := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var v2 := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0))
	var v3 := H.spawn_solo(self, _sm, ENEMY, Vector2i(3, 0))
	return _make_volley(attacker, Vector2i(2, 0), [v1, v2, v3])

# One action per victim.
func test_volley_makes_one_action_per_victim() -> void:
	assert_int(_three_victim_volley().size()).is_equal(3)

# First action is primary (lunges); the rest are secondary hits.
func test_volley_first_is_primary_rest_secondary() -> void:
	var volley := _three_victim_volley()
	assert_bool(volley[0].is_secondary_hit).is_false()
	assert_bool(volley[1].is_secondary_hit).is_true()
	assert_bool(volley[2].is_secondary_hit).is_true()

# Every sibling references the SAME shared volley array (identity, not just equal
# contents) — that shared link is what lets cancel/preview treat the volley as a unit.
func test_volley_siblings_share_one_array() -> void:
	var volley := _three_victim_volley()
	assert_bool(is_same(volley[0].volley, volley[1].volley)).is_true()
	assert_bool(is_same(volley[1].volley, volley[2].volley)).is_true()
	assert_array(volley[0].volley).contains_exactly(volley)

# Targets line up with the victim list, in order.
func test_volley_targets_match_victims_in_order() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var v1 := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var v2 := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0))
	var volley := _make_volley(attacker, Vector2i(1, 0), [v1, v2])
	assert_object(volley[0].target).is_same(v1)
	assert_object(volley[1].target).is_same(v2)

# Volley siblings are exempt from one-order-per-type replacement, so all of them
# survive in the squad's action queue (a normal re-attack would replace, not stack).
func test_volley_siblings_coexist_in_queue() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var v1 := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var v2 := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0))
	var volley := _make_volley(attacker, Vector2i(1, 0), [v1, v2])

	for atk in volley:
		attacker.squad._queue_action(atk)

	var attack_count := 0
	for action in attacker.squad.action_queue:
		if action is AttackAction:
			attack_count += 1
	assert_int(attack_count).is_equal(2)

# Volley cancel propagation (#19): cancelling ONE member of a volley cancels the whole volley
# (an AoE is one order). SquadManager.remove_action routes an AttackAction with a non-empty
# volley through Squad._remove_volley, which removes every sibling and clears the shared array.
func test_cancelling_one_volley_member_cancels_the_whole_volley() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var v1 := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var v2 := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0))
	var v3 := H.spawn_solo(self, _sm, ENEMY, Vector2i(3, 0))
	var volley := _make_volley(attacker, Vector2i(2, 0), [v1, v2, v3])
	for atk in volley:
		attacker.squad._queue_action(atk)
	assert_int(_attack_count(attacker.squad)).is_equal(3)   # all three queued

	_sm.remove_action(attacker.squad, volley[1])            # cancel a single (secondary) member

	assert_int(_attack_count(attacker.squad)).is_equal(0)   # the whole volley is gone

# AttackActions remaining in a squad's queue.
func _attack_count(squad: Squad) -> int:
	var n := 0
	for action in squad.action_queue:
		if action is AttackAction:
			n += 1
	return n
