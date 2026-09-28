# A MAP-ONLY attack (`targets = MAP`) hits no unit (#1135) -- and the hover already said so. Every case
# resolves through the real SquadManager.resolve_plan, as the issue asks, so what is pinned is the
# victim gather the game actually runs rather than a hand-built plan.
#
# The rule is one clause in RulesService.is_attack_victim, so no damage, state, shove or counter
# follows a map-only hit. What still reaches a unit is a SHOCK's current, which is tag-blind by the
# dev's ruling (2026-09-28) -- pinned here, because a later "map-only means nobody at all" tidy-up is
# exactly the regression that ruling rules out.
#
# And a map-only attack never COUNTERS (AttackData.can_ever_counter). The plan is BLIND to that gate:
# an empty counter volley simply vanishes, so a plan with the gate deleted still shows no counter.
# What does see it is can_counter, which the AI's exchange read and the threat outline both ask --
# so that is what the case asserts.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const MAP := EquippableData.TargetMode.MAP
const BOTH := EquippableData.TargetMode.BOTH
const TREE_CELL := Vector2i(1, 0)
const TOUGH := {Stats.Stat.MHP: 60}

# Terrain kinds authored per cell (test_cell_effects' idiom): which atlas coordinate is a tree is
# content, and the deposit rule is what is under test.
class _KindBoard extends BoardContext:
	var kinds: Dictionary
	func _init(g: TileMapLayer, u: Array[Unit], m: SquadManager, k: Dictionary) -> void:
		super(g, u, m)
		kinds = k
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.GRASS)

var _sm: SquadManager
var _plans: Array[ResolvedPlan] = []


func before_test() -> void:
	_sm = H.make_manager(self)
	_plans.clear()


# A volley is a self-referential array (a RefCounted cycle, #35), so every plan is broken apart.
func after_test() -> void:
	var empty: Array[AttackAction] = []
	for plan in _plans:
		for list: Array in [plan.attacks, plan.counters]:
			for atk: AttackAction in list:
				atk.volley = empty
				atk.source_aim = null
	_plans.clear()


func _main_of(unit: Unit) -> WeaponAttackData:
	return (unit.get_equipped_weapon() as WeaponInstance).template.main_attack

func _board(units: Array[Unit], kinds: Dictionary = {}) -> BoardContext:
	return _KindBoard.new(_sm.grid, units, _sm, kinds)

func _fire_burns_tree() -> TerrainReaction:
	var tr := TerrainReaction.new()
	tr.incoming_element = Elemental.Element.FIRE
	tr.required_kind = Terrain.Kind.TREE
	tr.add_tile_states.assign([Terrain.TileState.BURNING])
	return tr

# Queue one real aim at `cell` and resolve the squad's whole plan.
func _resolve(attacker: Unit, cell: Vector2i, board: BoardContext,
		terrain: Array[TerrainReaction] = []) -> ResolvedPlan:
	attacker.squad.action_queue.clear()
	attacker.squad._queue_action(AttackAction.declare(attacker, attacker.movement.cell, cell))
	var plan := _sm.resolve_plan(attacker.squad, board, [] as Array[ElementalReaction], terrain)
	_plans.append(plan)
	return plan


# The issue's own check, whole: aimed at an occupied cell, a map-only attack resolves as one
# target-less cell attack, leaves the unit's HP alone, and still lands on the ground.
func test_a_map_only_aim_at_a_unit_hits_nobody_and_still_lands_on_the_ground() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), TOUGH)
	_main_of(attacker).elemental_damage_type = Elemental.Element.FIRE
	_main_of(attacker).targets = MAP
	var foe := H.spawn_solo(self, _sm, ENEMY, TREE_CELL, TOUGH)
	var board := _board([attacker, foe] as Array[Unit], {TREE_CELL: Terrain.Kind.TREE})
	var before := PlanResolver.projected_hp(foe, {})

	var plan := _resolve(attacker, TREE_CELL, board, [_fire_burns_tree()] as Array[TerrainReaction])

	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].target).override_failure_message(
			"a map-only attack took the unit on its cell as a victim").is_null()
	assert_int(PlanResolver.projected_hp(foe, plan.hypo)).is_equal(before)
	var burned := false
	for effect in plan.cell_effects:
		if effect.cell == TREE_CELL and effect.states_added.has(Terrain.TileState.BURNING):
			burned = true
	assert_bool(burned).override_failure_message("the deposit never landed on the ground").is_true()


# Nothing hit it, so nothing answers -- though the foe could reach, which the control proves.
func test_the_unit_a_map_only_attack_passes_over_draws_no_counter() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), TOUGH)
	_main_of(attacker).targets = MAP
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), TOUGH)
	var board := _board([attacker, foe] as Array[Unit])
	assert_bool(_sm.can_counter(foe, attacker, board)).override_failure_message(
			"fixture: the foe could not have countered anyway").is_true()

	var plan := _resolve(attacker, Vector2i(1, 0), board)

	assert_array(plan.counters).is_empty()


# hits_self asks whether the caster is a legal victim, and a map-only attack has no legal victims --
# so it cannot fell its own caster. The BOTH run is the control that the fixture could hit itself.
func test_a_map_only_attack_that_hits_self_leaves_its_caster_alone() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), TOUGH)
	var main := _main_of(attacker)
	P.point(main, 1, 0)
	main.hits_self = true
	var board := _board([attacker] as Array[Unit])
	var before := PlanResolver.projected_hp(attacker, {})

	main.targets = BOTH
	var control := _resolve(attacker, Vector2i(0, 0), board)
	assert_int(PlanResolver.projected_hp(attacker, control.hypo)).override_failure_message(
			"fixture: a BOTH self-hit did not reach its caster").is_less(before)

	main.targets = MAP
	var plan := _resolve(attacker, Vector2i(0, 0), board)
	assert_int(PlanResolver.projected_hp(attacker, plan.hypo)).is_equal(before)


# THE RULING, pinned (dev, 2026-09-28): the current is electricity's, not the attack's, so a
# map-only SHOCK still catches a soaked body -- the one on the aimed cell included, since a wet body
# conducts wherever it stands. It is caught, not struck: `direct` is false.
func test_a_map_only_shock_still_catches_a_wet_unit_through_the_current() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), TOUGH)
	_main_of(attacker).elemental_damage_type = Elemental.Element.SHOCK
	_main_of(attacker).targets = MAP
	var soaked := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), TOUGH)
	soaked.add_element_state(Elemental.State.WET)
	var board := _board([attacker, soaked] as Array[Unit])
	var before := PlanResolver.projected_hp(soaked, {})

	var plan := _resolve(attacker, Vector2i(1, 0), board)

	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].target).override_failure_message(
			"the current did not catch the soaked unit").is_same(soaked)
	assert_bool(plan.attacks[0].direct).override_failure_message(
			"a map-only shock STRUCK the unit rather than the current catching it").is_false()
	assert_int(PlanResolver.projected_hp(soaked, plan.hypo)).is_less(before)


# A counter answers a UNIT, so a unit whose counter attack is map-only answers nothing. Asked of
# can_counter, the read the AI's exchange term and the threat outline share -- the plan cannot see
# this gate (see the header).
func test_a_unit_whose_counter_is_map_only_cannot_counter() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), TOUGH)
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), TOUGH)
	var board := _board([attacker, foe] as Array[Unit])
	assert_bool(_sm.can_counter(foe, attacker, board)).override_failure_message(
			"fixture: the foe could not counter even with a unit attack").is_true()

	_main_of(foe).targets = MAP

	assert_bool(_sm.can_counter(foe, attacker, board)).is_false()
	var plan := _resolve(attacker, Vector2i(1, 0), board)
	assert_array(plan.counters).is_empty()
