# #47: attacks target CELLS, not units. A legal aim at a tile with no unit is still a real
# order — it resolves to a cell-targeted attack (target == null, no unit damage) instead of
# vanishing the way the old `victims.is_empty()` gate made it. Units are a CONSEQUENCE of the
# aimed cells, not the gate. (The terrain-effect channel rides on top later — #50.)
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# Aiming at an empty tile resolves to ONE cell attack (target null, zero damage), not nothing.
func test_empty_tile_aim_resolves_to_a_cell_attack() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.create(attacker, attacker.movement.cell, null, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker]))
	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].target).is_null()
	assert_int(plan.attacks[0].resolved.damage).is_equal(0)
	_break_volleys(plan)

# A real unit in the aimed cell is still hit — cell-targeting didn't drop unit consequences.
func test_unit_in_aimed_cell_is_still_a_victim() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 3})
	_sm.active_squad = attacker.squad
	attacker.squad._queue_action(AttackAction.create(attacker, attacker.movement.cell, null, Vector2i(1, 0)))

	var plan := _sm.resolve_plan(attacker.squad, _board_with([attacker, foe]))
	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].target).is_same(foe)
	_break_volleys(plan)

func _board_with(units_in: Array) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm)

# create_volley links siblings into a shared self-referential array (a RefCounted cycle, #35).
# Cell attacks carry no volley, but break any to stay leak-clean like the sibling AoE test.
func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
