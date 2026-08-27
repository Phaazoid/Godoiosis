extends Object
class_name WeaponModCatalog

# Registry for authored WeaponModData content — the fitting tool's mod picker scans here.
# Fitted mods ride instances as direct refs, so editing a mod .tres updates every weapon
# it's fitted to (same live-sync model as templates) -- true only since #589 taught
# DevWidgets.save_over to write THROUGH to the object that owns the path, rather than
# orphaning it behind the editor's copy.
const MOD_DIR := "res://Resources/WeaponMods/"

static func get_mods() -> Dictionary:
	return ResourceCatalog.by_name(MOD_DIR, WeaponModData)
