extends Object
class_name WeaponAttackCatalog

# Registry for authored WeaponAttackData content (#72). Two tiers, partitioned by folder —
# the scans are non-recursive, so the split costs nothing:
#   LIBRARY_DIR (root) — the general pool: alt/extra attacks, authored in the Weapon
#                        Attacks dev tab.
#   MAIN_DIR           — the curated set: exactly ONE main attack per weapon family
#                        (+ Prototypes/ for named prototypes). Editing one changes that
#                        family everywhere; the Family Mains panel is their only in-tool
#                        editing surface.
const LIBRARY_DIR := "res://Resources/WeaponAttacks/"
const MAIN_DIR := "res://Resources/WeaponAttacks/MainAttacks/"
const PROTOTYPE_MAIN_DIR := "res://Resources/WeaponAttacks/MainAttacks/Prototypes/"

static func get_library() -> Dictionary:
	return _scan(LIBRARY_DIR)

static func get_mains() -> Dictionary:
	var mains := _scan(MAIN_DIR)
	var proto := _scan(PROTOTYPE_MAIN_DIR)
	for k in proto:
		mains[k] = proto[k]
	return mains

static func _scan(dir: String) -> Dictionary:
	var found := {}
	if not DirAccess.dir_exists_absolute(dir):
		return found
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".tres"):
			continue
		var res = load(dir + file)
		if res is WeaponAttackData:
			found[res.display_name if res.display_name != "" else file.get_basename()] = res
	return found
