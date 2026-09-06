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

# --- Damage kind (#424) ---
#
# The third override: a mod REPLACES the kind of the attacks it reaches. No OFF-beats-ON reading
# exists for two different kinds, so two kind-changers on one weapon are refused at the fit instead.

func _spike(kind: AttackData.Kind) -> WeaponModData:
	var m := WeaponModData.new()
	m.display_name = "Spiked Head"
	m.overrides_kind = true
	m.kind = kind
	return m

func test_a_mod_can_replace_the_kind_of_the_attacks_it_reaches() -> void:
	var hero := _unit(Team.Faction.PLAYER, Vector2i(0, 0))
	var swing := _attack(0, false)
	var weapon := _weapon(swing)
	hero.equipped_weapon = weapon
	assert_that(weapon.effective_kind(hero, swing)).is_equal(AttackData.Kind.BLUNT)   # the contrast

	_fit(weapon, 0, _spike(AttackData.Kind.PIERCE))

	assert_that(weapon.effective_kind(hero, swing)).is_equal(AttackData.Kind.PIERCE)

func test_a_main_attack_kind_mod_leaves_the_extras_alone() -> void:
	var hero := _unit(Team.Faction.PLAYER, Vector2i(0, 0))
	var swing := _attack(0, false)
	var extra := _attack(0, false)
	var weapon := _weapon(swing, extra)
	hero.equipped_weapon = weapon

	var mod := _spike(AttackData.Kind.SLASH)
	mod.applies_to = WeaponModData.AppliesTo.MAIN_ATTACK
	_fit(weapon, 0, mod)

	assert_that(weapon.effective_kind(hero, swing)).is_equal(AttackData.Kind.SLASH)
	assert_that(weapon.effective_kind(hero, extra)).is_equal(AttackData.Kind.BLUNT)

func test_a_kind_override_never_makes_a_utility_swing_deliver_a_kind() -> void:
	# NONE is a rule off the flags, not a stored value -- and the rule has ONE home, so a modded
	# no-damage attack reads NONE exactly as an unmodded one does.
	var hero := _unit(Team.Faction.PLAYER, Vector2i(0, 0))
	var shove := _attack(1, false)
	shove.deals_no_damage = true
	var weapon := _weapon(shove)
	hero.equipped_weapon = weapon
	_fit(weapon, 0, _spike(AttackData.Kind.PIERCE))

	assert_that(weapon.effective_kind(hero, shove)).is_equal(AttackData.Kind.NONE)
	assert_that(shove.delivered_kind()).is_equal(AttackData.Kind.NONE)

func test_a_heal_delivers_no_kind_whatever_is_authored() -> void:
	var mend := _attack(0, false)
	mend.heals = true
	mend.damage_kind = AttackData.Kind.FIRE
	assert_that(mend.delivered_kind()).is_equal(AttackData.Kind.NONE)

func test_a_second_kind_changer_is_refused_with_its_reason() -> void:
	var weapon := _weapon(_attack(0, false))
	var first := _spike(AttackData.Kind.PIERCE)
	_fit(weapon, 0, first)

	# Space 1 holds 2 and is empty, so capacity cannot be what refuses.
	assert_bool(weapon.can_fit(1, WeaponModData.new())) \
		.override_failure_message("fixture: space 1 must have room, or the refusal below is capacity's") \
		.is_true()

	var second := _spike(AttackData.Kind.SLASH)
	assert_bool(weapon.can_fit(1, second)).is_false()
	assert_str(weapon.fit_block_reason(1, second)).contains(first.display_name)

func test_the_readout_names_the_composed_kind() -> void:
	# The hover line says what the modded swing DELIVERS, not what its file says (Law #2).
	var hero := _unit(Team.Faction.PLAYER, Vector2i(0, 0))
	var swing := _attack(0, false)
	var weapon := _weapon(swing)
	hero.equipped_weapon = weapon
	_fit(weapon, 0, _spike(AttackData.Kind.PIERCE))

	assert_str(weapon.attack_detail(hero, swing)).contains("pierce")
	assert_str(weapon.attack_detail(hero, swing)).not_contains("blunt")
