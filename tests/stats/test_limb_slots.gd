# The limb-slot model (#56, will-and-death.md): limbs as equipment slots, effective
# STR/DEX as slot means (rounded up), the fixed maim rotation (naturals first,
# prosthetics last + recoverable), the never-escalates rule, and the aura limb tax.
# Pure Resource tests — no scene.
extends GdUnitTestSuite

func _make_instance(partial_stats: Dictionary[Stats.Stat, int], base_aura: Dictionary[Elemental.Element, int] = {}) -> UnitInstance:
	var data := UnitData.new()
	data.base_stats = partial_stats
	data.base_aura = base_aura
	var inst := UnitInstance.new()
	inst.data = data
	inst.initialize()
	return inst

func _empty(inst: UnitInstance, slot: UnitInstance.LimbSlot) -> void:
	inst.limbs[slot].state = UnitInstance.LimbState.EMPTY

func _fit_prosthetic(inst: UnitInstance, slot: UnitInstance.LimbSlot, stat: int) -> void:
	inst.limbs[slot].state = UnitInstance.LimbState.PROSTHETIC
	inst.limbs[slot].prosthetic_stat = stat

func test_intact_unit_reads_innate_stats() -> void:
	var inst := _make_instance({Stats.Stat.STR: 7, Stats.Stat.DEX: 6})
	assert_int(inst.get_effective_stat(Stats.Stat.STR)).is_equal(7)   # mean(7,7) — identity
	assert_int(inst.get_effective_stat(Stats.Stat.DEX)).is_equal(6)

func test_one_missing_arm_halves_str_rounded_up() -> void:
	# The prompt's done-when case: a maimed 7-STR unit reads effective STR 4 (ceil 3.5).
	var inst := _make_instance({Stats.Stat.STR: 7})
	_empty(inst, UnitInstance.LimbSlot.ARM_L)
	assert_int(inst.get_effective_stat(Stats.Stat.STR)).is_equal(4)

func test_one_missing_leg_halves_dex_rounded_up() -> void:
	var inst := _make_instance({Stats.Stat.DEX: 5})
	_empty(inst, UnitInstance.LimbSlot.LEG_R)
	assert_int(inst.get_effective_stat(Stats.Stat.DEX)).is_equal(3)

func test_prosthetic_contributes_its_own_stat() -> void:
	# Prosthetics can exceed baseline (will-and-death.md): 9-stat arm + natural 7 -> ceil(8).
	var inst := _make_instance({Stats.Stat.STR: 7})
	_fit_prosthetic(inst, UnitInstance.LimbSlot.ARM_R, 9)
	assert_int(inst.get_effective_stat(Stats.Stat.STR)).is_equal(8)

func test_non_limb_stats_pass_through() -> void:
	var inst := _make_instance({Stats.Stat.CON: 8})
	_empty(inst, UnitInstance.LimbSlot.ARM_L)   # CON is torso-bound — limbs never touch it
	assert_int(inst.get_effective_stat(Stats.Stat.CON)).is_equal(8)

func test_modifiers_apply_after_limb_substitution() -> void:
	var inst := _make_instance({Stats.Stat.STR: 7})
	_empty(inst, UnitInstance.LimbSlot.ARM_L)
	inst.stat_modifiers[Stats.Stat.STR] = 2
	assert_int(inst.get_effective_stat(Stats.Stat.STR)).is_equal(6)   # ceil(3.5) + 2

func test_is_maimed_derives_from_empty_slots_only() -> void:
	var inst := _make_instance({})
	assert_bool(inst.is_maimed()).is_false()
	_fit_prosthetic(inst, UnitInstance.LimbSlot.ARM_R, 5)
	assert_bool(inst.is_maimed()).is_false()   # repaired, not maimed
	_empty(inst, UnitInstance.LimbSlot.LEG_L)
	assert_bool(inst.is_maimed()).is_true()

func test_maim_rotation_takes_naturals_in_order() -> void:
	# WIL 0 -> every down is unaffordable -> each spend maims the next rotation slot.
	var inst := _make_instance({Stats.Stat.WIL: 0})
	assert_bool(inst.spend_will_for_down()).is_true()
	assert_that(inst.limbs[UnitInstance.LimbSlot.ARM_R].state).is_equal(UnitInstance.LimbState.EMPTY)
	inst.spend_will_for_down()
	assert_that(inst.limbs[UnitInstance.LimbSlot.LEG_L].state).is_equal(UnitInstance.LimbState.EMPTY)
	inst.spend_will_for_down()
	assert_that(inst.limbs[UnitInstance.LimbSlot.ARM_L].state).is_equal(UnitInstance.LimbState.EMPTY)
	inst.spend_will_for_down()
	assert_that(inst.limbs[UnitInstance.LimbSlot.LEG_R].state).is_equal(UnitInstance.LimbState.EMPTY)

func test_prosthetics_are_maimed_last() -> void:
	var inst := _make_instance({Stats.Stat.WIL: 0})
	_fit_prosthetic(inst, UnitInstance.LimbSlot.ARM_R, 6)
	inst.spend_will_for_down()   # skips the prosthetic weapon arm — flesh pays first
	assert_that(inst.limbs[UnitInstance.LimbSlot.ARM_R].state).is_equal(UnitInstance.LimbState.PROSTHETIC)
	assert_that(inst.limbs[UnitInstance.LimbSlot.LEG_L].state).is_equal(UnitInstance.LimbState.EMPTY)
	inst.spend_will_for_down()
	inst.spend_will_for_down()   # all naturals gone now
	assert_int(inst.next_maim_slot()).is_equal(UnitInstance.LimbSlot.ARM_R)   # the prosthetic, at last
	inst.spend_will_for_down()
	assert_that(inst.limbs[UnitInstance.LimbSlot.ARM_R].state).is_equal(UnitInstance.LimbState.EMPTY)

func test_fully_maimed_never_escalates() -> void:
	# "Will never kills" is absolute: with nothing left to take, the down still just stands.
	var inst := _make_instance({Stats.Stat.WIL: 0})
	for i in 4:
		inst.spend_will_for_down()
	assert_int(inst.next_maim_slot()).is_equal(-1)
	assert_bool(inst.spend_will_for_down()).is_false()   # no fifth limb, no escalation
	assert_int(inst.get_current_will()).is_equal(0)

func test_maim_taxes_highest_aura_pool() -> void:
	var inst := _make_instance({Stats.Stat.WIL: 0}, {Elemental.Element.WATER: 3, Elemental.Element.FIRE: 2})
	inst.spend_will_for_down()
	assert_int(inst.get_element_aura(Elemental.Element.WATER)).is_equal(2)
	assert_int(inst.get_element_aura(Elemental.Element.FIRE)).is_equal(2)

func test_aura_tax_tie_breaks_by_element_order() -> void:
	# FIRE precedes WATER in the enum -> ties go to FIRE (TODO(11): primary affinity).
	var inst := _make_instance({Stats.Stat.WIL: 0}, {Elemental.Element.FIRE: 2, Elemental.Element.WATER: 2})
	inst.spend_will_for_down()
	assert_int(inst.get_element_aura(Elemental.Element.FIRE)).is_equal(1)
	assert_int(inst.get_element_aura(Elemental.Element.WATER)).is_equal(2)

func test_aura_tax_noop_on_empty_pools() -> void:
	var inst := _make_instance({Stats.Stat.WIL: 0})
	inst.spend_will_for_down()   # must not crash or invent negative aura
	for element in Elemental.SIGIL_ELEMENTS:
		assert_int(inst.get_element_aura(element)).is_equal(0)

func test_maim_preview_matches_execution_pick() -> void:
	# Law #1/#2: next_maim_slot() is the public "next at risk" — the maim must take
	# exactly the slot it promised.
	var inst := _make_instance({Stats.Stat.WIL: 0})
	_empty(inst, UnitInstance.LimbSlot.ARM_R)                       # rotation already one deep
	var promised := inst.next_maim_slot()
	assert_int(promised).is_equal(UnitInstance.LimbSlot.LEG_L)
	inst.spend_will_for_down()
	assert_that(inst.limbs[promised].state).is_equal(UnitInstance.LimbState.EMPTY)

# --- Installed prosthetic weapons (#59 item 6, weapons.md Prosthetic family) ---
# limb_kind moved from WeaponData (template) to WeaponInstance (2026-07-19): different
# prosthetic INSTANCES of the same family need independent arm/leg identity (an arm and
# a leg built on the same shared template, installed at once), so it can't be a
# template-shared field the way built_in_stat still is.

func _prosthetic_weapon(built_in_stat: int, limb_kind: WeaponData.LimbKind = WeaponData.LimbKind.ARM) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.PROSTHETIC
	template.built_in_stat = built_in_stat
	var instance := WeaponInstance.make(template)
	instance.limb_kind = limb_kind
	return instance

func test_installed_prosthetic_reads_built_in_stat_from_template() -> void:
	# Parity with the bare-placeholder case above, but via a real content template:
	# 9-stat arm + natural 7 -> ceil(8), same formula, template-sourced this time.
	var inst := _make_instance({Stats.Stat.STR: 7})
	assert_bool(inst.install_prosthetic(UnitInstance.LimbSlot.ARM_R, _prosthetic_weapon(9))).is_true()
	assert_int(inst.get_effective_stat(Stats.Stat.STR)).is_equal(8)

func test_installed_prosthetics_on_both_arms_average_their_templates() -> void:
	var inst := _make_instance({Stats.Stat.STR: 0})
	inst.install_prosthetic(UnitInstance.LimbSlot.ARM_L, _prosthetic_weapon(6))
	inst.install_prosthetic(UnitInstance.LimbSlot.ARM_R, _prosthetic_weapon(11))
	assert_int(inst.get_effective_stat(Stats.Stat.STR)).is_equal(9)   # ceil(8.5)

func test_installed_prosthetic_stat_reads_live_off_the_template() -> void:
	# The whole point of a direct resource ref (mirrors scaling_blend): editing the
	# template after install propagates with zero re-fitting, same as any weapon.
	var inst := _make_instance({Stats.Stat.STR: 7})
	var weapon := _prosthetic_weapon(5)
	inst.install_prosthetic(UnitInstance.LimbSlot.ARM_R, weapon)
	assert_int(inst.get_effective_stat(Stats.Stat.STR)).is_equal(6)   # ceil(6)
	weapon.template.built_in_stat = 9
	assert_int(inst.get_effective_stat(Stats.Stat.STR)).is_equal(8)   # ceil(8) — no re-install needed

func test_is_installed_prosthetic_matches_only_the_fitted_template() -> void:
	var inst := _make_instance({})
	var fitted := _prosthetic_weapon(5)
	var other := _prosthetic_weapon(5)
	inst.install_prosthetic(UnitInstance.LimbSlot.ARM_R, fitted)
	assert_bool(inst.is_installed_prosthetic(fitted.template)).is_true()
	assert_bool(inst.is_installed_prosthetic(other.template)).is_false()
	assert_bool(inst.is_installed_prosthetic(null)).is_false()

func test_bare_placeholder_prosthetic_is_not_an_installed_weapon() -> void:
	# The dev/test shortcut (_fit_prosthetic: a raw stat, no real item) stays legal —
	# it just never counts as an "installed weapon" since there's no template to match.
	var inst := _make_instance({Stats.Stat.STR: 7})
	_fit_prosthetic(inst, UnitInstance.LimbSlot.ARM_R, 9)
	assert_int(inst.get_effective_stat(Stats.Stat.STR)).is_equal(8)
	assert_bool(inst.is_installed_prosthetic(_prosthetic_weapon(9).template)).is_false()

func test_install_prosthetic_refuses_an_arm_kind_instance_on_a_leg_slot() -> void:
	var inst := _make_instance({Stats.Stat.DEX: 6})
	var arm_weapon := _prosthetic_weapon(9, WeaponData.LimbKind.ARM)
	assert_bool(inst.install_prosthetic(UnitInstance.LimbSlot.LEG_L, arm_weapon)).is_false()
	assert_that(inst.limbs[UnitInstance.LimbSlot.LEG_L].state).is_equal(UnitInstance.LimbState.NATURAL)
	assert_int(inst.get_effective_stat(Stats.Stat.DEX)).is_equal(6)   # unaffected — the refused fit never applied

func test_install_prosthetic_refuses_a_leg_kind_instance_on_an_arm_slot() -> void:
	var inst := _make_instance({Stats.Stat.STR: 6})
	var leg_weapon := _prosthetic_weapon(9, WeaponData.LimbKind.LEG)
	assert_bool(inst.install_prosthetic(UnitInstance.LimbSlot.ARM_R, leg_weapon)).is_false()
	assert_that(inst.limbs[UnitInstance.LimbSlot.ARM_R].state).is_equal(UnitInstance.LimbState.NATURAL)

func test_install_prosthetic_succeeds_with_a_matching_leg_kind_instance() -> void:
	# Symmetry check: legs get the same live-template treatment as arms, gated on LEG kind.
	var inst := _make_instance({Stats.Stat.DEX: 7})
	var leg_weapon := _prosthetic_weapon(9, WeaponData.LimbKind.LEG)
	assert_bool(inst.install_prosthetic(UnitInstance.LimbSlot.LEG_R, leg_weapon)).is_true()
	assert_int(inst.get_effective_stat(Stats.Stat.DEX)).is_equal(8)   # ceil((7+9)/2)

func test_same_family_template_can_back_an_arm_instance_and_a_leg_instance_at_once() -> void:
	# The whole point of the move: two prosthetics sharing ONE template can independently
	# be an arm and a leg installed at the same time — impossible when limb_kind lived on
	# the template, since that would force every instance of the family to agree.
	var inst := _make_instance({Stats.Stat.STR: 7, Stats.Stat.DEX: 5})
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.PROSTHETIC
	template.built_in_stat = 9
	var arm := WeaponInstance.make(template)
	arm.limb_kind = WeaponData.LimbKind.ARM
	var leg := WeaponInstance.make(template)
	leg.limb_kind = WeaponData.LimbKind.LEG
	assert_bool(inst.install_prosthetic(UnitInstance.LimbSlot.ARM_R, arm)).is_true()
	assert_bool(inst.install_prosthetic(UnitInstance.LimbSlot.LEG_L, leg)).is_true()
	assert_int(inst.get_effective_stat(Stats.Stat.STR)).is_equal(8)   # ceil((7+9)/2)
	assert_int(inst.get_effective_stat(Stats.Stat.DEX)).is_equal(7)   # ceil((5+9)/2)
