extends GdUnitTestSuite

# Aura-scaled transmutations + the rune container (docs/design/alchemy-kit.md).
# Proves the MODEL: a transmutation scales off the wielder's per-element aura and is gated
# by a channeling rule (>=1 aura per element, minus the runestone's one leeway point); a rune
# holds carvings up to its size's capacity. FIRING through the resolver is a later slice.

const H := preload("res://tests/support/squad_fixtures.gd")

# An alchemist with an explicit per-element aura map (most fields default to 0).
func _alchemist(auras: Dictionary) -> Unit:
	var u: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	u.unit_instance.aura = auras
	return u

func _carving(elements: Array, power: int = 0) -> TransmutationData:
	var t: TransmutationData = TransmutationData.new()
	t.elements.assign(elements)
	t.power = power
	return t

# --- aura scaling (the corrected, multi-element model) ---

func test_single_element_scales_off_that_aura() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 7 })
	assert_int(_carving([Elemental.Element.FIRE], 5).base_damage(u)).is_equal(12)   # 5 + 7

func test_multi_element_sums_constituent_auras() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 3, Elemental.Element.WATER: 4 })
	var t: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER], 5)
	assert_int(t.tier()).is_equal(2)
	assert_int(t.base_damage(u)).is_equal(12)   # 5 + 3 + 4

# --- channeling gate (aura floor + the runestone's one leeway point) ---

func test_zero_aura_channels_one_simple_carving_via_leeway() -> void:
	var u: Unit = _alchemist({})
	assert_bool(_carving([Elemental.Element.FIRE]).can_channel(u)).is_true()                       # 1 uncovered <= 1
	assert_bool(_carving([Elemental.Element.FIRE, Elemental.Element.WATER]).can_channel(u)).is_false()  # 2 > 1

func test_one_point_unlocks_that_element_plus_one_other() -> void:
	var u: Unit = _alchemist({ Elemental.Element.FIRE: 1 })
	# fire covered by real aura; the partner element rides the leeway
	assert_bool(_carving([Elemental.Element.FIRE, Elemental.Element.WATER]).can_channel(u)).is_true()

# --- rune capacity ---

func test_small_rune_holds_one_basic_carving() -> void:
	var small: RuneData = RuneData.new()
	small.size = RuneData.Size.SMALL                                     # capacity 1
	assert_bool(small.inscribe(_carving([Elemental.Element.FIRE]))).is_true()     # cost 1 (tier 1)
	assert_bool(small.can_inscribe(_carving([Elemental.Element.WATER]))).is_false()   # full

func test_medium_rune_holds_a_tier3_plus_a_tier1() -> void:
	var med: RuneData = RuneData.new()
	med.size = RuneData.Size.MEDIUM                                      # capacity 6
	var tier3: TransmutationData = _carving([Elemental.Element.FIRE, Elemental.Element.WATER, Elemental.Element.SHOCK])
	var tier1: TransmutationData = _carving([Elemental.Element.FIRE])
	assert_bool(med.inscribe(tier3)).is_true()                          # cost 3
	assert_bool(med.inscribe(tier1)).is_true()                          # cost 1
	assert_int(med.used_capacity()).is_equal(4)
