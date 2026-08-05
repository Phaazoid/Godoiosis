extends Object
class_name ResourceCatalog

# One answer to "what authored content of this type lives in this folder?" (#141): load,
# type-check, key by name. Not for ScenarioManager or SpawnTool's sprites -- those collect
# paths and textures, not resources, and stay on ResourceDir.

const RESOURCE_EXT := ".tres"
static func load_all(dir: String, type) -> Array:
	var found := []
	for file in ResourceDir.files_with_extension(dir, RESOURCE_EXT):
		var res = load(dir + file)
		if is_instance_of(res, type):
			found.append(res)
	return found

# display_name -> resource, filename as the fallback. Kept separate from load_all on purpose:
# keying would collapse two resources sharing a name, and the unkeyed callers must keep both.
static func by_name(dir: String, type) -> Dictionary:
	var found := {}
	for file in ResourceDir.files_with_extension(dir, RESOURCE_EXT):
		var res = load(dir + file)
		if is_instance_of(res, type):
			found[_key_for(res, file)] = res
	return found

static func _key_for(res, file: String) -> String:
	var authored: String = res.display_name
	if authored != "":
		return authored
	return file.get_basename()
