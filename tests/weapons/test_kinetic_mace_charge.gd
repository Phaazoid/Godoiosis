# Kinetic Mace charge -> Blowback economy (#84), now driven entirely by the attack's own authored
# readiness flags (#108): charge lives on the WEAPON instance (the #73 seam read as a counter),
# an attack with builds_readiness banks +1 (capped), one with consumes_readiness spends 1, one with
# requires_readiness is gated at 0, and the whole thing resets each mission via make()/
# copy_equippable(). The family used to infer the spender from `knockback > 0` — a private second
# answer to what these flags already say (design law #4) — so several cases below exist purely to
# pin the decoupling. The displacement itself (shove distance, collisions, Law-#2 preview==exec)
# is proven on a real board in tests/play/test_knockback.gd.
extends GdUnitTestSuite


func _mace() -> KineticMaceWeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.KINETIC_MACE
	t.main_attack = _builder()
	return WeaponInstance.make(t) as KineticMaceWeaponInstance


# What Smash authors: a swing that stores kinetic energy.
func _builder() -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.builds_readiness = true
	return a


# What Blowback authors: needs a charge, spends it. `knockback` is the SHOVE, and deliberately
# not set here — the economy must not depend on it (#108).
func _blowback() -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.requires_readiness = true
	a.consumes_readiness = true
	return a


# Authors nothing: neither gated, nor spending, nor banking.
func _inert() -> WeaponAttackData:
	return WeaponAttackData.new()


func test_fresh_mace_has_no_charge() -> void:
	assert_int(_mace().charge).is_equal(0)


func test_a_building_attack_banks_a_charge() -> void:
	var m := _mace()
	m.consume_readiness_for(_builder())
	assert_int(m.charge).is_equal(1)


func test_charge_caps_at_max() -> void:
	var m := _mace()
	for _i in range(KineticMaceWeaponInstance.MAX_CHARGE + 2):
		m.consume_readiness_for(_builder())
	assert_int(m.charge).is_equal(KineticMaceWeaponInstance.MAX_CHARGE)


func test_an_ungated_attack_is_always_fireable() -> void:
	assert_bool(_mace().is_attack_fireable(_builder())).is_true()


func test_blowback_needs_charge_to_fire() -> void:
	var m := _mace()
	assert_bool(m.is_attack_fireable(_blowback())).is_false()   # 0 charge -> can't
	m.consume_readiness_for(_builder())
	assert_bool(m.is_attack_fireable(_blowback())).is_true()    # 1 charge -> can


func test_blowback_spends_one_charge() -> void:
	var m := _mace()
	m.consume_readiness_for(_builder())
	m.consume_readiness_for(_builder())
	assert_int(m.charge).is_equal(2)
	m.consume_readiness_for(_blowback())
	assert_int(m.charge).is_equal(1)


func test_charge_never_goes_negative() -> void:
	var m := _mace()
	m.consume_readiness_for(_blowback())   # spend with 0 charge — a no-op floor, not a debt
	assert_int(m.charge).is_equal(0)


# --- #108: the economy reads the authored flags, and ONLY those ---

func test_an_attack_authoring_nothing_neither_banks_nor_spends() -> void:
	# Pre-#108 this banked a charge, because "not a knockback attack" was read as "a builder".
	var m := _mace()
	m.consume_readiness_for(_builder())
	m.consume_readiness_for(_inert())
	assert_int(m.charge).is_equal(1)


func test_knockback_alone_does_not_gate_or_spend() -> void:
	# The exact inference that was wrong: knockback is the SHOVE (AttackData's own comment calls it
	# generic on purpose — a future air-blast rune could carry it). It must say nothing about charge.
	var shove := WeaponAttackData.new()
	shove.knockback = 3
	var m := _mace()
	assert_bool(m.is_attack_fireable(shove)).is_true()   # not gated at 0 charge
	m.consume_readiness_for(_builder())
	m.consume_readiness_for(shove)
	assert_int(m.charge).is_equal(1)                     # not spent, not banked


func test_an_authored_gate_is_honored_without_knockback() -> void:
	# The mirror: pre-#108 a requires_readiness attack with no knockback was silently ungated.
	var gated := WeaponAttackData.new()
	gated.requires_readiness = true
	assert_bool(_mace().is_attack_fireable(gated)).is_false()


func test_a_counter_banks_charge() -> void:
	# Ratified doctrine (dev, 2026-07-28): a counter stamps main, main builds, so countering
	# charges the mace — swinging it into an enemy is what stores the energy. Authored on Smash,
	# so this is a content decision the test pins rather than an emergent side effect.
	var t: WeaponData = load("res://Resources/Weapons/MainVarieties/Kinetic_Mace.tres")
	var m := WeaponInstance.make(t) as KineticMaceWeaponInstance
	m.consume_readiness_for(t.main_attack)   # what create_counter_volley stamps
	assert_int(m.charge).is_equal(1)


# --- the authored content itself ---

func test_family_content_wires_the_charge_economy() -> void:
	# Guards the .tres wiring both ways: main builds, and exactly one extra is the gated spender.
	# Loads the real resources — this pair is what makes the family playable at all, since a mace
	# whose Smash forgot builds_readiness could never fire Blowback twice.
	var mace: WeaponData = load("res://Resources/Weapons/MainVarieties/Kinetic_Mace.tres")
	assert_bool(mace != null).is_true()
	assert_bool(mace.main_attack.builds_readiness).is_true()

	var spenders := 0
	for atk in mace.extra_attacks:
		if atk.requires_readiness and atk.consumes_readiness:
			spenders += 1
	assert_int(spenders).is_equal(1)


# The copy reset, independence between two maces, and "no other family has a charge economy" are
# BASE-CLASS properties, not the mace's. They moved to tests/weapons/test_weapon_family_seam.gd
# (2026-08-01), which asserts them over every family from one table rather than per-family here.
# What stays is the charge economy itself — above all #108's decoupling from `knockback`.
