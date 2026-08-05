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
	return ResourceCatalog.by_name(LIBRARY_DIR, WeaponAttackData)

static func get_mains() -> Dictionary:
	var mains := ResourceCatalog.by_name(MAIN_DIR, WeaponAttackData)
	var proto := ResourceCatalog.by_name(PROTOTYPE_MAIN_DIR, WeaponAttackData)
	for k in proto:
		mains[k] = proto[k]
	return mains
