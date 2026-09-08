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


# Through fit(), which is the one door that GROWS spaces since #624 -- appending to space() reaches a
# throwaway on a weapon holding nothing, so a mod put on that way is silently not fitted and every
# case below would compare two empty weapons and pass for the wrong reason.
func _with_mod(weapon: WeaponInstance, index: int) -> WeaponInstance:
	assert_bool(weapon.fit(index, WeaponModData.new())).is_true()
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


# THE shape a shape-comparison would fail. #624 gave "nothing fitted" ONE spelling -- `[]`, with a
# read no longer growing the array -- but an instance saved BEFORE it carries [[], [], []], which is
# exactly the state that ticket's own copy_for_grant normalization exists for. Matching has to be
# immune to the shape either way, or a weapon out of an old save reads as "(empty)" in its own slot.
func test_a_weapon_in_the_pre_624_spaces_form_still_matches_its_entry() -> void:
	var template := _template()
	var entry := WeaponInstance.make(template)
	var held := WeaponInstance.make(template)

	var old_form: Array[Array] = []
	for i in template.mod_spaces.size():
		var empty: Array[WeaponModData] = []
		old_form.append(empty)
	held.spaces = old_form   # what a .tres written before #624 holds

	assert_int(held.spaces.size()).is_greater(entry.spaces.size())
	assert_bool(_tool()._entry_matches(entry, held)).override_failure_message(
			"a weapon in the pre-#624 spaces form stopped matching the entry it came from"
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
