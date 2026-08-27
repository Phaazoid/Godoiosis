# #589: a unit's gear is a copy_equippable() copy made at spawn, so which mods are FITTED to a
# weapon and which weapons are in a character's kit are per-instance composition -- the live-shared
# refs that carry an attack's or a mod's DATA reach them, and a change to the composition itself
# does not. Re-seeding is the dev answer: throw the gear away and re-grant it from the character
# FILE, so a mod fitted in the Item Editor or a weapon added in the Character Editor reaches a unit
# already standing on the board.
#
# The source is unit_data_source, never unit.unit_data -- UnitFactory hands each unit a
# duplicate(true) that deliberately stopped tracking its file (2026-07-27). So every case here
# spawns through the FACTORY off a real saved file, rather than assigning unit_data and stamping
# the provenance by hand: the stamp is a precondition the production path sets, and setting it
# directly would make these cases blind to it being dropped.
#
# The seeding itself is pinned by tests/unit/test_starting_kit.gd; this file pins the RE-seed.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const CHARACTER_PATH := "user://__test_reseed_character.tres"
const VARIANT_PATH := "user://__test_reseed_variant.tres"


func after_test() -> void:
	await await_idle_frame()   # #93/#101 orphan workaround
	for path in [CHARACTER_PATH, VARIANT_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# An Item Editor variant on disk, loaded back through the cache. UnitData.starting_inventory is
# documented to hold references to standalone equippable .tres, and that is load-bearing here: a
# PATH-LESS weapon serializes INLINE into the character file, so the loaded character would carry
# its own private copy and fitting a mod to this object would reach nothing. With a path it is an
# ext_resource, and both sides resolve to one shared object -- which is the whole model.
func _saved_variant(power: int) -> WeaponInstance:
	assert_int(ResourceSaver.save(H.make_weapon(power), VARIANT_PATH)).is_equal(OK)
	return load(VARIANT_PATH) as WeaponInstance


# A character FILE, loaded back through the cache -- the object the Character Editor's Update now
# writes through to, and the one a spawn stamps as provenance.
func _saved_character(kit: Array[EquippableData]) -> UnitData:
	var data := H.make_unit_data({}, Team.Faction.PLAYER)
	data.display_name = "Reseed Probe"
	data.starting_inventory = kit
	assert_int(ResourceSaver.save(data, CHARACTER_PATH)).is_equal(OK)
	return load(CHARACTER_PATH) as UnitData


func _spawn_from_file(character: UnitData) -> Unit:
	var unit: Unit = auto_free(UnitFactory.create_unit(character, null, Vector2i.ZERO))
	add_child(unit)   # triggers _ready -> initialize -> _seed_starting_kit
	return unit


func _carried_count(unit: Unit) -> int:
	var count := 0
	for item in unit.inventory:
		if item != null:
			count += 1
	return count


func test_a_unit_with_no_character_file_refuses_and_says_why() -> void:
	var unit: Unit = auto_free(H.UNIT_SCENE.instantiate())
	unit.unit_data = H.make_unit_data({}, Team.Faction.PLAYER)
	add_child(unit)

	assert_bool(unit.can_reseed_kit()).is_false()
	assert_str(unit.reseed_block_reason()).is_not_empty()
	assert_bool(unit.reseed_kit()).is_false()


func test_a_character_file_with_no_kit_refuses_and_says_why() -> void:
	var empty: Array[EquippableData] = []
	var unit := _spawn_from_file(_saved_character(empty))

	assert_bool(unit.can_reseed_kit()).is_false()
	assert_str(unit.reseed_block_reason()).is_not_empty()


# The Character Editor story: a weapon added to the character's kit reaches a unit already spawned.
func test_a_weapon_added_to_the_character_file_reaches_a_spawned_unit() -> void:
	var kit: Array[EquippableData] = [H.make_weapon(4)]
	var character := _saved_character(kit)
	var unit := _spawn_from_file(character)
	assert_int(_carried_count(unit)).is_equal(1)

	# What the Character Editor's Update now does to the live object at that path.
	character.starting_inventory.append(H.make_weapon(9))

	assert_bool(unit.reseed_kit()).is_true()
	assert_int(_carried_count(unit)).is_equal(2)


# The Item Editor story: a mod fitted to the authored variant reaches the CARRIED copy.
func test_a_mod_fitted_to_the_authored_variant_reaches_the_carried_copy() -> void:
	var authored := _saved_variant(4)
	var kit: Array[EquippableData] = [authored]
	var unit := _spawn_from_file(_saved_character(kit))

	var carried_before := unit.inventory[0] as WeaponInstance
	assert_array(carried_before.space(0)).is_empty()

	var mod := WeaponModData.new()
	mod.display_name = "Late Fitting"
	assert_bool(authored.fit(0, mod)).is_true()

	assert_bool(unit.reseed_kit()).is_true()
	var carried_after := unit.inventory[0] as WeaponInstance
	assert_array(carried_after.space(0)).contains([mod])


# The clear has to be a REPLACE. Appending on top is what apply_unit_state's own clear exists to
# stop one layer over, and a re-seed pressed twice is the ordinary way to hit it.
func test_re_seeding_twice_replaces_rather_than_doubles() -> void:
	var kit: Array[EquippableData] = [H.make_weapon(4)]
	var unit := _spawn_from_file(_saved_character(kit))

	assert_bool(unit.reseed_kit()).is_true()
	assert_bool(unit.reseed_kit()).is_true()

	assert_int(_carried_count(unit)).is_equal(1)
	assert_object(unit.get_equipped_weapon()).is_same(unit.inventory[0])


# An armed watch stamps the ATTACK it will fire, off a weapon the re-seed is about to discard.
# Dropping it is part of doing the re-seed correctly, not a guard against pressing it at a bad time.
func test_re_seeding_drops_an_armed_watch() -> void:
	var kit: Array[EquippableData] = [H.make_weapon(4)]
	var unit := _spawn_from_file(_saved_character(kit))
	var watched: Array[Vector2i] = [Vector2i(1, 0)]
	unit.arm_watch(Vector2i.ZERO, Vector2i(1, 0), watched, unit.get_equipped_weapon().default_attack(unit))
	assert_object(unit.watch).is_not_null()

	assert_bool(unit.reseed_kit()).is_true()

	assert_object(unit.watch).is_null()
