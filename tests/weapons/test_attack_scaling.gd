# Scaling is per ATTACK, not per weapon family (#485). The whole point of the move is that two
# attacks on ONE weapon can scale off different stats, so the headline case is exactly that -- it
# is unrepresentable under the old model and would have needed two weapons to express.
#
# Every expectation is DERIVED from the blend under test, never a literal: the blend is a weighted
# average, so a hardcoded damage number would pin the arithmetic rather than the routing.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

func _attack(power: int, blend: Dictionary[Stats.Stat, int]) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.power = power
	a.scaling_blend = blend
	return a

func _weapon(main: WeaponAttackData) -> WeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = main
	return WeaponInstance.make(t)

func _wielder() -> Unit:
	# Deliberately lopsided, so a blend reading the wrong stat cannot coincide with the right one.
	return H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 12, Stats.Stat.DEX: 3}, false)

func _mod(nudge: Dictionary[Stats.Stat, int]) -> WeaponModData:
	var m := WeaponModData.new()
	m.scaling_change = nudge
	return m

# --- The headline: one weapon, two attacks, two answers ---

func test_two_attacks_on_one_weapon_scale_off_different_stats() -> void:
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var strong := _attack(0, {Stats.Stat.STR: 100})
	var quick := _attack(0, {Stats.Stat.DEX: 100})
	var weapon := _weapon(strong)
	unit.equipped_weapon = weapon

	# Power is 0 on both, so base_damage IS the scaling contribution -- the claim is the routing.
	assert_int(weapon.base_damage(unit, strong)).is_equal(unit.get_effective_stat(Stats.Stat.STR))
	assert_int(weapon.base_damage(unit, quick)).is_equal(unit.get_effective_stat(Stats.Stat.DEX))
	# ...and they genuinely differ, so neither line above is passing by coincidence.
	assert_int(weapon.base_damage(unit, strong)).is_not_equal(weapon.base_damage(unit, quick))

func test_a_split_blend_lands_between_its_two_stats() -> void:
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var mixed := _attack(0, {Stats.Stat.STR: 50, Stats.Stat.DEX: 50})
	var weapon := _weapon(mixed)
	unit.equipped_weapon = weapon

	var str_stat := unit.get_effective_stat(Stats.Stat.STR)
	var dex_stat := unit.get_effective_stat(Stats.Stat.DEX)
	var got := weapon.base_damage(unit, mixed)
	assert_int(got).is_greater(mini(str_stat, dex_stat))
	assert_int(got).is_less(maxi(str_stat, dex_stat))

# --- The mod nudge still composes, and cannot go negative ---

func test_a_fitted_mod_shifts_the_attacks_own_blend() -> void:
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var main := _attack(0, {Stats.Stat.STR: 100})
	var weapon := _weapon(main)
	unit.equipped_weapon = weapon
	var unmodded := weapon.base_damage(unit, main)

	weapon.fit(0, _mod({Stats.Stat.DEX: 100}))
	# STR 100 + DEX 100 = an even split, so the answer moves toward the (lower) DEX stat.
	assert_int(weapon.base_damage(unit, main)).is_less(unmodded)

func test_a_nudge_cannot_drive_a_weight_negative() -> void:
	# A mod authored against a STR family, fitted to one that does not use STR at all. Left
	# unclamped, the negative weight SUBTRACTS the wielder's STR from their own damage.
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var main := _attack(0, {Stats.Stat.DEX: 100})
	var weapon := _weapon(main)
	unit.equipped_weapon = weapon

	weapon.fit(0, _mod({Stats.Stat.STR: -40}))
	var blend := weapon.effective_blend(main, weapon.active_modules(unit))
	assert_int(blend.get(Stats.Stat.STR, 0)).is_greater_equal(0)
	# The attack still scales off what it actually uses, unchanged.
	assert_int(weapon.base_damage(unit, main)).is_equal(unit.get_effective_stat(Stats.Stat.DEX))

# --- The readout ---

func test_blend_text_normalises_rather_than_printing_raw_weights() -> void:
	# THE reason the readout was worth building: raw weights summing to 130 are not percentages,
	# and printing them puts "100%" and "30%" on screen for a weapon that is neither.
	var text := Stats.blend_text({Stats.Stat.STR: 100, Stats.Stat.DEX: 30} as Dictionary[Stats.Stat, int])
	assert_str(text).contains("STR 77%")
	assert_str(text).contains("DEX 23%")

func test_an_empty_blend_says_so_rather_than_printing_nothing() -> void:
	assert_str(Stats.blend_text({} as Dictionary[Stats.Stat, int])).is_equal("no stat scaling")

func test_the_attack_tooltip_itemises_power_and_scaling() -> void:
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var main := _attack(4, {Stats.Stat.STR: 100})
	var weapon := _weapon(main)
	unit.equipped_weapon = weapon

	var detail := weapon.attack_detail(unit, main)
	assert_str(detail).contains("4 power")
	assert_str(detail).contains("STR 100%")
	# The headline survives above it -- the scaling line is an ADDITION, not a replacement.
	assert_str(detail).contains(main.payload_text(weapon.base_damage(unit, main), weapon.effective_kind(unit, main)))

func test_a_damageless_attack_prints_no_blend() -> void:
	# Scaling is suppressed entirely for a utility attack (#126), so naming a blend would describe
	# a contribution that is structurally zero.
	var unit := _wielder()
	var utility := _attack(4, {Stats.Stat.STR: 100})
	utility.deals_no_damage = true
	var weapon := _weapon(utility)
	unit.equipped_weapon = weapon

	assert_str(weapon.attack_detail(unit, utility)).not_contains("power +")

# --- The lint ---

func test_the_lint_flags_a_blend_that_does_not_total_100() -> void:
	var short_blend := _attack(3, {Stats.Stat.STR: 60, Stats.Stat.DEX: 30})
	short_blend.attack_pattern = ManhattanRangePattern.new()
	var findings := AttackLint.check(short_blend)
	assert_array(findings).is_not_empty()
	assert_int(findings[0]["severity"]).is_equal(AttackLint.Severity.DEGRADES)
	assert_str(findings[0]["text"]).contains("90")

func test_a_blend_totalling_100_passes_the_lint() -> void:
	var ok := _attack(3, {Stats.Stat.STR: 60, Stats.Stat.DEX: 40})
	ok.attack_pattern = ManhattanRangePattern.new()
	assert_array(AttackLint.check(ok)).is_empty()

func test_a_carving_has_no_blend_and_is_not_flagged_for_one() -> void:
	# TransmutationData scales off the wielder's aura, so it has no scaling_blend at all -- the
	# rule must skip it rather than read a missing field as a zero total.
	var carving := TransmutationData.new()
	carving.attack_pattern = ManhattanRangePattern.new()
	assert_array(AttackLint.check(carving)).is_empty()

func test_every_shipped_attack_totals_100() -> void:
	# The migration's own guard, and the reason the lint is in CI: content authored before the
	# sliders existed is exactly what can violate this.
	var offenders: Array[String] = []
	for dir in ["res://Resources/WeaponAttacks/", "res://Resources/WeaponAttacks/MainAttacks/",
			"res://Resources/WeaponAttacks/MainAttacks/Prototypes/"]:
		for file in ResourceDir.files_with_extension(dir, "tres"):
			var attack := load(dir + file) as WeaponAttackData
			if attack == null:
				continue
			for finding in AttackLint.check(attack):
				if finding["severity"] == AttackLint.Severity.DEGRADES:
					offenders.append(file)
	assert_array(offenders).is_empty()
