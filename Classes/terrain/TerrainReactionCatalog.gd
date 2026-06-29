extends Object
class_name TerrainReactionCatalog

# All terrain reactions the resolver considers, authored as .tres in Resources/TerrainReactions/
# and edited in the inspector — exactly like ReactionCatalog for unit reactions. Sorted so
# discovery is deterministic (R2).

const REACTION_DIR := "res://Resources/TerrainReactions/"

static func get_all() -> Array[TerrainReaction]:
	var reactions: Array[TerrainReaction] = []
	if not DirAccess.dir_exists_absolute(REACTION_DIR):
		return reactions
	var files := DirAccess.get_files_at(REACTION_DIR)
	files.sort()
	for file in files:
		if not file.ends_with(".tres"):
			continue
		var res = load(REACTION_DIR + file)
		if res is TerrainReaction:
			reactions.append(res)
	return reactions
