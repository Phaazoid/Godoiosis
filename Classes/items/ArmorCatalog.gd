extends Object
class_name ArmorCatalog

# Registry for armor pieces (#65). Unlike weapons, ArmorData carries no per-instance
# fitted state (no mod spaces exist yet) -- a catalog entry IS the equippable, scanned
# straight off disk the way WeaponCatalog.get_family_bases() scans weapon templates.
const VARIANT_DIR := "res://Resources/Armor/"

static func get_variants() -> Dictionary:
	var variants := {}
	if not DirAccess.dir_exists_absolute(VARIANT_DIR):
		return variants
	for file in DirAccess.get_files_at(VARIANT_DIR):
		if not file.ends_with(".tres"):
			continue
		var res = load(VARIANT_DIR + file)
		if res is ArmorData:
			variants[res.item_name if res.item_name != "" else file.get_basename()] = res
	return variants

# Authored armor -- for the unit editor's equip list (mirrors WeaponCatalog/RuneCatalog.get_editable).
static func get_editable() -> Dictionary:
	return get_variants()
