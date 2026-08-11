extends Object
class_name UnitCatalog

# Registry for authored characters (#177): the standalone UnitData files under Resources/Units/
# ARE the cast — the one authoritative answer to "who is this character". The SpawnTool's
# Character dropdown places them; authored saves reference these files instead of embedding
# copies, so editing a character file updates every mission it appears in.
const CHARACTER_DIR := "res://Resources/Units/"

static func get_characters() -> Dictionary:
	return ResourceCatalog.by_name(CHARACTER_DIR, UnitData)
