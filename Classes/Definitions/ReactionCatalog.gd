extends Object
class_name ReactionCatalog

# All elemental reactions the resolver considers, authored as .tres data and edited
# in the Godot inspector (Resources/Reactions/). Mirrors WeaponCatalog's variant scan.
# Files are sorted so discovery order is deterministic (R2) — though E8 composition
# is order-independent anyway, so order never changes an outcome.

const REACTION_DIR := "res://Resources/Reactions/"

static func get_all() -> Array[ElementReaction]:
	var reactions: Array[ElementReaction] = []
	if not DirAccess.dir_exists_absolute(REACTION_DIR):
		return reactions
	var files := DirAccess.get_files_at(REACTION_DIR)
	files.sort()
	for file in files:
		if not file.ends_with(".tres"):
			continue
		var res = load(REACTION_DIR + file)
		if res is ElementReaction:
			reactions.append(res)
	return reactions
