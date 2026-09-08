# Which catalog row the Unit Editor opens a gear slot on -- UnitEditorTool._entry_matches, and the
# "holds: X" label it falls back to when nothing matches (#80).
#
# Rewritten by #835. The catalog now offers DERIVED generics, whose display_name is empty on purpose
# (Item.shown_name reads the template's through), so the old name compare asked "" == "" and then
# refused itself on its own non-empty guard: a held generic read as "(empty)" beside a "holds:"
# label, which is the very symptom that label was typed for.
#
# The rule is INDISTINGUISHABILITY -- same template, same mods, same spaces -- never agreeing names.
# Everything here is built ad hoc (tests/README.md rule 4); no case reads a .tres.
extends GdUnitTestSuite


func _tool() -> UnitEditorTool:
	return auto_free(UnitEditorTool.new()) as UnitEditorTool


func _template(family: WeaponData.WeaponType = WeaponData.WeaponType.CHAINSWORD) -> WeaponData:
	var t := WeaponData.new()
	t.weapon_type = family
	t.main_attack = WeaponAttackData.new()
	t.mod_spaces = [1, 2, 3] as Array[int]
	return t


# Straight at the live array rather than through fit(): these cases ask what MATCHING does, and
# fit() would first apply the family and capacity rules, which are a different question.
func _with_mod(weapon: WeaponInstance, index: int) -> WeaponInstance:
	weapon.space(index).append(WeaponModData.new())
	return weapon


func test_a_plain_instance_matches_the_generic_entry_it_came_from() -> void:
	var template := _template()
	var entry := WeaponInstance.make(template)
	var held := WeaponInstance.make(template)
	assert_bool(_tool()._entry_matches(entry, held)).override_failure_message(
			"a held plain weapon did not match its own generic -- the slot would read '(empty)'"
			).is_true()


# The mods half is not optional: a fitted Gun and a plain Carbine share a template, so matching on
# the template alone would open the picker on one while the unit held the other.
func test_a_fitted_instance_does_not_match_the_plain_entry() -> void:
	var template := _template()
	var entry := WeaponInstance.make(template)
	var held := _with_mod(WeaponInstance.make(template), 0)
	assert_bool(_tool()._entry_matches(entry, held)).override_failure_message(
			"a modded weapon matched the plain entry -- the picker would offer one for the other"
			).is_false()


# THE shape a shape-comparison would fail. `spaces` grows lazily through space(), so a weapon any
# panel has already drawn carries [[], [], []] where a freshly derived one still carries [].
func test_a_lazily_grown_held_weapon_still_matches_an_ungrown_entry() -> void:
	var template := _template()
	var entry := WeaponInstance.make(template)
	var held := WeaponInstance.make(template)
	for i in held.space_count():
		held.space(i)   # what drawing the fitting card does
	assert_int(held.spaces.size()).is_greater(entry.spaces.size())
	assert_bool(_tool()._entry_matches(entry, held)).override_failure_message(
			"growing a weapon's spaces stopped it matching the entry it came from"
			).is_true()


# The latent half of #833's vroom collision: the name compare this replaced let two unrelated
# weapons match each other purely because the dev had named them the same.
func test_two_weapons_sharing_a_name_do_not_match_across_templates() -> void:
	var entry := WeaponInstance.make(_template(WeaponData.WeaponType.CHAINSWORD))
	var held := WeaponInstance.make(_template(WeaponData.WeaponType.CARBINE))
	entry.display_name = "Chainsword"
	held.display_name = "Chainsword"
	assert_bool(_tool()._entry_matches(entry, held)).override_failure_message(
			"two weapons matched on a shared name alone -- they are different weapons"
			).is_false()


# The branch #835 did not touch, kept because a scenario may still hold a template-built one-off.
func test_a_template_entry_still_matches_an_instance_built_on_it() -> void:
	var template := _template()
	assert_bool(_tool()._entry_matches(template, WeaponInstance.make(template))).is_true()
	assert_bool(_tool()._entry_matches(_template(), WeaponInstance.make(template))).is_false()
