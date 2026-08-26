# Content laws over the authored mods in Resources/WeaponMods/ (#74). These LOAD real .tres on
# purpose — the sibling shape of test_weapon_template_lint.gd's sweep, and rule 4's declared
# exception for a content law — while respecting the content razor: nothing here asserts what a
# mod CONTAINS. Every claim is either "the file and the loaded resource agree" or "no file writes
# a key that no longer exists".
extends GdUnitTestSuite


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
	var scanned := 0
	for path in _mod_files():
		for key in _resource_keys(FileAccess.get_file_as_string(path)):
			scanned += 1
			if not live.has(key):
				stale.append("%s: %s" % [path.get_file(), key])
	assert_array(stale).is_empty()
	assert_int(scanned).is_greater(0)	# nothing parsed: this sweep proves nothing


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
