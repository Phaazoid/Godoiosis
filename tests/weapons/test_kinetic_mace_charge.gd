# Kinetic Mace charge -> Blowback economy (#84): charge lives on the WEAPON instance (the #73
# readiness seam reinterpreted as a counter), a normal attack banks +1 (capped), the Blowback
# (any attack with knockback > 0) requires and spends 1, and it resets each mission via make()/
# copy_equippable(). The displacement itself (shove distance, collisions, Law-#2 preview==exec)
# is proven on a real board in tests/play/test_knockback.gd.
extends GdUnitTestSuite


func _mace() -> KineticMaceWeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.KINETIC_MACE
	t.main_attack = WeaponAttackData.new()
	return WeaponInstance.make(t) as KineticMaceWeaponInstance


func _regular() -> WeaponAttackData:
	return WeaponAttackData.new()   # knockback 0 -> a charge-builder


func _blowback() -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.knockback = 1                 # knockback > 0 -> the charge-spender
	return a


func test_fresh_mace_has_no_charge() -> void:
	assert_int(_mace().charge).is_equal(0)


func test_regular_attack_banks_a_charge() -> void:
	var m := _mace()
	m.consume_readiness_for(_regular())
	assert_int(m.charge).is_equal(1)


func test_charge_caps_at_max() -> void:
	var m := _mace()
	for _i in range(KineticMaceWeaponInstance.MAX_CHARGE + 2):
		m.consume_readiness_for(_regular())
	assert_int(m.charge).is_equal(KineticMaceWeaponInstance.MAX_CHARGE)


func test_regular_attack_is_always_fireable() -> void:
	assert_bool(_mace().is_attack_fireable(_regular())).is_true()


func test_blowback_needs_charge_to_fire() -> void:
	var m := _mace()
	assert_bool(m.is_attack_fireable(_blowback())).is_false()   # 0 charge -> can't
	m.consume_readiness_for(_regular())
	assert_bool(m.is_attack_fireable(_blowback())).is_true()    # 1 charge -> can


func test_blowback_spends_one_charge() -> void:
	var m := _mace()
	m.consume_readiness_for(_regular())
	m.consume_readiness_for(_regular())
	assert_int(m.charge).is_equal(2)
	m.consume_readiness_for(_blowback())
	assert_int(m.charge).is_equal(1)


func test_charge_never_goes_negative() -> void:
	var m := _mace()
	m.consume_readiness_for(_blowback())   # spend with 0 charge — a no-op floor, not a debt
	assert_int(m.charge).is_equal(0)


func test_charge_does_not_survive_a_copy() -> void:
	# Battle-scoped: a fresh mission (copy_equippable) starts uncharged.
	var m := _mace()
	m.consume_readiness_for(_regular())
	var fresh := m.copy_equippable() as KineticMaceWeaponInstance
	assert_int(fresh.charge).is_equal(0)


func test_two_maces_charge_independently() -> void:
	var a := _mace()
	var b := _mace()
	a.consume_readiness_for(_regular())
	assert_int(a.charge).is_equal(1)
	assert_int(b.charge).is_equal(0)


func test_family_template_carries_a_blowback_extra() -> void:
	# The authored content (Blowback.tres wired into the Kinetic Mace family's extra_attacks):
	# every mace offers a knockback attack. Loads the real .tres, guarding the wiring.
	var mace: WeaponData = load("res://Resources/Weapons/MainVarieties/Kinetic_Mace.tres")
	assert_bool(mace != null).is_true()
	var blowbacks := 0
	for atk in mace.extra_attacks:
		if atk.knockback > 0:
			blowbacks += 1
	assert_int(blowbacks).is_equal(1)


func test_a_non_mace_family_has_no_charge_economy() -> void:
	# Base WeaponInstance: a knockback attack is just fireable, no charge gate, no banking.
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = WeaponAttackData.new()
	var w := WeaponInstance.make(t)
	assert_bool(w.is_attack_fireable(_blowback())).is_true()
	w.consume_readiness_for(_regular())   # no-op on the base class (readiness surface)
