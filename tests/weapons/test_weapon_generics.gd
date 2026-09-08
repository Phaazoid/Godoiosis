# The DERIVED generic (#835): a plain, unfitted instance of every weapon template, so one of each
# weapon is always pickable without anyone authoring a file for it. The old bridge was a hand-saved
# mod-less variant per template -- content carrying no authored decision, which drifted (the file
# froze a copy of the template's name) and collided (#833's vroom shadowing).
#
# These LOAD real .tres on purpose -- tests/README.md rule 4's declared shape for a content law, as
# test_weapon_template_lint.gd already does: the catalog IS the subject, so a template built ad
# hoc would exercise nothing. Every case SWEEPS whatever is on disk and passes vacuously on an
# empty scan -- the claim is about the derivation, never which weapons exist (rule 9).
extends GdUnitTestSuite


func _templates() -> Dictionary:
	var found := {}
	for dir: String in [WeaponCatalog.MAIN_VARIETIES_DIR, WeaponCatalog.PROTOTYPE_DIR]:
		var scanned := ResourceCatalog.by_file(dir, WeaponData)
		for file: String in scanned:
			found[file] = scanned[file]
	return found


# The derivation itself, keyed by FILE because a generic's identity IS its template file (#812).
# SHARES the template rather than copying it: a copy severs the live sync the whole model rests on,
# so retuning a family would stop reaching the generic it is the generic OF.
func test_every_template_yields_a_generic_that_shares_it() -> void:
	var derived := WeaponCatalog.generics()
	var templates := _templates()
	for file: String in templates:
		assert_bool(derived.has(file)).override_failure_message(
				"'%s' is a template on disk with no derived generic -- it cannot be picked" % file
				).is_true()
		var generic: WeaponInstance = derived[file]
		var template: WeaponData = templates[file]
		assert_object(generic.template).override_failure_message(
				"the generic for '%s' copied its template instead of sharing it" % file
				).is_same(template)


func test_a_generic_arrives_with_nothing_fitted() -> void:
	var derived := WeaponCatalog.generics()
	for file: String in derived:
		var generic: WeaponInstance = derived[file]
		var total := 0
		for fitted: Array in generic.spaces:
			total += fitted.size()
		assert_int(total).override_failure_message(
				"the generic for '%s' arrived with mods already fitted" % file).is_equal(0)


# It carries no name of its OWN -- Item.shown_name reads the template's through. That is what keeps
# a family rename reaching its generic, which is exactly what the hand-authored files stopped doing.
func test_a_generic_reads_its_name_through_rather_than_freezing_one() -> void:
	var derived := WeaponCatalog.generics()
	var templates := _templates()
	for file: String in derived:
		var generic: WeaponInstance = derived[file]
		assert_str(generic.display_name).override_failure_message(
				"the generic for '%s' froze a name of its own" % file).is_equal("")
		var template: WeaponData = templates[file]
		assert_str(generic.shown_name()).is_equal(template.display_name)


# The grant door, and what makes offering a derived entry safe at all: a unit receives its OWN
# instance while the shared template travels un-copied. If the catalog's copy were handed out
# directly, two units picking "Carbine" would fit mods into one weapon.
func test_granting_a_generic_hands_back_an_independent_instance() -> void:
	var derived := WeaponCatalog.generics()
	for file: String in derived:
		var generic: WeaponInstance = derived[file]
		var granted := WeaponCatalog.instantiate_entry(generic) as WeaponInstance
		assert_object(granted).override_failure_message(
				"granting the generic for '%s' produced nothing" % file).is_not_null()
		assert_object(granted).is_not_same(generic)
		assert_object(granted.template).override_failure_message(
				"granting '%s' deep-copied the shared template" % file).is_same(generic.template)

		if granted.space_count() > 0:
			# Straight at the live array on purpose: this asks about SHARING, and fit() would first
			# apply the family and capacity rules, which are a different question.
			granted.space(0).append(WeaponModData.new())
			assert_int(generic.space(0).size()).override_failure_message(
					"fitting the grant of '%s' reached the catalog's own copy" % file).is_equal(0)


# The picker's view. Derived and still unreachable is the gap #835 exists to close, so the named
# list every editor reads has to carry one entry per template.
func test_get_editable_offers_every_template_by_name() -> void:
	var offered := WeaponCatalog.get_editable()
	var templates := _templates()
	for file: String in templates:
		var template: WeaponData = templates[file]
		var expected: String = template.display_name if template.display_name != "" else file
		assert_bool(offered.has(expected)).override_failure_message(
				"'%s' is authored on disk but no picker can offer it" % expected).is_true()


# An AUTHORED variant of that name keeps the row -- the specific thing beats the fallback -- which
# is what lets the hand-made generics be deleted later without the list changing underneath.
func test_an_authored_variant_is_not_displaced_by_a_generic() -> void:
	var offered := WeaponCatalog.get_editable()
	var saved := WeaponCatalog.get_saved()
	for name: String in saved:
		assert_object(offered.get(name)).override_failure_message(
				"the derived generic displaced the authored '%s'" % name).is_same(saved[name])
