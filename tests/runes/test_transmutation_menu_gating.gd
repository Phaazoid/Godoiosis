# The Transmutation submenu's SOURCE OF TRUTH (#88, 2026-07-29). #88 is a menu-layer regrouping:
# a rune's carvings moved out of the Attack pick-menu into their own top-level category, separate
# from Ability Action on purpose (dev call — runes are equippables, transmutations are not ability
# use, so folding them together as the issue originally proposed would conflate two things).
#
# What's testable is the data half, and it is the half that decides what the player sees:
# EquippableData.choice_attacks (inert by default) -> RuneData's override -> Unit's two delegators.
# The menu construction itself lives in MainActionMenu and has ZERO runner coverage (#114), so the
# category's *contents* are pinned here and its wiring is feel-tested.
#
# The paired law: Attack must stay submenu-free for a rune too, i.e. firing with no pick chosen
# still lands the rune's default carving. That's what let begin_attack collapse to two lines.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)


func _carving(element: Elemental.Element, power: int = 4) -> TransmutationData:
	var t := TransmutationData.new()
	t.power = power
	t.sigils.assign([element])
	return t


# A wielder who can actually pay for what the rune holds: aura in every element it's carved with.
func _alchemist(aura: Dictionary[Elemental.Element, int]) -> Unit:
	var u: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	u.unit_instance.aura = aura
	var affinity: Array[Elemental.Element] = []
	for element in aura:
		affinity.append(element)
	u.unit_instance.affinity = affinity
	return u


func _rune_with(carvings: Array[TransmutationData], size: RuneData.Size = RuneData.Size.LARGE) -> RuneData:
	var rune := RuneData.new()
	rune.size = size
	rune.display_name = "Test Rune"
	for c in carvings:
		rune.inscribe(c)
	return rune


func _wielding(unit: Unit, item: EquippableData) -> void:
	unit.add_item(item)
	unit.equipped_weapon = item


# --- the default: nothing offers a Transmutation category ---

func test_an_empty_slot_offers_no_transmutations() -> void:
	var unit: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, false)
	unit.equipped_weapon = null
	assert_array(unit.get_transmutation_choices()).is_empty()
	assert_bool(unit.has_transmutations()).is_false()


func test_a_weapon_offers_no_transmutations() -> void:
	# The split that keeps the two categories apart: a weapon's extras belong to Weapon Action,
	# because a weapon HAS an authored main_attack. choice_attacks is the rune's side of that fork
	# and stays inert here, exactly as secondary_attacks() stays empty for a rune.
	var unit: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, true, 4)
	assert_array(unit.get_transmutation_choices()).is_empty()
	assert_bool(unit.has_transmutations()).is_false()


# --- a rune fills it ---

func test_a_rune_offers_every_channelable_carving() -> void:
	# ALL of them, not "all but the default": a rune has no authored main, so its carvings are
	# interchangeable equals and hiding whichever one happens to sort first would be arbitrary.
	var alch := _alchemist({ Elemental.Element.FIRE: 4 })
	_wielding(alch, _rune_with([_carving(Elemental.Element.FIRE), _carving(Elemental.Element.FIRE, 6)]))
	assert_int(alch.get_transmutation_choices().size()).is_equal(2)
	assert_bool(alch.has_transmutations()).is_true()


func test_the_category_opens_for_a_SINGLE_carving() -> void:
	# Deliberately NOT gated at two (dev call 2026-07-29, reversing the first draft). With one
	# carving this duplicates what Attack fires, and that is accepted: the submenu is a READOUT as
	# much as a picker — hover descriptions and blotted-out unqualified carvings are coming
	# (visual-clarity.md), and those make it worth a row even with no alternative to choose.
	var alch := _alchemist({ Elemental.Element.FIRE: 4 })
	_wielding(alch, _rune_with([_carving(Elemental.Element.FIRE)]))
	assert_int(alch.get_transmutation_choices().size()).is_equal(1)
	assert_bool(alch.has_transmutations()).is_true()


func test_an_aura_dry_wielder_gets_no_category() -> void:
	# choice_attacks routes through the aura-filtered channelable(), so a carving you cannot pay
	# for is ABSENT rather than listed-and-disabled. That differs from a weapon's unfireable
	# secondary, and closing the gap is the open visual-clarity item — recorded here so a future
	# change to blotted-out entries updates this expectation on purpose, not by accident.
	var broke: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, false)
	_wielding(broke, _rune_with([_carving(Elemental.Element.FIRE)]))
	assert_array(broke.get_transmutation_choices()).is_empty()
	assert_bool(broke.has_transmutations()).is_false()


# --- the paired law: Attack stays submenu-free ---

func test_attack_with_no_pick_fires_the_runes_default_carving() -> void:
	# What let MainActionMenu.begin_attack collapse to `active_attack = null; enter_attack_mode`.
	# get_fired_attack()'s null fallback returns default_attack(), and RuneData.default_attack is
	# channelable()[0] — precisely the pick the old rune branch used to assign by hand. If this
	# ever diverges, pressing Attack on a rune silently fires the wrong carving.
	var alch := _alchemist({ Elemental.Element.FIRE: 4 })
	var first := _carving(Elemental.Element.FIRE)
	_wielding(alch, _rune_with([first, _carving(Elemental.Element.FIRE, 6)]))

	alch.active_attack = null
	assert_object(alch.get_fired_attack()).is_same(first)
	assert_object(alch.get_fired_attack()).is_same(alch.get_transmutation_choices()[0])


func test_a_live_pick_still_wins_over_the_default() -> void:
	var alch := _alchemist({ Elemental.Element.FIRE: 4 })
	var second := _carving(Elemental.Element.FIRE, 6)
	_wielding(alch, _rune_with([_carving(Elemental.Element.FIRE), second]))

	alch.active_attack = second
	assert_object(alch.get_fired_attack()).is_same(second)


# --- the two categories stay disjoint ---

func test_weapon_action_and_transmutation_never_both_fill() -> void:
	# One equipped slot, so exactly one of the two submenu sources can be non-empty. Pinning it
	# because the failure mode is a top-level menu showing both categories for one item.
	var alch := _alchemist({ Elemental.Element.FIRE: 4 })
	_wielding(alch, _rune_with([_carving(Elemental.Element.FIRE), _carving(Elemental.Element.FIRE, 6)]))
	assert_bool(alch.has_transmutations()).is_true()
	assert_array(alch.get_weapon_secondary_attacks()).is_empty()
	assert_bool(alch.has_weapon_actions()).is_false()
