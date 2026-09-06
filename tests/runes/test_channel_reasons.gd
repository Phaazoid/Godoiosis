# #166: channeling has ONE ladder, and it answers WHY — the boolean is derived from it.
#
# `TransmutationData.can_channel` used to be the ladder and the menu carried a single hardcoded
# string for the only refusal it knew about (a weapon's readiness). A menu can only grey what it
# can explain, so the reason moved to where the fact lives and `can_channel` became a one-line read
# of it. These cases pin that they agree, branch for branch: two answers to "may this be channeled"
# is exactly the drift Law #4 forbids, and it would show up as a carving greyed for the wrong
# stated reason — or worse, listed as fireable while the resolver refuses it.
#
# The other half is `Unit.is_attack_fireable`, which is now derived the same way and so answers
# false for an unchannelable carving for the first time. Its most consequential reader is the
# queue-time gate, covered at the bottom.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const FIRE := Elemental.Element.FIRE
const EARTH := Elemental.Element.EARTH

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)


func _alchemist(aura: Dictionary[Elemental.Element, int], cell: Vector2i = Vector2i.ZERO) -> Unit:
	var u: Unit = H.spawn_solo(self, _sm, Team.Faction.PLAYER, cell, {}, false)
	u.unit_instance.aura = aura
	var affinity: Array[Elemental.Element] = []
	for element in aura:
		affinity.append(element)
	u.unit_instance.affinity = affinity
	return u


func _carving(sigils: Array[Elemental.Element], name: String = "Carving") -> TransmutationData:
	var t: TransmutationData = TransmutationData.new()
	t.display_name = name
	t.power = 5
	t.sigils.assign(sigils)
	return t


func _rune(carvings: Array[TransmutationData]) -> RuneData:
	var rune: RuneData = RuneData.new()
	rune.size = RuneData.Size.LARGE
	for c: TransmutationData in carvings:
		assert_bool(rune.inscribe(c)).override_failure_message("fixture carving failed to inscribe").is_true()
	return rune


# ==============================================================================
#  The ladder's two branches (anchor / coverage), each naming its own shortfall
# ==============================================================================

func test_no_aura_anywhere_reads_as_the_anchor_naming_the_elements() -> void:
	var no_aura: Dictionary[Elemental.Element, int] = {}
	var rebecca: Unit = _alchemist(no_aura)
	var carving: TransmutationData = _carving([FIRE])

	var reason := carving.channel_block_reason(rebecca, FIRE)
	assert_str(reason).contains("aura")
	assert_str(reason).contains("Fire")
	assert_bool(carving.can_channel(rebecca, FIRE)).is_false()


func test_the_anchor_reason_lists_every_element_that_would_open_the_carving() -> void:
	# Real training in the wrong element is still the anchor branch, and the reason tells the
	# player which elements would fix it — not how much they hold elsewhere.
	var alch: Unit = _alchemist({ Elemental.Element.WATER: 5 })
	var carving: TransmutationData = _carving([FIRE, EARTH])

	var reason := carving.channel_block_reason(alch, FIRE)
	assert_str(reason).contains("Fire")
	assert_str(reason).contains("Earth")
	assert_bool(carving.can_channel(alch, FIRE)).is_false()


func test_a_coverage_shortfall_names_both_wildcard_numbers() -> void:
	var alch: Unit = _alchemist({ FIRE: 1 })
	var carving: TransmutationData = _carving([FIRE, FIRE, FIRE])   # deficit 2, capacity 1

	var reason := carving.channel_block_reason(alch, FIRE)
	assert_str(reason).contains("wildcard")
	assert_str(reason).contains("2")
	assert_str(reason).contains("1")
	assert_bool(carving.can_channel(alch, FIRE)).is_false()


func test_a_channelable_carving_has_no_reason_at_all() -> void:
	var alch: Unit = _alchemist({ FIRE: 2 })
	var carving: TransmutationData = _carving([FIRE, FIRE])

	assert_str(carving.channel_block_reason(alch, FIRE)).is_empty()
	assert_bool(carving.can_channel(alch, FIRE)).is_true()


# ==============================================================================
#  Unit.is_attack_fireable, now derived from the same answer
# ==============================================================================

func test_is_attack_fireable_answers_false_for_an_unchannelable_carving() -> void:
	# The change that lets the menu grey a row: before #166 this was unconditionally true for a
	# carving, because the rune's list arrived pre-filtered and the question never got here.
	# (Fixture is a 3-Fire at fire-1 — deficit 2 past the wildcard — since 2026-08-10's model
	# made the old [FIRE, FIRE] fixture channelable.)
	var alch: Unit = _alchemist({ FIRE: 1 })
	var affordable: TransmutationData = _carving([FIRE], "Ember")
	var dear: TransmutationData = _carving([FIRE, FIRE, FIRE], "Inferno")
	alch.equipped_weapon = _rune([affordable, dear])

	assert_bool(alch.is_attack_fireable(affordable)).is_true()
	assert_bool(alch.is_attack_fireable(dear)).is_false()
	assert_str(alch.attack_block_reason(dear)).is_not_empty()


func test_the_unit_level_reason_is_the_carvings_own_words() -> void:
	# Unit delegates to the equippable, which delegates to the carving WITH the rune's temper —
	# the pairing the carving cannot see on its own.
	var alch: Unit = _alchemist({ FIRE: 1 })
	var dear: TransmutationData = _carving([FIRE, FIRE, FIRE], "Inferno")
	var rune: RuneData = _rune([dear])
	alch.equipped_weapon = rune

	assert_str(alch.attack_block_reason(dear)).is_equal(dear.channel_block_reason(alch, rune.temper))


func test_an_empty_slot_and_a_null_attack_stay_inert() -> void:
	# can_fire_default_attack documents a dependency on is_attack_fireable(null) being true —
	# "is this gated?" and "is there anything here?" are different questions.
	var u: Unit = H.spawn_solo(self, _sm, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	assert_bool(u.is_attack_fireable(null)).is_true()
	assert_str(u.attack_block_reason(null)).is_empty()
	assert_str(u.attack_detail(null)).is_empty()


# ==============================================================================
#  The consequential reader: queue-time gating
# ==============================================================================

func test_an_unchannelable_carving_cannot_be_QUEUED() -> void:
	# AttackAction.actor_can_perform reads is_attack_fireable, so the greyed row is backed by a
	# real refusal rather than by the menu alone — "you cannot author an invalid order". Ordered
	# through the Law #3 chokepoint, the only door the AI has either.
	var alch: Unit = _alchemist({ FIRE: 1 })
	var dear: TransmutationData = _carving([FIRE, FIRE, FIRE], "Inferno")
	alch.equipped_weapon = _rune([_carving([FIRE], "Ember"), dear])
	var foe: Unit = H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(1, 0))

	var aim: AttackAction = AttackAction.create(alch, alch.movement.cell, foe, foe.movement.cell)
	aim.fired_attack = dear

	assert_bool(_sm.queue_action(alch.squad, aim)) \
		.override_failure_message("an unchannelable carving was accepted into the queue").is_false()


func test_a_channelable_carving_still_queues() -> void:
	var alch: Unit = _alchemist({ FIRE: 1 })
	var affordable: TransmutationData = _carving([FIRE], "Ember")
	alch.equipped_weapon = _rune([affordable])
	var foe: Unit = H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(1, 0))

	var aim: AttackAction = AttackAction.create(alch, alch.movement.cell, foe, foe.movement.cell)
	aim.fired_attack = affordable

	assert_bool(_sm.queue_action(alch.squad, aim)).is_true()


# --- #694: empowerment is POWER, never PERMISSION -------------------------------------------
#
# The anchor, the deficit and both wildcard pools all read wielder.get_element_aura directly, and
# RuneData.can_equip_reason derives from channel_block_reason (#744) -- so leaving that accessor
# position-blind is the ONE thing keeping materia out of all three gates at once.
#
# Each case below proves the source is genuinely LIVE by asserting that base_damage DOES move for
# the same wielder and carving. Without that half a green result would only mean the fixture never
# empowered anything, which is exactly the vacuous negative this pair exists to avoid.

const EMPOWERED_WATER: Array[Elemental.Element] = [Elemental.Element.WATER]

func test_standing_on_a_source_does_not_grant_the_anchor() -> void:
	# No aura anywhere: the Rebecca rule, per-carving. A river cannot lend what talent must hold.
	var dry: Unit = _alchemist({})
	var wet_carving: TransmutationData = _carving([Elemental.Element.WATER], "Splash")

	assert_bool(wet_carving.can_channel(dry, Elemental.Element.WATER)) \
		.override_failure_message("a materia source granted the anchor").is_false()
	assert_str(wet_carving.channel_block_reason(dry, Elemental.Element.WATER)).is_not_empty()
	# ...and the source really is live for this pair, so the refusal above is not vacuous:
	assert_int(wet_carving.base_damage(dry, EMPOWERED_WATER)) \
		.is_greater(wet_carving.base_damage(dry))


func test_standing_on_a_source_does_not_widen_the_wildcard_budget() -> void:
	# Anchored in fire, but the water sigils outrun every pool: deficit 2 against a capacity of 1.
	var alch: Unit = _alchemist({ FIRE: 1 })
	var stretched: TransmutationData = _carving(
		[FIRE, Elemental.Element.WATER, Elemental.Element.WATER], "Steam")

	assert_bool(stretched.can_channel(alch, FIRE)) \
		.override_failure_message("a materia source paid a wildcard deficit").is_false()
	assert_int(stretched.base_damage(alch, EMPOWERED_WATER)) \
		.is_greater(stretched.base_damage(alch))


func test_a_rune_does_not_become_equippable_beside_a_source() -> void:
	# The equip gate walks inscriptions asking can_channel, so it inherits the rule above -- but
	# it is its own door and #157 force-unequips through it, so it is asserted rather than assumed.
	var dry: Unit = _alchemist({})
	var wet_carving: TransmutationData = _carving([Elemental.Element.WATER], "Splash")
	var rune: RuneData = _rune([wet_carving])

	assert_bool(rune.can_equip(dry)) \
		.override_failure_message("a materia source made a dead rune equippable").is_false()
	assert_str(rune.can_equip_reason(dry)).is_not_empty()
