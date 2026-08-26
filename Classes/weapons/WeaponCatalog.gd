extends Object
class_name WeaponCatalog

# Registry for weapon TEMPLATES (family bases + prototypes) and saved fitted INSTANCES.
# Templates are the shared designs; a saved instance is "template + mods + a custom name"
# (the keep-a-named-weapon feature) and stays in sync with its template via direct ref.

# Family base templates — scanned from disk (dev-authored .tres, one per family). #72: this
# used to be a hardcoded const dict; the five #59-era shell families (Drill/Carbine/Kinetic
# Mace/Chemical Spitter/Prosthetic) were invisible to it purely because it never scanned
# their folder the way get_prototypes()/get_saved() already scan theirs.
const MAIN_VARIETIES_DIR := "res://Resources/Weapons/MainVarieties/"

# Named prebuilt prototype templates (weapons.md "the archetype clause made content").
const PROTOTYPE_DIR := "res://Resources/Weapons/Prototypes/"

# Saved fitted WeaponInstances — written by the fitting tool, scanned at runtime.
const SAVED_DIR := "res://Resources/Weapons/WeaponVariants/"

static func get_family_bases() -> Dictionary:
	return ResourceCatalog.by_name(MAIN_VARIETIES_DIR, WeaponData)

static func get_prototypes() -> Dictionary:
	return ResourceCatalog.by_name(PROTOTYPE_DIR, WeaponData)

static func get_saved() -> Dictionary:
	return ResourceCatalog.by_name(SAVED_DIR, WeaponInstance)

# The widest frame any template authors, floored at the standard three. Since #486 made mod
# spaces authored, this is the top of the proficiency range — the number that used to be the
# const 3. SCANNED rather than stored: a prototype saved with five spaces has to widen the range
# the moment it lands, and nothing would refresh a cached copy.
static func max_mod_spaces() -> int:
	var widest := WeaponData.SPACE_CAPACITIES.size()
	for template: WeaponData in get_templates().values():
		widest = maxi(widest, template.mod_spaces.size())
	return widest

# A family's own main attack — the BASE's, never a prototype's, since a prototype is a variant of
# its family rather than the other way round. Null when nothing on disk claims that family.
#
# It lives here rather than in whichever panel asked first because two now do (#74): the Item
# Editor's Prototype mode fills a new prototype's main from it, and its mod mode measures a scaling
# change against it. Two copies of this walk would be two answers to "what does this family swing"
# and would drift the moment one gained a rule about prototypes (Law #4).
static func family_main(weapon_type: WeaponData.WeaponType) -> WeaponAttackData:
	if weapon_type == WeaponData.WeaponType.NONE:
		return null
	for base: WeaponData in get_family_bases().values():
		if base.weapon_type == weapon_type:
			return base.main_attack
	return null

# All templates a new weapon can start from — for the fitting tool.
static func get_templates() -> Dictionary:
	var templates := get_family_bases()
	var prototypes := get_prototypes()
	for p in prototypes:
		templates[p] = prototypes[p]
	return templates

# Everything grantable to a unit — only authored, saved instances (mirrors RuneCatalog.
# get_editable): a bare family template is shared identity, not a real carryable weapon.
# Craft an instance from a template via the Item Editor first, then it shows up here.
static func get_editable() -> Dictionary:
	return get_saved()

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
