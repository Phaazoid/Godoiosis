# Previewing an aim from a CARRIED weapon that is not in hand (#929, the hover's F cycle) runs the pass
# with that weapon held. The numbers must be the ones the same aim resolves to once the weapon really
# is in hand, and the live hand must be the one it was. Since #1480 stage 4 the pass's copy of the body
# holds the weapon, so the live hand is never swapped at all.
#
# The carried weapon wears a fitted mod the one in hand lacks, so which weapon the pass held shows in
# the damage. The expectation is read off a real equip, never pinned.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const FAMILY := WeaponData.WeaponType.CHAINSWORD

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _board() -> BoardContext:
	return _sm.board_source.call()


func _aim_from(hero: Unit, weapon: WeaponInstance, foe: Unit) -> AttackAction:
	return hero.with_weapon_in_hand(weapon, func() -> AttackAction:
		hero.active_attack = weapon.template.main_attack
		var aim := AttackAction.declare(hero, hero.movement.cell, foe.movement.cell)
		hero.active_attack = null
		return aim)


func _hit_on(plan: ResolvedPlan, actor: Unit, target: Unit) -> AttackAction:
	for atk in plan.attacks:
		if atk.actor == actor and atk.target == target:
			return atk
	return null


func test_a_preview_from_a_carried_weapon_lands_what_holding_it_lands() -> void:
	var hero := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	hero.unit_instance.set_proficiency(FAMILY, 3)
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 60})
	var in_hand := H.make_weapon(2)
	var carried := H.make_weapon(2)
	var mod := WeaponModData.new()
	mod.power_delta = 5
	assert_bool(carried.fit(0, mod)).override_failure_message("fixture: the mod must fit").is_true()
	hero.inventory.clear()
	hero.inventory.append(in_hand)
	hero.inventory.append(carried)
	hero.equipped_weapon = in_hand
	var swing := carried.template.main_attack
	assert_int(carried.base_damage(hero.state, swing)).override_failure_message(
			"fixture: the mod moves nothing, so which weapon the pass holds cannot show") \
		.is_not_equal(in_hand.base_damage(hero.state, swing))

	var preview := _sm.preview_aim(hero.squad, _aim_from(hero, carried, foe), _board(), carried)
	assert_object(hero.equipped_weapon).override_failure_message(
			"the preview left a different weapon in the live hand").is_same(in_hand)
	assert_object(preview).override_failure_message("the preview refused the carried weapon").is_not_null()
	var previewed := _hit_on(preview, hero, foe)
	assert_object(previewed).override_failure_message("the previewed swing never resolved").is_not_null()

	assert_bool(hero.set_equipped_weapon(carried)).override_failure_message(
			"fixture: the carried weapon must be equippable").is_true()
	assert_bool(_sm.queue_action(hero.squad, _aim_from(hero, carried, foe))) \
		.override_failure_message("fixture failed to queue the swing").is_true()
	var real := _hit_on(_sm.resolve_plan(hero.squad, _board()), hero, foe)
	assert_object(real).override_failure_message("the real swing never resolved").is_not_null()
	if previewed == null or real == null:
		return
	assert_int(previewed.resolved.damage).override_failure_message(
			"the preview dealt %d; holding the weapon deals %d" % [previewed.resolved.damage, real.resolved.damage]) \
		.is_equal(real.resolved.damage)
	assert_int(previewed.resolved.target_hp_after).is_equal(real.resolved.target_hp_after)
