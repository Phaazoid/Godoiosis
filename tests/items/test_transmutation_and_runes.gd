extends GdUnitTestSuite

# Aura-scaled transmutations + the rune container (docs/design/alchemy-kit.md), on the Deep Alchemy
# Phase 2 recipe model (docs/design/deep-alchemy.md -> What is built):
#   - a carving is a RECIPE: verbs with substance arguments, `Break(F, A) + Push(F2)`
#   - cost = verbs; demand = depth, the most atoms any one verb works on, per element (#1530); delivery = what the last delivering verb
#     leaves at the target
#   - damage scales off the wielder's aura in each DELIVERED element, once each
#   - channeling: anchor + wildcards over the DEMAND (dev 2026-08-10, replacing #60's
#     temper/leeway/strain model) -- real aura in one demanded element, total deficit covered by
#     the universal +1 OR spare temper aura, never both
#   - hit tags: each delivered substance read back through SubstanceMap (flame is FIRE)
# What the recipe line itself parses to is tests/items/test_carving_recipe.gd's; here it is read
# through TransmutationData and RuneData, the seams the game asks. FIRING through the resolver is
# covered in tests/runes/test_rune_firing.gd.

const H := preload("res://tests/support/squad_fixtures.gd")

# An alchemist with an explicit per-element aura map (most fields default to 0). Affinity
# auto-derives from the aura keys unless explicitly overridden afterward -- aura only ever
# legitimately exists within affinity (#60 Rebecca rule).
func _alchemist(auras: Dictionary[Elemental.Element, int]) -> Unit:
	var u: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	u.unit_instance.aura = auras
	var affinity: Array[Elemental.Element] = []
	for element in auras:
		affinity.append(element)
	u.unit_instance.affinity = affinity
	return u

func _carving(recipe: String, power: int = 0) -> TransmutationData:
	var t: TransmutationData = TransmutationData.new()
	t.recipe = recipe
	t.power = power
	assert_str(t.recipe_error()).override_failure_message(
		"fixture recipe '%s' does not parse: %s" % [recipe, t.recipe_error()]).is_empty()
	return t

# --- aura scaling: the DELIVERED elements, once each ---

func test_a_single_element_delivery_scales_off_that_aura() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 7 })
	assert_int(_carving("Push(F2)", 5).base_damage(u.state)).is_equal(12)   # 5 + 7

# Lightning is one substance holding two elements, so the hit scales off both.
func test_a_multi_element_delivery_sums_its_elements() -> void:
	var u: Unit = _alchemist({ Elemental.Element.AETHER: 2, Elemental.Element.FIRE: 3 })
	assert_int(_carving("Push(QF)", 5).base_damage(u.state)).is_equal(10)   # 5 + 2 + 3

# A Break leaves both halves at the target, so it scales off both.
func test_a_break_scales_off_both_halves_it_leaves() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 3, Elemental.Element.WATER: 4 })
	var t: TransmutationData = _carving("Break(F, W)", 5)
	assert_int(t.tier()).is_equal(2)
	assert_int(t.base_damage(u.state)).is_equal(12)   # 5 + 3 + 4

# Flame is two fire atoms and a deeper recipe spends more of them, but the hit still scales off fire ONCE.
func test_damage_counts_each_delivered_element_once_however_many_atoms() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 3 })
	var deep: TransmutationData = _carving("Push(F) + Push(F2)", 5)
	assert_int(deep.demand_of(Elemental.Element.FIRE)).override_failure_message(
		"fixture: the recipe should demand more than one fire").is_greater(1)
	assert_int(deep.base_damage(u.state)).is_equal(8)   # 5 + 3, not 5 + 3 * 3

# Air the recipe SPENDS (Break(F, A) frees the fire) is not air it DELIVERS (it pushes the flame).
func test_an_element_the_recipe_only_spends_adds_no_damage() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 3, Elemental.Element.AIR: 4 })
	var t: TransmutationData = _carving("Break(F, A) + Push(F2)", 5)
	assert_int(t.demand_of(Elemental.Element.AIR)).override_failure_message(
		"fixture: the recipe should spend air").is_greater(0)
	assert_int(t.base_damage(u.state)).is_equal(8)   # 5 + 3; the 4 air buys nothing

# --- materia empowerment (#694): +1 EFFECTIVE aura in a delivered element the caster can draw on ---
# WHERE that list comes from is Materia's (tests/runes/test_materia_sources.gd); here it is
# passed in, because a carving has no board and must never grow one.

func test_empowerment_adds_one_per_matching_delivered_element() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 7 })
	var t: TransmutationData = _carving("Push(F2)", 5)
	assert_int(t.base_damage(u.state, [Elemental.Element.FIRE])).is_equal(13)   # 12 + 1

# Empowerment is +1 aura in an element the hit scales off, so it counts exactly as often as the aura
# does -- once, however many atoms the recipe spends.
func test_empowerment_counts_once_per_delivered_element() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 3 })
	var deep: TransmutationData = _carving("Push(F) + Push(F2)", 5)
	assert_int(deep.base_damage(u.state, [Elemental.Element.FIRE])).is_equal(9)   # 8 + 1

func test_empowerment_reaches_each_element_of_a_multi_element_delivery() -> void:
	var u: Unit = _alchemist({ Elemental.Element.AETHER: 2, Elemental.Element.FIRE: 3 })
	var t: TransmutationData = _carving("Push(QF)", 5)
	assert_int(t.base_damage(u.state, [Elemental.Element.AETHER, Elemental.Element.FIRE])).is_equal(12)   # 10 + 1 + 1

func test_empowerment_in_an_element_the_carving_lacks_does_nothing() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 7 })
	var t: TransmutationData = _carving("Push(F2)", 5)
	assert_int(t.base_damage(u.state, [Elemental.Element.WATER])).is_equal(12)   # unchanged

# A demanded element is not a delivered one, so standing on its source buys nothing either.
func test_empowerment_in_an_element_the_recipe_only_spends_does_nothing() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 3, Elemental.Element.AIR: 4 })
	var t: TransmutationData = _carving("Break(F, A) + Push(F2)", 5)
	assert_int(t.base_damage(u.state, [Elemental.Element.AIR])).is_equal(t.base_damage(u.state))

# Empowerment is SCALING, and a utility carving suppresses scaling entirely (#126) -- which is
# the structural reason #695's authored form exists: the fallback can never reach one.
func test_a_damageless_carving_gains_nothing_from_empowerment() -> void:
	var u: Unit = _alchemist({ Elemental.Element.AIR: 4 })
	var t: TransmutationData = _carving("Push(A2)", 5)
	t.deals_no_damage = true
	assert_int(t.base_damage(u.state, [Elemental.Element.AIR])).is_equal(0)

# An element the wielder has NO pool in still gains the point: empowerment is drawn from the
# ground, not from talent. (Whether the carving may be channelled at all is a different
# question, asked below and deliberately untouched by any of this.)
func test_empowerment_applies_without_a_pool_in_that_element() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 2 })
	var t: TransmutationData = _carving("Break(F, W)", 5)
	assert_int(t.base_damage(u.state, [Elemental.Element.WATER])).is_equal(8)   # 5 + 2 + 0 + 1

# --- channeling gate: anchor + wildcards over the DEMAND (dev 2026-08-10, replacing the
# 2026-07-04 temper/trained-leeway/strain model — repeal record in transmutation-model-proposal.md).
# One case per row of the plan's worked-examples table, each with a recipe demanding the same
# atoms the old sigil fixture did. ---

func test_rebecca_no_aura_anywhere_channels_nothing() -> void:
	var u: Unit = _alchemist({})   # no aura, no affinity
	assert_bool(_carving("Push(F)").can_channel(u.state, Elemental.Element.FIRE)).is_false()

# (The old stray-aura-outside-affinity case left with the ladder's has_any_affinity branch: the
# anchor reads AURA, and "aura never exists outside affinity" is the SEEDING seam's invariant —
# UnitInstance.initialize() drops out-of-affinity aura loudly, the dev editor erases it on an
# affinity untoggle. One question, one owner.)

func test_the_anchor_needs_aura_in_one_of_the_carvings_own_elements() -> void:
	# Water-5 is real training, but this recipe demands none of it — wildcards never anchor.
	var u: Unit = _alchemist({ Elemental.Element.WATER: 5 })
	var pair: TransmutationData = _carving("Break(F, A)")
	assert_bool(pair.can_channel(u.state, Elemental.Element.FIRE)).is_false()

func test_a_maim_taxed_pool_at_zero_loses_the_anchor() -> void:
	# Affinity (the birthright) persists at aura 0; the anchor reads the POINT, so it's gone.
	var u: Unit = _alchemist({ Elemental.Element.AIR: 0 })
	assert_bool(_carving("Push(A)").can_channel(u.state, Elemental.Element.AIR)).is_false()

func test_the_motivating_case_one_shared_element_plus_the_free_wildcard() -> void:
	# Aldin: aether-1 only, a recipe asking 1 Aether and 1 Air — anchor on aether, deficit 1 <= pool
	# A's universal +1, on ANY rune (here air-tempered, where his aether gives pool B nothing).
	var u: Unit = _alchemist({ Elemental.Element.AETHER: 1 })
	var wind: TransmutationData = _carving("Break(Q, A)")
	assert_bool(wind.can_channel(u.state, Elemental.Element.AIR)).is_true()
	assert_int(wind.total_deficit(u.state)).is_equal(1)

func test_a_fully_covered_carving_spends_no_wildcards() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 1 })
	var t: TransmutationData = _carving("Push(F)")
	assert_bool(t.can_channel(u.state, Elemental.Element.FIRE)).is_true()
	assert_int(t.total_deficit(u.state)).is_equal(0)

func test_the_free_wildcard_covers_one_point_of_depth_too() -> void:
	# "3-Fire demands true fire-3" is repealed: fire-1 channels a Fire 2 demand via pool A. Depth and
	# breadth are one currency now — but only one point of it on an unmatched rune.
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 1 })
	assert_bool(_carving("Push(F2)").can_channel(u.state, Elemental.Element.FIRE)).is_true()
	var athanor: TransmutationData = _carving("Break(F, A) + Push(F2)")   # Fire 2, Air 1: a point of each
	assert_bool(athanor.can_channel(u.state, Elemental.Element.FIRE)).is_false()   # deficit 2 > capacity 1

func test_spare_temper_aura_is_the_second_pool() -> void:
	# Dev's example: Air-3, a recipe asking 1 Fire, 1 Air, 1 Water — on the air rune spare 3-1 = 2
	# covers the deficit 2; on a fire rune (their fire is 0) only the universal +1 remains, and it
	# refuses.
	var u: Unit = _alchemist({ Elemental.Element.AIR: 3 })
	var triple: TransmutationData = _carving("Break(F, A) + Push(W)")
	assert_bool(triple.can_channel(u.state, Elemental.Element.AIR)).is_true()
	assert_bool(triple.can_channel(u.state, Elemental.Element.FIRE)).is_false()

func test_the_pools_never_stack_and_the_pool_is_the_SPARE() -> void:
	# Air-2, same triple, air rune: deficit 2, spare = 2-1 = 1, capacity = max(1, 1) = 1 ->
	# refused. This one fixture kills BOTH wrong models: stacked pools (1 + spare = 2) would
	# channel it, and a full-aura pool (max(1, 2) = 2) would channel it. Falsified against each.
	var u: Unit = _alchemist({ Elemental.Element.AIR: 2 })
	var triple: TransmutationData = _carving("Break(F, A) + Push(W)")
	assert_bool(triple.can_channel(u.state, Elemental.Element.AIR)).is_false()
	assert_int(triple.total_deficit(u.state)).is_equal(2)
	assert_int(triple.wildcard_capacity(u.state, Elemental.Element.AIR)).is_equal(1)

func test_isaac_alkahest_breadth_now_carries_one_point_of_depth() -> void:
	# Universal breadth, trained depth — amended 2026-08-10: pool A hands Isaac +1 depth in
	# every element (Fire 2 channels at fire-1), but only the one point (Fire 2 with Air 2 still refused).
	var isaac: Unit = _alchemist({
		Elemental.Element.FIRE: 1, Elemental.Element.WATER: 1, Elemental.Element.EARTH: 1,
		Elemental.Element.AIR: 1, Elemental.Element.AETHER: 1,
	})
	assert_bool(_carving("Push(F2)").can_channel(isaac.state, Elemental.Element.FIRE)).is_true()
	var athanor: TransmutationData = _carving("Push(F2) + Push(A2)")
	assert_bool(athanor.can_channel(isaac.state, Elemental.Element.FIRE)).is_false()   # deficit 2 > capacity 1

# --- rune capacity, counted in VERBS (Phase 2) ---

func test_small_rune_holds_one_one_verb_carving() -> void:
	var small: RuneData = RuneData.new()
	small.size = RuneData.Size.SMALL                                     # capacity 1
	assert_bool(small.inscribe(_carving("Push(F2)"))).is_true()         # one verb
	# A fire recipe, so only the capacity can be what refuses it -- the temper would take it.
	assert_bool(small.can_inscribe(_carving("Push(F)"))).is_false()     # full

func test_medium_rune_holds_two_two_verb_carvings() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM                                      # capacity 4, circle cap 2
	assert_bool(med.inscribe(_carving("Break(F, A) + Push(F2)"))).is_true()   # two verbs
	assert_bool(med.inscribe(_carving("Break(F, A) + Push(F2)"))).is_true()   # two more
	assert_int(med.used_capacity()).is_equal(4)
	assert_bool(med.can_inscribe(_carving("Push(F)"))).is_false()             # full

func test_large_rune_holds_two_three_verb_carvings() -> void:
	var large: RuneData = RuneData.new()
	large.size = RuneData.Size.LARGE                                     # capacity 6, circle cap 3
	var storm: String = "Break(F, A) + Bind(Q, F) + Push(QF)"
	assert_bool(large.inscribe(_carving(storm))).is_true()              # three verbs
	assert_bool(large.inscribe(_carving(storm))).is_true()              # three more
	assert_int(large.used_capacity()).is_equal(6)

func test_circle_cap_blocks_a_carving_with_too_many_verbs_even_with_capacity_free() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM                                      # capacity 4, circle cap 2
	var three: TransmutationData = _carving("Break(F, A) + Bind(Q, F) + Push(QF)")
	assert_int(three.cost()).override_failure_message(
		"premise: the carving must fit the rune's free capacity").is_less_equal(med.remaining_capacity())
	assert_bool(med.can_inscribe(three)).is_false()                     # three verbs don't fit the cap

# The verbs are what a rune pays for. Each verb brings its own argument slots, so the atoms in them
# are not counted again.
func test_cost_is_per_verb_not_per_atom() -> void:
	assert_int(_carving("Push(F2)").cost()).is_equal(1)                  # two atoms, one verb
	assert_int(_carving("Break(F, A) + Push(F2)").cost()).is_equal(2)    # four atoms, two verbs

# --- load-time legality (#60: both knobs enforced independently of inscribe()'s add-time gate) ---

func test_rune_is_legal_catches_a_hand_edited_capacity_violation() -> void:
	var small: RuneData = RuneData.new()
	small.size = RuneData.Size.SMALL                                     # capacity 1, circle cap 1
	small.temper = Elemental.Element.FIRE                                # so only the capacity can fail
	small.inscriptions.append(_carving("Push(F2)"))
	small.inscriptions.append(_carving("Push(F2)"))                      # bypasses inscribe()'s gate
	assert_bool(small.is_legal()).is_false()

func test_rune_is_legal_catches_a_hand_edited_circle_cap_violation() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM                                      # capacity 4, circle cap 2
	med.temper = Elemental.Element.FIRE
	# three verbs fit the capacity; they don't fit the cap
	med.inscriptions.append(_carving("Break(F, A) + Bind(Q, F) + Push(QF)"))
	assert_bool(med.is_legal()).is_false()

func test_transmutation_is_legal_rejects_an_unparseable_an_empty_and_an_oversized_recipe() -> void:
	assert_bool(_carving("Push(F2)").is_legal()).is_true()
	# Built bare rather than through _carving, which refuses a recipe that does not parse.
	var unknown := TransmutationData.new()
	unknown.recipe = "Push(no_such_substance)"
	assert_bool(unknown.is_legal()).is_false()                           # an argument names nothing
	var empty := TransmutationData.new()
	assert_bool(empty.is_legal()).is_false()                             # names no verbs
	var four: TransmutationData = _carving("Push(F) + Push(A) + Push(W) + Push(E)")
	assert_bool(four.is_legal()).is_false()                              # 4 verbs > the global max circle cap (L, 3)

# --- the temper rule (#60), over the DEMAND: first carving sets it permanently; later carvings
# must demand it and never outweigh it (ties legal) ---

func test_inscribe_sets_temper_from_the_first_carving() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM
	med.inscribe(_carving("Break(W, F)"))   # Water 1, Fire 1: primary = WATER (first-named tie)
	assert_int(med.temper).is_equal(Elemental.Element.WATER)

func test_temper_accepts_a_tied_demand_carving() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM
	med.inscribe(_carving("Push(F)"))                                   # temper = FIRE, demand 1
	var tied: TransmutationData = _carving("Break(F, W)")                # Fire 1, Water 1: a tie is legal
	assert_bool(med.can_inscribe(tied)).is_true()

func test_temper_rejects_a_carving_that_outweighs_it() -> void:
	var large: RuneData = RuneData.new()
	large.size = RuneData.Size.LARGE
	large.inscribe(_carving("Push(F)"))                                 # temper = FIRE, demand 1
	var outweighs: TransmutationData = _carving("Push(FA2)")             # Fire 1, Air 2 -- off-temper heavier
	assert_bool(large.can_inscribe(outweighs)).is_false()

func test_temper_rejects_a_carving_missing_the_temper_element() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM
	med.inscribe(_carving("Push(F)"))                                   # temper = FIRE
	assert_bool(med.can_inscribe(_carving("Push(W2)"))).is_false()      # no fire at all

func test_rune_is_legal_catches_a_hand_edited_temper_violation() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM
	med.temper = Elemental.Element.FIRE
	med.inscriptions.append(_carving("Push(W2)"))                        # bypasses inscribe() -- no fire at all
	assert_bool(med.is_legal()).is_false()

func test_rune_is_legal_catches_inscriptions_with_no_temper_set() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM
	med.inscriptions.append(_carving("Push(F2)"))                        # bypassed inscribe(); temper never set
	assert_bool(med.is_legal()).is_false()

# --- identity ---

func test_primary_element_is_the_most_demanded() -> void:
	# Fire is named first, but the recipe asks Earth 2 to Fire 1.
	var t: TransmutationData = _carving("Break(F, E) + Push(E2)")
	assert_int(t.primary_element()).is_equal(Elemental.Element.EARTH)

func test_primary_element_tie_goes_to_the_first_named() -> void:
	assert_int(_carving("Break(W, F)").primary_element()).is_equal(Elemental.Element.WATER)
	assert_int(_carving("Break(F, W)").primary_element()).is_equal(Elemental.Element.FIRE)

# --- hit elements: what the recipe DELIVERS, read back through SubstanceMap ---

func test_flame_hits_as_fire() -> void:
	assert_array(_carving("Push(F2)").get_elements()).contains_exactly([Elemental.Element.FIRE])

func test_lightning_hits_as_shock() -> void:
	assert_array(_carving("Push(QF)").get_elements()).contains_exactly([Elemental.Element.SHOCK])

func test_ice_hits_as_ice_whether_bound_or_free_aether() -> void:
	assert_array(_carving("Break(A, W) + Bind(Q, W)").get_elements()).contains_exactly([Elemental.Element.ICE])
	assert_array(_carving("Push(Q)").get_elements()).contains_exactly([Elemental.Element.ICE])

func test_essence_hits_as_aether() -> void:
	assert_array(_carving("Bind(Q, Q)").get_elements()).contains_exactly([Elemental.Element.AETHER])

func test_a_break_delivers_both_halves() -> void:
	assert_array(_carving("Break(F, A)").get_elements()).contains_exactly_in_any_order(
		[Elemental.Element.FIRE, Elemental.Element.AIR])

# Pull and Still act toward the caster or on time, so the hit is what the step before them left.
func test_pull_and_still_are_read_past() -> void:
	assert_array(_carving("Push(W2) + Still(W2)").get_elements()).contains_exactly([Elemental.Element.WATER])
	assert_array(_carving("Push(A2) + Pull(A2)").get_elements()).contains_exactly([Elemental.Element.AIR])

# A carving's authored elements ARE its outgoing tags (#900) -- the Attack Editor's look section
# keys off the same answer the resolver reacts on.
func test_authored_elements_are_the_hit_tags() -> void:
	var t: TransmutationData = _carving("Push(QF)")
	assert_array(t.authored_elements()).is_equal(t.get_elements())
