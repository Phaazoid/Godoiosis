# The #72 multi-attack weapon model: WeaponData main_attack/extra_attacks composition,
# per-attack damage/element/hits_map reads on WeaponInstance (null = the main attack),
# and the WeaponAttackCatalog folder partition (curated mains vs the general pool).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

func _attack(power: int = 0, hits_allies: bool = false, element: Elemental.Element = Elemental.Element.NONE, targets: EquippableData.TargetMode = EquippableData.TargetMode.UNIT) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.power = power
	a.hits_allies = hits_allies
	a.elemental_damage_type = element
	a.targets = targets
	return a

func _template_with(main: WeaponAttackData, extras: Array[WeaponAttackData] = []) -> WeaponData:
	var t := WeaponData.new()
	t.main_attack = main
	t.extra_attacks = extras
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	return t

func _wielder(overrides: Dictionary = {}) -> Unit:
	return H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), overrides, false)

# --- attack-list composition ---

func test_attacks_lists_main_first_then_extras() -> void:
	var main := _attack(1)
	var spring := _attack(9)
	var t := _template_with(main, [spring])
	assert_array(t.attacks()).contains_exactly([main, spring])

func test_attacks_skips_null_main() -> void:
	var spring := _attack(9)
	var t := _template_with(null, [spring])
	assert_array(t.attacks()).contains_exactly([spring])

func test_available_attacks_reads_template_and_handles_no_template() -> void:
	var main := _attack(1)
	var w := WeaponInstance.make(_template_with(main))
	var wielder := _wielder()
	assert_array(w.available_attacks(wielder)).contains_exactly([main])
	var bare := WeaponInstance.new()
	assert_array(bare.available_attacks(wielder)).is_empty()

# --- per-attack damage (family scaling stays weapon-wide) ---

func test_base_damage_defaults_to_main_attack() -> void:
	var w := WeaponInstance.make(_template_with(_attack(10)))
	var wielder := _wielder({Stats.Stat.STR: 6})
	assert_int(w.base_damage(wielder)).is_equal(16)   # 10 main power + 6 STR (100% blend)

func test_base_damage_uses_passed_attack_over_main() -> void:
	var spring := _attack(9)
	var w := WeaponInstance.make(_template_with(_attack(2), [spring]))
	var wielder := _wielder({Stats.Stat.STR: 6})
	assert_int(w.base_damage(wielder, spring)).is_equal(15)   # 9 + 6 — blend is the family's, not the attack's

func test_base_damage_with_null_main_is_scaling_plus_mods_only() -> void:
	var w := WeaponInstance.make(_template_with(null))
	var wielder := _wielder({Stats.Stat.STR: 6})
	assert_int(w.base_damage(wielder)).is_equal(6)

# --- per-attack elements ---

func test_get_elements_reads_the_passed_attack() -> void:
	var acid := _attack(0, false, Elemental.Element.WATER)
	var w := WeaponInstance.make(_template_with(_attack(0, false, Elemental.Element.FIRE), [acid]))
	var wielder := _wielder()
	assert_array(w.get_elements(wielder)).contains_exactly([Elemental.Element.FIRE])
	assert_array(w.get_elements(wielder, acid)).contains_exactly([Elemental.Element.WATER])

# --- per-attack hits_map ---

func test_hits_map_defaults_to_main_and_accepts_override() -> void:
	var cell_burst := _attack(0, false, Elemental.Element.NONE, EquippableData.TargetMode.BOTH)
	var w := WeaponInstance.make(_template_with(_attack(), [cell_burst]))
	assert_bool(w.hits_map()).is_false()
	assert_bool(w.hits_map(cell_burst)).is_true()
	var no_main := WeaponInstance.make(_template_with(null))
	assert_bool(no_main.hits_map()).is_false()

# --- catalog partition: curated mains vs the general pool ---

func test_mains_catalog_contains_every_family_and_prototype() -> void:
	var mains := WeaponAttackCatalog.get_mains()
	# Springspear's main is authored (Stab, #73) and Kinetic Mace's now is too (Smash, #84) —
	# both key by their real display_name instead of the filename fallback the still-placeholder
	# families use.
	for key in ["ChainSword", "Stab", "Drill", "Carbine", "Smash", "Chemical_Spitter", "Prosthetic", "TheJaw"]:
		assert_bool(mains.has(key)).is_true()

func test_library_scan_ignores_the_mains_subfolder() -> void:
	var lib := WeaponAttackCatalog.get_library()
	assert_bool(lib.has("ChainSword")).is_false()
	assert_bool(lib.has("TheJaw")).is_false()
