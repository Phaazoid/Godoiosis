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
