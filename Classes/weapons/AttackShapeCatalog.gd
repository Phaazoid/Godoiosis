extends Object
class_name AttackShapeCatalog

# Registry for authored AttackShape content (#808) -- the named stamps every attack picks from,
# shared BY REFERENCE, so this folder is a census: every shape in use is in it, and editing one
# reaches every attack that names it.
#
# One tier, unlike WeaponAttackCatalog's two: a shape has no "main vs pool" distinction to make,
# since nothing owns a shape the way a family owns its main attack.
const LIBRARY_DIR := "res://Resources/AttackShapes/"

static func get_library() -> Dictionary:
	return ResourceCatalog.by_name(LIBRARY_DIR, AttackShape)


# The roots a referrer can live under. Resources/ holds the attacks and the families; Scenarios/
# holds missions, which EMBED attacks -- and an embedded attack is exactly the referrer a catalog
# scan cannot see, which is why this reads files rather than asking WeaponAttackCatalog.
const SCANNED_ROOTS: Array[String] = ["res://Resources/", "res://Scenarios/"]

# Which FILES name this shape, by basename. Read as text rather than by loading: a mission is
# expensive to load and its embedded attacks are not in any catalog anyway, and both forms Godot
# writes a reference in (`uid=` plus `path=`) carry the path, so one substring answers both.
#
# It is what the Attack Editor's "used by" caption says out loud before a shared edit, and what
# refuses to delete a shape something still holds -- a dangling ext_resource is a hard PARSE error
# that takes the whole referring file down, never a field that comes back null.
static func users_of(shape_path: String) -> Array[String]:
	var users: Array[String] = []
	if shape_path == "":
		return users
	for root in SCANNED_ROOTS:
		_collect_users(root, shape_path, users)
	users.sort()
	return users

static func _collect_users(dir_path: String, shape_path: String, users: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect_users(dir_path.path_join(sub), shape_path, users)
	for file in ResourceDir.files_with_extension(dir_path, ResourceCatalog.RESOURCE_EXT):
		var path := dir_path.path_join(file)
		# NO self-reference guard, and that is measured rather than assumed: a .tres never names its
		# own path -- the [gd_resource] header carries a uid and nothing else -- so a shape can never
		# be found as its own user. One sat here and was DEAD; deleting it reddened nothing, which is
		# what named the file format as the mechanism. The #807 select(0) lesson, one ticket on.
		if FileAccess.get_file_as_string(path).contains(shape_path):
			users.append(file)
