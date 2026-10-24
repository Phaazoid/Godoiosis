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
		if refuses(rune, name):
			continue
		variants[name] = rune
	return variants

# The one refusal of an authored rune, asked by every list that offers one (ItemCatalog too, #1414).
static func refuses(rune: RuneData, name: String) -> bool:
	if rune.is_legal():
		return false
	push_error("%s: illegal under the two-knob rune rules — refused" % name)
	return true

# Authored runes by name. The editors' list is ItemCatalog.by_name, which asks refuses() itself.
static func get_editable() -> Dictionary:
	return get_variants()
