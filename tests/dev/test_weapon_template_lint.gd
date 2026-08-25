# WeaponTemplateLint (#486) -- "can this authored template actually become a weapon?" -- plus the
# CI sweep the rule exists for, over every template on disk. AttackLint's suite shape.
#
# The sweep and the two content guards below LOAD real .tres on purpose (tests/README.md rule 4's
# declared shape for a content law, as test_attack_lint.gd already does). They still respect the
# content razor: nothing here asserts what a template CONTAINS -- not a space count, not a
# capacity, not a family. They claim only that the shipped set passes its own rule, and that what
# a file writes is what loads back.
extends GdUnitTestSuite


func _template(family: WeaponData.WeaponType = WeaponData.WeaponType.CHAINSWORD) -> WeaponData:
	var t := WeaponData.new()
	t.weapon_type = family
	t.main_attack = WeaponAttackData.new()
	return t


func _texts(findings: Array[Dictionary]) -> String:
	var joined := ""
	for finding in findings:
		joined += finding["text"] + " "
	return joined


# ==============================================================================
#  The rules
# ==============================================================================

func test_a_complete_template_reports_nothing() -> void:
	assert_array(WeaponTemplateLint.check(_template())).is_empty()


# The fault the lint exists for: make() answers an unmapped family with null, so the template
# lists everywhere and produces nothing.
func test_an_unset_family_blocks() -> void:
	var findings := WeaponTemplateLint.check(_template(WeaponData.WeaponType.NONE))
	assert_array(findings).is_not_empty()
	assert_int(findings[0]["severity"]).is_equal(WeaponTemplateLint.Severity.BLOCKS)
	assert_str(_texts(findings)).contains("family")


# DEGRADES, matching the Attack Editor's Weapon Families mode rather than contradicting it.
func test_a_missing_main_attack_degrades_rather_than_blocks() -> void:
	var t := _template()
	t.main_attack = null
	var findings := WeaponTemplateLint.check(t)
	assert_array(findings).is_not_empty()
	assert_int(findings[0]["severity"]).is_equal(WeaponTemplateLint.Severity.DEGRADES)


# A capacity below 1 refuses every mod including a size-1 one, leaving a space the fitting UI
# still draws and nothing can go into. The editor's SpinBox floors at 1, so this covers the door
# the lint does not own -- a hand-edited .tres.
func test_a_space_too_small_for_any_mod_degrades_and_names_which() -> void:
	var t := _template()
	t.mod_spaces = [1, 0, 3]
	var findings := WeaponTemplateLint.check(t)
	assert_array(findings).is_not_empty()
	assert_int(findings[0]["severity"]).is_equal(WeaponTemplateLint.Severity.DEGRADES)
	assert_str(_texts(findings)).contains("Space 2")


# A template with NO spaces is a legal design (predetermined power, no customization), not a
# mistake -- a check that fires on a deliberate choice trains you to ignore the panel.
func test_a_template_with_no_spaces_at_all_is_not_a_fault() -> void:
	var t := _template()
	t.mod_spaces = []
	assert_array(WeaponTemplateLint.check(t)).is_empty()


func test_a_null_template_answers_empty_rather_than_erroring() -> void:
	assert_array(WeaponTemplateLint.check(null)).is_empty()


# ==============================================================================
#  The sweep over shipped content
# ==============================================================================

# Every template on disk must at least be carryable. A DEGRADES finding is deliberately tolerated:
# a stub family awaiting real content is a known state of this project, and failing CI over one
# would make the tier meaningless.
func test_no_shipped_template_is_uncarryable() -> void:
	var broken: Array[String] = []
	var templates := WeaponCatalog.get_templates()
	for name in templates:
		for finding in WeaponTemplateLint.check(templates[name]):
			if finding["severity"] == WeaponTemplateLint.Severity.BLOCKS:
				broken.append("%s: %s" % [name, finding["text"]])
	assert_array(broken).is_empty()
	assert_int(templates.size()).is_greater(0)   # nothing scanned: this sweep proves nothing


# ==============================================================================
#  The #486 migration guards
# ==============================================================================

# space_1/2/3 became one `spaces` array, and a renamed .tres key is dropped SILENTLY on load --
# the file keeps its text, the mods just stop arriving. So: a variant whose FILE writes a spaces
# line must load with mods actually in it. Reading the file's own text rather than pinning a mod
# count is what keeps this blind to what the dev authors (the content razor).
func test_a_saved_variants_fitted_mods_survive_the_load() -> void:
	var checked := 0
	var empty: Array[String] = []
	var saved := WeaponCatalog.get_saved()
	for name in saved:
		var weapon: WeaponInstance = saved[name]
		var text := FileAccess.get_file_as_string(weapon.resource_path)
		if not text.contains("\nspaces = "):
			continue
		checked += 1
		var total := 0
		for i in range(weapon.space_count()):
			total += weapon.space(i).size()
		if total == 0:
			empty.append(name)
	assert_array(empty).is_empty()
	assert_int(checked).is_greater(0)   # no shipped variant carries a fitted mod: this guard proves nothing


# The other half of the fireball rule. .tres omits properties at their default, so a template that
# never wrote mod_spaces silently inherits whatever the default becomes -- which is exactly how a
# prototype forced to one space would have quietly gained two. The claim is that every template
# SAYS what its spaces are, not what any of them says.
func test_every_prototype_writes_its_mod_spaces_rather_than_inheriting_the_default() -> void:
	var silent: Array[String] = []
	var prototypes := WeaponCatalog.get_prototypes()
	for name in prototypes:
		var template: WeaponData = prototypes[name]
		if not FileAccess.get_file_as_string(template.resource_path).contains("\nmod_spaces = "):
			silent.append(name)
	assert_array(silent).is_empty()
	assert_int(prototypes.size()).is_greater(0)   # nothing in Prototypes/: this guard proves nothing
