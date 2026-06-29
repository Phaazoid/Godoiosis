extends Object
class_name WeaponCatalog

# Base weapon TYPES — hardcoded, never edited in-game (edit the .tres in the inspector).
const TYPES := {
	"Chainsword": preload("res://Resources/ChainSword.tres"),
	"Springspear": preload("res://Resources/Springspear.tres")
	}

# Saved customized variants — written by the Weapon Editor, scanned at runtime.
const VARIANT_DIR := "res://Resources/WeaponVariants/"

static func get_variants() -> Dictionary:
	var variants := {}
	if not DirAccess.dir_exists_absolute(VARIANT_DIR):
		return variants
	for file in DirAccess.get_files_at(VARIANT_DIR):
		if not file.ends_with(".tres"):
			continue
		var res = load(VARIANT_DIR + file)
		if res is WeaponData:
			variants[res.item_name if res.item_name != "" else file.get_basename()] = res
	return variants

# Types + variants — for the editor's load list.
static func get_editable() -> Dictionary:
	var editable := {}
	for t in TYPES:
		editable[t] = TYPES[t]
	var variants := get_variants()
	for v in variants:
		editable[v] = variants[v]
	return editable

# Types + variants + None — for the spawner / unit editor.
static func get_spawnable() -> Dictionary:
	var all := get_editable()
	all["None"] = null
	return all
