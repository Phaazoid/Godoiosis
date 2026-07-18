extends Object
class_name WeaponModCatalog

# Registry for authored WeaponModData content — the fitting tool's mod picker scans here.
# Fitted mods ride instances as direct refs, so editing a mod .tres updates every weapon
# it's fitted to (same live-sync model as templates).
const MOD_DIR := "res://Resources/WeaponMods/"

static func get_mods() -> Dictionary:
	var mods := {}
	if not DirAccess.dir_exists_absolute(MOD_DIR):
		return mods
	for file in DirAccess.get_files_at(MOD_DIR):
		if not file.ends_with(".tres"):
			continue
		var res = load(MOD_DIR + file)
		if res is WeaponModData:
			mods[res.display_name if res.display_name != "" else file.get_basename()] = res
	return mods
