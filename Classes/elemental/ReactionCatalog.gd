extends Object
class_name ReactionCatalog

# All elemental reactions the resolver considers, authored as .tres data and edited
# in the Godot inspector (Resources/Reactions/). Mirrors WeaponCatalog's variant scan.
# Files are sorted so discovery order is deterministic (R2) — though E8 composition
# is order-independent anyway, so order never changes an outcome.

const REACTION_DIR := "res://Resources/Reactions/"

static func get_all() -> Array[ElementalReaction]:
	var reactions: Array[ElementalReaction] = []
	reactions.assign(ResourceCatalog.load_all(REACTION_DIR, ElementalReaction))
	return reactions
