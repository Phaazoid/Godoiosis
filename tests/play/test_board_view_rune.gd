# Guards the headless unit line for a carried RUNE (#614). BoardView's weapon branch has always
# named power, pattern and counter — the rune branch named a size and a count, so a driver reading
# the bridge could not see an alchemist's reach, damage or counter at all and had to go read the
# .tres files. Asserts through render_overview rather than the private helper, so the wire that
# hands the WIELDER down (_unit_line -> _weapon_str -> _rune_str) is covered as well as the format:
# the rune's attack list is a property OF the pairing, so a rune rendered without its wielder can
# only ever report a catalogue.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")

const PLAYER := Team.Faction.PLAYER
const FIRE := Elemental.Element.FIRE
const WATER := Elemental.Element.WATER

var _board: Dictionary


func before_test() -> void:
	_board = BoardBuilder.build(self)
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(-2, -2, 12, 12))


# ---- fixtures ----

func _spawn(unit_name: String, cell := Vector2i(0, 0)) -> Unit:
	var data := UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, PLAYER)
	return BoardBuilder.spawn(_board, data, cell)


# Aura + affinity together, mirroring tests/runes/test_channel_reasons.gd's alchemist: a carving
# channels off BOTH, so seeding one alone still reads as blocked.
func _give_aura(unit: Unit, element: Elemental.Element, amount: int = 5) -> void:
	var aura: Dictionary[Elemental.Element, int] = {}
	aura[element] = amount
	unit.unit_instance.aura = aura
	var affinity: Array[Elemental.Element] = [element]
	unit.unit_instance.affinity = affinity


func _line_carving(display_name: String, power: int, length: int) -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = display_name
	t.power = power
	var p := ForwardLinePattern.new()
	p.length = length
	t.attack_pattern = p
	t.sigils.assign([FIRE] as Array[Elemental.Element])
	return t


func _wide_carving(display_name: String, power: int, length: int, width: int) -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = display_name
	t.power = power
	var p := ForwardWidePattern.new()
	p.length = length
	p.width = width
	t.attack_pattern = p
	t.sigils.assign([FIRE] as Array[Elemental.Element])
	return t


func _rune_of(carvings: Array[TransmutationData]) -> RuneData:
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	for c in carvings:
		assert_bool(rune.inscribe(c)) \
			.override_failure_message("fixture carving '%s' failed to inscribe" % c.display_name) \
			.is_true()
	return rune


func _overview() -> String:
	var session = PlaySession.new(_board)
	return BoardView.render_overview(session)


# ==============================================================================
#  The bug: a rune's reach and power were invisible
# ==============================================================================

func test_a_rune_line_names_every_carvings_power_and_pattern() -> void:
	var alch := _spawn("Isaac")
	_give_aura(alch, FIRE)
	alch.add_item(_rune_of([
		_line_carving("Emberline", 4, 3),
		_wide_carving("Emberwash", 2, 2, 1),
	]))

	var text := _overview()

	# The size/count head is kept — it is the one thing the old line got right.
	assert_str(text).contains("rune[LARGE x2]")
	# ...and each carving now carries what actually decides a move: damage and reach.
	assert_str(text).contains("Emberline pow4 ForwardLine[L3]")
	assert_str(text).contains("Emberwash pow2 ForwardWide[L2 W1]")


func test_a_carvings_element_comes_from_its_sigils() -> void:
	# elemental_damage_type is WeaponAttackData-only; a carving carries FIRE in `sigils`, and
	# reading the weapon field here would be a runtime error rather than a blank.
	var alch := _spawn("Isaac")
	_give_aura(alch, FIRE)
	alch.add_item(_rune_of([_line_carving("Emberline", 4, 3)]))

	assert_str(_overview()).contains("ForwardLine[L3]/FIRE")


# ==============================================================================
#  The catalogue law: unfireable is LISTED and explained, never hidden
# ==============================================================================

func test_an_unchannelable_carving_is_still_listed_and_carries_its_reason() -> void:
	# RuneData.choice_attacks is deliberately the catalogue rather than the affordable subset —
	# dropping the row would tell a driver the carving does not exist, when what it needs to know
	# is what would unlock it.
	#
	# The wielder must still be able to WIELD the rune: can_equip (#157) needs one channelable
	# carving, so "an alchemist with no aura" renders (unarmed) and cannot exercise this at all.
	# Aura FIRE 1 pays the cheap carving and leaves the expensive one 2 wildcards short of 1.
	var alch := _spawn("Rebecca")
	_give_aura(alch, FIRE, 1)
	var payable := _line_carving("Emberline", 4, 3)                 # sigils [FIRE]
	var unpayable := _line_carving("Emberstorm", 6, 3)
	unpayable.sigils.assign([FIRE, FIRE, WATER] as Array[Elemental.Element])
	var rune := _rune_of([payable, unpayable])                      # payable first: it sets temper

	# Preconditions, or the case passes vacuously on a rune nobody could hold.
	assert_bool(payable.can_channel(alch, rune.temper)) \
		.override_failure_message("fixture: the cheap carving must channel or the rune won't equip") \
		.is_true()
	assert_bool(unpayable.can_channel(alch, rune.temper)) \
		.override_failure_message("fixture: the expensive carving must NOT channel") \
		.is_false()
	alch.add_item(rune)

	var text := _overview()

	assert_str(text).contains("Emberline pow4 ForwardLine[L3]")
	assert_str(text).contains("Emberstorm pow6 ForwardLine[L3]")
	assert_str(text).contains("blocked:")


# ==============================================================================
#  The widened signature changes nothing for a weapon
# ==============================================================================

func test_a_weapon_line_is_unchanged_by_the_wielder_parameter() -> void:
	var fighter := _spawn("Ross")
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 6
	fighter.add_item(WeaponInstance.make(template))

	assert_str(_overview()).contains("CHAINSWORD pow6 melee[1]/ctr")
