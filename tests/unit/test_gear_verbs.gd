# GearVerbs (#46 slice 2b): the inspect dock's six verbs, judged and performed through one rule that
# the dock, the replay viewer and the headless Play API all ask.
#
# Every piece of gear is authored here, in memory. Each refusal is read against the owning gate's
# own sentence rather than retyped, so retuning a gate's wording cannot red this file.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


var _sm: SquadManager
var _unit: Unit


func before_test() -> void:
	_sm = H.make_manager(self)
	_unit = H.spawn_solo(self, _sm, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)


# Armour this unit cannot wear: a CON floor nobody meets.
static func _heavy_plate() -> ArmorData:
	var plate := ArmorData.new()
	plate.display_name = "Test Heavy Plate"
	plate.stat_minimums = {Stats.Stat.CON: 999}
	return plate


static func _light_plate() -> ArmorData:
	var plate := ArmorData.new()
	plate.display_name = "Test Light Plate"
	return plate


static func _vial(element: Elemental.Element) -> VialData:
	var vial := VialData.new()
	vial.display_name = "Test Vial"
	vial.element = element
	return vial


func _slot_of(item: Item) -> int:
	return _unit.inventory.find(item)


func test_the_recorded_names_round_trip() -> void:
	# The wire MissionLog writes into every run's "gear" events: pinned because a renamed member
	# would stop every recorded run from replaying.
	var names: Array[String] = ["equip", "unequip", "wear", "remove_armor", "use", "toss"]
	for verb_name: String in names:
		var verb := GearVerbs.from_name(verb_name)
		assert_int(verb).override_failure_message("'%s' is no longer a gear verb" % verb_name).is_not_equal(-1)
		assert_str(GearVerbs.name_of(verb as GearVerbs.Verb)).is_equal(verb_name)
	assert_int(GearVerbs.from_name("polish")).is_equal(-1)


func test_equip_and_unequip() -> void:
	var first := H.make_weapon()
	var second := H.make_weapon()
	_unit.add_item(first)    # auto-equips
	_unit.add_item(second)
	assert_str(GearVerbs.block_reason(_unit, GearVerbs.Verb.EQUIP, _slot_of(first))).contains("already equipped")
	assert_str(GearVerbs.perform(_unit, GearVerbs.Verb.EQUIP, _slot_of(second))).is_empty()
	assert_object(_unit.get_equipped_weapon()).is_same(second)

	assert_str(GearVerbs.perform(_unit, GearVerbs.Verb.UNEQUIP, -1)).is_empty()
	assert_bool(_unit.has_equipped_weapon()).is_false()
	assert_str(GearVerbs.block_reason(_unit, GearVerbs.Verb.UNEQUIP, -1)).contains("nothing equipped")


func test_wear_refuses_in_the_armours_own_words_and_remove_takes_no_slot() -> void:
	var heavy := _heavy_plate()
	var light := _light_plate()
	_unit.add_item(heavy)
	_unit.add_item(light)

	var refused := GearVerbs.perform(_unit, GearVerbs.Verb.WEAR, _slot_of(heavy))
	assert_str(refused).override_failure_message("a plate the unit cannot wear was worn").is_not_empty()
	assert_str(refused).is_equal(heavy.can_equip_reason(_unit))
	assert_object(_unit.worn_armor).is_null()

	assert_str(GearVerbs.perform(_unit, GearVerbs.Verb.WEAR, _slot_of(light))).is_empty()
	assert_object(_unit.worn_armor).is_same(light)
	assert_str(GearVerbs.block_reason(_unit, GearVerbs.Verb.WEAR, _slot_of(light))).contains("already worn")

	# The index an old run recorded for Remove: -1.
	assert_str(GearVerbs.perform(_unit, GearVerbs.Verb.REMOVE_ARMOR, -1)).is_empty()
	assert_object(_unit.worn_armor).is_null()
	assert_str(GearVerbs.block_reason(_unit, GearVerbs.Verb.REMOVE_ARMOR, -1)).contains("wearing no armour")


func test_the_kinds_refuse_each_others_verbs() -> void:
	var plate := _light_plate()
	var weapon := H.make_weapon()
	_unit.add_item(weapon)
	_unit.add_item(plate)
	assert_str(GearVerbs.block_reason(_unit, GearVerbs.Verb.EQUIP, _slot_of(plate))).is_not_empty()
	assert_str(GearVerbs.block_reason(_unit, GearVerbs.Verb.WEAR, _slot_of(weapon))).is_not_empty()
	assert_str(GearVerbs.block_reason(_unit, GearVerbs.Verb.USE, _slot_of(weapon))).is_not_empty()
	var empty := _unit.inventory.find(null)
	for verb: GearVerbs.Verb in [GearVerbs.Verb.EQUIP, GearVerbs.Verb.WEAR, GearVerbs.Verb.USE, GearVerbs.Verb.TOSS]:
		assert_str(GearVerbs.block_reason(_unit, verb, empty)).override_failure_message(
			"%s on an empty slot was allowed" % GearVerbs.name_of(verb)).is_not_empty()


func test_use_spends_the_vial_and_refuses_in_its_own_words() -> void:
	var sigil := _vial(Elemental.Element.FIRE)
	var fuel := _vial(Elemental.Element.CORROSION)
	_unit.add_item(sigil)
	_unit.add_item(fuel)

	var refused := GearVerbs.perform(_unit, GearVerbs.Verb.USE, _slot_of(fuel))
	assert_str(refused).override_failure_message("a vial that empowers nothing was spent").is_not_empty()
	assert_str(refused).is_equal(fuel.use_block_reason(_unit))
	assert_bool(_unit.inventory.has(fuel)).is_true()

	assert_str(GearVerbs.perform(_unit, GearVerbs.Verb.USE, _slot_of(sigil))).is_empty()
	assert_object(_unit.attunement).is_same(sigil)
	assert_bool(_unit.inventory.has(sigil)).override_failure_message("a used vial is still carried").is_false()


func test_toss_drops_the_piece_and_refuses_in_the_units_own_words() -> void:
	var weapon := H.make_weapon()
	_unit.add_item(weapon)
	var slot := _slot_of(weapon)
	assert_str(GearVerbs.perform(_unit, GearVerbs.Verb.TOSS, slot)).is_empty()
	assert_bool(_unit.inventory.has(weapon)).is_false()
	assert_str(GearVerbs.block_reason(_unit, GearVerbs.Verb.TOSS, slot)).is_equal(_unit.remove_block_reason(slot))
