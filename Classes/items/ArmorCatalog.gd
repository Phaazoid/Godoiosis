extends Object
class_name ArmorCatalog

# Registry for armor pieces (#65). Unlike weapons, ArmorData carries no per-instance
# fitted state (no mod spaces exist yet) -- a catalog entry IS the equippable, scanned
# straight off disk the way WeaponCatalog.get_family_bases() scans weapon templates.
const VARIANT_DIR := "res://Resources/Armor/"

static func get_variants() -> Dictionary:
	return ResourceCatalog.by_name(VARIANT_DIR, ArmorData)

# Authored armor -- for the unit editor's equip list (mirrors WeaponCatalog/RuneCatalog.get_editable).
static func get_editable() -> Dictionary:
	return get_variants()
