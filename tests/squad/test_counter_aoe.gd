# resolve_plan counter expansion: an AoE counter must splash EVERY unit in its blast —
# including the counterer's OWN allies when the weapon has friendly fire (hits_allies).
# Before the fix, counters were built single-target (only the chosen counter target was hit),
# so an AoE counter silently spared everyone else in range. This mirrors the attack-side AoE
# derivation in test_aoe_victim_derivation.gd (#15): derive victims from the blast at resolve
# time, never freeze a single target.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# A fixed 2-cell blast (the aimed cell + the cell to its LEFT). Hand-rolled so the test
# exercises the counter volley + friendly-fire gather, not real pattern geometry/facing.
class TwoCellBlast extends AttackPattern:
	func get_affected_cells(_user: Unit, _origin_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
		return [target_cell, target_cell + Vector2i.LEFT]
	func get_selectable_cells(_user: Unit, origin_cell: Vector2i, _facing_hint: Vector2i) -> Array[Vector2i]:
		return GridUtils.cells_within_manhattan_range(origin_cell, 3)

# Friendly fire ON: the blast covers the attacker's cell AND the counterer's weaponless
# ally one cell over -> the counter is a volley that hits BOTH (this was the bug).
func test_aoe_counter_splashes_friendlies_in_the_blast() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var counterer := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var ally := H.spawn_solo(self, _sm, ENEMY, Vector2i(-1, 0), {}, false)   # weaponless: a victim, never a counterer
	_sm.join_squad(ally, counterer.squad)
	(counterer.get_equipped_weapon() as WeaponData).attack_pattern = TwoCellBlast.new()
	(counterer.get_equipped_weapon() as WeaponData).hits_allies = true

	attacker.squad._queue_action(AttackAction.create(attacker, attacker.movement.cell, counterer, counterer.movement.cell))
	var board := _board_with([attacker, counterer, ally])

	var plan := _sm.resolve_plan(attacker.squad, board)

	var counter_targets: Array[Unit] = []
	for c in plan.counters:
		counter_targets.append(c.target)

	assert_int(plan.counters.size()).is_equal(2)
	assert_bool(counter_targets.has(attacker)).is_true()   # the unit it countered
	assert_bool(counter_targets.has(ally)).is_true()       # the friendly-fire splash
	assert_object(plan.counters[0].actor).is_same(counterer)
	_break_volleys(plan)

# Friendly fire OFF (control): the same blast spares the ally, leaving a single-target
# counter against the attacker. Proves the splash is gated on hits_allies, not the volley.
func test_aoe_counter_without_friendly_fire_spares_allies() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var counterer := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var ally := H.spawn_solo(self, _sm, ENEMY, Vector2i(-1, 0), {}, false)
	_sm.join_squad(ally, counterer.squad)
	(counterer.get_equipped_weapon() as WeaponData).attack_pattern = TwoCellBlast.new()
	(counterer.get_equipped_weapon() as WeaponData).hits_allies = false

	attacker.squad._queue_action(AttackAction.create(attacker, attacker.movement.cell, counterer, counterer.movement.cell))
	var board := _board_with([attacker, counterer, ally])

	var plan := _sm.resolve_plan(attacker.squad, board)

	assert_int(plan.counters.size()).is_equal(1)
	assert_object(plan.counters[0].target).is_same(attacker)
	_break_volleys(plan)

func _board_with(units_in: Array) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm)

# Volley siblings link into a shared self-referential array (a RefCounted cycle, #35) — break
# attacks AND counters so the derived plan doesn't leak after the test.
func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty
