extends GdUnitTestSuite

# Aura-scaled transmutations + the rune container (docs/design/alchemy-kit.md), now on the
# sigil/flourish anatomy (docs/design/transmutation-model-proposal.md):
#   - sigils: repeats = weight; cost capacity, scale off aura, grant flourish slots
#   - channeling: anchor + wildcards (dev 2026-08-10, replacing #60's temper/leeway/strain
#     model) -- real aura in one of the carving's elements, total deficit covered by the
#     universal +1 OR spare temper aura, never both
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

# --- materia empowerment (#694): +1 EFFECTIVE aura in an element the caster can draw on ---
# WHERE that list comes from is Materia's (tests/runes/test_materia_sources.gd); here it is
# passed in, because a carving has no board and must never grow one.

func test_empowerment_adds_one_per_matching_sigil() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 7 })
	var t: TransmutationData = _carving([Elemental.Element.FIRE], 5)
	assert_int(t.base_damage(u, [Elemental.Element.FIRE])).is_equal(13)   # 12 + 1

# It is +1 AURA, not +1 damage, so a repeated sigil weights it exactly as it weights the real
# pool -- the reason it enters the loop rather than the total.
func test_empowerment_weights_with_repeated_sigils() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 3, Elemental.Element.EARTH: 2 })
	var t: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.FIRE, Elemental.Element.EARTH], 5)
	assert_int(t.base_damage(u, [Elemental.Element.FIRE])).is_equal(15)   # 13 + 1 + 1

func test_empowerment_in_an_element_the_carving_lacks_does_nothing() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 7 })
	var t: TransmutationData = _carving([Elemental.Element.FIRE], 5)
	assert_int(t.base_damage(u, [Elemental.Element.WATER])).is_equal(12)   # unchanged

# Empowerment is SCALING, and a utility carving suppresses scaling entirely (#126) -- which is
# the structural reason #695's authored form exists: the fallback can never reach one.
func test_a_damageless_carving_gains_nothing_from_empowerment() -> void:
	var u: Unit = _alchemist({ Elemental.Element.AIR: 4 })
	var t: TransmutationData = _carving([Elemental.Element.AIR], 5)
	t.deals_no_damage = true
	assert_int(t.base_damage(u, [Elemental.Element.AIR])).is_equal(0)

# An element the wielder has NO pool in still gains the point: empowerment is drawn from the
# ground, not from talent. (Whether the carving may be channelled at all is a different
# question, asked below and deliberately untouched by any of this.)
func test_empowerment_applies_without_a_pool_in_that_element() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 2 })
	var t: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER], 5)
	assert_int(t.base_damage(u, [Elemental.Element.WATER])).is_equal(8)   # 5 + 2 + 0 + 1

# --- channeling gate: anchor + wildcards (dev 2026-08-10, replacing the 2026-07-04 temper/
# trained-leeway/strain model — repeal record in transmutation-model-proposal.md). One case per
# row of the plan's worked-examples table. NB the dev's own two illustration carvings were
# 4-sigil arithmetic sketches, which the circle caps make un-authorable; the pins below use
# the legal 3-sigil fixtures that isolate the same two rules (spare accounting, no stacking). ---

func test_rebecca_no_aura_anywhere_channels_nothing() -> void:
	var u: Unit = _alchemist({})   # no aura, no affinity
	assert_bool(_carving([Elemental.Element.FIRE]).can_channel(u, Elemental.Element.FIRE)).is_false()

# (The old stray-aura-outside-affinity case left with the ladder's has_any_affinity branch: the
# anchor reads AURA, and "aura never exists outside affinity" is the SEEDING seam's invariant —
# UnitInstance.initialize() drops out-of-affinity aura loudly, the dev editor erases it on an
# affinity untoggle. One question, one owner.)

func test_the_anchor_needs_aura_in_one_of_the_carvings_own_elements() -> void:
	# Water-5 is real training, but this carving touches none of it — wildcards never anchor.
	var u: Unit = _alchemist({ Elemental.Element.WATER: 5 })
	var pair: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.AIR])
	assert_bool(pair.can_channel(u, Elemental.Element.FIRE)).is_false()

func test_a_maim_taxed_pool_at_zero_loses_the_anchor() -> void:
	# Affinity (the birthright) persists at aura 0; the anchor reads the POINT, so it's gone.
	var u: Unit = _alchemist({ Elemental.Element.AIR: 0 })
	assert_bool(_carving([Elemental.Element.AIR]).can_channel(u, Elemental.Element.AIR)).is_false()

func test_the_motivating_case_one_shared_element_plus_the_free_wildcard() -> void:
	# Aldin: aether-1 only, [1 Air, 1 Aether] — anchor on aether, deficit 1 <= pool A's
	# universal +1, on ANY rune (here air-tempered, where his aether gives pool B nothing).
	var u: Unit = _alchemist({ Elemental.Element.AETHER: 1 })
	var wind: TransmutationData = _carving([Elemental.Element.AIR, Elemental.Element.AETHER])
	assert_bool(wind.can_channel(u, Elemental.Element.AIR)).is_true()
	assert_int(wind.total_deficit(u)).is_equal(1)

func test_a_fully_covered_carving_spends_no_wildcards() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 1 })
	var t: TransmutationData = _carving([Elemental.Element.FIRE])
	assert_bool(t.can_channel(u, Elemental.Element.FIRE)).is_true()
	assert_int(t.total_deficit(u)).is_equal(0)

func test_the_free_wildcard_covers_one_point_of_depth_too() -> void:
	# "3-Fire demands true fire-3" is repealed: fire-1 channels 2-Fire via pool A. Depth and
	# breadth are one currency now — but only one point of it on an unmatched rune.
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 1 })
	assert_bool(_carving([Elemental.Element.FIRE, Elemental.Element.FIRE]).can_channel(u, Elemental.Element.FIRE)).is_true()
	var athanor: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.FIRE, Elemental.Element.FIRE])
	assert_bool(athanor.can_channel(u, Elemental.Element.FIRE)).is_false()   # deficit 2 > capacity 1

func test_spare_temper_aura_is_the_second_pool() -> void:
	# Dev's example: Air-3, [1A 1F 1W] — on the air rune spare 3-1 = 2 covers the deficit 2;
	# on a fire rune (their fire is 0) only the universal +1 remains, and it refuses.
	var u: Unit = _alchemist({ Elemental.Element.AIR: 3 })
	var triple: TransmutationData = _carving([Elemental.Element.AIR, Elemental.Element.FIRE, Elemental.Element.WATER])
	assert_bool(triple.can_channel(u, Elemental.Element.AIR)).is_true()
	assert_bool(triple.can_channel(u, Elemental.Element.FIRE)).is_false()

func test_the_pools_never_stack_and_the_pool_is_the_SPARE() -> void:
	# Air-2, same triple, air rune: deficit 2, spare = 2-1 = 1, capacity = max(1, 1) = 1 ->
	# refused. This one fixture kills BOTH wrong models: stacked pools (1 + spare = 2) would
	# channel it, and a full-aura pool (max(1, 2) = 2) would channel it. Falsified against each.
	var u: Unit = _alchemist({ Elemental.Element.AIR: 2 })
	var triple: TransmutationData = _carving([Elemental.Element.AIR, Elemental.Element.FIRE, Elemental.Element.WATER])
	assert_bool(triple.can_channel(u, Elemental.Element.AIR)).is_false()
	assert_int(triple.total_deficit(u)).is_equal(2)
	assert_int(triple.wildcard_capacity(u, Elemental.Element.AIR)).is_equal(1)

func test_isaac_alkahest_breadth_now_carries_one_point_of_depth() -> void:
	# Universal breadth, trained depth — amended 2026-08-10: pool A hands Isaac +1 depth in
	# every element (2-Fire channels at fire-1), but only the one point (Athanor still refused).
	var isaac: Unit = _alchemist({
		Elemental.Element.FIRE: 1, Elemental.Element.WATER: 1, Elemental.Element.EARTH: 1,
		Elemental.Element.AIR: 1, Elemental.Element.AETHER: 1,
	})
	assert_bool(_carving([Elemental.Element.FIRE, Elemental.Element.FIRE]).can_channel(isaac, Elemental.Element.FIRE)).is_true()
	var athanor: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.FIRE, Elemental.Element.FIRE])
	assert_bool(athanor.can_channel(isaac, Elemental.Element.FIRE)).is_false()   # deficit 2 > capacity 1

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
