extends Object
class_name TransmutationCatalog

# Carvings authored in the dev Attack Editor tab (or the inspector), saved as .tres here.
# Scanned so the rune editor can offer them to inscribe. docs/design/alchemy-kit.md.
const CARVING_DIR := "res://Resources/TransmutationData/"

static func get_all() -> Dictionary:
	var carvings := {}
	if not DirAccess.dir_exists_absolute(CARVING_DIR):
		return carvings
	for file in DirAccess.get_files_at(CARVING_DIR):
		if not file.ends_with(".tres"):
			continue
		var res = load(CARVING_DIR + file)
		if res is TransmutationData:
			carvings[res.display_name if res.display_name != "" else file.get_basename()] = res
	return carvings
