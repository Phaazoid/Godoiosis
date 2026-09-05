# #744: EquippableData.can_equip_reason is THE rule and can_equip is derived from it, so a refusal
# and its explanation cannot drift apart. Before this there were three answers to "why not" -- armor's
# wielder-free requirement_text, a hardcoded "can't channel" on the equip button, and a generic
# "cannot equip it" on the pre-mission card, the last two of which could only ever be right by
# accident.
#
# THE INVARIANT CASE IS ONLY WORTH ANYTHING ON BOTH SIDES OF A GATE. Since can_equip IS
# reason.is_empty() on the base, a single default wielder makes the equivalence "" == "" and proves
# nothing; the one thing it can still catch is a kind re-overriding the boolean, and that only shows
# up where the two would disagree. So every shipped piece is asked against a wielder that passes it
# and one that fails it, and the sweep refuses to be vacuous.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const FIRE := Elemental.Element.FIRE
const PLAYER := Team.Faction.PLAYER

var _cell_seq := 0


func _next_cell() -> Vector2i:
	_cell_seq += 1
	return Vector2i(_cell_seq, 0)


func _wearer(overrides: Dictionary) -> Unit:
	return H.spawn_unit(self, PLAYER, _next_cell(), overrides, false)


# Aura and affinity in everything: whatever a shipped rune's carvings ask for, this body has it.
func _adept() -> Unit:
	var unit := _wearer({})
	var aura: Dictionary[Elemental.Element, int] = {}
	var affinity: Array[Elemental.Element] = []
	for element: Elemental.Element in Elemental.Element.values():
		if element == Elemental.Element.NONE:
			continue
		aura[element] = 9
		affinity.append(element)
	unit.unit_instance.aura = aura
	unit.unit_instance.affinity = affinity
	return unit


func _carving(sigils: Array[Elemental.Element]) -> TransmutationData:
	var carving := TransmutationData.new()
	carving.power = 5
	carving.sigils.assign(sigils)
	return carving


# ==================================================================================================
#  The seam: nothing overrides the boolean
# ==================================================================================================

# What a kind may override is the REASON. Overriding can_equip puts the two answers back in separate
# places, which is the state #744 replaced -- and nothing else in the tree would notice, because both
# halves would still be internally consistent. This is the case that notices.
func test_no_kind_answers_the_boolean_differently_from_its_reason() -> void:
	var refused := 0
	var admitted := 0

	var armors: Dictionary = ArmorCatalog.get_editable()
	for name: String in armors:
		var piece: ArmorData = armors[name]
		# A body either side of every gate this piece declares: one that clears each floor and sits
		# under each ceiling, one that fails all of them at once.
		var pass_overrides: Dictionary = {}
		var fail_overrides: Dictionary = {}
		for stat: Stats.Stat in piece.stat_minimums:
			pass_overrides[stat] = piece.stat_minimums[stat]
			fail_overrides[stat] = piece.stat_minimums[stat] - 1
		for stat: Stats.Stat in piece.stat_maximums:
			pass_overrides[stat] = piece.stat_maximums[stat]
			fail_overrides[stat] = piece.stat_maximums[stat] + 1
		for wearer: Unit in [_wearer(pass_overrides), _wearer(fail_overrides)]:
			var reason: String = piece.can_equip_reason(wearer)
			assert_bool(piece.can_equip(wearer)).override_failure_message(
				"%s: can_equip and its reason disagree (reason was %s)"
				% [name, "empty" if reason == "" else "\"%s\"" % reason]).is_equal(reason.is_empty())
			if reason == "":
				admitted += 1
			else:
				refused += 1

	var runes: Dictionary = RuneCatalog.get_editable()
	var adept := _adept()
	var novice := _wearer({})   # no aura, no affinity: nothing channels
	for name: String in runes:
		var rune: RuneData = runes[name]
		for wielder: Unit in [adept, novice]:
			var reason: String = rune.can_equip_reason(wielder)
			assert_bool(rune.can_equip(wielder)).override_failure_message(
				"%s: can_equip and its reason disagree (reason was %s)"
				% [name, "empty" if reason == "" else "\"%s\"" % reason]).is_equal(reason.is_empty())
			if reason == "":
				admitted += 1
			else:
				refused += 1

	# The vacuity guard: an equivalence nobody ever fails is an equivalence nobody is checking.
	assert_int(refused).override_failure_message(
		"no shipped piece refused anybody, so the disagreeing half of the invariant never ran").is_greater(0)
	assert_int(admitted).override_failure_message(
		"no shipped piece admitted anybody, so the agreeing half of the invariant never ran").is_greater(0)


# ==================================================================================================
#  What the sentences actually say
# ==================================================================================================

# The whole point of the widening: a bool could say "incompatible", so the player could not tell
# whether they were two points short or holding something their build can never wear. Both numbers,
# and EVERY failing gate rather than the first -- told only about the CON, you go and fix the wrong
# thing while the DEX ceiling still refuses you.
func test_armor_names_every_gate_it_fails_and_how_far_short() -> void:
	var plate := ArmorData.new()
	plate.display_name = "Test Plate"
	plate.stat_minimums[Stats.Stat.CON] = 8
	plate.stat_maximums[Stats.Stat.DEX] = 4

	var reason: String = plate.can_equip_reason(_wearer({Stats.Stat.CON: 5, Stats.Stat.DEX: 9}))
	assert_str(reason).override_failure_message(
		"the floor is not named: %s" % reason).contains("CON 8+")
	assert_str(reason).override_failure_message(
		"the body's own number is missing, so the player cannot see the gap: %s" % reason).contains("5")
	assert_str(reason).override_failure_message(
		"only the first failing gate was reported: %s" % reason).contains("DEX 4 or less")

	# ...and the same grammar the wielder-free question uses, which is the point of sharing _gate_text.
	assert_str(plate.requirement_text()).contains("CON 8+")
	assert_str(plate.requirement_text()).contains("DEX 4 or less")


# A rune's gate is "at least one channelable carving" (#157), so its refusal has to say what each
# carving would need -- one of three means the player's choice is which gap to close. Delegated to
# TransmutationData.channel_block_reason rather than re-worded, which is what keeps the equip refusal
# and the carving row in the inventory tooltip from describing one rune two ways.
func test_a_runes_refusal_carries_its_carvings_own_sentences() -> void:
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	rune.display_name = "Test Rune"
	var hot := _carving([FIRE])
	var hotter := _carving([FIRE, FIRE, FIRE])
	assert_bool(rune.inscribe(hot)).is_true()
	assert_bool(rune.inscribe(hotter)).is_true()

	var novice := _wearer({})
	var reason: String = rune.can_equip_reason(novice)
	assert_str(reason).override_failure_message("a dead rune said nothing").is_not_empty()
	assert_str(reason).override_failure_message(
		"the carving's own sentence did not reach the equip refusal: %s" % reason) \
		.contains(hot.channel_block_reason(novice, rune.temper))

	# One channelable carving is enough, and then there is nothing to say.
	var adept := _adept()
	assert_str(rune.can_equip_reason(adept)).override_failure_message(
		"a rune with a live carving still refused").is_empty()

	# A rune with nothing carved on it fails for everyone, and says which kind of nothing.
	var blank := RuneData.new()
	blank.size = RuneData.Size.SMALL
	assert_str(blank.can_equip_reason(adept)).override_failure_message(
		"a blank rune refused silently").is_not_empty()
