# The applies_to selector (#530): which of a weapon's attacks a fitted mod's effects reach.
#
# Every case fires ONE mod at TWO attacks on ONE weapon and compares each against its own unmodded
# baseline. That shape is deliberate: a selector that ignored applies_to would move both attacks,
# and a fit that silently failed would move neither, so each law is pinned from both sides rather
# than resting on the two attacks simply being different attacks.
#
# Main and extra are built identical on purpose -- any difference a case sees is the MOD's doing.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BUMP := 5

func _attack(name: String) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.display_name = name
	a.power = 4
	a.scaling_blend = {Stats.Stat.STR: 100}
	return a

func _weapon(main: WeaponAttackData, extra: WeaponAttackData) -> WeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = main
	var extras: Array[WeaponAttackData] = [extra]
	t.extra_attacks = extras
	return WeaponInstance.make(t)

func _wielder() -> Unit:
	# Lopsided stats, so a blend reading the wrong stat cannot coincide with the right one.
	var u := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 12, Stats.Stat.DEX: 3}, false)
	u.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	return u

func _mod(applies: WeaponModData.AppliesTo) -> WeaponModData:
	var m := WeaponModData.new()
	m.applies_to = applies
	return m

# Fitting is the precondition every law below stands on: if it fails, nothing changes and "the
# extra was untouched" reads exactly like a pass.
func _fit(weapon: WeaponInstance, mod: WeaponModData) -> void:
	assert_bool(weapon.fit(0, mod)) \
		.override_failure_message("fixture: the mod must actually fit, or every effect reads as absent") \
		.is_true()

# --- Power ---

func test_a_main_attack_mod_bumps_the_main_and_leaves_the_extra_alone() -> void:
	var unit := _wielder()
	var main := _attack("Main")
	var extra := _attack("Extra")
	var weapon := _weapon(main, extra)
	unit.equipped_weapon = weapon
	var was_main := weapon.base_damage(unit, main)
	var was_extra := weapon.base_damage(unit, extra)

	var mod := _mod(WeaponModData.AppliesTo.MAIN_ATTACK)
	mod.power_delta = BUMP
	_fit(weapon, mod)

	assert_int(weapon.base_damage(unit, main)).is_equal(was_main + BUMP)
	assert_int(weapon.base_damage(unit, extra)).is_equal(was_extra)

func test_the_default_reaches_every_attack_the_weapon_fires() -> void:
	var unit := _wielder()
	var main := _attack("Main")
	var extra := _attack("Extra")
	var weapon := _weapon(main, extra)
	unit.equipped_weapon = weapon
	var was_main := weapon.base_damage(unit, main)
	var was_extra := weapon.base_damage(unit, extra)

	var mod := WeaponModData.new()	 # deliberately NOT via _mod: an un-authored mod is the case
	mod.power_delta = BUMP
	assert_int(mod.applies_to).is_equal(WeaponModData.AppliesTo.EVERY_ATTACK)
	_fit(weapon, mod)

	assert_int(weapon.base_damage(unit, main)).is_equal(was_main + BUMP)
	assert_int(weapon.base_damage(unit, extra)).is_equal(was_extra + BUMP)

# --- Element ---

func test_a_main_attack_mod_elements_only_the_main() -> void:
	var unit := _wielder()
	var main := _attack("Main")
	var extra := _attack("Extra")
	var weapon := _weapon(main, extra)
	unit.equipped_weapon = weapon

	var mod := _mod(WeaponModData.AppliesTo.MAIN_ATTACK)
	mod.added_element = Elemental.Element.FIRE
	_fit(weapon, mod)

	assert_array(weapon.get_elements(unit, main)).contains([Elemental.Element.FIRE])
	assert_array(weapon.get_elements(unit, extra)).is_empty()

# --- Scaling ---

func test_a_main_attack_mod_shifts_only_the_mains_blend() -> void:
	var unit := _wielder()
	var main := _attack("Main")
	var extra := _attack("Extra")
	var weapon := _weapon(main, extra)
	unit.equipped_weapon = weapon
	var was_main := weapon.base_damage(unit, main)
	var was_extra := weapon.base_damage(unit, extra)

	# Half the weight onto the stat this wielder is WORST at, so the shift has to move the number.
	var mod := _mod(WeaponModData.AppliesTo.MAIN_ATTACK)
	mod.scaling_change = {Stats.Stat.DEX: 100}
	mod.family = WeaponData.WeaponType.CHAINSWORD
	_fit(weapon, mod)

	assert_int(weapon.base_damage(unit, main)).is_less(was_main)
	assert_int(weapon.base_damage(unit, extra)).is_equal(was_extra)

# --- The boundary the selector does NOT cross ---

func test_a_main_attack_mod_still_grants_the_attacks_it_carries() -> void:
	var unit := _wielder()
	var main := _attack("Main")
	var extra := _attack("Extra")
	var weapon := _weapon(main, extra)
	unit.equipped_weapon = weapon

	# applies_to says which attacks a mod CHANGES; it has no say over which it ADDS.
	var granted := _attack("Granted")
	var mod := _mod(WeaponModData.AppliesTo.MAIN_ATTACK)
	var carried: Array[WeaponAttackData] = [granted]
	mod.granted_attacks = carried
	_fit(weapon, mod)

	assert_array(weapon.available_attacks(unit)).contains([granted])
