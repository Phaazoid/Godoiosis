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

# A plain, unfitted instance of EVERY template -- families and prototypes alike -- derived rather
# than authored (#835). The dev wants one of each weapon always pickable; the old bridge was a
# hand-saved mod-less variant per template, which is content carrying no authored decision. It
# drifted (the file froze a copy of the template's display_name, so a family rename stopped
# reaching its own generic) and it collided (a generic is named after its family, which is the
# most collidable name there is -- see #833).
#
# Keyed by FILE, and built off by_file, because a generic's identity IS its template file (#812's
# rule): by_name would silently drop one the day two templates shared a display name.
#
# UNCONDITIONAL -- never "unless a plain variant already exists". That condition would stop
# deriving the moment such a variant was authored, which is a rule that changes its mind about
# content. Which of the two a NAMED list shows is get_editable's business, one door down.
#
# A null is dropped rather than carried: make() answers an unmapped weapon_type with null, and
# this list does not get to lean on WeaponTemplateLint blocking that at the save door.
static func generics() -> Dictionary:
	var found := {}
	for dir: String in [MAIN_VARIETIES_DIR, PROTOTYPE_DIR]:
		var templates := ResourceCatalog.by_file(dir, WeaponData)
		for file: String in templates:
			var template: WeaponData = templates[file]
			var made := WeaponInstance.make(template)
			if made != null:
				found[file] = made
	return found

# Everything grantable to a unit, by display name. Since #835 that is the authored instances PLUS
# a derived generic for every template, which is #80's rule kept rather than repealed: what a
# picker offers is a real WeaponInstance, never the shared template. Only who CREATES the instance
# changed -- the catalog derives it instead of the dev saving a file (dev, 2026-09-08).
#
# AUTHORED WINS a name clash. A saved variant is the specific thing and a generic is the fallback,
# so an authored "Carbine" keeps the row and its derived twin simply does not list. That is what
# lets the hand-made generics be deleted as a separate step without the list changing under him.
static func get_editable() -> Dictionary:
	var all := get_saved()
	var derived := generics()
	for file: String in derived:
		var generic: WeaponInstance = derived[file]
		# ResourceCatalog._key_for's own fallback, said again here because a DERIVED entry has no
		# display_name of its own: the template's name where it authored one, the file where not.
		var key: String = generic.shown_name()
		if key == "":
			key = file
		if not all.has(key):
			all[key] = generic
	return all

static func get_spawnable() -> Dictionary:
	var all := get_editable()
	all["None"] = null
	return all

# The one grant path: turn any catalog entry into something a unit can own.
static func instantiate_entry(entry) -> EquippableData:
	if entry is WeaponData:
		return WeaponInstance.make(entry)
	if entry is EquippableData:
		# Cast: the copy door is typed Item since #697; this path only ever reaches equippables.
		return entry.copy_for_grant() as EquippableData
	return null
