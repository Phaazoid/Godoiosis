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


# Depth (#1530): per element, the most atoms any ONE verb works on. Push(F2) asks Fire 2, the Break
# Fire 1 and Air 1, so the carving asks Fire 2, Air 1 -- not the Fire 3 of every argument summed.
func test_the_demand_is_the_hungriest_verb_per_element() -> void:
	var demand := _parse("Break(F, A) + Push(F2)").demand()
	assert_int(demand.get(Elemental.Element.FIRE, 0)).is_equal(2)
	assert_int(demand.get(Elemental.Element.AIR, 0)).is_equal(1)
	assert_int(demand.size()).is_equal(2)


# The flame Bind(F, F) makes is the flame Push(F2) moves; summing the verbs would charge it twice.
func test_the_demand_is_never_summed_across_verbs() -> void:
	var demand := _parse("Bind(F, F) + Push(F2)").demand()
	assert_int(demand.get(Elemental.Element.FIRE, 0)).is_equal(2)
	assert_int(demand.size()).is_equal(1)


# One verb works on its arguments together, so a Break or a Bind asks for both at once.
func test_one_verbs_arguments_count_together() -> void:
	var bind := _parse("Bind(Q, Q)").demand()
	assert_int(bind.get(Elemental.Element.AETHER, 0)).is_equal(2)
	var bound := _parse("Bind(F, F)").demand()
	assert_int(bound.get(Elemental.Element.FIRE, 0)).is_equal(2)


# Each element takes its OWN deepest verb: the deeper fire sets Fire, the shallower one beside it adds
# nothing, and the Air comes from a different verb. A test-only F3 shows the rule has no ceiling of 2.
func test_each_element_takes_its_own_deepest_verb() -> void:
	var catalog := _catalog()
	catalog["deep_fire"] = _sub("F3")
	var demand := CarvingRecipe.parse("Push(F2) + Push(F3) + Push(A2)", catalog).demand()
	assert_int(demand.get(Elemental.Element.FIRE, 0)).is_equal(3)
	assert_int(demand.get(Elemental.Element.AIR, 0)).is_equal(2)
	assert_int(demand.size()).is_equal(2)


func test_a_push_delivers_what_it_pushes() -> void:
	var r := _parse("Break(F, A) + Push(F2)")
	assert_array(r.delivered()).is_equal(["flame"])
	assert_array(r.hit_elements()).is_equal([Elemental.Element.FIRE])


# A lone fire atom is free HEAT (2026-10-12): it hits as Heat, and still scales off Fire aura, since
# damage reads the atoms delivered rather than the hit's tag.
func test_a_lone_fire_atom_delivers_heat() -> void:
	var r := _parse("Break(F, A) + Push(F)")
	assert_array(r.delivered()).is_equal(["atom_fire"])
	assert_array(r.hit_elements()).is_equal([Elemental.Element.HEAT])
	assert_array(r.damage_elements()).is_equal([Elemental.Element.FIRE])


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


func _walk(recipe: String, available: Dictionary[String, int]) -> String:
	var catalog := _fizzle_catalog()
	var parsed := CarvingRecipe.parse(recipe, catalog)
	assert_str(parsed.error).override_failure_message("fixture recipe '%s' does not parse: %s"
			% [recipe, parsed.error]).is_empty()
	return parsed.fizzle_reason(available, catalog)


# The ambient air alone, at the air's one of each (#1328).
func _ambient() -> Dictionary[String, int]:
	var supply: Dictionary[String, int] = {}
	for id: String in Atmosphere.SUBSTANCES:
		supply[id] = CellSubstances.AIR
	return supply


# `ids` as real sources, on top of `supply`.
func _with(supply: Dictionary[String, int], ids: Array[String]) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	out.assign(supply)
	for id: String in ids:
		out[id] = CellSubstances.PLENTY
	return out


# Break frees the air and water out of vapor, the water pairs into W2, and the Push finds it: Splash
# works anywhere, on the ambient air alone.
func test_a_break_makes_what_the_next_verb_needs() -> void:
	assert_str(_walk("Break(A, W) + Push(W2)", _ambient())).is_empty()


# A Break needs the BOND it splits present -- vapor is ambient, the molecule F+W is not one at all, so
# the case that bites is a Break of something absent.
func test_a_break_needs_its_molecule() -> void:
	assert_str(_walk("Break(F, A)", _ambient())).is_empty()
	var no_air: Dictionary[String, int] = { "atom_aether": CellSubstances.AIR }
	assert_str(_walk("Break(F, A)", no_air)).contains("vital")


func test_a_tied_carving_fizzles_without_its_material_and_works_with_it() -> void:
	assert_str(_walk("Focus(W2) + Push(W2)", _ambient())).is_not_empty()
	assert_str(_walk("Focus(W2) + Push(W2)", _with(_ambient(), ["water"]))).is_empty()


func test_lightning_from_nowhere_fizzles() -> void:
	assert_str(_walk("Extract(QF) + Push(QF)", _ambient())).is_not_empty()


# Heat is in every cell's air, so binding it into flame needs nothing else (#1333): both Fireball forms
# work anywhere, the stronger one breaking more heat out of vital air first.
func test_binding_the_airs_heat_works_on_the_air_alone() -> void:
	assert_str(_walk("Bind(F, F) + Push(F2)", _ambient())).is_empty()
	assert_str(_walk("Break(F, A) + Bind(F, F) + Push(F2)", _ambient())).is_empty()


func test_a_bind_needs_both_halves() -> void:
	assert_str(_walk("Bind(Q, Q)", _ambient())).is_empty()
	assert_str(_walk("Break(A, W) + Bind(Q, W)", _ambient())).is_empty()
	var no_aether: Dictionary[String, int] = { "vapor": CellSubstances.AIR }
	assert_str(_walk("Break(A, W) + Bind(Q, W)", no_aether)).contains("aether")


# Rock Throw: salt is no ambient substance, so it needs dirt's (or stone's) parts beside it.
func test_a_push_of_salt_works_where_salt_is_present() -> void:
	assert_str(_walk("Push(E2)", _ambient())).is_not_empty()
	assert_str(_walk("Push(E2)", _with(_ambient(), ["dirt", "salt", "ash"]))).is_empty()


# The reason NAMES the first missing substance, by its display name lower-cased.
func test_the_reason_names_the_missing_substance() -> void:
	var reason := _walk("Focus(W2) + Push(W2)", _ambient())
	assert_str(reason).contains("water")
	assert_str(reason).contains("Fizzles")
	assert_str(_walk("Extract(QF) + Push(QF)", _ambient())).contains("lightning")


# --- amounts (#1328) -------------------------------------------------------------------------

# The amount is the equations' coefficient in front of the argument; no number is one.
func test_an_amount_is_a_coefficient_on_the_argument() -> void:
	var r := _parse("Focus(3W2) + Push(W2)")
	assert_str(r.error).is_empty()
	assert_array(r.steps[0].args).is_equal(["water"])
	assert_int(r.steps[0].amount).is_equal(3)
	assert_int(r.steps[1].amount).is_equal(1)
	var spaced := _parse("Push(3 W2)")
	assert_str(spaced.error).is_empty()
	assert_int(spaced.steps[0].amount).is_equal(3)


# A Break or Bind works on one amount, written on both arguments.
func test_a_two_argument_verb_takes_one_amount() -> void:
	var r := _parse("Break(3A, 3W)")
	assert_str(r.error).is_empty()
	assert_int(r.steps[0].amount).is_equal(3)
	assert_str(_parse("Break(3A, W)").error).contains("same amount")
	assert_str(_parse("Bind(Q, 2Q)").error).contains("same amount")


func test_an_amount_of_zero_is_illegal() -> void:
	assert_str(_parse("Push(0W2)").error).is_not_empty()


# Phaazoid@, 2026-10-18: the amount is not aura. The source supplies the bulk, so tying a carving to a
# river must not make it cost more. Cost stays the verb count.
func test_the_amount_counts_toward_neither_demand_nor_cost() -> void:
	var plain := _parse("Focus(W2) + Push(W2)")
	var jet := _parse("Focus(3W2) + Push(3W2)")
	assert_dict(jet.demand()).is_equal(plain.demand())
	assert_int(jet.verb_count()).is_equal(plain.verb_count())
	assert_array(jet.damage_elements()).is_equal(plain.damage_elements())


# The air supplies one: a number past it needs a real source, and the reason says so.
func test_more_than_the_air_holds_needs_a_source() -> void:
	assert_str(_walk("Push(A2)", _ambient())).is_empty()
	var reason := _walk("Push(3A2)", _ambient())
	assert_str(reason).contains("Fizzles")
	assert_str(reason).contains("needs a source of inert")
	assert_str(_walk("Push(3A2)", _with(_ambient(), ["inert_air"]))).is_empty()
	# An amount of one keeps the plain wording.
	assert_str(_walk("Push(W2)", _ambient())).not_contains("source of")


# A step makes its products at its OWN amount, so nothing multiplies: the air's one vapor makes one
# water, which is a splash and not a jet.
func test_a_made_substance_counts_up_to_its_own_amount() -> void:
	assert_str(_walk("Break(A, W) + Push(W2)", _ambient())).is_empty()
	assert_str(_walk("Break(A, W) + Push(3W2)", _ambient())).contains("source of water")
	# Three vapor makes three water -- but only beside a vapor source, since the air holds one.
	assert_str(_walk("Break(3A, 3W) + Push(3W2)", _ambient())).contains("source of vapor")
	assert_str(_walk("Break(3A, 3W) + Push(3W2)", _with(_ambient(), ["vapor"]))).is_empty()
	# What a step makes never LOWERS a source already present.
	assert_str(_walk("Break(A, W) + Push(3W2)", _with(_ambient(), ["water"]))).is_empty()


# Nothing is used up: two steps of three need three, not six.
func test_nothing_is_consumed_between_steps() -> void:
	var three: Dictionary[String, int] = _ambient()
	three["water"] = 3
	assert_str(_walk("Focus(3W2) + Push(3W2)", three)).is_empty()
	three["water"] = 2
	assert_str(_walk("Focus(3W2) + Push(3W2)", three)).contains("source of water")
