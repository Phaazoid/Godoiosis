extends Object
class_name VialCatalog

# Registry for authored vials (#697). ArmorCatalog's shape exactly: a vial carries no per-instance
# state, so a catalog entry IS the item, scanned straight off disk.
#
# It exists because without it the vials were UNREACHABLE -- four .tres nothing in the project
# referenced, so the only way to hold one was to hand-edit a scenario. A content kind with no
# catalog is a content kind the editors cannot offer and the game cannot grant.
const VARIANT_DIR := "res://Resources/Vials/"

static func get_variants() -> Dictionary:
	return ResourceCatalog.by_name(VARIANT_DIR, VialData)

# Authored vials -- for the editors' item list (mirrors WeaponCatalog/ArmorCatalog/RuneCatalog).
static func get_editable() -> Dictionary:
	return get_variants()
