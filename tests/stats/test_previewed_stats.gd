# #745's preview-at-decision: what a unit's numbers WOULD be with a piece of gear on.
#
# THE PROPERTY IS THAT THE PREVIEW EQUALS THE REALITY, so every case here equips the thing for real
# and compares -- never against a hand-computed expectation, which would pin today's arithmetic and
# say nothing about the two walks agreeing. That is also what makes them falsifiable against the
# actual hazard: DEF is a SECOND walk reading both the worn piece AND the CON its own modifiers move,
# so a preview that judges the new plate against the old plate's CON is wrong in a way only this
# comparison sees.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func _wearer(con: int) -> Unit:
	return H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: con}, false)


# A plate that pays DEF and also MOVES the CON that DEF scales off, which is the pairing that
# separates a correct preview from a plausible one.
func _plate() -> ArmorData:
	var plate := ArmorData.new()
	plate.display_name = "Test Plate"
	plate.def_power = 3
	plate.stat_modifiers[Stats.Stat.CON] = 4
	plate.stat_modifiers[Stats.Stat.DEX] = -1
	return plate


func test_the_preview_is_the_number_the_player_actually_gets() -> void:
	var unit := _wearer(5)
	var plate := _plate()
	assert_bool(unit.add_item(plate)).is_true()

	var promised: Dictionary[Stats.Stat, int] = {}
	for stat: Stats.Stat in Stats.STAT_DEFAULTS:
		promised[stat] = unit.previewed_stat(stat, plate)
	var promised_def := unit.previewed_def(plate)

	assert_bool(unit.wear_armor(unit.inventory.find(plate))).override_failure_message(
		"fixture: the plate would not go on").is_true()

	for stat: Stats.Stat in Stats.STAT_DEFAULTS:
		assert_int(unit.get_effective_stat(stat)).override_failure_message(
			"%s: the preview promised %d and wearing it gave %d"
			% [Stats.Stat.keys()[stat], promised[stat], unit.get_effective_stat(stat)]
			).is_equal(promised[stat])
	assert_int(unit.get_effective_def()).override_failure_message(
		"DEF: the preview promised %d and wearing it gave %d -- the plate moves the CON its own "
		% [promised_def, unit.get_effective_def()]
		+ "scaling reads, so the preview has to substitute BOTH").is_equal(promised_def)


# ...and it has to be a real preview rather than a restatement of what is already worn.
func test_the_preview_differs_from_the_live_numbers_it_replaces() -> void:
	var unit := _wearer(5)
	var plate := _plate()
	unit.add_item(plate)
	assert_int(unit.previewed_stat(Stats.Stat.CON, plate)).override_failure_message(
		"the preview ignored the candidate entirely").is_not_equal(
		unit.get_effective_stat(Stats.Stat.CON))
	assert_int(unit.previewed_def(plate)).is_not_equal(unit.get_effective_def())


# WEIGHT is the one answer that forks on WHERE the thing is coming from, because the two gestures
# ask different questions: taking a piece off the stash adds its mass to what this unit carries,
# while equipping something already in the pack moves nothing at all.
func test_weight_counts_an_incoming_piece_and_ignores_one_already_carried() -> void:
	var unit := _wearer(5)
	var plate := _plate()
	plate.weight = 7

	assert_int(unit.previewed_weight(plate, true)).override_failure_message(
		"an incoming piece weighed nothing").is_equal(unit.get_weight() + 7)
	unit.add_item(plate)
	assert_int(unit.previewed_weight(plate, false)).override_failure_message(
		"equipping something already carried changed what the unit is carrying").is_equal(
		unit.get_weight())


# --- what a hovered item DISPLACES (#1453) ------------------------------------------------------
#
# One case per item kind. Each hovers a STASH item beside a held weapon whose fitted mod pays DEX,
# then takes it for real: add_item, then the dock's own verb (GearVerbs) for a kind that has one. A
# kind that fills no slot displaces nothing, and a held prosthetic stays a mod source whatever comes
# into the hand. No shipped mod moves a stat, so the mods are built here.

const CARRY := -1   # taking it is carrying it: add_item, and no verb after


func _stat_mod(stat: Stats.Stat, amount: int) -> WeaponModData:
	var mod := WeaponModData.new()
	mod.display_name = "Test %s Mod" % Stats.Stat.keys()[stat]
	mod.stat_modifiers[stat] = amount
	return mod


func _modded(weapon: WeaponInstance, stat: Stats.Stat, amount: int) -> WeaponInstance:
	assert_bool(weapon.fit(0, _stat_mod(stat, amount))).override_failure_message(
		"fixture: the mod did not fit").is_true()
	return weapon


# Fire aura and affinity, so the rune case has a carving this unit can channel.
func _wielder_holding(held: WeaponInstance) -> Unit:
	var unit := _wearer(5)
	unit.unit_instance.aura = {Elemental.Element.FIRE: 4}
	var affinity: Array[Elemental.Element] = [Elemental.Element.FIRE]
	unit.unit_instance.affinity = affinity
	assert_bool(unit.add_item(held)).is_true()
	assert_object(unit.get_equipped_weapon()).override_failure_message(
		"fixture: add_item did not put the first weapon in hand").is_same(held)
	assert_int(unit.get_effective_stat(Stats.Stat.DEX)).override_failure_message(
		"fixture: the held weapon's mod pays nothing, so no case can see it displaced").is_not_equal(
		unit.get_body_stat(Stats.Stat.DEX))
	return unit


func _armed_wielder() -> Unit:
	return _wielder_holding(_modded(H.make_weapon(), Stats.Stat.DEX, 2))


# A prosthetic arm, fitted to a limb through the real door, that is ALSO the weapon in hand.
func _prosthetic_wielder() -> Unit:
	var template := WeaponData.new()
	template.display_name = "Test Arm"
	template.weapon_type = WeaponData.WeaponType.PROSTHETIC
	template.main_attack = WeaponAttackData.new()
	var arm := _modded(WeaponInstance.make(template), Stats.Stat.DEX, 2)
	var unit := _wielder_holding(arm)
	assert_bool(unit.unit_instance.install_prosthetic(UnitInstance.LimbSlot.ARM_L, arm)) \
		.override_failure_message("fixture: the arm did not install").is_true()
	return unit


# Every number the pre-mission card previews for an incoming item, against the number that arrives.
func _assert_preview_is_real(unit: Unit, candidate: Item, verb: int) -> void:
	var promised: Dictionary[Stats.Stat, int] = {}
	for stat: Stats.Stat in Stats.STAT_DEFAULTS:
		promised[stat] = unit.previewed_stat(stat, candidate)
	var promised_def := unit.previewed_def(candidate)
	var promised_mov := unit.previewed_mov(candidate, true)

	assert_bool(unit.add_item(candidate)).override_failure_message(
		"fixture: %s would not go into the pack" % candidate.shown_name()).is_true()
	if verb != CARRY:
		var refusal := GearVerbs.perform(unit, verb as GearVerbs.Verb, unit.inventory.find(candidate))
		assert_str(refusal).override_failure_message(
			"fixture: %s was refused: %s" % [candidate.shown_name(), refusal]).is_empty()

	for stat: Stats.Stat in Stats.STAT_DEFAULTS:
		assert_int(unit.get_effective_stat(stat)).override_failure_message(
			"%s with %s: the preview promised %d and taking it gave %d"
			% [Stats.Stat.keys()[stat], candidate.shown_name(), promised[stat], unit.get_effective_stat(stat)]
			).is_equal(promised[stat])
	assert_int(unit.get_effective_def()).override_failure_message(
		"DEF with %s: the preview promised %d and taking it gave %d"
		% [candidate.shown_name(), promised_def, unit.get_effective_def()]).is_equal(promised_def)
	assert_int(unit.get_mov()).override_failure_message(
		"MOV with %s: the preview promised %d and taking it gave %d"
		% [candidate.shown_name(), promised_mov, unit.get_mov()]).is_equal(promised_mov)


func test_a_hovered_weapon_displaces_the_one_in_hand() -> void:
	var sword := _modded(H.make_weapon(), Stats.Stat.STR, 3)
	sword.display_name = "Test Sword"
	_assert_preview_is_real(_armed_wielder(), sword, GearVerbs.Verb.EQUIP)


func test_a_hovered_rune_displaces_the_weapon_in_hand() -> void:
	var carving := TransmutationData.new()
	carving.power = 3
	carving.recipe = "Break(F, A) + Push(F2)"
	carving.targets = EquippableData.TargetMode.UNIT
	var rune := RuneData.new()
	rune.display_name = "Test Rune"
	rune.size = RuneData.Size.MEDIUM
	assert_bool(rune.inscribe(carving)).override_failure_message(
		"fixture: the carving would not inscribe").is_true()
	_assert_preview_is_real(_armed_wielder(), rune, GearVerbs.Verb.EQUIP)


func test_hovered_armour_displaces_only_the_worn_piece() -> void:
	_assert_preview_is_real(_armed_wielder(), _plate(), GearVerbs.Verb.WEAR)


# The two kinds the old "anything else is a weapon" fork got wrong: carried, never in hand.
func test_a_hovered_vial_displaces_nothing() -> void:
	var vial := VialData.new()
	vial.display_name = "Test Vial"
	vial.element = Elemental.Element.FIRE
	_assert_preview_is_real(_armed_wielder(), vial, CARRY)


func test_a_hovered_conduit_displaces_nothing() -> void:
	var conduit := ConduitData.new()
	conduit.display_name = "Test Conduit"
	_assert_preview_is_real(_armed_wielder(), conduit, CARRY)


# A fitted limb is a mod source whatever is in hand (_mod_sources), so swapping a weapon into the
# hand it occupied keeps the arm's bonus.
func test_a_held_prosthetic_keeps_paying_through_a_swap() -> void:
	var sword := _modded(H.make_weapon(), Stats.Stat.STR, 3)
	sword.display_name = "Test Sword"
	_assert_preview_is_real(_prosthetic_wielder(), sword, GearVerbs.Verb.EQUIP)
