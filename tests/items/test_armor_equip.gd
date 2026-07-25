# The armor equip surface (#65 follow-on): armor is carried in the SAME inventory as weapons but
# fills a DIFFERENT slot. That overlap is the whole risk -- ArmorData extends EquippableData, so
# every weapon-slot path had to learn to say no to it, and the armor slot had to grow its own.
# Unit.wear_armor is the one chokepoint where the wear gate lives.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func _vest(def_power: int = 2) -> ArmorData:
	var armor := ArmorData.new()
	armor.item_name = "Test Vest"
	armor.def_power = def_power
	return armor


func _gated_plate() -> ArmorData:
	var armor := ArmorData.new()
	armor.item_name = "Test Plate"
	armor.def_power = 6
	armor.stat_minimums[Stats.Stat.CON] = 8
	return armor


# --- the slot collision: armor must never be mistaken for a weapon ---

func test_picking_up_armor_does_not_arm_an_unarmed_unit() -> void:
	# ArmorData IS an EquippableData, so a naive add_item would "arm" a unit with a vest.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	unit.add_item(_vest())
	assert_bool(unit.has_equipped_weapon()).is_false()


func test_armor_does_not_shadow_a_weapon_picked_up_later() -> void:
	# The subtler half: if armor had claimed the weapon slot, the real weapon arriving next
	# would find it taken and the unit would walk around swinging a vest.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	unit.add_item(_vest())
	var weapon: WeaponInstance = H.make_weapon(3)
	unit.add_item(weapon)
	assert_object(unit.get_equipped_weapon()).is_same(weapon)


func test_armor_cannot_be_equipped_as_a_weapon() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	unit.add_item(_vest())
	assert_bool(unit.equip_weapon_from_inventory(0)).is_false()
	assert_bool(unit.has_equipped_weapon()).is_false()


func test_a_weapon_cannot_be_worn_as_armor() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	unit.add_item(H.make_weapon(3))
	assert_bool(unit.wear_armor(0)).is_false()
	assert_object(unit.worn_armor).is_null()


func test_a_unit_wears_armor_and_wields_a_weapon_at_once() -> void:
	# Two slots, one inventory -- the whole point. Neither assignment disturbs the other.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var weapon: WeaponInstance = H.make_weapon(3)
	unit.add_item(weapon)
	unit.add_item(_vest())
	unit.wear_armor(1)

	assert_object(unit.get_equipped_weapon()).is_same(weapon)
	assert_object(unit.worn_armor).is_same(unit.inventory[1])
	assert_int(unit.get_effective_def()).is_equal(2)


# --- the gate lives at the one chokepoint ---

func test_wear_armor_enforces_the_gate() -> void:
	var frail: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 5}, false)
	frail.add_item(_gated_plate())
	assert_bool(frail.wear_armor(0)).is_false()
	assert_object(frail.worn_armor).is_null()
	assert_int(frail.get_effective_def()).is_equal(0)   # refused, so no DEF leaks through


func test_wear_armor_admits_a_qualified_wearer() -> void:
	var mighty: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 8}, false)
	mighty.add_item(_gated_plate())
	assert_bool(mighty.wear_armor(0)).is_true()
	assert_object(mighty.worn_armor).is_not_null()


func test_wear_armor_rejects_an_out_of_range_slot() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	assert_bool(unit.wear_armor(-1)).is_false()
	assert_bool(unit.wear_armor(99)).is_false()
	assert_bool(unit.wear_armor(0)).is_false()   # empty slot


# --- taking it off ---

func test_remove_armor_clears_the_slot_and_its_def() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	unit.add_item(_vest())
	unit.wear_armor(0)
	unit.remove_armor()

	assert_object(unit.worn_armor).is_null()
	assert_int(unit.get_effective_def()).is_equal(0)
	assert_object(unit.inventory[0]).is_not_null()   # taken off, not thrown away


func test_tossing_worn_armor_stops_granting_def() -> void:
	# The dangling-reference bug: worn_armor pointed at an item no longer carried, so a tossed
	# vest kept paying DEF forever.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	unit.add_item(_vest())
	unit.wear_armor(0)
	assert_int(unit.get_effective_def()).is_equal(2)

	unit.remove_item(0)
	assert_object(unit.worn_armor).is_null()
	assert_int(unit.get_effective_def()).is_equal(0)


func test_tossing_a_weapon_leaves_worn_armor_alone() -> void:
	# Control for the test above -- clearing one slot must not clear the other.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	unit.add_item(H.make_weapon(3))
	unit.add_item(_vest())
	unit.wear_armor(1)

	unit.remove_item(0)
	assert_object(unit.worn_armor).is_not_null()
	assert_int(unit.get_effective_def()).is_equal(2)


func test_swapping_armor_replaces_rather_than_stacks() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	unit.add_item(_vest(2))
	unit.add_item(_vest(4))
	unit.wear_armor(0)
	unit.wear_armor(1)

	assert_object(unit.worn_armor).is_same(unit.inventory[1])
	assert_int(unit.get_effective_def()).is_equal(4)   # the second piece only, never 2 + 4
