# WeaponTemplateLint (#486) -- "can this authored template actually become a weapon?" -- plus the
# CI sweep the rule exists for, over every template on disk. AttackLint's suite shape.
#
# The sweep and the two content guards below LOAD real .tres on purpose (tests/README.md rule 4's
# declared shape for a content law, as test_attack_lint.gd already does). They still respect the
# content razor: nothing here asserts what a template CONTAINS -- not a space count, not a
# capacity, not a family. They claim only that the shipped set passes its own rule, and that what
# a file writes is what loads back.
#
# None of it may REQUIRE the dev to ship content of a given shape -- an absence of authored
# content is not a failure (tests/README.md rule 9, dev 2026-08-27). The sweeps grade whatever
# is on disk and pass vacuously on an empty one; the mechanism law owns a fixture instead.
extends GdUnitTestSuite

const FIXTURE_PATH := "user://__test_template_lint_variant.tres"


func after_test() -> void:
	if FileAccess.file_exists(FIXTURE_PATH):
		DirAccess.remove_absolute(FIXTURE_PATH)



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


# #590: a can_overwatch attack is watch-ONLY, so a main authored that way leaves the weapon with
# nothing to attack with -- BLOCKS, the same tier an unset family gets and for the same reason.
# Deliberately harsher than the missing-main rule above: a family with no main yet is a known
# intermediate state, while a main that exists and can never fire is finished and wrong.
func test_a_watch_only_main_blocks() -> void:
	var t := _template()
	t.main_attack.display_name = "Overwatch"
	t.main_attack.can_overwatch = true
	var findings := WeaponTemplateLint.check(t)
	assert_array(findings).is_not_empty()
	assert_int(findings[0]["severity"]).is_equal(WeaponTemplateLint.Severity.BLOCKS)
	assert_str(_texts(findings)).contains("Overwatch")


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


# ==============================================================================
#  The #486 migration guards
# ==============================================================================

# space_1/2/3 became one `spaces` array, and a renamed .tres key is dropped SILENTLY on load --
# the file keeps its text, the mods just stop arriving. So: a variant whose FILE writes a spaces
# line must load with mods actually in it. Reading the file's own text rather than pinning a mod
# count is what keeps this blind to what the dev authors (the content razor).
func test_a_saved_variants_fitted_mods_survive_the_load() -> void:
	var empty: Array[String] = []
	var saved := WeaponCatalog.get_saved()
	for name in saved:
		var weapon: WeaponInstance = saved[name]
		var text := FileAccess.get_file_as_string(weapon.resource_path)
		if not text.contains("\nspaces = "):
			continue
		var total := 0
		for i in range(weapon.space_count()):
			total += weapon.space(i).size()
		if total == 0:
			empty.append(name)
	assert_array(empty).is_empty()

# The mechanism the sweep above cannot reach on its own. space_1/2/3 became one `spaces` array,
# and a renamed .tres key is dropped SILENTLY on load -- the file keeps its text, the mods just
# stop arriving. The sweep sees that only while some shipped variant happens to carry a fitted mod,
# and DEMANDING one exist is what made deleting content a test failure (#597). So the law owns a
# fixture instead: authored here, written by the real writer, read back cold with CACHE_MODE_IGNORE
# and asserted not-same, or the round trip would just be reading the object it saved.
func test_a_fitted_mod_survives_a_save_and_load() -> void:
	var weapon := WeaponInstance.make(_template())
	var mod := WeaponModData.new()
	mod.display_name = "Fixture Mod"
	assert_bool(weapon.fit(0, mod)).is_true()
	assert_int(ResourceSaver.save(weapon, FIXTURE_PATH)).is_equal(OK)
	# The writer must put the key in the file, or the load below proves nothing about it.
	assert_str(FileAccess.get_file_as_string(FIXTURE_PATH)).contains("\nspaces = ")

	var loaded := ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as WeaponInstance
	assert_object(loaded).is_not_null()
	assert_object(loaded).is_not_same(weapon)
	assert_int(loaded.space(0).size()).is_equal(1)


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
