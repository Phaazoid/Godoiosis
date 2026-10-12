extends Object
class_name ConduitCatalog

# Registry for authored conduits (#1312). VialCatalog's shape exactly: a conduit carries no
# per-instance state, so a catalog entry IS the item, scanned straight off disk. Without it the
# editors could not offer one and the game could not grant one.
const VARIANT_DIR := "res://Resources/Conduits/"

static func get_variants() -> Dictionary:
	return ResourceCatalog.by_name(VARIANT_DIR, ConduitData)

# Authored conduits -- for the editors' item list (mirrors VialCatalog/ArmorCatalog/RuneCatalog).
static func get_editable() -> Dictionary:
	return get_variants()
