extends Object
class_name WeaponCatalog

# Registry for weapon TEMPLATES (family bases + prototypes) and saved fitted INSTANCES.
# Templates are the shared designs; a saved instance is "template + mods + a custom name"
# (the keep-a-named-weapon feature) and stays in sync with its template via direct ref.

# Family base templates — hardcoded, edited via the .tres in the inspector.
const TYPES := {
	"Chainsword": preload("res://Resources/Weapons/MainVarieties/ChainSword.tres"),
	"Springspear": preload("res://Resources/Weapons/MainVarieties/Springspear.tres")
	}

# Named prebuilt prototype templates (weapons.md "the archetype clause made content").
const PROTOTYPE_DIR := "res://Resources/Weapons/Prototypes/"

# Saved fitted WeaponInstances — written by the fitting tool, scanned at runtime.
const SAVED_DIR := "res://Resources/Weapons/WeaponVariants/"

static func get_prototypes() -> Dictionary:
	return _scan(PROTOTYPE_DIR, WeaponData)

static func get_saved() -> Dictionary:
	return _scan(SAVED_DIR, WeaponInstance)

static func _scan(dir: String, type) -> Dictionary:
	var found := {}
	if not DirAccess.dir_exists_absolute(dir):
		return found
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".tres"):
			continue
		var res = load(dir + file)
		if is_instance_of(res, type):
			found[res.item_name if res.item_name != "" else file.get_basename()] = res
	return found

# All templates a new weapon can start from — for the fitting tool.
static func get_templates() -> Dictionary:
	var templates := {}
	for t in TYPES:
		templates[t] = TYPES[t]
	var prototypes := get_prototypes()
	for p in prototypes:
		templates[p] = prototypes[p]
	return templates

# Everything grantable to a unit (templates get wrapped in a fresh instance at grant time;
# saved instances get copied) — for the spawner / unit editor equip lists.
static func get_editable() -> Dictionary:
	var editable := get_templates()
	var saved := get_saved()
	for s in saved:
		editable[s] = saved[s]
	return editable

static func get_spawnable() -> Dictionary:
	var all := get_editable()
	all["None"] = null
	return all

# The one grant path: turn any catalog entry into something a unit can own.
static func instantiate_entry(entry) -> EquippableData:
	if entry is WeaponData:
		return WeaponInstance.make(entry)
	if entry is EquippableData:
		return entry.copy_equippable()
	return null
