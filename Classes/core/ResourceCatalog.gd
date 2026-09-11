extends Object
class_name ResourceCatalog

# One answer to "what authored content of this type lives in this folder?" (#141): load,
# type-check, key by name. Not for ScenarioManager or SpawnTool's sprites -- those collect
# paths and textures, not resources, and stay on ResourceDir.

const RESOURCE_EXT := ".tres"
static func load_all(dir: String, type) -> Array:
	var found := []
	for file in ResourceDir.files_with_extension(dir, RESOURCE_EXT):
		var res = ContentRepair.load_tolerant(dir + file)
		if is_instance_of(res, type):
			found.append(res)
	return found

# display_name -> resource, filename as the fallback. Kept separate from load_all on purpose:
# keying would collapse two resources sharing a name, and the unkeyed callers must keep both.
static func by_name(dir: String, type) -> Dictionary:
	var found := {}
	for file in ResourceDir.files_with_extension(dir, RESOURCE_EXT):
		var res = ContentRepair.load_tolerant(dir + file)
		if is_instance_of(res, type):
			found[_key_for(res, file)] = res
	return found

static func _key_for(res, file: String) -> String:
	var authored: String = res.display_name
	if authored != "":
		return authored
	return file.get_basename()


# filename (no extension) -> resource. The THIRD projection, for a caller whose key has to be the
# FILE (#812): a roster stores its picks as ext_resource paths, so the file IS the identity, and
# by_name above would collapse two variants of one character into a single pickable entry -- which
# is exactly what a roster gets used for (dev, 2026-09-07: "if I want different versions of the same
# character, I will author them specifically for different missions").
#
# It is a projection rather than a replacement: a display name is the right key for a dropdown a
# human reads and is what every existing catalog wants. What a caller needs is which of the two
# questions it is asking -- "what is this called" or "which file is this" -- and a filename key
# cannot answer the first any more than by_name can answer the second.
static func by_file(dir: String, type) -> Dictionary:
	var found := {}
	for file in ResourceDir.files_with_extension(dir, RESOURCE_EXT):
		var res = ContentRepair.load_tolerant(dir + file)
		if is_instance_of(res, type):
			found[file.get_basename()] = res
	return found


# The roots a referrer can live under. Resources/ holds the attacks, the families and the looks;
# Scenarios/ holds missions, which EMBED attacks -- and an embedded attack is exactly the referrer
# a catalog scan cannot see, which is why this reads files rather than asking a catalog.
const SCANNED_ROOTS: Array[String] = ["res://Resources/", "res://Scenarios/"]

# Which FILES name this resource, by basename. Read as text rather than by loading: a mission is
# expensive to load and its embedded attacks are not in any catalog anyway, and both forms Godot
# writes a reference in (`uid=` plus `path=`) carry the path, so one substring answers both.
#
# It is what a dev tool's "used by" caption says out loud before a shared edit, and what refuses to
# delete a library file something still holds -- a dangling ext_resource is a hard PARSE error that
# takes the whole referring file down, never a field that comes back null.
#
# LIVED ON AttackShapeCatalog until #900. The question is about a path and a .tres rather than
# about shapes, so the second library (EffectLook) wanted the identical answer, not a copy of it.
static func users_of(resource_path: String) -> Array[String]:
	var users: Array[String] = []
	if resource_path == "":
		return users
	for root in SCANNED_ROOTS:
		_collect_users(root, resource_path, users)
	users.sort()
	return users

static func _collect_users(dir_path: String, resource_path: String, users: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect_users(dir_path.path_join(sub), resource_path, users)
	for file in ResourceDir.files_with_extension(dir_path, RESOURCE_EXT):
		var path := dir_path.path_join(file)
		# NO self-reference guard, and that is measured rather than assumed: a .tres never names its
		# own path -- the [gd_resource] header carries a uid and nothing else -- so a file can never
		# be found as its own user. One sat here and was DEAD; deleting it reddened nothing, which is
		# what named the file format as the mechanism. The #807 select(0) lesson, one ticket on.
		if FileAccess.get_file_as_string(path).contains(resource_path):
			users.append(file)
