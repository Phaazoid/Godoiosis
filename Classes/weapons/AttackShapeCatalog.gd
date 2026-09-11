extends Object
class_name AttackShapeCatalog

# Registry for authored AttackShape content (#808) -- the named stamps every attack picks from,
# shared BY REFERENCE, so this folder is a census: every shape in use is in it, and editing one
# reaches every attack that names it.
#
# One tier, unlike WeaponAttackCatalog's two: a shape has no "main vs pool" distinction to make,
# since nothing owns a shape the way a family owns its main attack.
#
# `users_of` used to live here. It moved to ResourceCatalog when #900 gave EffectLook the same
# library shape and needed the same question answered -- "which files name this path" is about a
# .tres reference and not about shapes, so a copy here would have been a second answer to it
# (Law #4). See ResourceCatalog.users_of.
const LIBRARY_DIR := "res://Resources/AttackShapes/"

static func get_library() -> Dictionary:
	return ResourceCatalog.by_name(LIBRARY_DIR, AttackShape)
