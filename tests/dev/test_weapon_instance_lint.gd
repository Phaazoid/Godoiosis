# WeaponInstanceLint (#837) -- "is this weapon's fitting still legal?" -- plus the CI sweep over every
# saved variant. WeaponTemplateLint's suite shape, one content type along.
#
# The four faults each have a case because the whole claim of the design is that ONE borrowed clause
# catches all four: the rule is fit_block_reason re-asked, so a case per fault is a case per clause
# the borrow reaches. If a fifth clause is added to fit_block_reason, this file is where it earns a
# case -- not the lint, which needs no edit for it.
#
# NOTE for falsifying anything here: a failing case aborts the rest of its own suite file, so a mutant
# that reds an early case hides every later one. Disable the earlier failure and re-run, one at a time.
extends GdUnitTestSuite


func _template(mod_spaces: Array[int] = [1, 2, 3], family: WeaponData.WeaponType = WeaponData.WeaponType.CHAINSWORD) -> WeaponData:
	var t := WeaponData.new()
	t.main_attack = WeaponAttackData.new()
	t.mod_spaces = mod_spaces
	t.weapon_type = family
	return t


func _mod(size: int = 1, name: String = "Test Mod") -> WeaponModData:
	var m := WeaponModData.new()
	m.size = size
	m.display_name = name
	return m


func _texts(weapon: WeaponInstance) -> Array[String]:
	var out: Array[String] = []
	for finding: Dictionary in WeaponInstanceLint.check(weapon):
		assert_int(finding["severity"]).override_failure_message(
			"every finding here is DEGRADES -- a BLOCKS would refuse the save that repairs it"
			).is_equal(WeaponInstanceLint.Severity.DEGRADES)
		out.append(finding["text"])
	return out


# ==============================================================================
#  Nothing to report
# ==============================================================================

# FIRST, and it carries more weight than it looks: fit_block_reason answers "already fitted to this
# weapon" for any mod that is on the weapon, so a probe that forgot to take the mod off would report
# EVERY legally fitted mod in the game. This is the case that says the probe works at all.
func test_a_legal_fitting_reports_nothing() -> void:
	var w := WeaponInstance.make(_template())
	assert_bool(w.fit(0, _mod(1))).is_true()
	assert_bool(w.fit(2, _mod(3))).is_true()
	assert_array(_texts(w)).is_empty()


# The tight case for the same thing: a mod occupying exactly its space's capacity. A probe that left
# the mod in place would double-count its size and report an overfill that is not there.
func test_a_mod_exactly_filling_its_space_is_legal() -> void:
	var w := WeaponInstance.make(_template([1, 2, 3]))
	assert_bool(w.fit(1, _mod(2))).is_true()
	assert_int(w.used_capacity(1)).is_equal(2)   # exactly the capacity -- the precondition, asserted
	assert_array(_texts(w)).is_empty()


func test_a_weapon_with_nothing_fitted_reports_nothing() -> void:
	assert_array(_texts(WeaponInstance.make(_template()))).is_empty()


func test_a_weapon_with_no_template_reports_nothing() -> void:
	assert_array(_texts(WeaponInstance.new())).is_empty()


# An unmapped family is the TEMPLATE's fault and WeaponTemplateLint BLOCKS it there. Asking anyway
# would deref make()'s null inside the probe, so this is a guard rather than a policy -- and stating
# it as a case is what stops someone "simplifying" the guard away.
func test_an_unmapped_family_is_left_to_the_template_lint() -> void:
	var w := WeaponInstance.make(_template())
	assert_bool(w.fit(0, _mod(1))).is_true()
	w.template.weapon_type = WeaponData.WeaponType.NONE   # what a retype to (none) leaves behind
	assert_array(_texts(w)).is_empty()
	assert_array(WeaponTemplateLint.check(w.template)).is_not_empty()   # ...and it IS reported, there


# ==============================================================================
#  The four faults a live template edit can produce
# ==============================================================================

# #837 ITSELF: press Remove on a mod space and whatever was in it is stranded past space_count().
# It is also the only one of the four that is UNREMOVABLE -- space_holding scans the spaces the
# template still has, so unfit can never reach it, which is why silence here costs the most.
func test_a_mod_stranded_past_a_removed_space_is_reported() -> void:
	var w := WeaponInstance.make(_template([1, 2, 3]))
	assert_bool(w.fit(2, _mod(3, "Line Sniper"))).is_true()

	w.template.mod_spaces.remove_at(2)   # exactly what the Prototype editor's Remove button does
	var texts := _texts(w)
	assert_int(texts.size()).is_equal(1)
	assert_str(texts[0]).contains("Line Sniper")
	assert_str(texts[0]).contains("Space 3 does not exist")


func test_a_mod_over_a_narrowed_capacity_is_reported() -> void:
	var w := WeaponInstance.make(_template([1, 2, 3]))
	assert_bool(w.fit(2, _mod(3, "Heavy Barrel"))).is_true()

	w.template.mod_spaces[2] = 1   # what dragging the capacity spinner down does
	var texts := _texts(w)
	assert_int(texts.size()).is_equal(1)
	assert_str(texts[0]).contains("Heavy Barrel")
	assert_str(texts[0]).contains("this needs")


func test_a_mod_whose_family_stopped_matching_is_reported() -> void:
	var w := WeaponInstance.make(_template([1, 2, 3]))
	var mod := _mod(1, "Chain Oiler")
	mod.family = WeaponData.WeaponType.CHAINSWORD
	assert_bool(w.fit(0, mod)).is_true()

	w.template.weapon_type = WeaponData.WeaponType.CARBINE   # a retype in the Prototype editor
	var texts := _texts(w)
	assert_int(texts.size()).is_equal(1)
	assert_str(texts[0]).contains("Chain Oiler")
	assert_str(texts[0]).contains("Chainsword only")


# The door refuses a second replacer, so this state can only arrive by hand -- which is exactly the
# case fit_block_reason's own comment says it is answering for, and base_main resolves it silently by
# taking the first.
#
# BOTH are reported, and that is the borrow being symmetric rather than a miscount: each is asked
# without itself and finds the other, so neither is "the offender". Naming only the loser would mean
# this lint restating base_main's first-in-space-order rule -- a second copy of the very thing the
# borrow exists to avoid -- and the useful sentence is that these two collide, not which one wins.
func test_a_second_main_replacer_is_reported() -> void:
	var w := WeaponInstance.make(_template([1, 2, 3]))
	var first := _mod(1, "Lob Shot Mod")
	first.replaces_main = WeaponAttackData.new()
	var second := _mod(1, "Scatter Mod")
	second.replaces_main = WeaponAttackData.new()
	assert_bool(w.fit(0, first)).is_true()
	# Hand-edited, since the door would have refused it: appended straight onto `spaces`, which is
	# what a .tres carrying two replacers loads as. Built as a typed local first -- an Array[Array]
	# refuses a typed array assigned into an index, and takes one appended.
	var second_space: Array[WeaponModData] = [second]
	w.spaces.append(second_space)

	var texts := _texts(w)
	assert_int(texts.size()).is_equal(2)
	assert_str("\n".join(texts)).contains("Lob Shot Mod")
	assert_str("\n".join(texts)).contains("Scatter Mod")
	assert_str(texts[0]).contains("replaces this weapon's main")


# The rule is BORROWED, so a finding must quote the model's own sentence rather than a second wording
# authored here. Asserted as an equality against fit_block_reason itself, or the two can drift.
func test_a_finding_quotes_the_models_own_refusal() -> void:
	var w := WeaponInstance.make(_template([1, 2, 3]))
	assert_bool(w.fit(2, _mod(3, "Line Sniper"))).is_true()
	w.template.mod_spaces.remove_at(2)

	var bare := WeaponInstance.make(w.template)
	assert_str(_texts(w)[0]).contains(bare.fit_block_reason(2, _mod(3)))


# ==============================================================================
#  The sweep over shipped content
# ==============================================================================

# Every saved variant on disk must be wearing a legal fitting. The bigger population -- the 100-odd
# weapons embedded in Scenarios/ -- is swept by tests/flow/test_scenario_load_integrity.gd, where
# those files are already loaded; the rule is one, the SCOPE stays at each caller (#150's precedent).
func test_no_saved_variant_wears_an_illegal_fitting() -> void:
	var saved := WeaponCatalog.get_saved()
	assert_int(saved.size()).override_failure_message(
		"the variant scan found nothing, so this sweep proves nothing").is_greater(0)

	var problems: Array[String] = []
	for name in saved:
		var weapon: WeaponInstance = saved[name]
		for finding: Dictionary in WeaponInstanceLint.check(weapon):
			problems.append("%s: %s" % [name, finding["text"]])
	assert_array(problems).is_empty()
