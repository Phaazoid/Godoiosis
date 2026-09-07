# WeaponModData as an Item (#732), and the one door that answer changes: copying.
#
# The base is NOT a claim that a mod is carryable -- WeaponData extends Item too and is a shared
# template nobody holds. What it buys is that a mod can ride the Item-typed drag widget #741 shipped,
# which is what let the fitting card reuse it instead of growing a second one. The counterweight is
# the last case here: a unit is refused a loose mod, and told where it does go.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const SCRATCH := "user://__mod_item_732.tres"


func after_test() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _mod(name_text: String = "Probe", size: int = 1) -> WeaponModData:
	var mod := WeaponModData.new()
	mod.display_name = name_text
	mod.size = size
	return mod


func test_a_mod_is_an_item() -> void:
	assert_bool(_mod() is Item).is_true()


# The migration claim, on a BUILT mod rather than authored content: display_name and weight moved off
# this class onto the base, and a .tres keeps working only because the property NAMES did not change.
# CACHE_MODE_IGNORE so this reads the file rather than the object still in memory.
func test_the_two_fields_that_moved_to_the_base_survive_a_save() -> void:
	var mod := _mod("Galvanised Cogs", 2)
	mod.weight = 3
	mod.id = "cogs"
	assert_int(ResourceSaver.save(mod, SCRATCH)).is_equal(OK)

	var back := ResourceLoader.load(SCRATCH, "", ResourceLoader.CACHE_MODE_IGNORE) as WeaponModData
	assert_object(back).is_not_null()
	assert_str(back.display_name).is_equal("Galvanised Cogs")
	assert_int(back.weight).is_equal(3)
	assert_int(back.size).is_equal(2)
	assert_str(back.id).is_equal("cogs")


# Every shipped file still loads as one. Deliberately no count and no name -- that is authored
# content, and the claim here is only that rebasing the class did not break the folder.
func test_every_shipped_mod_still_loads_as_a_mod() -> void:
	var mods := WeaponModCatalog.get_mods()
	if mods.is_empty():
		push_warning("no mods authored, so there is nothing for this sweep to prove")
		return
	for key in mods:
		var mod: WeaponModData = mods[key]
		assert_object(mod).override_failure_message("%s did not load as a WeaponModData" % key).is_not_null()
		assert_bool(mod is Item).override_failure_message("%s is not an Item" % key).is_true()


# THE CASE THE OVERRIDE EXISTS FOR. Item's default copy_for_grant is duplicate(true), and a mod is
# mostly REFERENCES -- identity is what reads all three of them, and a save writes an unshared attack
# INLINE instead of as an ExtResource. So the copy has to be the mod itself, and the sharp half of
# this case is the second assertion: the same object is not enough, the attack has to survive too.
func test_copying_a_mod_for_a_grant_hands_back_the_mod_itself() -> void:
	var granted := WeaponAttackData.new()
	granted.display_name = "Super Gun"
	var mod := _mod()
	mod.granted_attacks = [granted]

	var copy := mod.copy_for_grant()
	assert_object(copy).is_same(mod)
	assert_object((copy as WeaponModData).granted_attacks[0]).is_same(granted)


# What a mod does, in its own words. The applies_to clause rides the EFFECTS and not the grants:
# a MAIN_ATTACK mod still hands over whatever it grants, it just does not buff the rest.
func test_effect_text_names_the_change_and_says_which_attacks_it_reaches() -> void:
	var mod := _mod()
	mod.power_delta = 5
	assert_str(mod.effect_text()).contains("+5 power")
	assert_str(mod.effect_text()).not_contains("main attack only")

	mod.applies_to = WeaponModData.AppliesTo.MAIN_ATTACK
	assert_str(mod.effect_text()).contains("main attack only")


func test_a_grant_is_never_narrowed_to_the_main_attack() -> void:
	var granted := WeaponAttackData.new()
	granted.display_name = "Super Gun"
	var mod := _mod()
	mod.applies_to = WeaponModData.AppliesTo.MAIN_ATTACK
	mod.granted_attacks = [granted]

	# No effect field is set, so there is nothing for the clause to qualify -- and the grant must not
	# collect it, since applies_to does not govern grants at all.
	assert_str(mod.effect_text()).contains("Super Gun")
	assert_str(mod.effect_text()).not_contains("main attack only")


func test_a_mod_with_nothing_authored_still_says_something() -> void:
	assert_str(_mod().effect_text()).is_not_empty()


# The counterweight to the base class: an Item a unit may not take. The refusal names the door that
# DOES work, which is the whole reason it is a sentence rather than a bool (#166's shape).
func test_a_unit_is_refused_a_loose_mod_and_told_where_it_goes() -> void:
	var unit := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	var refusal := unit.add_block_reason(_mod())
	assert_str(refusal).is_not_empty()
	assert_str(refusal).contains("weapon")
	# ...and an ordinary carryable is still waved through, so the clause did not close the door.
	assert_str(unit.add_block_reason(Item.new())).is_empty()
