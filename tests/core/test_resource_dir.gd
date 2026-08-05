# Guard for Classes/core/ResourceDir (#141). The bug is only reachable in an EXPORTED build,
# which the suite can't run in -- but the EDITOR holds Mage.png and Mage.png.import side by
# side, so the normalize-and-de-dup path is exercisable here. Falsified: drop the de-dup and
# the sprite case returns 108 instead of 54.
#
# Pure static calls -- no nodes built -- so this stays orphan-clean.
extends GdUnitTestSuite

const SPRITE_DIR := "res://Art/Units/MapSprites/"

func test_import_sidecars_normalize_and_deduplicate() -> void:
	# Fixture premise: every .png in this folder has a .png.import beside it. If that ever
	# stops being true the de-dup assertion below goes quiet, so assert it outright.
	var raw := DirAccess.get_files_at(SPRITE_DIR)
	var sources := 0
	var sidecars := 0
	for file: String in raw:
		if file.ends_with(".png"):
			sources += 1
		elif file.ends_with(".png.import"):
			sidecars += 1
	assert_int(sources).is_greater(0)
	assert_int(sidecars).is_equal(sources)

	# Without the de-dup this returns sources + sidecars.
	var found := ResourceDir.files_with_extension(SPRITE_DIR, ".png")
	assert_int(found.size()).is_equal(sources)

func test_no_packed_suffix_survives_into_the_result() -> void:
	for name: String in ResourceDir.files_with_extension(SPRITE_DIR, ".png"):
		assert_bool(name.ends_with(".import")).is_false()
		assert_bool(name.ends_with(".remap")).is_false()
		assert_bool(name.ends_with(".png")).is_true()

func test_a_known_source_name_is_present() -> void:
	var found := ResourceDir.files_with_extension(SPRITE_DIR, ".png")
	assert_array(found).contains(["Mage.png"])

func test_results_are_sorted_so_discovery_is_deterministic() -> void:
	var found := ResourceDir.files_with_extension(SPRITE_DIR, ".png")
	var expected := PackedStringArray(found)
	expected.sort()
	assert_array(found).is_equal(expected)

func test_finds_tres_in_a_real_catalog_folder() -> void:
	var found := ResourceDir.files_with_extension(ArmorCatalog.VARIANT_DIR, ".tres")
	assert_int(found.size()).is_greater(0)
	for name: String in found:
		assert_bool(name.ends_with(".tres")).is_true()

func test_the_extension_filter_actually_filters() -> void:
	# .png files exist in the sprite folder; .tres ones do not.
	assert_int(ResourceDir.files_with_extension(SPRITE_DIR, ".tres").size()).is_equal(0)

func test_a_missing_directory_is_empty_not_an_error() -> void:
	var found := ResourceDir.files_with_extension("res://Resources/NoSuchFolder/", ".tres")
	assert_int(found.size()).is_equal(0)
