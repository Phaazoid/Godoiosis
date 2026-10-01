# A unit's weight (#120, dev 2026-10-01): its own body (the BLD stat) plus every item it carries.
#
# Two corrections stand behind this file. 2026-07-27 took CON out of the measurement -- it was
# drift, CON was never meant to add mass -- and widened the sweep from the equipped weapon to the
# whole inventory. 2026-10-01 gave every unit a body weight of its own ("units will need to have
# weight"), which is BLD and not CON: the CON case below still holds.
#
# Body values here are authored IN the test, never read off a tuning default, so retuning BLD's
# default moves nothing these cases assert.
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


# --- the body ---

func test_a_bare_unit_weighs_its_body() -> void:
	assert_int(_bare_unit({Stats.Stat.BLD: 13}).get_weight()).is_equal(13)


func test_an_unauthored_body_reads_the_default() -> void:
	# Missing stat keys read STAT_DEFAULTS, never 0 -- so a unit nobody authored is an ordinary
	# body rather than a weightless one.
	var data := UnitData.new()
	var inst := UnitInstance.new()
	inst.data = data
	inst.initialize()
	assert_int(inst.get_base_stat(Stats.Stat.BLD)).is_equal(Stats.STAT_DEFAULTS[Stats.Stat.BLD])


func test_weight_is_the_body_plus_everything_carried() -> void:
	var unit := _bare_unit({Stats.Stat.BLD: 13})
	unit.inventory[0] = _item(3)
	unit.inventory[2] = _item(4)
	assert_int(unit.get_carried_weight()).is_equal(7)
	assert_int(unit.get_weight()).is_equal(20)


func test_a_temporary_effect_on_build_moves_weight() -> void:
	# The body is read EFFECTIVE, so a tonic that lightens or burdens a unit reaches its weight.
	var unit := _bare_unit({Stats.Stat.BLD: 13})
	unit.apply_stat_effect(StatEffect.make("Ballast", {Stats.Stat.BLD: 5}))
	assert_int(unit.get_weight()).is_equal(18)


func test_con_contributes_nothing() -> void:
	# The 2026-07-27 correction: CON is not a term, so two bodies differing only in CON weigh the same.
	var sturdy := _bare_unit({Stats.Stat.CON: 20, Stats.Stat.BLD: 13})
	var frail := _bare_unit({Stats.Stat.CON: 3, Stats.Stat.BLD: 13})
	assert_int(sturdy.get_weight()).is_equal(frail.get_weight())


# --- what is carried ---

func test_an_empty_inventory_carries_nothing() -> void:
	assert_int(_bare_unit().get_carried_weight()).is_equal(0)


func test_carried_weight_sums_every_item() -> void:
	var unit := _bare_unit()
	unit.inventory[0] = _item(3)
	unit.inventory[2] = _item(4)
	assert_int(unit.get_carried_weight()).is_equal(7)


func test_unequipped_items_still_count() -> void:
	# Encumbrance is about what you HAUL, not what you're holding -- a spare in the pack
	# weighs the same as the one in your hands.
	var unit := _bare_unit()
	unit.inventory[0] = _item(5)
	assert_object(unit.get_equipped_weapon()).is_null()
	assert_int(unit.get_carried_weight()).is_equal(5)


func test_worn_armor_counts() -> void:
	# The gap #89 left behind: armor had no weight field at all, so plate was weightless.
	var unit := _bare_unit()
	var plate := _armor(6)
	unit.inventory[0] = plate
	unit.worn_armor = plate
	assert_int(unit.get_carried_weight()).is_equal(6)


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
	assert_int(unit.get_carried_weight()).is_equal(6)


func test_weight_does_not_reach_mov() -> void:
	# Weight slowing movement is deliberately unwired (2026-07-27) and its return is #1176's
	# question. If this goes red, someone re-connected encumbrance -- a design decision, not an
	# incidental change.
	var unit := _bare_unit()
	var before := unit.get_mov()
	unit.inventory[0] = _item(50)
	assert_int(unit.get_mov()).is_equal(before)
