extends Object
class_name AbilityCatalog

# Registry for authored AbilityData content under Resources/Abilities/ (#179): the character
# editor's innate-abilities picker is the first thing to ENUMERATE abilities rather than
# reference them file-by-file (JobData.ability_pool, ArmorData.granted_abilities). Uncached,
# like every flat catalog outside hot paths.

const ABILITY_DIR := "res://Resources/Abilities/"

static func get_abilities() -> Dictionary:
	return ResourceCatalog.by_name(ABILITY_DIR, AbilityData)
