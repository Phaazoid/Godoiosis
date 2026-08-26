# Content laws over the authored mods in Resources/WeaponMods/ (#74). These LOAD real .tres on
# purpose — the sibling shape of test_weapon_template_lint.gd's sweep, and rule 4's declared
# exception for a content law — while respecting the content razor: nothing here asserts what a
# mod CONTAINS. Every claim is either "the file and the loaded resource agree" or "no file writes
# a key that no longer exists".
extends GdUnitTestSuite


# scaling_nudge became scaling_change in #74, and a renamed .tres key is dropped SILENTLY on load:
# the file keeps its text, the values just stop arriving. Two shipped mods carried one, so this is
# the guard for a migration that has no other way to fail loudly.
func test_no_mod_still_writes_the_retired_scaling_nudge_key() -> void:
	var stale: Array[String] = []
	for path in _mod_files():
		if FileAccess.get_file_as_string(path).contains("scaling_nudge"):
			stale.append(path.get_file())
	assert_array(stale).is_empty()


# The other direction, and the one that catches a rename that half-landed: a file that WRITES a
# scaling change must load with one. Reading the file's own text rather than pinning any mod's
# numbers is what keeps this blind to what the dev authors.
func test_a_mod_whose_file_writes_a_scaling_change_loads_it() -> void:
	var checked := 0
	var empty: Array[String] = []
	var mods := WeaponModCatalog.get_mods()
	for name in mods:
		var mod: WeaponModData = mods[name]
		if not FileAccess.get_file_as_string(mod.resource_path).contains("\nscaling_change = "):
			continue
		checked += 1
		if mod.scaling_change.is_empty():
			empty.append(name)
	assert_array(empty).is_empty()
	assert_int(checked).is_greater(0)   # no shipped mod authors a scaling change: this guard proves nothing


# The same for the family field that arrived beside it -- a mod whose file names a family must
# load holding one, or the key was dropped exactly as scaling_nudge would have been.
func test_a_mod_whose_file_writes_a_family_loads_it() -> void:
	var checked := 0
	var unset: Array[String] = []
	var mods := WeaponModCatalog.get_mods()
	for name in mods:
		var mod: WeaponModData = mods[name]
		if not FileAccess.get_file_as_string(mod.resource_path).contains("\nfamily = "):
			continue
		checked += 1
		if mod.family == WeaponData.WeaponType.NONE:
			unset.append(name)
	assert_array(unset).is_empty()
	assert_int(checked).is_greater(0)   # no shipped mod names a family: this guard proves nothing


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
	assert_int(mods.size()).is_greater(0)   # nothing scanned: this sweep proves nothing
