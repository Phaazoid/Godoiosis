# Starting kit (#177): a UnitData's kit block seeds a freshly spawned unit — jobs, proficiency,
# inventory (as copies, never the authored resources), the explicit equip/wear picks, and
# prosthetic installs — while a kit-less UnitData spawns exactly as before. The scenario-side
# reference semantics live in tests/flow/test_cast_references.gd; this file pins the seeding.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func _spawn_with(data: UnitData) -> Unit:
	var unit: Unit = auto_free(H.UNIT_SCENE.instantiate())
	unit.unit_data = data
	add_child(unit)   # triggers _ready -> initialize -> _seed_starting_kit
	return unit


func _kit_armor() -> ArmorData:
	var armor := ArmorData.new()
	armor.display_name = "Kit Vest"
	return armor


func _kit_prosthetic() -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.PROSTHETIC
	template.main_attack = WeaponAttackData.new()
	template.built_in_stat = 7
	var item := WeaponInstance.make(template)
	item.limb_kind = WeaponData.LimbKind.ARM
	return item


func _carried_count(unit: Unit) -> int:
	var count := 0
	for item in unit.inventory:
		if item != null:
			count += 1
	return count


func test_kitless_unit_data_spawns_bare() -> void:
	var unit := _spawn_with(H.make_unit_data({}, Team.Faction.PLAYER))
	assert_int(_carried_count(unit)).is_equal(0)
	assert_array(unit.unit_instance.jobs).is_empty()
	assert_bool(unit.has_equipped_weapon()).is_false()


func test_kit_seeds_jobs_and_proficiency() -> void:
	var data := H.make_unit_data({}, Team.Faction.PLAYER)
	data.starting_jobs = ["scout", "no_such_job"]   # the unknown id warns and skips, never crashes
	data.starting_proficiency = {WeaponData.WeaponType.CHAINSWORD: 1}
	var unit := _spawn_with(data)
	assert_bool(unit.unit_instance.has_job("scout")).is_true()
	assert_bool(unit.unit_instance.has_job("no_such_job")).is_false()
	assert_int(unit.unit_instance.get_proficiency(WeaponData.WeaponType.CHAINSWORD)).is_equal(1)


func test_kit_items_are_granted_as_copies_and_auto_equip() -> void:
	var authored := H.make_weapon(4)
	var data := H.make_unit_data({}, Team.Faction.PLAYER)
	data.starting_inventory = [authored]
	var unit := _spawn_with(data)

	var carried := unit.inventory[0] as WeaponInstance
	assert_object(carried).is_not_null()
	assert_bool(carried == authored).is_false()               # a copy, never the authored resource
	assert_object(carried.template).is_same(authored.template)  # copy_for_grant keeps the template SHARED
	assert_object(unit.get_equipped_weapon()).is_same(carried)  # add_item's auto-equip picked it up


func test_explicit_equip_and_wear_picks() -> void:
	var data := H.make_unit_data({}, Team.Faction.PLAYER)
	data.starting_inventory = [H.make_weapon(3), H.make_weapon(5), _kit_armor()]
	data.starting_equipped_index = 1
	data.starting_worn_index = 2
	var unit := _spawn_with(data)

	assert_object(unit.get_equipped_weapon()).is_same(unit.inventory[1])
	assert_object(unit.worn_armor).is_same(unit.inventory[2])


func test_kit_prosthetic_installs_into_its_slot() -> void:
	var data := H.make_unit_data({}, Team.Faction.PLAYER)
	data.starting_inventory = [_kit_prosthetic()]
	data.starting_prosthetics = {UnitInstance.LimbSlot.ARM_R: 0}
	var unit := _spawn_with(data)

	var fitting: UnitInstance.LimbFitting = unit.unit_instance.limbs[UnitInstance.LimbSlot.ARM_R]
	assert_int(fitting.state).is_equal(UnitInstance.LimbState.PROSTHETIC)
	assert_object(fitting.prosthetic_item).is_same(unit.inventory[0])
	assert_int(unit.unit_instance.limb_stat(UnitInstance.LimbSlot.ARM_R)).is_equal(7)


# A TEMPLATE authored into the kit (#835) -- which is what a character file names once its plain
# weapon stopped being a hand-saved variant. The template itself is not carryable (a unit holding a
# shared family object is the fault #80 closed), so the grant door instantiates it and the unit ends
# up with a real weapon of that family, its template still SHARED.
func test_a_template_in_the_kit_is_granted_as_an_instance_sharing_it() -> void:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CARBINE
	template.main_attack = WeaponAttackData.new()
	template.display_name = "Kit Carbine"

	var data := H.make_unit_data({}, Team.Faction.PLAYER)
	data.starting_inventory = [template]
	var unit := _spawn_with(data)

	var carried := unit.inventory[0] as WeaponInstance
	assert_object(carried).override_failure_message(
			"a template in the kit was carried as a bare WeaponData, or dropped").is_not_null()
	assert_object(carried.template).override_failure_message(
			"the granted weapon forked the shared template").is_same(template)
	assert_int(carried.spaces.size()).is_equal(0)


# The null half of that door: make() answers an unmapped family with null, and add_item would take
# it into the first free slot and report success, so the kit refuses it before that.
func test_a_template_with_no_family_leaves_the_slot_empty() -> void:
	var data := H.make_unit_data({}, Team.Faction.PLAYER)
	data.starting_inventory = [WeaponData.new()]   # weapon_type NONE
	var unit := _spawn_with(data)

	assert_int(_carried_count(unit)).override_failure_message(
			"a weapon nothing can build was still counted as carried").is_equal(0)
