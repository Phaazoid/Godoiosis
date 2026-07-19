extends GdUnitTestSuite

# Aura-scaled transmutations + the rune container (docs/design/alchemy-kit.md), now on the
# sigil/flourish anatomy (docs/design/transmutation-model-proposal.md, provisional):
#   - sigils: repeats = weight; cost capacity, scale off aura, grant flourish slots
#   - channeling: >=1 aura per DISTINCT element, minus the runestone's one leeway point
#   - flourishes: slot-capped shaping marks; opposites reject; derive exotics (ICE/SHOCK)
# FIRING through the resolver is covered in tests/runes/test_rune_firing.gd.

const H := preload("res://tests/support/squad_fixtures.gd")

# An alchemist with an explicit per-element aura map (most fields default to 0).
func _alchemist(auras: Dictionary[Elemental.Element, int]) -> Unit:
	var u: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	u.unit_instance.aura = auras
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

# --- channeling gate (aura floor + the runestone's one leeway point) ---

func test_zero_aura_channels_one_simple_carving_via_leeway() -> void:
	var u: Unit = _alchemist({})
	assert_bool(_carving([Elemental.Element.FIRE]).can_channel(u)).is_true()                       # 1 uncovered <= 1
	assert_bool(_carving([Elemental.Element.FIRE, Elemental.Element.WATER]).can_channel(u)).is_false()  # 2 > 1

func test_one_point_unlocks_that_element_plus_one_other() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 1 })
	# fire covered by real aura; the partner element rides the leeway
	assert_bool(_carving([Elemental.Element.FIRE, Elemental.Element.WATER]).can_channel(u)).is_true()

func test_repeated_sigils_do_not_double_count_the_channel_gate() -> void:
	var u: Unit = _alchemist({})
	# 2 Fire = ONE distinct uncovered element -> still rides the single leeway point
	assert_bool(_carving([Elemental.Element.FIRE, Elemental.Element.FIRE]).can_channel(u)).is_true()

# --- rune capacity ---

func test_small_rune_holds_one_basic_carving() -> void:
	var small: RuneData = RuneData.new()
	small.size = RuneData.Size.SMALL                                     # capacity 1
	assert_bool(small.inscribe(_carving([Elemental.Element.FIRE]))).is_true()     # cost 1 (one sigil)
	assert_bool(small.can_inscribe(_carving([Elemental.Element.WATER]))).is_false()   # full

func test_medium_rune_holds_a_tier3_plus_a_tier1() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM                                      # capacity 6
	var tier3: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER, Elemental.Element.EARTH])
	var tier1: TransmutationData = _carving([Elemental.Element.FIRE])
	assert_bool(med.inscribe(tier3)).is_true()                          # cost 3
	assert_bool(med.inscribe(tier1)).is_true()                          # cost 1
	assert_int(med.used_capacity()).is_equal(4)

func test_repeated_sigils_cost_capacity_per_sigil() -> void:
	assert_int(_carving([Elemental.Element.FIRE, Elemental.Element.FIRE]).cost()).is_equal(2)

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
