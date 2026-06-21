# Swap-chain validation must be order-independent (#16): the validity verdict for a set of
# planned moves must not depend on the order the actions happen to sit in the list. The
# occupancy resolver decides whether a destination is free by reading whether the current
# occupant has a *valid* move away — a flag other moves in the same pass can still flip — so
# _validate_action_list must settle to a fixpoint that is stable across orderings.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# leader -> m1's cell; m1 and m2 BOTH -> the same empty cell (double-booked => both invalid).
# Because m1's move is invalid it never vacates its cell, so the leader's move into it must
# also be invalid. A single-pass resolver gets this right or wrong depending on which
# destination it visits first; the verdict must be identical for every ordering.
func test_swap_chain_validity_is_order_independent() -> void:
	var leader := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var m1 := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	var m2 := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.LDR: 3})
	_sm.join_squad(m1, leader.squad)
	_sm.join_squad(m2, leader.squad)
	var squad := leader.squad

	# [label, actor, destination]. Labels (strings) key the verdict so failures format cleanly.
	var specs := [["L", leader, Vector2i(1, 0)], ["m1", m1, Vector2i(1, 1)], ["m2", m2, Vector2i(1, 1)]]

	var baseline := _validity_for(squad, specs)
	# The settled verdict: every move is invalid (the double-book sinks m1/m2; the stuck m1
	# sinks the leader). Pin it so the test also guards against an all-permissive regression.
	assert_bool(baseline["L"]).is_false()
	assert_bool(baseline["m1"]).is_false()
	assert_bool(baseline["m2"]).is_false()

	for perm in _permutations(specs):
		var result := _validity_for(squad, perm)
		assert_dict(result).is_equal(baseline)

# Build fresh MoveActions in the given order, validate the hypothetical list through the real
# SquadManager, and return {label: is_valid}. Fresh actions each call so there is no is_valid
# carryover between orderings; labelled keys map back to the same unit regardless of order.
func _validity_for(squad: Squad, specs: Array) -> Dictionary:
	var actions: Array[BaseAction] = []
	for spec in specs:
		var move := MoveAction.new()
		move.init(spec[1], [spec[2]], null)   # one-cell path => destination = that cell
		actions.append(move)
	_sm._validate_action_list(squad, actions)
	var by_label := {}
	for i in specs.size():
		by_label[specs[i][0]] = actions[i].is_valid
	return by_label

func _permutations(arr: Array) -> Array:
	if arr.size() <= 1:
		return [arr.duplicate()]
	var result := []
	for i in arr.size():
		var rest := arr.duplicate()
		var head = rest.pop_at(i)
		for perm in _permutations(rest):
			perm.push_front(head)
			result.append(perm)
	return result
