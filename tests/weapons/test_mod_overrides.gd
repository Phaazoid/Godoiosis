# The two fields a fitted mod may EDIT on the attacks it reaches (#529): the shove and the ally
# splash. The pair is small on purpose -- an override may only touch what is read AFTER the attack
# is chosen, so anything that changes how an attack is AIMED is a whole replacement instead.
#
# The ally-splash cases ask RulesService.is_attack_victim, which is the production rule itself
# rather than a restatement of it: the volley gather is a loop around that one call.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

func _attack(shove: int, splashes: bool) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.display_name = "Swing"
	a.knockback = shove
	a.hits_allies = splashes
	return a

func _weapon(main: WeaponAttackData, extra: WeaponAttackData = null) -> WeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = main
	if extra != null:
		var extras: Array[WeaponAttackData] = [extra]
		t.extra_attacks = extras
	return WeaponInstance.make(t)

func _unit(faction: Team.Faction, cell: Vector2i) -> Unit:
	var u := H.spawn_unit(self, faction, cell, {}, false)
	u.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	return u

func _fit(weapon: WeaponInstance, index: int, mod: WeaponModData) -> void:
	assert_bool(weapon.fit(index, mod)) \
		.override_failure_message("fixture: the mod must actually fit, or the override reads as absent") \
		.is_true()

func _splash(setting: WeaponModData.Override) -> WeaponModData:
	var m := WeaponModData.new()
	m.hits_allies_override = setting
	return m

# --- Shove ---

func test_a_mod_can_give_a_shove_to_an_attack_that_had_none() -> void:
	var hero := _unit(Team.Faction.PLAYER, Vector2i(0, 0))
	var swing := _attack(0, false)
	var weapon := _weapon(swing)
	hero.equipped_weapon = weapon
	assert_int(weapon.effective_knockback(hero, swing)).is_equal(0)     # the contrast

	var mod := WeaponModData.new()
	mod.knockback_delta = 1
	_fit(weapon, 0, mod)

	assert_int(weapon.effective_knockback(hero, swing)).is_equal(1)

func test_a_shove_driven_below_zero_is_no_shove_rather_than_a_pull() -> void:
	var hero := _unit(Team.Faction.PLAYER, Vector2i(0, 0))
	var swing := _attack(1, false)
	var weapon := _weapon(swing)
	hero.equipped_weapon = weapon

	var mod := WeaponModData.new()
	mod.knockback_delta = -3
	_fit(weapon, 0, mod)

	assert_int(weapon.effective_knockback(hero, swing)).is_equal(0)

func test_a_main_attack_mod_does_not_shove_the_extras() -> void:
	var hero := _unit(Team.Faction.PLAYER, Vector2i(0, 0))
	var swing := _attack(0, false)
	var extra := _attack(0, false)
	var weapon := _weapon(swing, extra)
	hero.equipped_weapon = weapon

	var mod := WeaponModData.new()
	mod.applies_to = WeaponModData.AppliesTo.MAIN_ATTACK
	mod.knockback_delta = 1
	_fit(weapon, 0, mod)

	assert_int(weapon.effective_knockback(hero, swing)).is_equal(1)
	assert_int(weapon.effective_knockback(hero, extra)).is_equal(0)

# --- Ally splash ---

func test_a_mod_can_take_allies_out_of_a_splash() -> void:
	var hero := _unit(Team.Faction.PLAYER, Vector2i(0, 0))
	var ally := _unit(Team.Faction.PLAYER, Vector2i(1, 0))
	var foe := _unit(Team.Faction.ENEMY, Vector2i(2, 0))
	var swing := _attack(0, true)
	var weapon := _weapon(swing)
	hero.equipped_weapon = weapon
	assert_bool(RulesService.is_attack_victim(hero, ally, swing)) \
		.override_failure_message("fixture: the attack must splash allies to begin with") \
		.is_true()

	_fit(weapon, 0, _splash(WeaponModData.Override.OFF))

	assert_bool(RulesService.is_attack_victim(hero, ally, swing)).is_false()
	# The enemy is still a victim, so the mod narrowed the splash rather than killing the attack.
	assert_bool(RulesService.is_attack_victim(hero, foe, swing)).is_true()

func test_off_beats_on_whichever_space_each_sits_in() -> void:
	for off_first in [true, false]:
		var hero := _unit(Team.Faction.PLAYER, Vector2i(0, 0))
		var ally := _unit(Team.Faction.PLAYER, Vector2i(1, 0))
		var swing := _attack(0, false)
		var weapon := _weapon(swing)
		hero.equipped_weapon = weapon

		# Space 0 holds one, space 1 holds two -- so both mods fit either way round.
		_fit(weapon, 0, _splash(WeaponModData.Override.OFF if off_first else WeaponModData.Override.ON))
		_fit(weapon, 1, _splash(WeaponModData.Override.ON if off_first else WeaponModData.Override.OFF))

		assert_bool(RulesService.is_attack_victim(hero, ally, swing)) \
			.override_failure_message("OFF must win with off_first = %s" % off_first) \
			.is_false()
