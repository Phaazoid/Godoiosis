# Deep Alchemy's notation (AlchemyFormula) and the substance files it reads (SubstanceCatalog).
#
# The notation cases build their own catalogs, so they answer whether the PARSER works whatever is on
# disk; the last two ask the shipped files. Nothing here pins which substances exist or their
# formulas (tests/README.md #9) -- that content is codev's to change.
extends GdUnitTestSuite


func _sub(formula: String) -> Substance:
	var s := Substance.new()
	s.formula = formula
	return s


func _count(atoms: AlchemyFormula.Atoms, element: Elemental.Element) -> int:
	return atoms.counts.get(element, 0)


func test_a_molecule_counts_its_elements() -> void:
	var atoms := AlchemyFormula.molecule_atoms("F2W")
	assert_str(atoms.error).is_empty()
	assert_int(_count(atoms, Elemental.Element.FIRE)).is_equal(2)
	assert_int(_count(atoms, Elemental.Element.WATER)).is_equal(1)
	assert_int(atoms.counts.size()).is_equal(2)


func test_a_star_composition_sums_its_parts() -> void:
	# The doc's silver: metal + sulfur + mercury, written out, is QFWE3.
	var composed := AlchemyFormula.molecule_atoms("QE*FE*WE")
	var ordered := AlchemyFormula.molecule_atoms("QFWE3")
	assert_str(composed.error).is_empty()
	assert_bool(composed.counts == ordered.counts).is_true()


func test_a_malformed_formula_is_an_error_not_a_guess() -> void:
	assert_str(AlchemyFormula.molecule_atoms("F2x").error).is_not_empty()
	assert_str(AlchemyFormula.molecule_atoms("").error).is_not_empty()
	assert_str(AlchemyFormula.molecule_atoms("F0").error).is_not_empty()


func test_alchemical_order_is_Q_F_A_W_E_once_each() -> void:
	assert_bool(AlchemyFormula.in_alchemical_order("FW")).is_true()
	assert_bool(AlchemyFormula.in_alchemical_order("QFWE3")).is_true()
	assert_bool(AlchemyFormula.in_alchemical_order("QE*FE*WE")).is_true()
	assert_bool(AlchemyFormula.in_alchemical_order("WF")).is_false()
	assert_bool(AlchemyFormula.in_alchemical_order("AFE")).is_false()
	assert_bool(AlchemyFormula.in_alchemical_order("FFW")).is_false()


func test_a_compound_sums_its_parts_with_their_counts() -> void:
	var catalog := {"ash": _sub("AE"), "inert_air": _sub("A2"), "smoke": _sub("AE + 2A2")}
	var atoms := AlchemyFormula.atoms_of(catalog["smoke"], catalog)
	assert_str(atoms.error).is_empty()
	assert_int(_count(atoms, Elemental.Element.AIR)).is_equal(5)
	assert_int(_count(atoms, Elemental.Element.EARTH)).is_equal(1)


func test_a_compound_that_contains_itself_is_refused() -> void:
	var catalog := {"loop": _sub("A2 + loop"), "inert_air": _sub("A2")}
	var atoms := AlchemyFormula.atoms_of(catalog["loop"], catalog)
	assert_str(atoms.error).contains("contains itself")


func test_a_formula_two_molecules_share_must_be_named_by_id() -> void:
	# Ice and water could both be W2; a formula token cannot then say which it means.
	var catalog := {"water": _sub("W2"), "ice": _sub("W2")}
	var by_formula := AlchemyFormula.resolve("W2", catalog)
	assert_str(by_formula.error).contains("name one by id")
	var by_id := AlchemyFormula.resolve("ice", catalog)
	assert_str(by_id.error).is_empty()
	assert_str(by_id.id).is_equal("ice")


func test_a_formula_resolves_to_its_one_molecule_whatever_the_spelling() -> void:
	var catalog := {"silver": _sub("QFWE3")}
	var found := AlchemyFormula.resolve("QE*FE*WE", catalog)
	assert_str(found.error).is_empty()
	assert_str(found.id).is_equal("silver")


func test_a_compound_is_never_reached_by_formula() -> void:
	var catalog := {"smoke": _sub("AE + A2"), "ash": _sub("AE"), "inert_air": _sub("A2")}
	assert_str(AlchemyFormula.resolve("A3E", catalog).error).contains("no substance has the formula")


func test_an_unknown_id_is_named() -> void:
	assert_str(AlchemyFormula.resolve("phlogiston", {}).error).contains("phlogiston")


func test_every_substance_file_is_in_the_catalog() -> void:
	SubstanceCatalog.refresh()
	var on_disk := ResourceDir.files_with_extension(SubstanceCatalog.DIR, ".tres")
	assert_bool(on_disk.is_empty()).override_failure_message(
			"no substance files under %s -- the cases below would pass over nothing" % SubstanceCatalog.DIR).is_false()
	assert_int(SubstanceCatalog.get_all().size()).override_failure_message(
			"%d substance files on disk, a different number in the catalog -- one is not a Substance"
			% on_disk.size()).is_equal(on_disk.size())


func test_every_shipped_substance_is_well_formed() -> void:
	var catalog := SubstanceCatalog.get_all()
	var broken: Array[String] = []
	for id: String in catalog:
		for finding: Dictionary in ReactionLint.check_substance(catalog[id] as Substance, catalog):
			broken.append("%s: %s" % [id, finding["text"]])
	assert_array(broken).is_empty()
