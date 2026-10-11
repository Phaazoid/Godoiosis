# What a carving's recipe line means (Deep Alchemy Phase 2): CarvingRecipe parses `Break(F, A) +
# Push(F2)` into verbs and resolved arguments, and derives the cost, the aura demand and what a hit
# delivers. Every case hands the parse its own small catalog, so nothing here reads authored
# substances or pins a shipped carving (tests/README.md rule 9).
extends GdUnitTestSuite


func _sub(formula: String) -> Substance:
	var s := Substance.new()
	s.formula = formula
	return s


# Ids match the real SubstanceMap rows, so a hit's element reads back through it.
func _catalog() -> Dictionary:
	return {
		"atom_fire": _sub("F"), "atom_air": _sub("A"), "atom_water": _sub("W"), "atom_aether": _sub("Q"),
		"flame": _sub("F2"), "inert_air": _sub("A2"), "water": _sub("W2"), "essence": _sub("Q2"),
		"vital_air": _sub("FA"), "vapor": _sub("AW"), "ice": _sub("QW"), "lightning": _sub("QF"),
	}


func _parse(text: String) -> CarvingRecipe:
	return CarvingRecipe.parse(text, _catalog())


func test_each_verb_parses_with_its_arguments_resolved() -> void:
	var r := _parse("Break(F, A) + Push(F2)")
	assert_str(r.error).is_empty()
	assert_int(r.steps.size()).is_equal(2)
	assert_int(r.steps[0].verb).is_equal(Flourish.Type.BREAK)
	assert_array(r.steps[0].args).is_equal(["atom_fire", "atom_air"])
	assert_int(r.steps[1].verb).is_equal(Flourish.Type.PUSH)
	assert_array(r.steps[1].args).is_equal(["flame"])


func test_the_cost_is_the_verb_count() -> void:
	assert_int(_parse("Push(A2)").verb_count()).is_equal(1)
	assert_int(_parse("Break(F, A) + Bind(Q, F) + Push(QF)").verb_count()).is_equal(3)


func test_the_demand_sums_atoms_across_every_argument() -> void:
	var demand := _parse("Break(F, A) + Push(F2)").demand()
	assert_int(demand.get(Elemental.Element.FIRE, 0)).is_equal(3)
	assert_int(demand.get(Elemental.Element.AIR, 0)).is_equal(1)
	assert_int(demand.size()).is_equal(2)


func test_a_push_delivers_what_it_pushes() -> void:
	var r := _parse("Break(F, A) + Push(F2)")
	assert_array(r.delivered()).is_equal(["flame"])
	assert_array(r.hit_elements()).is_equal([Elemental.Element.FIRE])


# Flame is two fire atoms, and still scales off fire ONCE -- what kept a one-element hit's damage
# where a one-sigil carving's was.
func test_damage_scales_off_each_delivered_element_once() -> void:
	assert_array(_parse("Push(F2)").damage_elements()).is_equal([Elemental.Element.FIRE])
	assert_array(_parse("Extract(QF) + Push(QF)").damage_elements()).contains_exactly_in_any_order(
		[Elemental.Element.AETHER, Elemental.Element.FIRE])


func test_a_bind_delivers_its_product() -> void:
	var r := _parse("Break(A, W) + Bind(Q, W)")
	assert_str(r.error).is_empty()
	assert_array(r.delivered()).is_equal(["ice"])
	# Ice is read through SubstanceMap's one extra row: what a Freeze's free aether becomes.
	assert_array(r.hit_elements()).is_equal([Elemental.Element.ICE])


func test_a_lone_break_delivers_its_halves_with_lone_atoms_paired() -> void:
	var r := _parse("Break(F, A)")
	assert_array(r.delivered()).contains_exactly_in_any_order(["flame", "inert_air"])
	assert_array(r.hit_elements()).contains_exactly_in_any_order([Elemental.Element.FIRE, Elemental.Element.AIR])


# Pull, Extract, Quicken and Still act toward the caster or on time, so the hit reads past them.
func test_a_verb_that_leaves_nothing_at_the_target_is_read_past() -> void:
	assert_array(_parse("Push(W2) + Still(W2)").delivered()).is_equal(["water"])
	assert_array(_parse("Push(A2) + Pull(A2)").delivered()).is_equal(["inert_air"])
	assert_array(_parse("Pull(A2)").delivered()).is_empty()


func test_opposites_combine_rather_than_refuse() -> void:
	assert_str(_parse("Push(A2) + Pull(A2)").error).is_empty()
	assert_str(_parse("Spread(W2) + Focus(W2)").error).is_empty()


func test_no_verbs_is_illegal() -> void:
	assert_str(_parse("").error).is_not_empty()
	assert_str(_parse("   ").error).is_not_empty()


func test_an_unknown_verb_or_shape_is_illegal() -> void:
	assert_str(_parse("Shove(A2)").error).contains("not a verb")
	assert_str(_parse("Push A2").error).is_not_empty()


func test_break_and_bind_need_both_arguments_and_the_rest_one() -> void:
	assert_str(_parse("Break(F)").error).contains("2 arguments")
	assert_str(_parse("Bind(Q)").error).contains("2 arguments")
	assert_str(_parse("Push(A2, W2)").error).contains("1 argument")


func test_an_argument_must_name_a_real_substance() -> void:
	assert_str(_parse("Push(nothing_at_all)").error).contains("nothing_at_all")
	assert_str(_parse("Push(E2)").error).contains("E2")


func test_a_break_must_split_and_a_bind_must_make_a_real_molecule() -> void:
	assert_str(_parse("Break(F, W)").error).contains("nothing to break")
	assert_str(_parse("Bind(F, W)").error).contains("makes nothing real")


# --- the fizzle walk (Deep Alchemy Phase 2: a verb whose argument is not present fizzles) -------

# Every argument the walk below can name, with display names so the reason's wording is the parse's.
func _fizzle_catalog() -> Dictionary:
	var catalog := _catalog()
	for id: String in catalog:
		(catalog[id] as Substance).display_name = id.capitalize()
	catalog["salt"] = _sub("E2")
	catalog["ash"] = _sub("AE")
	return catalog


func _walk(recipe: String, available: Array[String]) -> String:
	var catalog := _fizzle_catalog()
	var parsed := CarvingRecipe.parse(recipe, catalog)
	assert_str(parsed.error).override_failure_message("fixture recipe '%s' does not parse: %s"
			% [recipe, parsed.error]).is_empty()
	return parsed.fizzle_reason(available, catalog)


func _ambient() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(CellSubstances.AMBIENT)
	return ids


# Break frees the air and water out of vapor, the water pairs into W2, and the Push finds it: Splash
# works anywhere, on the ambient air alone.
func test_a_break_makes_what_the_next_verb_needs() -> void:
	assert_str(_walk("Break(A, W) + Push(W2)", _ambient())).is_empty()


# A Break needs the BOND it splits present -- vapor is ambient, the molecule F+W is not one at all, so
# the case that bites is a Break of something absent.
func test_a_break_needs_its_molecule() -> void:
	assert_str(_walk("Break(F, A)", _ambient())).is_empty()
	var no_air: Array[String] = ["atom_aether"]
	assert_str(_walk("Break(F, A)", no_air)).contains("vital")


func test_a_tied_carving_fizzles_without_its_material_and_works_with_it() -> void:
	assert_str(_walk("Focus(W2) + Push(W2)", _ambient())).is_not_empty()
	var by_water := _ambient()
	by_water.append("water")
	assert_str(_walk("Focus(W2) + Push(W2)", by_water)).is_empty()


func test_lightning_from_nowhere_fizzles() -> void:
	assert_str(_walk("Extract(QF) + Push(QF)", _ambient())).is_not_empty()


func test_a_bind_needs_both_halves() -> void:
	assert_str(_walk("Bind(Q, Q)", _ambient())).is_empty()
	assert_str(_walk("Break(A, W) + Bind(Q, W)", _ambient())).is_empty()
	var no_aether: Array[String] = ["vapor"]
	assert_str(_walk("Break(A, W) + Bind(Q, W)", no_aether)).contains("aether")


# Rock Throw: salt is no ambient substance, so it needs dirt's (or stone's) parts beside it.
func test_a_push_of_salt_works_where_salt_is_present() -> void:
	assert_str(_walk("Push(E2)", _ambient())).is_not_empty()
	var by_dirt := _ambient()
	by_dirt.append_array(["dirt", "salt", "ash"])
	assert_str(_walk("Push(E2)", by_dirt)).is_empty()


# The reason NAMES the first missing substance, by its display name lower-cased.
func test_the_reason_names_the_missing_substance() -> void:
	var reason := _walk("Focus(W2) + Push(W2)", _ambient())
	assert_str(reason).contains("water")
	assert_str(reason).contains("Fizzles")
	assert_str(_walk("Extract(QF) + Push(QF)", _ambient())).contains("lightning")
