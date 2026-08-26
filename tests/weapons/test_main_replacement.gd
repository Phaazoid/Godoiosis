# A mod that REPLACES the weapon's main attack (#529) -- "the standard attack BECOMES this", how
# half the mod bank is written.
#
# #529 named the counter as the surface that would go stale. It is one of four, and not the worst:
# secondary_attacks filtered by the TEMPLATE's main, so a replaced main was fired by Attack AND
# listed in the submenu beside it. The exactly-once case below is aimed at that, and the fixture
# carries a real extra attack so "the old main is not in the submenu" cannot pass on an empty list.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

var _stock: WeaponAttackData
var _extra: WeaponAttackData
var _swap: WeaponAttackData

func before_test() -> void:
	_stock = _attack("Stock Main")
	_extra = _attack("Spring")
	_swap = _attack("Wide Cleave")

func _attack(name: String) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.display_name = name
	return a

func _weapon() -> WeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = _stock
	var extras: Array[WeaponAttackData] = [_extra]
	t.extra_attacks = extras
	return WeaponInstance.make(t)

func _wielder(proficiency := UnitInstance.UNREDUCED) -> Unit:
	var u := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	u.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, proficiency)
	return u

func _replacer() -> WeaponModData:
	var m := WeaponModData.new()
	m.display_name = "Widened Cleave Head"
	m.replaces_main = _swap
	return m

func _fit(weapon: WeaponInstance, index: int, mod: WeaponModData) -> void:
	assert_bool(weapon.fit(index, mod)) \
		.override_failure_message("fixture: the mod must actually fit, or nothing below is testing a replacement") \
		.is_true()

# --- The four surfaces that read the main ---

func test_a_counter_fires_the_replacement() -> void:
	var unit := _wielder()
	var weapon := _weapon()
	unit.equipped_weapon = weapon
	assert_object(weapon.counter_attack(unit)).is_same(_stock)	 # precondition, and the contrast

	_fit(weapon, 0, _replacer())
	assert_object(weapon.counter_attack(unit)).is_same(_swap)

func test_the_default_aim_is_the_replacement() -> void:
	var unit := _wielder()
	var weapon := _weapon()
	unit.equipped_weapon = weapon
	_fit(weapon, 0, _replacer())

	assert_object(weapon.default_attack(unit)).is_same(_swap)

func test_the_repertoire_carries_the_replacement_and_drops_the_stock_main() -> void:
	var unit := _wielder()
	var weapon := _weapon()
	unit.equipped_weapon = weapon
	_fit(weapon, 0, _replacer())

	var available := weapon.available_attacks(unit)
	assert_array(available).contains([_swap])
	assert_array(available).not_contains([_stock])
	assert_array(available).contains([_extra])	 # a replacement swaps the MAIN, not the stock list

func test_the_replaced_main_is_offered_exactly_once() -> void:
	var unit := _wielder()
	var weapon := _weapon()
	unit.equipped_weapon = weapon
	_fit(weapon, 0, _replacer())

	# The submenu is what Attack does NOT already fire. Both halves matter: the replacement must
	# not be listed beside itself, and the stock main it displaced must be gone entirely.
	var secondaries := weapon.secondary_attacks(unit)
	assert_array(secondaries).contains([_extra])   # non-vacuity: the submenu really has entries
	assert_array(secondaries).not_contains([_swap])
	assert_array(secondaries).not_contains([_stock])

# --- Gating ---

func test_a_replacer_in_a_proficiency_locked_space_does_not_replace() -> void:
	var unit := _wielder(1)	  # space 0 only
	var weapon := _weapon()
	unit.equipped_weapon = weapon
	_fit(weapon, 1, _replacer())

	assert_int(weapon.active_space_count(unit)).is_equal(1)	  # the lock is real, not assumed
	assert_object(weapon.default_attack(unit)).is_same(_stock)

# --- Refusal ---

func test_a_second_replacer_is_refused_with_its_reason() -> void:
	var weapon := _weapon()
	var first := _replacer()
	_fit(weapon, 0, first)

	# Space 1 holds 2 and is empty, so capacity cannot be what refuses -- proved by fitting an
	# ordinary mod of the same size there first, then asking about a second replacer.
	var ordinary := WeaponModData.new()
	assert_bool(weapon.can_fit(1, ordinary)) \
		.override_failure_message("fixture: space 1 must have room, or the refusal below is capacity's") \
		.is_true()

	var second := _replacer()
	assert_bool(weapon.can_fit(1, second)).is_false()
	assert_str(weapon.fit_block_reason(1, second)).contains(first.display_name)
