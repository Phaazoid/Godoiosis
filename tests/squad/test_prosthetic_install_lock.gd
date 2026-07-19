# Installed prosthetic weapons (#59 item 6, weapons.md Prosthetic family): equip/unequip
# freely like any ordinary weapon — the only lock is Toss (Unit.remove_item), since removing
# an installed prosthetic from inventory would mean detaching a limb (a between-mission
# action that isn't built yet). No CombatComponent special-casing needed: it's just a normal
# WeaponInstance sitting in inventory once equipped.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _prosthetic_weapon(built_in_stat: int = 5) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.PROSTHETIC
	template.built_in_stat = built_in_stat
	var instance := WeaponInstance.make(template)
	instance.limb_kind = WeaponData.LimbKind.ARM   # every test here installs onto ARM_R
	return instance

func test_installed_prosthetic_can_be_unequipped_and_a_different_weapon_equipped() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, false)
	var prosthetic := _prosthetic_weapon()
	unit.add_item(prosthetic)                                              # slot 0, auto-equips
	assert_bool(unit.unit_instance.install_prosthetic(UnitInstance.LimbSlot.ARM_R, prosthetic)).is_true()
	assert_object(unit.get_equipped_weapon()).is_same(prosthetic)

	unit.unequip_weapon()
	assert_bool(unit.has_equipped_weapon()).is_false()

	var sword := H.make_weapon(4)
	unit.add_item(sword)                                                   # slot 1
	assert_bool(unit.equip_weapon_from_inventory(1)).is_true()
	assert_object(unit.get_equipped_weapon()).is_same(sword)

func test_installed_prosthetic_can_be_re_equipped_after_being_swapped_out() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, false)
	var prosthetic := _prosthetic_weapon()
	unit.add_item(prosthetic)
	unit.unit_instance.install_prosthetic(UnitInstance.LimbSlot.ARM_R, prosthetic)
	unit.unequip_weapon()

	assert_bool(unit.equip_weapon_from_inventory(0)).is_true()
	assert_object(unit.get_equipped_weapon()).is_same(prosthetic)

func test_installed_prosthetic_cannot_be_tossed_while_equipped() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, false)
	var prosthetic := _prosthetic_weapon()
	unit.add_item(prosthetic)
	unit.unit_instance.install_prosthetic(UnitInstance.LimbSlot.ARM_R, prosthetic)

	unit.remove_item(0)
	assert_object(unit.inventory[0]).is_same(prosthetic)
	assert_object(unit.get_equipped_weapon()).is_same(prosthetic)

func test_installed_prosthetic_cannot_be_tossed_while_unequipped() -> void:
	# The lock is on the ITEM, not on "being the current equip" — holstering a fitted
	# prosthetic to wield something else must not open a door to discarding it.
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, false)
	var prosthetic := _prosthetic_weapon()
	unit.add_item(prosthetic)
	unit.unit_instance.install_prosthetic(UnitInstance.LimbSlot.ARM_R, prosthetic)
	unit.unequip_weapon()

	unit.remove_item(0)
	assert_object(unit.inventory[0]).is_same(prosthetic)

func test_ordinary_weapon_can_still_be_tossed() -> void:
	# Regression control: the lock only ever fires for an actually-installed prosthetic.
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, false)
	var sword := H.make_weapon(4)
	unit.add_item(sword)

	unit.remove_item(0)
	assert_object(unit.inventory[0]).is_null()
