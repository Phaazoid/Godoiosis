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

static func get_variants() -> Dictionary:
	var variants := {}
	var candidates := ResourceCatalog.by_name(VARIANT_DIR, RuneData)
	for name in candidates:
		var rune: RuneData = candidates[name]
		if not rune.is_legal():
			push_error("%s: illegal under the two-knob rune rules — refused" % name)
			continue
		variants[name] = rune
	return variants

# Authored runes — for the unit editor's equip list.
static func get_editable() -> Dictionary:
	return get_variants()
