# What a mission OFFERS versus what the phase HOLDS (#835). A roster names its stash by FILE, and a
# weapon's plain form has no file of its own -- its TEMPLATE's is its identity -- so a curated stash
# may legitimately name a WeaponData. What reaches the phase must still be a real WeaponInstance,
# because the fitting card fits mods onto stash gear and a template has no spaces to fit into.
#
# Built ad hoc (tests/README.md rule 4): every claim here is about the DOOR, never about which
# weapons happen to be authored.
extends GdUnitTestSuite


func _template(family: WeaponData.WeaponType = WeaponData.WeaponType.CHAINSWORD) -> WeaponData:
	var t := WeaponData.new()
	t.weapon_type = family
	t.main_attack = WeaponAttackData.new()
	t.display_name = "Kit Chainsword"
	return t


func _roster_offering(item: Item) -> Roster:
	var roster := Roster.new()
	var stash: Array[Item] = []
	stash.append(item)
	roster.stash = stash   # offers_every_item defaults FALSE, so this IS the offered list
	return roster


# THE WIRE, not its two ends. Roster names a template, Loadout is what the phase reads, and a case
# asserting on either alone would pass with nothing joining them.
func test_a_template_in_a_curated_stash_reaches_the_phase_as_an_instance() -> void:
	var template := _template()
	var loadout := Loadout.from_roster(_roster_offering(template))

	assert_int(loadout.stash.size()).is_equal(1)
	var held := loadout.stash[0] as WeaponInstance
	assert_object(held).override_failure_message(
			"a template reached the phase as a bare WeaponData -- nothing can fit a mod to one"
			).is_not_null()
	assert_object(held.template).override_failure_message(
			"the granted weapon forked its own template instead of sharing it").is_same(template)


# The instance path is unchanged: a copy, with the template still shared.
func test_an_authored_instance_still_arrives_as_its_own_copy() -> void:
	var authored := WeaponInstance.make(_template())
	var loadout := Loadout.from_roster(_roster_offering(authored))

	var held := loadout.stash[0] as WeaponInstance
	assert_object(held).is_not_same(authored)
	assert_object(held.template).is_same(authored.template)


# An unmapped family answers make() with null, and Unit.add_item takes a null into the first free
# slot and answers TRUE -- so the door has to drop it here rather than leave a hole to be carried.
func test_a_template_with_no_family_is_dropped_rather_than_stashed() -> void:
	var broken := WeaponData.new()   # weapon_type NONE; make() push_errors and answers null
	assert_array(Loadout.from_roster(_roster_offering(broken)).stash).override_failure_message(
			"a weapon nothing can build was carried into the phase anyway").is_empty()
