extends Object
class_name RuneCatalog

# Authored rune loadouts — written by the rune editor, scanned at runtime. A rune is a blank
# container until carvings are inscribed (docs/design/alchemy-kit.md), so there are no useful
# hardcoded "types" the way weapons have; authoring starts from a blank of a chosen size.
const VARIANT_DIR := "res://Resources/RuneVariants/"

# A blank rune of each size — the editor's starting points (D3).
static func base_runes() -> Dictionary:
	var bases := {}
	for size in RuneData.Size.values():
		var rune := RuneData.new()
		rune.size = size
		bases["Rune - %s" % RuneData.Size.keys()[size].capitalize()] = rune
	return bases

# Saved authored runes, scanned from disk (mirrors WeaponCatalog.get_saved).
static func get_variants() -> Dictionary:
	var variants := {}
	if not DirAccess.dir_exists_absolute(VARIANT_DIR):
		return variants
	for file in DirAccess.get_files_at(VARIANT_DIR):
		if not file.ends_with(".tres"):
			continue
		var res = load(VARIANT_DIR + file)
		if res is RuneData:
			variants[res.item_name if res.item_name != "" else file.get_basename()] = res
	return variants

# Authored runes — for the unit editor's equip list.
static func get_editable() -> Dictionary:
	return get_variants()
