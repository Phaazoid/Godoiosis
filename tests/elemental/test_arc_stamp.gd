# THE ARC REACHES PLAYBACK (#887): the current's own tree is stamped on the volley the resolve
# builds, so the effect draws what the rule decided rather than asking again.
#
# WHY IT CANNOT BE RE-DERIVED AT EXECUTION. The conductor set depends on the PASS's own wetness -- a
# soak queued three orders earlier is in the resolver's hypo and nowhere else -- so an effect that
# floods again at playback reads the live board and quietly draws a different current from the one
# that dealt the damage. Same reason the damage itself is stamped (R3).
#
# Water is AUTHORED per cell, the test_conduction.gd idiom: which atlas coordinate is water is
# content, and the rule is what is under test.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager


class _WaterBoard extends BoardContext:
	var water: Dictionary
	func _init(grid_layer: TileMapLayer, unit_list: Array[Unit], manager: SquadManager,
			water_cells: Array[Vector2i]) -> void:
		super(grid_layer, unit_list, manager)
		water = {}
		for cell in water_cells:
			water[cell] = true
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.WATER if water.has(cell) else Terrain.Kind.GRASS


func before_test() -> void:
	_sm = H.make_manager(self)


func _river(length: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in length:
		cells.append(Vector2i(x, 0))
	return cells


func _board(units_in: Array, water: Array[Vector2i]) -> _WaterBoard:
	var units: Array[Unit] = []
	units.assign(units_in)
	return _WaterBoard.new(_sm.grid, units, _sm, water)


# A shock rod aimed as a point attack, so the blast is the one cell and everything else is current.
func _shocker(cell: Vector2i) -> Unit:
	var unit := H.spawn_solo(self, _sm, PLAYER, cell, {Stats.Stat.LDR: 3})
	var attack := (unit.get_equipped_weapon() as WeaponInstance).template.main_attack
	attack.elemental_damage_type = Elemental.Element.SHOCK
	P.point(attack, 6)
	return unit


func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty


# THE CELL-ATTACK BRANCH (#47): the water conducts whether or not anybody is standing in it, so the
# attack with no victim is the one whose current has nowhere else to be recorded.
#
# Queued through the squad's own door rather than the manager's gate, which is the derivation suite's
# idiom for reaching this branch: the gate has its own opinion about whiffs (#126) and what is under
# test here is the RESOLVE.
func test_a_shock_into_empty_water_carries_the_whole_current() -> void:
	var hero := _shocker(Vector2i(0, 2))
	_sm.active_squad = hero.squad
	hero.squad._queue_action(AttackAction.declare(hero, hero.movement.cell, Vector2i(0, 0)))
	var board := _board([hero], _river(4))

	var plan := _sm.resolve_plan(hero.squad, board)
	assert_int(plan.attacks.size()).is_equal(1)
	var shot: AttackAction = plan.attacks[0]
	assert_object(shot.target).override_failure_message(
		"fixture: somebody was standing in the river, so this is not the cell-attack branch").is_null()
	assert_int(shot.arc_links.size()).override_failure_message(
		"a shock into open water stamped no current at all").is_equal(3)
	var ends: Array[Vector2i] = []
	for link in shot.arc_links:
		ends.append(link.to)
	for x in range(1, 4):
		assert_bool(ends.has(Vector2i(x, 0))).override_failure_message(
			"the current reached %d cells out and no hop was stamped over it" % x).is_true()
	_break_volleys(plan)


func test_every_member_of_a_shock_volley_carries_the_current() -> void:
	var hero := _shocker(Vector2i(0, 2))
	_sm.active_squad = hero.squad
	var swimmer := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	hero.squad._queue_action(AttackAction.declare(hero, hero.movement.cell, Vector2i(0, 0)))
	var board := _board([hero, swimmer], _river(4))

	var plan := _sm.resolve_plan(hero.squad, board)
	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].target).override_failure_message(
		"fixture: the current did not catch the swimmer, so there is no volley here").is_same(swimmer)
	for shot: AttackAction in plan.attacks:
		assert_int(shot.arc_links.size()).is_equal(3)
	_break_volleys(plan)


# An ordinary swing stamps nothing, so the effect's own gate is never the only thing standing
# between a sword and a lightning bolt.
func test_an_attack_with_no_shock_stamps_no_current() -> void:
	var hero := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 2), {Stats.Stat.LDR: 3})
	P.point((hero.get_equipped_weapon() as WeaponInstance).template.main_attack, 6)
	_sm.active_squad = hero.squad
	hero.squad._queue_action(AttackAction.declare(hero, hero.movement.cell, Vector2i(0, 0)))
	var board := _board([hero], _river(4))

	var plan := _sm.resolve_plan(hero.squad, board)
	assert_int(plan.attacks.size()).is_equal(1)
	assert_array(plan.attacks[0].arc_links).is_empty()
	_break_volleys(plan)
