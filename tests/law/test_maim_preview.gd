# Law #2 at the limb (#1174): a blow of LethalityRules.LIMB_LOSS_DAMAGE takes a limb, whether or not
# it downs, and LIMB_LOSS_DAMAGE_WOUNDED does once the unit has gone down this battle. The queue
# previews the slot (ResolvedOutcome.severed_limb) and execution takes that same slot.
#
# Every threshold is READ off the knobs and every swing is sized off them, so retuning 10 and 8
# reds nothing here. Execution runs through the real AttackAction.execute, because the blow-versus-
# water split is passed at THAT call site and a direct take_damage would walk around it.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)


# An attacker whose swing deals exactly `damage` to an unarmoured target. MEASURED rather than
# assumed: a swing is its power plus the wielder's scaling, and the weapon is the one that knows the
# second half.
func _attacker_dealing(damage: int, cell: Vector2i) -> Unit:
	var a := H.spawn_solo(self, _sm, PLAYER, cell, {}, true, 0)
	var weapon := a.get_equipped_weapon() as WeaponInstance
	var main: WeaponAttackData = weapon.template.main_attack
	main.power = damage - weapon.base_damage(a, main)
	return a


# A target with a deep pool, standing at `hp`. SET rather than authored as MHP, because max HP also
# carries the CON band and the cases below need the current number exactly.
func _sturdy(cell: Vector2i, hp := 200) -> Unit:
	var target := H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.MHP: 200}, false)
	target.set_current_hp(hp)
	return target


func _resolve(attacks: Array[AttackAction]) -> ResolvedPlan:
	var plan := ResolvedPlan.new()
	plan.attacks = attacks
	PlanResolver.resolve(plan)
	return plan


func _hit(attacker: Unit, target: Unit) -> AttackAction:
	var atk := H.stamped_attack(attacker, target)
	_resolve([atk])
	assert_int(atk.resolved.mitigation) \
		.override_failure_message("fixture target is armoured; the swing is not the number it was sized to") \
		.is_equal(0)
	return atk


# ==============================================================================
#  The threshold, standing
# ==============================================================================

func test_a_blow_at_the_threshold_takes_a_limb_from_a_standing_unit() -> void:
	var target := _sturdy(Vector2i(1, 0))
	var first: int = target.unit_instance.maim_order()[0]
	var atk := _hit(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE, Vector2i(0, 0)), target)
	assert_that(atk.resolved.lethality).is_equal(ResolvedOutcome.Lethality.NONE)
	assert_int(atk.resolved.severed_limb) \
		.override_failure_message("a blow at the threshold previewed no limb").is_equal(first)

	await atk.execute()

	assert_bool(target.is_active()).is_true()
	assert_int(target.unit_instance.limbs[first].state) \
		.override_failure_message("execution did not take the limb the preview named") \
		.is_equal(UnitInstance.LimbState.EMPTY)
	assert_bool(target.wounded) \
		.override_failure_message("a standing limb loss wounded the unit -- only a down does").is_false()


func test_a_blow_under_the_threshold_takes_nothing() -> void:
	var target := _sturdy(Vector2i(1, 0))
	var atk := _hit(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE - 1, Vector2i(0, 0)), target)
	assert_int(atk.resolved.severed_limb).is_equal(-1)

	await atk.execute()

	assert_bool(target.unit_instance.is_maimed()) \
		.override_failure_message("execution took a limb the preview did not").is_false()


# A down is a blow like any other: one that is limb-sized takes the limb AND downs.
func test_a_limb_sized_down_takes_the_limb_and_downs() -> void:
	var target := _sturdy(Vector2i(1, 0), LethalityRules.LIMB_LOSS_DAMAGE)
	var first: int = target.unit_instance.maim_order()[0]
	var atk := _hit(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE, Vector2i(0, 0)), target)
	assert_that(atk.resolved.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)
	assert_int(atk.resolved.severed_limb).is_equal(first)

	await atk.execute()

	assert_bool(target.is_downed()).is_true()
	assert_int(target.unit_instance.limbs[first].state).is_equal(UnitInstance.LimbState.EMPTY)


# ==============================================================================
#  Wounded
# ==============================================================================

# Downed for REAL -- through take_damage, never by setting the flag -- then stood back up. The
# smaller threshold now applies. The downing hit is kept under BOTH thresholds so it takes nothing
# itself, which is what makes the later limb attributable to the wound.
func test_a_unit_that_went_down_is_held_to_the_wounded_threshold() -> void:
	assert_int(LethalityRules.LIMB_LOSS_DAMAGE_WOUNDED) \
		.override_failure_message("the wounded threshold is not below the fresh one; nothing to test") \
		.is_less(LethalityRules.LIMB_LOSS_DAMAGE)
	var target := _sturdy(Vector2i(1, 0), 1)
	target.take_damage(target.get_current_hp())
	assert_bool(target.is_downed()).override_failure_message("fixture failed to down the unit").is_true()
	assert_bool(target.unit_instance.is_maimed()) \
		.override_failure_message("the downing hit took a limb itself").is_false()
	target.revive()
	target.set_current_hp(200)

	var atk := _hit(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE_WOUNDED, Vector2i(0, 0)), target)
	assert_int(atk.resolved.severed_limb) \
		.override_failure_message("a wounded unit kept its limb at the wounded threshold").is_not_equal(-1)

	await atk.execute()

	assert_bool(target.unit_instance.is_maimed()).is_true()


# The threshold is read off the state BEFORE the hit: the blow that wounds is judged as a fresh one.
func test_the_hit_that_wounds_is_judged_fresh() -> void:
	var target := _sturdy(Vector2i(1, 0), LethalityRules.LIMB_LOSS_DAMAGE_WOUNDED)
	var atk := _hit(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE_WOUNDED, Vector2i(0, 0)), target)
	assert_that(atk.resolved.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)
	assert_int(atk.resolved.severed_limb) \
		.override_failure_message("the down's own blow was held to the wounded threshold").is_equal(-1)


# ==============================================================================
#  What takes no limb
# ==============================================================================

func test_a_kill_takes_no_limb() -> void:
	var target := _sturdy(Vector2i(1, 0), 1)
	var atk := _hit(_attacker_dealing(
			1 + LethalityRules.OVERKILL_CEILING + LethalityRules.LIMB_LOSS_DAMAGE, Vector2i(0, 0)), target)
	assert_that(atk.resolved.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)
	assert_int(atk.resolved.severed_limb).is_equal(-1)


func test_a_fully_maimed_target_has_nothing_to_take() -> void:
	var target := _sturdy(Vector2i(1, 0), LethalityRules.LIMB_LOSS_DAMAGE)
	for slot in UnitInstance.LimbSlot.values():
		target.unit_instance.limbs[slot].state = UnitInstance.LimbState.EMPTY
	var atk := _hit(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE, Vector2i(0, 0)), target)
	assert_that(atk.resolved.lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)
	assert_int(atk.resolved.severed_limb).is_equal(-1)


# Iron Will caps the BLOW, and the limb is judged on what is left of it.
func test_iron_will_keeps_the_limb() -> void:
	assert_int(Abilities.IRON_WILL_DAMAGE_CAP) \
		.override_failure_message("Iron Will's cap reaches the limb threshold; this case has no subject") \
		.is_less(LethalityRules.LIMB_LOSS_DAMAGE)
	var target := _sturdy(Vector2i(1, 0))
	var iron := AbilityData.new()
	iron.id = Abilities.Id.IRON_WILL
	target.unit_instance.data.innate_abilities = [iron]
	var atk := _hit(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE * 2, Vector2i(0, 0)), target)
	assert_bool(atk.resolved.iron_will_held).override_failure_message("fixture: the cap never bit").is_true()
	assert_int(atk.resolved.severed_limb).is_equal(-1)


# ==============================================================================
#  Crisis, and more than one limb in a pass
# ==============================================================================

func test_crisis_fires_and_still_takes_the_limb() -> void:
	var target := _sturdy(Vector2i(1, 0), LethalityRules.LIMB_LOSS_DAMAGE)
	target.unit_instance.jobs.append("berserker")
	var first: int = target.unit_instance.maim_order()[0]
	var atk := _hit(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE, Vector2i(0, 0)), target)
	assert_that(atk.resolved.lethality).is_equal(ResolvedOutcome.Lethality.CRISIS)
	assert_int(atk.resolved.severed_limb).is_equal(first)

	await atk.execute()

	assert_bool(target.in_crisis).is_true()
	assert_int(target.unit_instance.limbs[first].state).is_equal(UnitInstance.LimbState.EMPTY)


# The threaded rotation: the second big hit in one pass takes the SECOND limb, and execution, playing
# the two in order, takes the same two.
func test_two_big_hits_in_one_pass_take_two_limbs_in_rotation_order() -> void:
	var target := _sturdy(Vector2i(1, 0))
	var order := target.unit_instance.maim_order()
	var first := _attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE, Vector2i(0, 0))
	var second := _attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE, Vector2i(2, 0))
	var a1 := H.stamped_attack(first, target)
	var a2 := H.stamped_attack(second, target)
	_resolve([a1, a2])
	assert_int(a1.resolved.severed_limb).is_equal(order[0])
	assert_int(a2.resolved.severed_limb) \
		.override_failure_message("the second limb-sized hit previewed the same limb, or none") \
		.is_equal(order[1])

	await a1.execute()
	await a2.execute()

	assert_int(target.unit_instance.limbs[order[0]].state).is_equal(UnitInstance.LimbState.EMPTY)
	assert_int(target.unit_instance.limbs[order[1]].state).is_equal(UnitInstance.LimbState.EMPTY)
	assert_int(target.unit_instance.maim_order().size()).is_equal(order.size() - 2)
