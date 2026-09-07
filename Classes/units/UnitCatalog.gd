extends Object
class_name UnitCatalog

# Registry for authored characters (#177): the standalone UnitData files under Resources/Units/
# ARE the cast — the one authoritative answer to "who is this character". The SpawnTool's
# Character dropdown places them; authored saves reference these files instead of embedding
# copies, so editing a character file updates every mission it appears in.
const CHARACTER_DIR := "res://Resources/Units/"

static func get_characters() -> Dictionary:
	return ResourceCatalog.by_name(CHARACTER_DIR, UnitData)


# filename -> UnitData, for a caller whose key must be the FILE (#812). A roster stores its picks
# as ext_resource paths, and by_name COLLAPSES two characters sharing a display_name -- which is
# exactly what authoring a mission-specific variant of someone produces, so a name-keyed list would
# make one of the two unpickable in the roster editor.
static func get_characters_by_file() -> Dictionary:
	return ResourceCatalog.by_file(CHARACTER_DIR, UnitData)
