# What a fitted WeaponModData GRANTS (#74): an attack to its weapon, and abilities + wielder stats
# to the unit carrying it. The numeric effects (power_delta, scaling_nudge, weight) predate this
# and live in test_weapon_instance_fitting.gd; this suite is only the three grant fields.
#
# Two rulings are pinned here rather than described anywhere else:
#   * proficiency gates a grant exactly as it gates power -- a locked space gives nothing;
#   * which SLOTS contribute is the equipped weapon plus installed prosthetics, DEDUPED, because
#     one prosthetic arm can be both at once.
#
# Stat cases measure a DELTA across fitting the mod, never an absolute. Installing a prosthetic
# rewrites the limb stage (arms carry STR, and a built_in_stat of 0 halves it), so an absolute
# expectation would be reading the limb model rather than this ticket's seam.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

func _template(family := WeaponData.WeaponType.CHAINSWORD) -> WeaponData:
	var t := WeaponData.new()
	t.main_attack = WeaponAttackData.new()
	t.main_attack.display_name = "Main"
	t.weapon_type = family
	return t

func _mod(stats: Dictionary[Stats.Stat, int] = {}, abilities: Array[AbilityData] = [],
		attacks: Array[WeaponAttackData] = []) -> WeaponModData:
	var m := WeaponModData.new()
	m.stat_modifiers = stats
	m.granted_abilities = abilities
	m.granted_attacks = attacks
	return m

func _ability(id: Abilities.Id) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.display_name = "Braced"
	return a

func _attack(name: String) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.display_name = name
	return a

func _wielder() -> Unit:
	return H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)

func _has_ability(unit: Unit, id: Abilities.Id) -> bool:
	return unit.has_live_ability(id)

# --- The three grants, through the equipped weapon ---

func test_a_fitted_mod_adds_its_attack_to_the_weapons_repertoire() -> void:
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var weapon := WeaponInstance.make(_template())
	var extra := _attack("Overcharge")
	var granted: Array[WeaponAttackData] = [extra]
	weapon.fit(0, _mod({}, [], granted))
	unit.equipped_weapon = weapon

	var available := weapon.available_attacks(unit)
	assert_array(available).contains([weapon.template.main_attack, extra])
	# Main stays first -- the canonical order menus and the default pick read.
	assert_object(available[0]).is_same(weapon.template.main_attack)

func test_a_fitted_mod_grants_its_ability_to_the_wielder() -> void:
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	assert_bool(_has_ability(unit, Abilities.Id.BRACE)).is_false()

	var weapon := WeaponInstance.make(_template())
	var abilities: Array[AbilityData] = [_ability(Abilities.Id.BRACE)]
	weapon.fit(0, _mod({}, abilities))
	unit.equipped_weapon = weapon

	assert_bool(_has_ability(unit, Abilities.Id.BRACE)).is_true()

func test_a_fitted_mod_moves_the_wielders_effective_stat() -> void:
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var weapon := WeaponInstance.make(_template())
	unit.equipped_weapon = weapon
	var before := unit.get_effective_stat(Stats.Stat.STR)

	weapon.fit(0, _mod({Stats.Stat.STR: 4}))
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(before + 4)

	# The BODY is untouched -- a mod is gear, and gear is the one stage get_body_stat excludes,
	# so the whole contribution has to sit in the difference between the two readings.
	assert_int(unit.get_effective_stat(Stats.Stat.STR) - unit.get_body_stat(Stats.Stat.STR)).is_equal(4)

# --- The proficiency ruling ---

func test_a_mod_in_a_proficiency_locked_space_grants_nothing() -> void:
	# Proficiency N activates spaces 1..N, so at 1 only space index 0 is live. All three grants
	# answer the same way as power does: a space you cannot use gives you nothing.
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 1)
	var weapon := WeaponInstance.make(_template())
	unit.equipped_weapon = weapon
	var before := unit.get_effective_stat(Stats.Stat.STR)

	var extra := _attack("Locked")
	var abilities: Array[AbilityData] = [_ability(Abilities.Id.BRACE)]
	var granted: Array[WeaponAttackData] = [extra]
	weapon.fit(1, _mod({Stats.Stat.STR: 4}, abilities, granted))   # space index 1 = inactive at proficiency 1

	assert_array(weapon.available_attacks(unit)).not_contains([extra])
	assert_bool(_has_ability(unit, Abilities.Id.BRACE)).is_false()
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(before)

	# ...and the SAME mod in an active space does pay out, so the case above is a gate rather
	# than a mod that never worked.
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 2)
	assert_array(weapon.available_attacks(unit)).contains([extra])
	assert_bool(_has_ability(unit, Abilities.Id.BRACE)).is_true()
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(before + 4)

# --- Which slots contribute ---

func test_an_unequipped_weapons_mods_grant_nothing() -> void:
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var before := unit.get_effective_stat(Stats.Stat.STR)

	var carried := WeaponInstance.make(_template())
	var abilities: Array[AbilityData] = [_ability(Abilities.Id.BRACE)]
	carried.fit(0, _mod({Stats.Stat.STR: 4}, abilities))
	# Deliberately never equipped and never installed: owning a weapon is not wielding it, the
	# same way get_effective_def reads the worn piece rather than everything carried.

	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(before)
	assert_bool(_has_ability(unit, Abilities.Id.BRACE)).is_false()

func test_an_installed_prosthetics_mods_grant_without_being_equipped() -> void:
	# A prosthetic is a LIMB, not held gear (UnitInstance.is_installed_prosthetic), so what is
	# bolted into it rides the body whether or not it is the thing being swung.
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.PROSTHETIC, 3)
	var arm := WeaponInstance.make(_template(WeaponData.WeaponType.PROSTHETIC))
	arm.limb_kind = WeaponData.LimbKind.ARM
	assert_bool(unit.unit_instance.install_prosthetic(UnitInstance.LimbSlot.ARM_L, arm)).is_true()
	unit.equipped_weapon = null

	var before := unit.get_effective_stat(Stats.Stat.STR)
	var abilities: Array[AbilityData] = [_ability(Abilities.Id.BRACE)]
	arm.fit(0, _mod({Stats.Stat.WIL: 2}, abilities))

	assert_bool(_has_ability(unit, Abilities.Id.BRACE)).is_true()
	assert_int(unit.get_effective_stat(Stats.Stat.WIL)).is_greater(0)
	# STR is read only to show the limb stage did not move underneath the WIL claim.
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(before)

func test_a_prosthetic_that_is_also_the_equipped_weapon_pays_out_once() -> void:
	# add_item auto-equips the first weapon-shaped equippable and a ProstheticWeaponInstance
	# qualifies, so one object can be BOTH the equipped weapon and a limb fitting. Counted twice,
	# its mods pay twice -- which is what Unit._mod_sources' dedupe exists to stop.
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.PROSTHETIC, 3)
	var arm := WeaponInstance.make(_template(WeaponData.WeaponType.PROSTHETIC))
	arm.limb_kind = WeaponData.LimbKind.ARM
	assert_bool(unit.unit_instance.install_prosthetic(UnitInstance.LimbSlot.ARM_R, arm)).is_true()
	unit.equipped_weapon = arm

	# Both roles really are filled by the one object -- without this the case could pass by the
	# prosthetic simply not being installed.
	assert_bool(unit.unit_instance.is_installed_prosthetic(arm)).is_true()
	assert_object(unit.get_equipped_weapon()).is_same(arm)

	var before := unit.get_effective_stat(Stats.Stat.WIL)
	arm.fit(0, _mod({Stats.Stat.WIL: 3}))
	assert_int(unit.get_effective_stat(Stats.Stat.WIL)).is_equal(before + 3)

func test_a_mod_grants_its_attack_only_to_the_weapon_it_is_fitted_to() -> void:
	# The declared asymmetry: abilities and stats describe the WIELDER and union across every
	# contributing weapon; an attack belongs to the weapon that fires it.
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.PROSTHETIC, 3)
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)

	var leg := WeaponInstance.make(_template(WeaponData.WeaponType.PROSTHETIC))
	leg.limb_kind = WeaponData.LimbKind.LEG
	assert_bool(unit.unit_instance.install_prosthetic(UnitInstance.LimbSlot.LEG_L, leg)).is_true()
	var kick := _attack("Piston Kick")
	var granted: Array[WeaponAttackData] = [kick]
	leg.fit(0, _mod({}, [], granted))

	var sword := WeaponInstance.make(_template())
	unit.equipped_weapon = sword

	assert_array(sword.available_attacks(unit)).not_contains([kick])
	assert_array(leg.available_attacks(unit)).contains([kick])

# --- The live-read and the gate-blindness the chain depends on ---

func test_unequipping_takes_the_grants_with_it() -> void:
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var weapon := WeaponInstance.make(_template())
	var abilities: Array[AbilityData] = [_ability(Abilities.Id.BRACE)]
	weapon.fit(0, _mod({Stats.Stat.STR: 4}, abilities))
	unit.equipped_weapon = weapon
	var armed := unit.get_effective_stat(Stats.Stat.STR)

	unit.equipped_weapon = null
	assert_bool(_has_ability(unit, Abilities.Id.BRACE)).is_false()
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(armed - 4)

func test_a_mod_granting_con_does_not_open_an_armor_wear_gate() -> void:
	# THE property both _enforce_gear_gates clauses depend on: wear gates read get_body_stat, so
	# no gear can unlock gear. Break it and the strip stops being a single pass with no cascade
	# (ArmorData.can_equip's own header: do not "simplify" this into get_effective_stat).
	var unit := _wielder()
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var weapon := WeaponInstance.make(_template())
	unit.equipped_weapon = weapon

	var gate := unit.get_body_stat(Stats.Stat.CON) + 3
	var armor := ArmorData.new()
	armor.stat_minimums[Stats.Stat.CON] = gate
	assert_bool(armor.can_equip(unit)).is_false()

	weapon.fit(0, _mod({Stats.Stat.CON: 5}))
	# The mod really did move the effective stat past the gate...
	assert_int(unit.get_effective_stat(Stats.Stat.CON)).is_greater_equal(gate)
	# ...and the gate still refuses, because it never reads gear.
	assert_bool(armor.can_equip(unit)).is_false()
