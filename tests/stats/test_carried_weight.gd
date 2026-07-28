# Carried weight as a Unit-level readout (doctrine corrected 2026-07-27).
#
# Weight is PURELY gear: every item in the inventory contributes its own mass, and no stat
# feeds it. It used to be `CON body + equipped weapon`, which was drift -- CON was never meant
# to be part of the measurement, and only the equipped weapon was ever summed. Both are fixed
# here. If a stat ever influences carry again it is meant to be STR (capacity, letting you
# carry more before a penalty), never CON adding mass.
#
# The value is deliberately INERT: nothing reads it into a rule yet. These tests pin the
# arithmetic and the two negative claims, so re-wiring it later starts from a known quantity.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func _bare_unit(overrides: Dictionary = {}) -> Unit:
	# give_weapon = false: the fixture assigns equipped_weapon WITHOUT putting it in the
	# inventory, which is not how the real equip path works (set_equipped_weapon requires
	# inventory.has). These tests drive the inventory directly instead.
	return H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), overrides, false)


func _item(weight: int) -> Item:
	var item := Item.new()
	item.weight = weight
	return item


func _armor(weight: int) -> ArmorData:
	var armor := ArmorData.new()
	armor.weight = weight
	return armor


func test_empty_inventory_weighs_nothing() -> void:
	assert_int(_bare_unit().get_weight()).is_equal(0)


func test_weight_sums_every_carried_item() -> void:
	var unit := _bare_unit()
	unit.inventory[0] = _item(3)
	unit.inventory[2] = _item(4)
	assert_int(unit.get_weight()).is_equal(7)


func test_unequipped_items_still_count() -> void:
	# Encumbrance is about what you HAUL, not what you're holding -- a spare in the pack
	# weighs the same as the one in your hands.
	var unit := _bare_unit()
	unit.inventory[0] = _item(5)
	assert_object(unit.get_equipped_weapon()).is_null()
	assert_int(unit.get_weight()).is_equal(5)


func test_worn_armor_counts() -> void:
	# The gap #89 left behind: armor had no weight field at all, so plate was weightless.
	var unit := _bare_unit()
	var plate := _armor(6)
	unit.inventory[0] = plate
	unit.worn_armor = plate
	assert_int(unit.get_weight()).is_equal(6)


func test_a_weapon_carries_its_family_and_module_mass() -> void:
	# get_effective_weight is the composite override: family template + every fitted module,
	# active or not. One item, but its mass is assembled.
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.weight = 4
	var weapon := WeaponInstance.make(template)
	var mod := WeaponModData.new()
	mod.size = 1
	mod.weight = 2
	weapon.fit(0, mod)

	var unit := _bare_unit()
	unit.inventory[0] = weapon
	assert_int(unit.get_weight()).is_equal(6)


func test_con_contributes_nothing() -> void:
	# The whole point of the correction: a heavy-CON unit carrying nothing weighs nothing.
	assert_int(_bare_unit({Stats.Stat.CON: 20}).get_weight()).is_equal(0)
	assert_int(_bare_unit({Stats.Stat.CON: 3}).get_weight()).is_equal(0)


func test_weight_does_not_reach_mov() -> void:
	# Tracked but wired to nothing. If this test ever goes red, someone re-connected the
	# encumbrance rule -- that is a design decision, not an incidental change.
	var unit := _bare_unit()
	var before := unit.get_mov()
	unit.inventory[0] = _item(50)
	assert_int(unit.get_weight()).is_equal(50)
	assert_int(unit.get_mov()).is_equal(before)
