extends GdUnitTestSuite

# Aura-scaled transmutations + the rune container (docs/design/alchemy-kit.md), now on the
# sigil/flourish anatomy (docs/design/transmutation-model-proposal.md):
#   - sigils: repeats = weight; cost capacity, scale off aura, grant flourish slots
#   - channeling: temper + trained leeway + strain (#60) -- floors = weight, the temper
#     element is never brute-forced, real temper aura is the leeway budget for the rest
#   - flourishes: slot-capped shaping marks; opposites reject; derive exotics (ICE/SHOCK)
# FIRING through the resolver is covered in tests/runes/test_rune_firing.gd.

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

func _carving(sigils: Array, power: int = 0) -> TransmutationData:
	var t: TransmutationData = TransmutationData.new()
	t.sigils.assign(sigils)
	t.power = power
	return t

# --- aura scaling ---

func test_single_element_scales_off_that_aura() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 7 })
	assert_int(_carving([Elemental.Element.FIRE], 5).base_damage(u)).is_equal(12)   # 5 + 7

func test_multi_element_sums_constituent_auras() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 3, Elemental.Element.WATER: 4 })
	var t: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER], 5)
	assert_int(t.tier()).is_equal(2)
	assert_int(t.base_damage(u)).is_equal(12)   # 5 + 3 + 4

func test_repeated_sigils_weight_the_scaling() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 3, Elemental.Element.EARTH: 2 })
	# "2 Fire, 1 Earth" scales twice off fire, once off earth
	var t: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.FIRE, Elemental.Element.EARTH], 5)
	assert_int(t.base_damage(u)).is_equal(13)   # 5 + 3 + 3 + 2

# --- channeling gate: temper + trained leeway + strain (#60, transmutation-model-proposal.md) ---

func test_rebecca_rule_empty_affinity_blocks_everything() -> void:
	var u: Unit = _alchemist({})   # no aura, no affinity
	assert_bool(_carving([Elemental.Element.FIRE]).can_channel(u, Elemental.Element.FIRE)).is_false()

func test_rebecca_rule_blocks_even_with_stray_aura() -> void:
	# Data-integrity edge case: aura present but affinity explicitly cleared -- the gate must
	# not be routable around just by having numbers sitting in the aura dict.
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 5 })
	u.unit_instance.affinity = []
	assert_bool(_carving([Elemental.Element.FIRE]).can_channel(u, Elemental.Element.FIRE)).is_false()

func test_temper_element_can_never_be_brute_forced() -> void:
	# 3-Fire (Athanor-tier) demands TRUE fire-3 -- no amount of leeway substitutes for depth.
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 2 })
	var athanor: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.FIRE, Elemental.Element.FIRE])
	assert_bool(athanor.can_channel(u, Elemental.Element.FIRE)).is_false()

func test_earned_temper_channels_free() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 1 })
	assert_bool(_carving([Elemental.Element.FIRE]).can_channel(u, Elemental.Element.FIRE)).is_true()
	assert_int(_carving([Elemental.Element.FIRE]).strain_cost(u, Elemental.Element.FIRE)).is_equal(0)

func test_repeated_temper_sigils_never_count_as_forced() -> void:
	# 2 Fire is temper DEPTH, not breadth -- forced_points only counts OTHER elements.
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 2 })
	var t: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.FIRE])
	assert_bool(t.can_channel(u, Elemental.Element.FIRE)).is_true()
	assert_int(t.strain_cost(u, Elemental.Element.FIRE)).is_equal(0)

func test_trained_temper_buys_leeway_on_a_partner_element() -> void:
	# 1 fire aura -> leeway budget 1 -> 1F+1W forces exactly 1 point, priced in strain.
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 1 })
	var pair: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER])
	assert_bool(pair.can_channel(u, Elemental.Element.FIRE)).is_true()
	assert_int(pair.strain_cost(u, Elemental.Element.FIRE)).is_equal(1)

func test_leeway_budget_is_exhausted_by_a_wider_array() -> void:
	# fire-1 budget = 1 forced point; 1F+1W+1A forces 2 -> over budget, can't channel at all.
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 1 })
	var triple: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER, Elemental.Element.AIR])
	assert_bool(triple.can_channel(u, Elemental.Element.FIRE)).is_false()

func test_deeper_temper_training_buys_more_leeway() -> void:
	# fire-3 -> budget 3 -> the same triple a fire-1 alchemist can't reach is affordable.
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 3 })
	var triple: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER, Elemental.Element.AIR])
	assert_bool(triple.can_channel(u, Elemental.Element.FIRE)).is_true()
	assert_int(triple.forced_points(u, Elemental.Element.FIRE)).is_equal(2)
	assert_int(triple.strain_cost(u, Elemental.Element.FIRE)).is_equal(3)   # STRAIN_BY_FORCED[2]

func test_repeated_off_temper_sigils_weight_the_forced_count() -> void:
	# 2 Water forces 2 points against a fire-1 leeway budget -- over budget.
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 1 })
	var t: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER, Elemental.Element.WATER])
	assert_bool(t.can_channel(u, Elemental.Element.FIRE)).is_false()
	assert_int(t.forced_points(u, Elemental.Element.FIRE)).is_equal(2)

func test_isaac_alkahest_breadth_one_everywhere_transcends_nothing() -> void:
	# Universal breadth, trained depth (alchemy-kit.md Special cases): aura-1 in every element
	# channels any weight-1-temper carving strain-free, but never brute-forces past its own 1.
	var isaac: Unit = _alchemist({
		Elemental.Element.FIRE: 1, Elemental.Element.WATER: 1, Elemental.Element.EARTH: 1,
		Elemental.Element.AIR: 1, Elemental.Element.AETHER: 1,
	})
	assert_bool(_carving([Elemental.Element.FIRE]).can_channel(isaac, Elemental.Element.FIRE)).is_true()
	var athanor: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.FIRE, Elemental.Element.FIRE])
	assert_bool(athanor.can_channel(isaac, Elemental.Element.FIRE)).is_false()   # depth is still trained

# --- rune capacity ---

func test_small_rune_holds_one_basic_carving() -> void:
	var small: RuneData = RuneData.new()
	small.size = RuneData.Size.SMALL                                     # capacity 1
	assert_bool(small.inscribe(_carving([Elemental.Element.FIRE]))).is_true()     # cost 1 (one sigil)
	assert_bool(small.can_inscribe(_carving([Elemental.Element.WATER]))).is_false()   # full

func test_medium_rune_holds_a_pair_and_a_pure() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM                                      # capacity 3, circle cap 2
	var pair: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER])
	var pure: TransmutationData = _carving([Elemental.Element.FIRE])
	assert_bool(med.inscribe(pair)).is_true()                           # cost 2
	assert_bool(med.inscribe(pure)).is_true()                           # cost 1
	assert_int(med.used_capacity()).is_equal(3)

func test_large_rune_holds_a_triple_and_a_pure() -> void:
	var large: RuneData = RuneData.new()
	large.size = RuneData.Size.LARGE                                     # capacity 6, circle cap 3
	var triple: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER, Elemental.Element.EARTH])
	var pure: TransmutationData = _carving([Elemental.Element.FIRE])
	assert_bool(large.inscribe(triple)).is_true()                       # cost 3
	assert_bool(large.inscribe(pure)).is_true()                         # cost 1
	assert_int(large.used_capacity()).is_equal(4)

func test_circle_cap_blocks_an_oversized_carving_even_with_capacity_free() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM                                      # capacity 3, circle cap 2
	var triple: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER, Elemental.Element.EARTH])
	assert_bool(med.can_inscribe(triple)).is_false()                    # cost 3 fits capacity, 3 sigils don't fit the cap

func test_repeated_sigils_cost_capacity_per_sigil() -> void:
	assert_int(_carving([Elemental.Element.FIRE, Elemental.Element.FIRE]).cost()).is_equal(2)

# --- load-time legality (#60: both knobs enforced independently of inscribe()'s add-time gate) ---

func test_rune_is_legal_catches_a_hand_edited_capacity_violation() -> void:
	var small: RuneData = RuneData.new()
	small.size = RuneData.Size.SMALL                                     # capacity 1, circle cap 1
	small.inscriptions.append(_carving([Elemental.Element.FIRE]))
	small.inscriptions.append(_carving([Elemental.Element.WATER]))       # bypasses inscribe()'s gate
	assert_bool(small.is_legal()).is_false()

func test_rune_is_legal_catches_a_hand_edited_circle_cap_violation() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM                                      # capacity 3, circle cap 2
	med.inscriptions.append(_carving([Elemental.Element.FIRE, Elemental.Element.WATER, Elemental.Element.EARTH]))   # cost 3 fits capacity; 3 sigils don't fit the cap
	assert_bool(med.is_legal()).is_false()

func test_transmutation_is_legal_rejects_exotic_sigils_and_oversized_carvings() -> void:
	assert_bool(_carving([Elemental.Element.FIRE]).is_legal()).is_true()
	assert_bool(_carving([Elemental.Element.ICE]).is_legal()).is_false()   # exotic, not a sigil
	var four: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER, Elemental.Element.EARTH, Elemental.Element.AIR])
	assert_bool(four.is_legal()).is_false()                             # 4 sigils > the global max circle cap (L, 3)

# --- the temper rule (#60): first carving sets it permanently; later carvings must contain
# it and never outweigh it (ties legal) ---

func test_inscribe_sets_temper_from_the_first_carving() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM
	med.inscribe(_carving([Elemental.Element.WATER, Elemental.Element.FIRE]))   # primary = WATER (first-seen tie)
	assert_int(med.temper).is_equal(Elemental.Element.WATER)

func test_temper_accepts_a_tied_weight_carving() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM
	med.inscribe(_carving([Elemental.Element.FIRE]))                    # temper = FIRE, weight 1
	var tied: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER])   # tie is legal
	assert_bool(med.can_inscribe(tied)).is_true()

func test_temper_rejects_a_carving_that_outweighs_it() -> void:
	var large: RuneData = RuneData.new()
	large.size = RuneData.Size.LARGE
	large.inscribe(_carving([Elemental.Element.FIRE]))                  # temper = FIRE, weight 1
	var outweighs: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.AIR, Elemental.Element.AIR])   # 1F/2A -- off-temper heavier
	assert_bool(large.can_inscribe(outweighs)).is_false()

func test_temper_rejects_a_carving_missing_the_temper_element() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM
	med.inscribe(_carving([Elemental.Element.FIRE]))                    # temper = FIRE
	assert_bool(med.can_inscribe(_carving([Elemental.Element.WATER]))).is_false()   # no fire at all

func test_rune_is_legal_catches_a_hand_edited_temper_violation() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM
	med.temper = Elemental.Element.FIRE
	med.inscriptions.append(_carving([Elemental.Element.WATER]))         # bypasses inscribe() -- no fire at all
	assert_bool(med.is_legal()).is_false()

func test_rune_is_legal_catches_inscriptions_with_no_temper_set() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM
	med.inscriptions.append(_carving([Elemental.Element.FIRE]))          # bypassed inscribe(); temper never set
	assert_bool(med.is_legal()).is_false()

# --- sigil identity ---

func test_primary_element_is_the_highest_weight() -> void:
	var t: TransmutationData = _carving([Elemental.Element.EARTH, Elemental.Element.FIRE, Elemental.Element.EARTH])
	assert_int(t.primary_element()).is_equal(Elemental.Element.EARTH)

func test_primary_element_tie_goes_to_first_inscribed() -> void:
	var t: TransmutationData = _carving([Elemental.Element.WATER, Elemental.Element.FIRE])
	assert_int(t.primary_element()).is_equal(Elemental.Element.WATER)

func test_exotics_are_not_legal_sigils() -> void:
	assert_bool(_carving([Elemental.Element.FIRE]).has_legal_sigils()).is_true()
	assert_bool(_carving([Elemental.Element.ICE]).has_legal_sigils()).is_false()

# --- flourishes: slots + opposites ---

func test_flourish_slots_follow_the_sigil_curve() -> void:
	assert_int(_carving([]).flourish_slots()).is_equal(0)
	assert_int(_carving([Elemental.Element.FIRE]).flourish_slots()).is_equal(1)
	assert_int(_carving([Elemental.Element.FIRE, Elemental.Element.FIRE]).flourish_slots()).is_equal(3)
	assert_int(_carving([Elemental.Element.FIRE, Elemental.Element.AIR, Elemental.Element.AIR]).flourish_slots()).is_equal(5)

func test_flourishes_capped_by_slots() -> void:
	var t: TransmutationData = _carving([Elemental.Element.FIRE])   # 1 slot
	assert_bool(t.can_add_flourish(Flourish.Type.SPREAD)).is_true()
	t.flourishes.append(Flourish.Type.SPREAD)
	assert_bool(t.can_add_flourish(Flourish.Type.PUSH)).is_false()   # full

func test_opposite_flourishes_reject() -> void:
	var t: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.FIRE])   # 3 slots
	t.flourishes.append(Flourish.Type.SPREAD)
	assert_bool(t.can_add_flourish(Flourish.Type.FOCUS)).is_false()   # solve et coagula
	assert_bool(t.can_add_flourish(Flourish.Type.PUSH)).is_true()

# --- derived elements (the exotic lookup) ---

func test_water_stillness_derives_ice() -> void:
	var t: TransmutationData = _carving([Elemental.Element.WATER])
	t.flourishes.append(Flourish.Type.STILLNESS)
	assert_array(t.get_elements()).contains_exactly([Elemental.Element.ICE])

func test_fire_quickening_derives_shock() -> void:
	var t: TransmutationData = _carving([Elemental.Element.FIRE])
	t.flourishes.append(Flourish.Type.QUICKENING)
	assert_array(t.get_elements()).contains_exactly([Elemental.Element.SHOCK])

func test_underived_sigils_tag_as_themselves() -> void:
	var t: TransmutationData = _carving([Elemental.Element.WATER, Elemental.Element.FIRE])
	t.flourishes.append(Flourish.Type.STILLNESS)   # derives water only; fire has no STILLNESS entry
	assert_array(t.get_elements()).contains_exactly([Elemental.Element.ICE, Elemental.Element.FIRE])

func test_no_flourish_tags_the_raw_sigils() -> void:
	assert_array(_carving([Elemental.Element.WATER]).get_elements()).contains_exactly([Elemental.Element.WATER])
