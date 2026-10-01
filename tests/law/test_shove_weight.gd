# WEIGHT RESISTS A SHOVE (#120, dev 2026-10-01): a shove travels the attack's knockback (mods
# included) less the TARGET's weight band, floored at 0, and the tiles weight absorbed are reported on
# the outcome as `knockback_held` -- the one trace a fully held shove leaves, since it draws no trail.
#
# Driven through the real resolve. Weights are set relative to the band THRESHOLDS (Stats.WEIGHT_BAND_*),
# never as literal numbers, so retuning a threshold moves nothing these cases assert.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const HOLE_TILE := Vector2i(18, 2)   # the authored VOID tile ("hole") in TestTiles
const TOUGH := {Stats.Stat.MHP: 60}

var _no_reactions: Array[ElementalReaction] = []
var _plans: Array[ResolvedPlan] = []


func after_test() -> void:
	# A volley is a self-referential array (a RefCounted cycle, #35), so every plan is broken apart.
	var empty: Array[AttackAction] = []
	for plan in _plans:
		for atk: AttackAction in plan.attacks:
			atk.volley = empty
			atk.source_aim = null
			atk.dropped_by = null
	_plans.clear()


# Loads a unit to exactly a band threshold with one carried item, so the band is the one asked for
# whatever the body's default happens to be.
func _weigh_to(unit: Unit, weight: int) -> void:
	var ballast := Item.new()
	ballast.weight = weight - unit.get_weight()
	assert_int(ballast.weight).override_failure_message(
		"the body alone is already past this threshold, so the case cannot set the band it needs") \
		.is_greater_equal(0)
	assert_bool(unit.add_item(ballast)).is_true()
	assert_int(unit.get_weight()).is_equal(weight)


func _setup(knockback: int, a_cell: Vector2i, d_cell: Vector2i) -> Dictionary:
	var sm := H.make_manager(self)
	var a := H.spawn_solo(self, sm, PLAYER, a_cell)
	var d := H.spawn_solo(self, sm, ENEMY, d_cell, TOUGH)
	(a.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = knockback
	return {"sm": sm, "a": a, "d": d, "grid": sm.get_node("../Grid") as TileMapLayer}


func _resolve(setup: Dictionary) -> ResolvedOutcome:
	var attack := H.stamped_attack(setup.a, setup.d)
	var plan := ResolvedPlan.new()
	var attacks: Array[AttackAction] = [attack]
	plan.attacks = attacks
	var sm: SquadManager = setup.sm
	PlanResolver.resolve(plan, _no_reactions, sm.board_source.call())
	return attack.resolved


func _tiles_moved(outcome: ResolvedOutcome) -> int:
	return maxi(0, outcome.knockback_path.size() - 1)


# --- the band takes tiles off the shove ------------------------------------------------------

func test_an_ordinary_body_is_shoved_the_full_distance() -> void:
	var s := _setup(2, Vector2i(1, 0), Vector2i(2, 0))
	assert_int(Stats.weight_band((s.d as Unit).get_weight())).override_failure_message(
		"the default body is already heavy, so this control measures nothing").is_equal(0)
	var outcome := _resolve(s)
	assert_int(_tiles_moved(outcome)).is_equal(2)
	assert_int(outcome.knockback_held).is_equal(0)


func test_a_band_one_target_is_shoved_one_tile_short() -> void:
	var s := _setup(2, Vector2i(1, 0), Vector2i(2, 0))
	_weigh_to(s.d as Unit, Stats.WEIGHT_BAND_1)
	var outcome := _resolve(s)
	assert_int(_tiles_moved(outcome)).is_equal(1)
	assert_int(outcome.knockback_held).is_equal(1)
	assert_that(outcome.knockback_to).is_equal(Vector2i(3, 0))


# The case the telemetry is full of: Gust throwing an enemy into a hole. Heavy enough, it stays put.
func test_a_band_two_target_holds_beside_a_hole() -> void:
	var s := _setup(2, Vector2i(1, 0), Vector2i(2, 0))
	(s.grid as TileMapLayer).set_cell(Vector2i(3, 0), 0, HOLE_TILE)
	_weigh_to(s.d as Unit, Stats.WEIGHT_BAND_2)
	var outcome := _resolve(s)
	assert_bool(outcome.knockback_applied).is_false()
	assert_int(outcome.knockback_held).is_equal(2)
	assert_bool(outcome.removed).is_false()
	assert_int(outcome.fall_damage).is_equal(0)
	assert_array(outcome.popups).contains([PlanResolver.HELD_POPUP % 2])


func test_the_same_hole_takes_an_ordinary_body() -> void:
	# The control for the case above: the hole is live, so the hold is weight's doing.
	var s := _setup(1, Vector2i(1, 0), Vector2i(2, 0))
	(s.grid as TileMapLayer).set_cell(Vector2i(3, 0), 0, HOLE_TILE)
	assert_bool(_resolve(s).removed).is_true()


# A mod's +1 adds on the attacker's side and the band subtracts on the target's: the two compose.
func test_a_mods_extra_tile_composes_with_the_band() -> void:
	var s := _setup(1, Vector2i(1, 0), Vector2i(2, 0))
	var mod := WeaponModData.new()
	mod.size = 1
	mod.knockback_delta = 1
	assert_bool(((s.a as Unit).get_equipped_weapon() as WeaponInstance).fit(0, mod)).is_true()
	_weigh_to(s.d as Unit, Stats.WEIGHT_BAND_1)
	var outcome := _resolve(s)
	assert_int(_tiles_moved(outcome)).is_equal(1)
	assert_int(outcome.knockback_held).is_equal(1)


# --- whose weight answers --------------------------------------------------------------------

# A Guard takes the whole hit as the victim, so the BLOCKER's weight answers the shove. The attacker
# is the light one and the blocker the heavy one, so reading the wrong unit's weight reds here.
func test_a_heavy_guard_holds_the_shove_it_takes() -> void:
	var sm := H.make_manager(self)
	var attacker := H.spawn_solo(self, sm, ENEMY, Vector2i(0, 0))
	var ward := H.spawn_solo(self, sm, PLAYER, Vector2i(1, 0), TOUGH, false)
	var blocker := H.spawn_solo(self, sm, PLAYER, Vector2i(2, 0), TOUGH, false)
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = 2
	_weigh_to(blocker, Stats.WEIGHT_BAND_2)
	var atk := _guarded_hit(sm, attacker, ward, blocker)
	assert_int(atk.resolved.knockback_held).is_equal(2)
	assert_bool(atk.resolved.knockback_applied).is_false()


func test_a_light_guard_is_thrown_by_the_shove_it_takes() -> void:
	var sm := H.make_manager(self)
	var attacker := H.spawn_solo(self, sm, ENEMY, Vector2i(0, 0))
	var ward := H.spawn_solo(self, sm, PLAYER, Vector2i(1, 0), TOUGH, false)
	var blocker := H.spawn_solo(self, sm, PLAYER, Vector2i(2, 0), TOUGH, false)
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = 2
	_weigh_to(attacker, Stats.WEIGHT_BAND_2)   # a heavy ATTACKER changes nothing about the shove
	var atk := _guarded_hit(sm, attacker, ward, blocker)
	assert_int(atk.resolved.knockback_held).is_equal(0)
	assert_bool(atk.resolved.knockback_applied).is_true()
	assert_that(atk.resolved.knockback_to).is_equal(Vector2i(4, 0))


func _guarded_hit(sm: SquadManager, attacker: Unit, ward: Unit, blocker: Unit) -> AttackAction:
	var plan := ResolvedPlan.new()
	plan.guards.append(GuardWard.arm(blocker, ward, 1))
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	var units: Array[Unit] = [attacker, ward, blocker]
	var no_terrain: Array[TerrainReaction] = []
	PlanResolver.resolve(plan, _no_reactions, BoardContext.new(sm.grid, units, sm), no_terrain)
	return atk


# Every victim of one volley reads its OWN weight: a line through two enemies, the near one heavy and
# the far one light, resolved through the real plan. Near-first order means the heavy one holding
# changes nothing about where the light one lands.
func test_each_victim_of_one_volley_reads_its_own_weight() -> void:
	var sm := H.make_manager(self)
	var line := WeaponAttackData.new()
	line.display_name = "Line"
	line.power = 1
	line.knockback = 2
	P.stamped(line, 0, [Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3)] as Array[Vector2i])
	line.swing = false   # after stamped(), which defaults it on: a true AoE, so no lane stops at a body
	var thrower := H.spawn_solo(self, sm, PLAYER, Vector2i(0, 0), TOUGH)
	(thrower.get_equipped_weapon() as WeaponInstance).template.main_attack = line
	var heavy := H.spawn_solo(self, sm, ENEMY, Vector2i(0, -1), TOUGH, false)
	var light := H.spawn_solo(self, sm, ENEMY, Vector2i(0, -3), TOUGH, false)
	_weigh_to(heavy, Stats.WEIGHT_BAND_2)

	thrower.squad._queue_action(AttackAction.declare(thrower, thrower.movement.cell, Vector2i(0, -1)))
	var plan := sm.resolve_plan(thrower.squad, sm.board_source.call(), _no_reactions, [] as Array[TerrainReaction])
	_plans.append(plan)
	var by_target := {}
	for atk: AttackAction in plan.attacks:
		if atk.target != null:
			by_target[atk.target] = atk.resolved
	assert_bool(by_target.has(heavy) and by_target.has(light)).override_failure_message(
		"the line did not catch both enemies, so the case measures nothing").is_true()
	var heavy_out: ResolvedOutcome = by_target[heavy]
	var light_out: ResolvedOutcome = by_target[light]
	assert_int(heavy_out.knockback_held).is_equal(2)
	assert_bool(heavy_out.knockback_applied).is_false()
	assert_int(light_out.knockback_held).is_equal(0)
	assert_that(light_out.knockback_to).is_equal(Vector2i(0, -5))


# A knockback payload never shoves the unit it sticks to (#1058), so nothing is HELD there either:
# reporting one would badge a shove that was never coming. The carrier itself shoves nobody.
func test_a_payload_stuck_to_a_heavy_victim_reports_no_hold() -> void:
	var sm := H.make_manager(self)
	var carrier := WeaponAttackData.new()
	carrier.display_name = "Tap"
	carrier.power = 1
	P.point(carrier, 1)
	var bomb := WeaponAttackData.new()
	bomb.display_name = "Bomb"
	bomb.power = 1
	bomb.knockback = 2
	bomb.targets = EquippableData.TargetMode.BOTH
	P.point(bomb, 1)
	carrier.payload = bomb
	var thrower := H.spawn_solo(self, sm, PLAYER, Vector2i(0, 0), TOUGH)
	(thrower.get_equipped_weapon() as WeaponInstance).template.main_attack = carrier
	var victim := H.spawn_solo(self, sm, ENEMY, Vector2i(0, -1), TOUGH, false)
	_weigh_to(victim, Stats.WEIGHT_BAND_2)

	thrower.squad._queue_action(AttackAction.declare(thrower, thrower.movement.cell, Vector2i(0, -1)))
	var plan := sm.resolve_plan(thrower.squad, sm.board_source.call(), _no_reactions, [] as Array[TerrainReaction])
	_plans.append(plan)
	var stuck: AttackAction = null
	for atk: AttackAction in plan.attacks:
		if atk.dropped_by != null and atk.target == victim:
			stuck = atk
	assert_object(stuck).override_failure_message(
		"the payload never went off on its victim, so the case measures nothing").is_not_null()
	assert_int(stuck.resolved.knockback_held).is_equal(0)
	assert_array(stuck.resolved.popups).not_contains([PlanResolver.HELD_POPUP % 2])
