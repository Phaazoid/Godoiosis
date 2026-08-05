extends Object
class_name TransmutationCatalog

# Carvings authored in the dev Attack Editor tab (or the inspector), saved as .tres here.
# Scanned so the rune editor can offer them to inscribe. docs/design/alchemy-kit.md.
const CARVING_DIR := "res://Resources/TransmutationData/"

static func get_all() -> Dictionary:
	var carvings := {}
	var candidates := ResourceCatalog.by_name(CARVING_DIR, TransmutationData)
	for name in candidates:
		var carving: TransmutationData = candidates[name]
		if not carving.is_legal():
			push_error("%s: illegal carving (bad sigils or over the max circle cap) — refused" % name)
			continue
		carvings[name] = carving
	return carvings
