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
