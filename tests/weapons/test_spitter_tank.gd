# Chemical Spitter's tank (#97, the seventh and last family signature). What this suite owns is the
# three things the family invented and nothing else invents:
#
#   1. INJECTION is the first rearm in the game that CONSUMES INVENTORY, which is why the reload
#      seam now takes a wielder at all;
#   2. the SUBSTITUTION -- an attack authors what it becomes while the tank is hot, and
#      effective_main swaps it in, which is the single point the whole feature enters the pipeline;
#   3. the SPEND, threaded across a resolve pass so reactive fire cannot double-draw one charge.
#
# The shared family properties (state does not survive a grant copy, two instances are independent,
# verbs do not leak) live in test_weapon_family_seam.gd over all seven and are deliberately not
# repeated here.
#
# NOTHING HERE PINS THE AUTHORED GEOMETRY. The charged form's range is content the dev tunes in the
# Attack Editor, and its stamp belongs to #808's cone -- so every case asserts on IDENTITY ("is
# effective_main the empowered form") rather than on a number the next content pass will move.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const SPITTER_ELEMENT := Elemental.Element.CORROSION


# A spitter-shaped template: an ordinary main that authors an empowered form. The baseline is a
# REGULAR attack (dev, 2026-09-06) -- materia supercharges it, it is not a diminished thing -- so
# both forms carry real power and the charged one differs by reach.
func _spitter_template() -> WeaponData:
	var charged := WeaponAttackData.new()
	charged.display_name = "Pressurised Spray"
	charged.elemental_damage_type = SPITTER_ELEMENT
	charged.power = 7

	var spray := WeaponAttackData.new()
	spray.display_name = "Spray"
	spray.elemental_damage_type = SPITTER_ELEMENT
	spray.power = 4
	spray.empowered_form = charged

	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHEMICAL_SPITTER
	t.main_attack = spray
	return t


func _spitter() -> ChemicalSpitterWeaponInstance:
	return WeaponInstance.make(_spitter_template()) as ChemicalSpitterWeaponInstance


func _vial(element: Elemental.Element, alkahest: bool = false) -> VialData:
	var v := VialData.new()
	v.element = element
	v.is_alkahest = alkahest
	v.display_name = "Vial of Alkahest" if alkahest else Elemental.display_name(element)
	return v


# A unit holding a spitter, plus whatever vials the case wants in its inventory.
func _wielder(vials: Array = []) -> Unit:
	var unit := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	unit.equipped_weapon = _spitter()
	for v: VialData in vials:
		unit.add_item(v)
	return unit


func _tank(unit: Unit) -> ChemicalSpitterWeaponInstance:
	return unit.get_equipped_weapon() as ChemicalSpitterWeaponInstance


# --- 1. the injection ---

func test_a_spitter_starts_empty_and_fires_its_baseline() -> void:
	# Empty rather than full is the design: a mission's first injection is a real decision about a
	# scarce item. And the whole of the one law -- an empty tank refuses NOTHING.
	var unit := _wielder()
	assert_int(_tank(unit).charges).is_equal(0)
	assert_bool(_tank(unit).is_supercharged()).is_false()
	assert_object(unit.get_default_attack()).is_same(_tank(unit).template.main_attack)
	assert_bool(unit.can_fire_default_attack()).is_true()


func test_injection_refuses_with_no_matching_vial_and_says_which_reason() -> void:
	# The two refusals are DIFFERENT sentences on purpose: a hidden verb cannot tell them apart,
	# which is the whole reason the row lists greyed.
	var empty_handed := _wielder()
	assert_str(empty_handed.reload_block_reason()).is_equal("No matching vial to inject.")

	var wrong_element := _wielder([_vial(Elemental.Element.FIRE)])
	assert_str(wrong_element.reload_block_reason()).is_equal("No matching vial to inject.")

	var right := _wielder([_vial(SPITTER_ELEMENT)])
	assert_str(right.reload_block_reason()).is_empty()
	right.reload_weapon()
	assert_str(right.reload_block_reason()).is_equal("The tank is full.")


func test_injecting_consumes_the_vial_out_of_the_right_slot() -> void:
	# The first rearm in the game that spends inventory. The SLOT matters: clearing the wrong one
	# would silently destroy other gear, and a unit carrying six things is the normal case.
	var wrong := _vial(Elemental.Element.FIRE)
	var right := _vial(SPITTER_ELEMENT)
	var unit := _wielder([wrong, right])
	var carried_before := unit.inventory.count(null)

	unit.reload_weapon()

	assert_int(_tank(unit).charges).is_equal(ChemicalSpitterWeaponInstance.TANK_SIZE)
	assert_bool(unit.inventory.has(right)).override_failure_message(
		"the injected vial is still in the inventory -- the rearm did not consume it").is_false()
	assert_bool(unit.inventory.has(wrong)).override_failure_message(
		"injecting took the WRONG vial out of the bag").is_true()
	assert_int(unit.inventory.count(null)).is_equal(carried_before + 1)


func test_alkahest_charges_a_spitter_no_ordinary_vial_matches() -> void:
	# Canon's word is that alkahest matches ANYTHING, and corrosion is the case that tests it: it
	# is not a sigil, so granted_elements() (which answers about CASTS, where only sigils carry
	# aura) never lists it. matches() and granted_elements() disagree in exactly this one cell, and
	# both are right -- an alkahest vial charges this weapon and still empowers no corrosion cast.
	var unit := _wielder([_vial(Elemental.Element.NONE, true)])
	assert_str(unit.reload_block_reason()).is_empty()
	unit.reload_weapon()
	assert_int(_tank(unit).charges).is_equal(ChemicalSpitterWeaponInstance.TANK_SIZE)

	var alkahest := _vial(Elemental.Element.NONE, true)
	assert_bool(alkahest.matches(SPITTER_ELEMENT)).is_true()
	assert_bool(alkahest.granted_elements().has(SPITTER_ELEMENT)).override_failure_message(
		"alkahest now grants CORROSION to a caster -- empowerment is aura-scaled and corrosion has"
		+ " no aura, so this would hand out an empowerment that scales nothing").is_false()


func test_an_ordinary_vial_is_preferred_over_alkahest() -> void:
	# Alkahest is authored sparingly and answers for everything, so spending it while an ordinary
	# vial sat in the next slot is the one outcome nobody would choose. Order-independent: the
	# alkahest is carried FIRST, so a naive first-match walk fails this.
	var alkahest := _vial(Elemental.Element.NONE, true)
	var vitriol := _vial(SPITTER_ELEMENT)
	var unit := _wielder([alkahest, vitriol])

	unit.reload_weapon()

	assert_bool(unit.inventory.has(alkahest)).override_failure_message(
		"the rare universal vial was spent while an ordinary match was carried").is_true()
	assert_bool(unit.inventory.has(vitriol)).is_false()


func test_the_verb_is_named_for_the_family() -> void:
	assert_str(_wielder().reload_label()).is_equal("Tank Injection")


func test_the_weapon_slice_opens_even_with_nothing_to_inject() -> void:
	# The #97 ruling, and the case it was made for: a spitter with an empty tank and no vial has no
	# actionable verb at all, so a slice gated on availability hides the greyed row that explains
	# exactly that. It opens on OWNING the verb instead.
	var unit := _wielder()
	assert_bool(unit.can_reload_weapon()).is_false()
	assert_bool(unit.has_weapon_actions()).override_failure_message(
		"the Weapon Action slice is shut, so 'Tank Injection -- no matching vial' is unreachable"
		).is_true()


# --- 2. the substitution ---

func test_a_hot_tank_makes_the_empowered_form_the_main() -> void:
	var unit := _wielder([_vial(SPITTER_ELEMENT)])
	var weapon := _tank(unit)
	var base := weapon.template.main_attack
	var charged := base.empowered_form

	assert_object(weapon.effective_main(unit)).is_same(base)
	unit.reload_weapon()
	assert_object(weapon.effective_main(unit)).override_failure_message(
		"a full tank did not swap the main for its empowered form").is_same(charged)

	# ...and every surface that reads the main follows, which is the point of substituting at ONE
	# place: the default aim and the counter are not told about tanks.
	assert_object(unit.get_default_attack()).is_same(charged)
	assert_object(unit.get_counter_attack()).is_same(charged)

	weapon.charges = 0
	assert_object(weapon.effective_main(unit)).is_same(base)


func test_the_base_form_is_never_offered_as_a_secondary_attack() -> void:
	# While the tank is hot the main IS the charged form, so filtering the submenu by
	# `!= effective_main` would list the BASE spray beside it as though it were a second attack.
	var unit := _wielder([_vial(SPITTER_ELEMENT)])
	unit.reload_weapon()
	var weapon := _tank(unit)

	for attack: AttackData in weapon.secondary_attacks(unit):
		assert_object(attack).override_failure_message(
			"the base form is listed as a secondary attack while the tank is hot").is_not_same(
			weapon.template.main_attack)


func test_a_weapon_with_no_empowered_form_is_untouched_by_a_charge() -> void:
	# The field is general on WeaponAttackData and inert everywhere it is unauthored, which is
	# every attack in the game but this one.
	var unit := _wielder()
	var weapon := _tank(unit)
	weapon.template.main_attack.empowered_form = null
	weapon.charges = ChemicalSpitterWeaponInstance.TANK_SIZE

	assert_object(weapon.effective_main(unit)).is_same(weapon.template.main_attack)


func test_a_mod_fitted_to_the_main_still_reaches_the_charged_form() -> void:
	# _mods_for keys on "is this the main", and the substitution made that answer depend on the
	# TANK for the first time. Asked of effective_main alone, a stamp of the other form silently
	# loses every MAIN_ATTACK mod -- its power, its element, its kind, its knockback.
	var unit := _wielder()
	var weapon := _tank(unit)
	var charged := weapon.template.main_attack.empowered_form

	var mod := WeaponModData.new()
	mod.display_name = "Test Bore"
	mod.applies_to = WeaponModData.AppliesTo.MAIN_ATTACK
	mod.power_delta = 5
	mod.family = WeaponData.WeaponType.CHEMICAL_SPITTER
	weapon.fit(0, mod)

	# Measured against an UNMODDED twin rather than against raw power: base_damage also folds in
	# the stat blend, so subtracting `power` alone would be comparing against the wrong number.
	var plain := _tank(_wielder())
	var base_gain := weapon.base_damage(unit, weapon.template.main_attack) \
			- plain.base_damage(unit, plain.template.main_attack)
	weapon.charges = ChemicalSpitterWeaponInstance.TANK_SIZE
	plain.charges = ChemicalSpitterWeaponInstance.TANK_SIZE
	var charged_gain := weapon.base_damage(unit, charged) \
			- plain.base_damage(unit, plain.template.main_attack.empowered_form)

	assert_int(base_gain).override_failure_message(
		"the mod does not reach the BASE form either -- the fixture is wrong, not the rule"
		).is_equal(5)
	assert_int(charged_gain).override_failure_message(
		"a mod fitted to the main stopped applying once the tank made the charged form the main"
		).is_equal(5)


func test_both_forms_answer_as_the_main() -> void:
	var unit := _wielder()
	var weapon := _tank(unit)
	assert_bool(weapon.is_main_form(unit, weapon.template.main_attack)).is_true()
	assert_bool(weapon.is_main_form(unit, weapon.template.main_attack.empowered_form)).is_true()
	assert_bool(weapon.is_main_form(unit, WeaponAttackData.new())).is_false()


# --- 3. the spend ---

func test_firing_the_charged_form_spends_exactly_one_charge() -> void:
	var unit := _wielder([_vial(SPITTER_ELEMENT)])
	unit.reload_weapon()
	var weapon := _tank(unit)
	var before := weapon.charges

	weapon.spend_charge()

	assert_int(weapon.charges).is_equal(before - 1)
	assert_bool(weapon.is_supercharged()).is_true()   # TANK_SIZE > 1, so one shot is not the lot


func test_the_tank_never_goes_negative() -> void:
	var weapon := _spitter()
	weapon.spend_charge()
	assert_int(weapon.charges).is_equal(0)


func test_the_tank_gates_nothing() -> void:
	# The one law, stated as a case: materia never gates function. An empty tank must leave every
	# attack fireable -- if this ever reds, the tank has been wired through the readiness seam.
	var unit := _wielder()
	var weapon := _tank(unit)
	assert_bool(weapon.is_attack_fireable(weapon.template.main_attack)).is_true()
	assert_bool(unit.can_fire_default_attack()).is_true()
	assert_bool(unit.attack_source_can_counter()).is_true()


func test_status_text_says_what_the_player_decides_on() -> void:
	var unit := _wielder([_vial(SPITTER_ELEMENT)])
	assert_str(_tank(unit).status_text()).contains("empty")
	unit.reload_weapon()
	assert_str(_tank(unit).status_text()).contains(str(ChemicalSpitterWeaponInstance.TANK_SIZE))
