# #745: what a piece of gear TELLS you, and the two ways that can go wrong.
#
# The derived half was largely already built -- ArmorData.mechanical_text (#44),
# TransmutationData.mechanical_text (#166) and WeaponInstance.attack_detail (#485) all read their
# numbers at display time. What NOTHING pinned is the property those tickets exist for: that a
# retuned value re-words the readout. A snapshot of expected strings pins the exact opposite, so
# every case here CHANGES a number and asserts the text followed it.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func _wielder(overrides: Dictionary = {}) -> Unit:
	return H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, overrides, false)


func _weapon(power: int) -> WeaponInstance:
	var attack := WeaponAttackData.new()
	attack.display_name = "Test Swing"
	attack.power = power
	attack.scaling_blend = {Stats.Stat.STR: Stats.BLEND_TOTAL}
	var template := WeaponData.new()
	template.display_name = "Test Blade"
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = attack
	return WeaponInstance.make(template)


# THE property, on the surface that carries the most authored numbers. Retuning a mod must reword
# every readout that mentions it -- which is what makes hand-writing "Adds 2 power" into a
# description the trap #745 exists to prevent.
func test_a_retuned_mod_rewords_the_attack_readout() -> void:
	var unit := _wielder()
	var weapon := _weapon(10)
	unit.add_item(weapon)
	var attack: WeaponAttackData = weapon.template.main_attack

	var mod := WeaponModData.new()
	mod.display_name = "Test Mod"
	mod.power_delta = 3
	assert_bool(weapon.fit(0, mod)).override_failure_message("fixture: the mod did not fit").is_true()
	var before := weapon.attack_detail(unit, attack)

	mod.power_delta = 9
	var after := weapon.attack_detail(unit, attack)
	assert_str(after).override_failure_message(
		"the readout did not follow the mod's power: %s" % after).is_not_equal(before)
	assert_str(after).override_failure_message(
		"the retuned power is not in the readout: %s" % after).contains("19")


# Armor's own itemisation, same property one domain over: the DEF line is derived from def_power and
# the wearer's CON, so moving either moves the sentence.
func test_a_retuned_plate_rewords_its_own_def_line() -> void:
	var plate := ArmorData.new()
	plate.display_name = "Test Plate"
	plate.def_power = 2
	var wearer := _wielder({Stats.Stat.CON: 6})

	var before := plate.mechanical_text(wearer)
	plate.def_power = 5
	assert_str(plate.mechanical_text(wearer)).override_failure_message(
		"the DEF readout ignored the piece's own power").is_not_equal(before)


# --- the flavour half ------------------------------------------------------------------------

# THE WIRE #745's body got wrong, and the reason the content pass could not have worked without it:
# WeaponInstance.make() has never copied its template's description, and copy_equippable only copies
# instance-to-instance -- so authoring a line on a family reached nothing a player could hover.
# describe() reads THROUGH, so re-wording a family re-words every weapon built on it, saved scenarios
# included, with no migration.
func test_a_weapon_inherits_its_familys_description_and_may_override_it() -> void:
	var weapon := _weapon(10)
	weapon.template.description = "A family line."
	assert_str(weapon.description).override_failure_message(
		"the instance stores a copy, so re-wording the family would not reach it").is_empty()
	assert_str(weapon.describe()).override_failure_message(
		"a weapon carrying no wording of its own did not fall through to its family").is_equal(
		"A family line.")

	weapon.template.description = "Re-worded."
	assert_str(weapon.describe()).override_failure_message(
		"the read-through is a copy after all").is_equal("Re-worded.")

	# ...and a named variant with a story of its own still wins.
	weapon.description = "This one has a name."
	assert_str(weapon.describe()).is_equal("This one has a name.")


# The content pass, and the ONE law over it: flavour never states a number, because a number in prose
# goes stale while the data stays right (#552's shape, in a different field). Asserted over every
# shipped family rather than the seven this ticket wrote, so the next one authored is covered too.
func test_no_shipped_weapon_family_states_a_number_in_its_flavour() -> void:
	# Every authored weapon-shaped file, not one folder: get_editable() serves the saved VARIANTS
	# alone, so a law pointed there sweeps nothing and the guard below is what said so.
	var described := 0
	var catalog: Dictionary = {}
	catalog.merge(WeaponCatalog.get_family_bases())
	catalog.merge(WeaponCatalog.get_prototypes())
	catalog.merge(WeaponCatalog.get_saved())
	for name: String in catalog:
		var template := catalog[name] as Item
		if template == null or template.description == "":
			continue
		described += 1
		assert_bool(template.description.contains("%")).override_failure_message(
			"%s's description states a percentage, which the data already answers" % name).is_false()
		var digits := 0
		for c: String in template.description:
			if c.is_valid_int():
				digits += 1
		assert_int(digits).override_failure_message(
			"%s's description carries digits, so retuning the weapon leaves its prose lying:\n%s"
			% [name, template.description]).is_equal(0)
	assert_int(described).override_failure_message(
		"no shipped family carries a description, so this law swept nothing").is_greater(0)
