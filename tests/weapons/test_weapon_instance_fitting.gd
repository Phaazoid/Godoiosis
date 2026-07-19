# WeaponInstance fitting, proficiency-gated activation, and the effective-weapon math
# (#59 weapon parts core — the one gap the item-6 pass didn't touch). Covers: space
# capacities/fit validation, active-space gating by proficiency, the mass-is-physical
# rule (get_effective_weight counts every fitted mod, active or not), and the
# scaling_blend + per-mod scaling_nudge weighted-average math feeding base_damage.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

func _template(power: int = 0, blend: Dictionary[Stats.Stat, int] = {Stats.Stat.STR: 100}, base_weight: int = 0, is_prototype: bool = false, elemental: Elemental.Element = Elemental.Element.NONE) -> WeaponData:
	var t := WeaponData.new()
	t.main_attack = WeaponAttackData.new()
	t.main_attack.power = power
	t.main_attack.elemental_damage_type = elemental
	t.scaling_blend = blend
	t.base_weight = base_weight
	t.is_prototype = is_prototype
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	return t

func _mod(size: int = 1, power_delta: int = 0, weight: int = 0, scaling_nudge: Dictionary[Stats.Stat, int] = {}, added_element: Elemental.Element = Elemental.Element.NONE) -> WeaponModData:
	var m := WeaponModData.new()
	m.size = size
	m.power_delta = power_delta
	m.weight = weight
	m.scaling_nudge = scaling_nudge
	m.added_element = added_element
	return m

func _wielder(overrides: Dictionary = {}) -> Unit:
	return H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), overrides, false)

func _set_proficiency(unit: Unit, n: int) -> void:
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, n)

# --- Fitting / capacity ---

func test_space_count_matches_template_capacities() -> void:
	var w := WeaponInstance.make(_template())
	assert_int(w.space_count()).is_equal(3)

func test_prototype_collapses_to_one_space() -> void:
	var w := WeaponInstance.make(_template(0, {Stats.Stat.STR: 100}, 0, true))
	assert_int(w.space_count()).is_equal(1)

func test_can_fit_true_within_capacity_false_over() -> void:
	var w := WeaponInstance.make(_template())
	assert_bool(w.can_fit(2, _mod(1))).is_true()    # space index 2 -> capacity 3
	assert_bool(w.fit(2, _mod(1))).is_true()
	assert_bool(w.fit(2, _mod(2))).is_true()        # 1 + 2 = 3, exactly fits
	assert_int(w.used_capacity(2)).is_equal(3)
	assert_bool(w.can_fit(2, _mod(1))).is_false()   # 3 + 1 = 4 > capacity 3
	assert_bool(w.fit(2, _mod(1))).is_false()
	assert_int(w.used_capacity(2)).is_equal(3)      # a refused fit doesn't mutate the space

func test_can_fit_false_for_out_of_range_index() -> void:
	var w := WeaponInstance.make(_template())
	assert_bool(w.can_fit(-1, _mod(1))).is_false()
	assert_bool(w.can_fit(3, _mod(1))).is_false()   # only indices 0..2 exist

func test_can_fit_false_with_no_template() -> void:
	var w := WeaponInstance.new()
	assert_bool(w.can_fit(0, _mod(1))).is_false()
	assert_int(w.space_count()).is_equal(0)

# --- Proficiency-gated activation ---

func test_active_space_count_capped_by_proficiency() -> void:
	var w := WeaponInstance.make(_template())
	var wielder := _wielder()
	_set_proficiency(wielder, 1)
	assert_int(w.active_space_count(wielder)).is_equal(1)
	_set_proficiency(wielder, 2)
	assert_int(w.active_space_count(wielder)).is_equal(2)
	_set_proficiency(wielder, 0)
	assert_int(w.active_space_count(wielder)).is_equal(0)

func test_active_modules_only_pulls_from_activated_spaces() -> void:
	var w := WeaponInstance.make(_template())
	var mod_0 := _mod(1, 2)
	var mod_1 := _mod(1, 3)
	var mod_2 := _mod(1, 5)
	w.fit(0, mod_0)
	w.fit(1, mod_1)
	w.fit(2, mod_2)
	var wielder := _wielder()

	_set_proficiency(wielder, 1)
	assert_array(w.active_modules(wielder)).contains_exactly([mod_0])

	_set_proficiency(wielder, 2)
	assert_array(w.active_modules(wielder)).contains_exactly([mod_0, mod_1])

	_set_proficiency(wielder, 3)
	assert_array(w.active_modules(wielder)).contains_exactly([mod_0, mod_1, mod_2])

# --- Effective weight: ALL fitted mods count, active or not (mass is physical) ---

func test_effective_weight_counts_inactive_mods_too() -> void:
	var w := WeaponInstance.make(_template(0, {Stats.Stat.STR: 100}, 2))   # base_weight 2
	w.fit(0, _mod(1, 0, 3))   # weight 3, in the one space that stays active below
	w.fit(2, _mod(1, 0, 4))   # weight 4, in a space that stays INACTIVE below
	var wielder := _wielder()
	_set_proficiency(wielder, 1)
	assert_int(w.active_space_count(wielder)).is_equal(1)         # confirms space 2 is inactive
	assert_int(w.get_effective_weight()).is_equal(9)               # 2 + 3 + 4 regardless

# --- base_damage / scaling: only ACTIVE mods contribute ---

func test_base_damage_pure_str_blend() -> void:
	var w := WeaponInstance.make(_template(10, {Stats.Stat.STR: 100}))
	var wielder := _wielder({Stats.Stat.STR: 6})
	_set_proficiency(wielder, 3)
	assert_int(w.base_damage(wielder)).is_equal(16)   # 10 power + 6 STR (100% blend)

func test_base_damage_ignores_inactive_space_power_delta() -> void:
	var w := WeaponInstance.make(_template(10, {Stats.Stat.STR: 100}))
	w.fit(0, _mod(1, 2))     # active at proficiency 1
	w.fit(2, _mod(1, 100))   # inactive at proficiency 1 — must NOT count
	var wielder := _wielder({Stats.Stat.STR: 5})
	_set_proficiency(wielder, 1)
	assert_int(w.base_damage(wielder)).is_equal(17)   # 10 + 2 (active mod) + 5 (STR) — the +100 never applies

func test_scaling_nudge_from_active_mod_shifts_blend() -> void:
	var w := WeaponInstance.make(_template(0, {Stats.Stat.STR: 100}))
	w.fit(0, _mod(1, 0, 0, {Stats.Stat.DEX: 50}))   # active mod adds a DEX slice to the blend
	var wielder := _wielder({Stats.Stat.STR: 8, Stats.Stat.DEX: 2})
	_set_proficiency(wielder, 1)
	# blend becomes {STR:100, DEX:50}; weighted = (8*100 + 2*50) / 150 = 900/150 = 6
	assert_int(w.base_damage(wielder)).is_equal(6)

func test_inactive_mod_scaling_nudge_is_ignored() -> void:
	var w := WeaponInstance.make(_template(0, {Stats.Stat.STR: 100}))
	w.fit(2, _mod(1, 0, 0, {Stats.Stat.DEX: 100}))   # sits in a space that never activates here
	var wielder := _wielder({Stats.Stat.STR: 7, Stats.Stat.DEX: 20})
	_set_proficiency(wielder, 1)
	assert_int(w.base_damage(wielder)).is_equal(7)   # pure STR — the DEX nudge never entered the blend

# --- Elements: main attack + active mods, deduped ---

func test_get_elements_includes_main_attack_element() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, false, Elemental.Element.FIRE))
	var wielder := _wielder()
	assert_array(w.get_elements(wielder)).contains_exactly([Elemental.Element.FIRE])

func test_get_elements_includes_active_mod_elements_and_dedupes() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, false, Elemental.Element.FIRE))
	w.fit(0, _mod(1, 0, 0, {}, Elemental.Element.FIRE))   # duplicate of the template's own element
	w.fit(1, _mod(1, 0, 0, {}, Elemental.Element.WATER))
	var wielder := _wielder()
	_set_proficiency(wielder, 2)
	assert_array(w.get_elements(wielder)).contains_exactly([Elemental.Element.FIRE, Elemental.Element.WATER])

func test_get_elements_excludes_inactive_mod_elements() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, false, Elemental.Element.NONE))
	w.fit(2, _mod(1, 0, 0, {}, Elemental.Element.WATER))   # inactive at proficiency 1
	var wielder := _wielder()
	_set_proficiency(wielder, 1)
	assert_array(w.get_elements(wielder)).is_empty()
