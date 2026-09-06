# #589: DevWidgets.save_over -- the single writer every dev-tool save routes through -- used to
# ORPHAN the object it was overwriting. The pool editors stage edits on a duplicate(true), and
# take_over_path on that copy clears the ORIGINAL's resource_path and evicts it from the cache, so
# the object every board unit, every mod's granted_attacks and every template's main_attack still
# points at kept the old values. Three symptoms from one cause: the board never saw an edit, a
# RESPAWN never saw it either (a catalog scan is a cache hit still holding the orphan, so only a
# relaunch cleared it), and the path-less orphan re-saved INLINE as a sub_resource rather than an
# ext_resource, forking the content silently.
#
# Every case here holds the ORIGINAL object reference and asserts on THAT. Asserting through
# load(path) is the blind version: it returns the edited copy either way, so it passes against the
# bug. The identity assertion is what says the two are the same object rather than two that agree.
#
# Writes to a user:// temp file and cleans up, matching test_dev_tool_save_uid.gd's discipline --
# a shipped .tres is served from the resource cache to every suite in the run.
extends GdUnitTestSuite

const P := preload("res://tests/support/pattern_fixtures.gd")

const TEMP_PATH := "user://__test_live_sync.tres"
const OTHER_PATH := "user://__test_live_sync_other.tres"

const SEEDED_POWER := 5
const EDITED_POWER := 42


func after_test() -> void:
	await await_idle_frame()   # #93/#101 orphan workaround
	for path in [TEMP_PATH, OTHER_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# The object a board unit would be holding: written to disk, then loaded back through the cache the
# catalogs read.
func _staged_live_attack() -> WeaponAttackData:
	var seed_attack := WeaponAttackData.new()
	seed_attack.display_name = "Live Sync Probe"
	seed_attack.power = SEEDED_POWER
	assert_int(ResourceSaver.save(seed_attack, TEMP_PATH)).is_equal(OK)
	var live := load(TEMP_PATH) as WeaponAttackData
	assert_object(live).is_not_null()
	assert_int(live.power).is_equal(SEEDED_POWER)
	return live


# What a pool editor's Load hands out, and what its Update saves.
func _editor_copy(live: WeaponAttackData) -> WeaponAttackData:
	return live.duplicate(true) as WeaponAttackData


func test_an_update_reaches_the_object_the_board_is_holding() -> void:
	var live := _staged_live_attack()

	var edited := _editor_copy(live)
	edited.power = EDITED_POWER
	assert_bool(DevWidgets.save_over(edited, TEMP_PATH, null)).is_true()

	assert_int(live.power).is_equal(EDITED_POWER)


func test_an_update_leaves_one_object_at_the_path() -> void:
	var live := _staged_live_attack()

	var edited := _editor_copy(live)
	edited.power = EDITED_POWER
	assert_bool(DevWidgets.save_over(edited, TEMP_PATH, null)).is_true()

	# The cache still resolves to the SAME object, so a catalog rescan and the board agree. Without
	# the write-through this is the edited copy while `live` is a stale orphan beside it.
	assert_object(load(TEMP_PATH)).is_same(live)


# The inline-fork hazard, pinned directly: an orphan's resource_path is empty, and a holder saved
# afterwards writes it as a sub_resource instead of an ext_resource.
func test_an_update_leaves_the_overwritten_object_still_owning_its_path() -> void:
	var live := _staged_live_attack()

	var edited := _editor_copy(live)
	edited.power = EDITED_POWER
	assert_bool(DevWidgets.save_over(edited, TEMP_PATH, null)).is_true()

	assert_str(live.resource_path).is_equal(TEMP_PATH)


# The whole point, one layer up: a mod holding the attack by reference is what a carried weapon
# reaches it through, and it must not need re-fitting to see the edit.
func test_a_mod_granting_the_attack_sees_the_edit_without_being_touched() -> void:
	var live := _staged_live_attack()
	var mod := WeaponModData.new()
	var granted: Array[WeaponAttackData] = [live]
	mod.granted_attacks = granted

	var edited := _editor_copy(live)
	edited.power = EDITED_POWER
	assert_bool(DevWidgets.save_over(edited, TEMP_PATH, null)).is_true()

	assert_int(mod.granted_attacks[0].power).is_equal(EDITED_POWER)


# The commit point is UPDATE, not every keystroke (dev ruling 2026-08-27). The editor's form stays
# live afterwards, and what it holds must not reach the board until the next save -- including on
# a NESTED resource, which is why _adopt copies a duplicate(true) snapshot rather than assigning
# the edited object's own sub-resources across.
func test_editing_on_after_a_save_does_not_reach_the_board_until_the_next_one() -> void:
	var live := _staged_live_attack()
	live.attack_pattern = P.point(3)

	var edited := _editor_copy(live)
	edited.power = EDITED_POWER
	assert_bool(DevWidgets.save_over(edited, TEMP_PATH, null)).is_true()

	edited.power = 999
	var edited_pattern := edited.attack_pattern
	edited_pattern.max_range = 9

	assert_int(live.power).is_equal(EDITED_POWER)
	var live_pattern := live.attack_pattern
	assert_int(live_pattern.max_range).is_equal(3)

	assert_bool(DevWidgets.save_over(edited, TEMP_PATH, null)).is_true()
	assert_int(live.power).is_equal(999)
	live_pattern = live.attack_pattern
	assert_int(live_pattern.max_range).is_equal(9)


# Save As: nothing is cached at a fresh path, so nobody holds a stale reference and the cheap
# take_over_path is still the right answer.
func test_saving_to_a_fresh_path_still_claims_it() -> void:
	var fresh := WeaponAttackData.new()
	fresh.display_name = "Fresh"
	fresh.power = SEEDED_POWER

	assert_bool(DevWidgets.save_over(fresh, OTHER_PATH, null)).is_true()

	assert_str(fresh.resource_path).is_equal(OTHER_PATH)
	assert_object(load(OTHER_PATH)).is_same(fresh)


# The three tools that already hand out the LIVE object -- the Attack Editor's Weapon Families
# mode, the Item Editor's templates, ObjectKnobs' TileSet -- save the very object at the path, and
# must be untouched by any of this.
func test_saving_the_live_object_itself_is_unchanged() -> void:
	var live := _staged_live_attack()
	live.power = EDITED_POWER

	assert_bool(DevWidgets.save_over(live, TEMP_PATH, null)).is_true()

	assert_int(live.power).is_equal(EDITED_POWER)
	assert_object(load(TEMP_PATH)).is_same(live)
	assert_str(live.resource_path).is_equal(TEMP_PATH)
