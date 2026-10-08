extends Object
class_name SubstanceCatalog

# Every substance Deep Alchemy knows (Resources/Substances/), keyed by id = file name. Cached like
# ReactionCatalog; anything that adds or removes a file at runtime calls refresh().

const DIR := "res://Resources/Substances/"

static var _cache: Dictionary = {}   # id -> Substance
static var _scanned := false


# A COPY, so a caller adding to it cannot change everyone's.
static func get_all() -> Dictionary:
	if not _scanned:
		_cache.clear()
		for file: String in ResourceDir.files_with_extension(DIR, ".tres"):
			var substance := ContentRepair.load_tolerant(DIR + file) as Substance
			if substance != null:
				_cache[file.get_basename()] = substance
		_scanned = true
	return _cache.duplicate()


static func by_id(id: String) -> Substance:
	return get_all().get(id) as Substance


static func refresh() -> void:
	_scanned = false
