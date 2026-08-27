# Content laws over the authored mods in Resources/WeaponMods/ (#74). The sweeps LOAD real .tres on
# purpose — the sibling shape of test_weapon_template_lint.gd's sweep, and rule 4's declared
# exception for a content law — while respecting the content razor: nothing here asserts what a
# mod CONTAINS. Every claim is either "the file and the loaded resource agree" or "no file writes
# a key that no longer exists".
#
# None of it may depend on the dev SHIPPING a mod of any particular shape (dev ruling, 2026-08-27:
# "a lack of authored content shouldn't cause tests to fail"). #596 is the case that earned it --
# deleting `Super Scope.tres` took away the only mod authoring a family or a scaling change, and
# two cases here reddened over content that was never their subject, two suites from the rename
# that caused it. So the two field laws below round-trip a fixture of their OWN, and the sweeps
# grade whatever is on disk without demanding anything be there: an empty folder breaks no content
# law, and saying otherwise makes deleting a mod a test failure.
extends GdUnitTestSuite

# One path per case: load() caches by path, so sharing one would let a later case read an earlier
# case's resource straight out of the cache.
const SCALING_PATH := "user://__test_mod_scaling.tres"
const FAMILY_PATH := "user://__test_mod_family.tres"


func after_test() -> void:
	for path in [SCALING_PATH, FAMILY_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# The fault this guards is a field that stops ARRIVING: rename or retype a key and it is dropped
# SILENTLY on load, the file keeping its text while the value simply stops coming. A
# Dictionary[Stats.Stat, int] is the likeliest shape to go that way.
#
# Read back with CACHE_MODE_IGNORE and asserted not-same, so the round trip cannot be satisfied
# by the resource cache returning the object saved a line earlier. Whether ResourceSaver.save
# claims the path here is a Godot detail this should not be resting on in either direction --
# the assertion measures it rather than the comment asserting it.
func test_a_scaling_change_survives_a_save_and_load() -> void:
	var change: Dictionary[Stats.Stat, int] = {Stats.Stat.DEX: 5, Stats.Stat.PER: -5}
	var authored := WeaponModData.new()
	authored.family = WeaponData.WeaponType.CARBINE   # required once a scaling change is set
	authored.scaling_change = change
	assert_int(ResourceSaver.save(authored, SCALING_PATH)).is_equal(OK)
	# The writer must put the key in the file, or the load proves nothing about it.
	assert_str(FileAccess.get_file_as_string(SCALING_PATH)).contains("\nscaling_change = ")

	var loaded := ResourceLoader.load(SCALING_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as WeaponModData
	assert_object(loaded).is_not_null()
	assert_object(loaded).is_not_same(authored)   # a cached hit would make the rest vacuous
	assert_dict(loaded.scaling_change).has_size(2)
	assert_dict(loaded.scaling_change).contains_key_value(Stats.Stat.DEX, 5)
	assert_dict(loaded.scaling_change).contains_key_value(Stats.Stat.PER, -5)


# The same for the family field that arrived beside it -- an enum, which reaches the file as a bare
# int and so has no way to announce that it came back meaning nothing.
func test_a_family_survives_a_save_and_load() -> void:
	var authored := WeaponModData.new()
	authored.family = WeaponData.WeaponType.CARBINE
	assert_int(ResourceSaver.save(authored, FAMILY_PATH)).is_equal(OK)
	assert_str(FileAccess.get_file_as_string(FAMILY_PATH)).contains("\nfamily = ")

	var loaded := ResourceLoader.load(FAMILY_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as WeaponModData
	assert_object(loaded).is_not_null()
	assert_object(loaded).is_not_same(authored)
	assert_int(loaded.family).is_equal(WeaponData.WeaponType.CARBINE)


func _mod_files() -> Array[String]:
	var paths: Array[String] = []
	for file in ResourceDir.files_with_extension(WeaponModCatalog.MOD_DIR, ".tres"):
		paths.append(WeaponModCatalog.MOD_DIR + file)
	return paths


# The derived restriction swept over shipped content (#74): a mod that changes scaling names the
# family its shift is measured against. Nothing could enforce this before the field existed, and
# two shipped mods carried a change with no family at all.
func test_no_shipped_mod_changes_scaling_without_naming_a_family() -> void:
	var broken: Array[String] = []
	var mods := WeaponModCatalog.get_mods()
	for name in mods:
		var mod: WeaponModData = mods[name]
		var reason := mod.save_block_reason()
		if reason != "":
			broken.append("%s: %s" % [name, reason])
	assert_array(broken).is_empty()


# Every key a shipped mod file writes must still be a property of WeaponModData. A renamed or
# retired key is dropped SILENTLY on load -- the file keeps its text, the value just stops
# arriving -- and that is not a failure any other test can see.
#
# ABSORBS #74's scaling_nudge check, which asked the same question about one key: that name is
# simply one this class no longer has. Written generally because the fields keep coming --
# applies_to and replaces_main (#529/#530) arrive with no content of their own, so a per-field
# guard for either would assert nothing at all today and rot quietly until it did.
func test_no_mod_file_writes_a_key_the_class_no_longer_has() -> void:
	var live := {}
	for prop: Dictionary in WeaponModData.new().get_property_list():
		live[prop.get("name", "")] = true
	var stale: Array[String] = []
	for path in _mod_files():
		for key in _resource_keys(FileAccess.get_file_as_string(path)):
			if not live.has(key):
				stale.append("%s: %s" % [path.get_file(), key])
	assert_array(stale).is_empty()


# Keys from the [resource] block alone. The ext_resource/sub_resource headers above it speak the
# file FORMAT's vocabulary (type/path/uid/id), which is nothing to do with this class.
func _resource_keys(text: String) -> Array[String]:
	var keys: Array[String] = []
	var in_resource := false
	for line: String in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("["):
			in_resource = trimmed.begins_with("[resource]")
			continue
		if not in_resource:
			continue
		if trimmed.begins_with("metadata/"):
			continue   # Godot's own editor metadata, not a property of this class
		var eq := trimmed.find(" = ")
		if eq > 0:
			keys.append(trimmed.substr(0, eq))
	return keys
