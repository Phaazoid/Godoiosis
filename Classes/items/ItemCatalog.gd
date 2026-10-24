extends Object
class_name ItemCatalog

# "What items exist at all?" -- the union of the folders a carryable thing is authored in (#812).
# There is no other answer to this in the codebase: WeaponCatalog, ArmorCatalog, RuneCatalog,
# VialCatalog and ConduitCatalog each own one kind, and nothing had ever needed the whole set until
# a second caller appeared.
#
# It was UnitEditorTool._item_catalog(), private to the tool that asked first, and the promotion is
# Law #4 rather than tidiness -- the roster editor asks the same question. The editors kept their
# own walk until #1414, and it had already drifted: it refused an illegal rune and this did not.
# Both editors now read by_name().
#
# NOT equippables only, and that is #697's ruling carried forward: a vial is CARRIED and never
# slotted, and leaving the kind out made the authored ones unreachable from any editor.
#
# WEAPON TEMPLATES ARE IN, since #835, and that is the ONE thing to understand before adding a
# source here. This answers what a mission may OFFER, which is a question about FILES: a roster
# stores its picks as ext_resource paths, and the plain form of a weapon has no file of its own --
# its template's IS its identity. What the phase HOLDS is a different question one door along, and
# `Roster.offered_stash` answers it, because a template becomes a real WeaponInstance the moment it
# is granted (WeaponData.copy_for_grant).
#
# So #80's rule is intact rather than bent: a bare template still reaches no unit and no stash. It
# is nameable here and instantiated on the way out, which is what lets the seven prototypes and the
# Prosthetic base be put in a mission's gear at all.


# The folders, declared once. A new carryable kind is one line here and reaches all three
# projections and every caller -- which is the whole reason this is a class rather than a helper
# copied into whoever needs it next.
#
# Each projection takes `sources` for a case that stands up its own folder under user:// rather
# than writing a test file into Resources/ (ResourceCatalog.users_of's rule, #1366). Every
# production caller takes the default.
const SOURCES: Array[String] = [
	WeaponCatalog.MAIN_VARIETIES_DIR,
	WeaponCatalog.PROTOTYPE_DIR,
	WeaponCatalog.SAVED_DIR,
	ArmorCatalog.VARIANT_DIR,
	RuneCatalog.VARIANT_DIR,
	VialCatalog.VARIANT_DIR,
	ConduitCatalog.VARIANT_DIR,
]

# Every authored item, in no particular order. The unkeyed form, because the two callers key it
# DIFFERENTLY and neither key is the catalog's business (ResourceCatalog's own by_name/by_file
# split, one layer up): the Unit Editor's dropdown reads display names, while a roster stores files.
static func everything(sources: Array[String] = SOURCES) -> Array[Item]:
	var found: Array[Item] = []
	for dir: String in sources:
		for item: Item in _admitted(ResourceCatalog.by_file(dir, Item)).values():
			found.append(item)
	return found


# display_name -> Item, the editors' shape: what a picker hands a unit. Two items sharing a display
# name COLLAPSE here, the later kind winning, which is why the roster tool uses by_file instead.
#
# The weapon kinds answer through WeaponCatalog.get_editable, whose folders are its own: a hand holds
# an INSTANCE, so a template lists as the generic derived from it (#835), and an authored variant
# wins a name clash with one. That is the rule the editors already listed by, and its order with it
# (variants, then generics, then every other kind).
static func by_name(sources: Array[String] = SOURCES) -> Dictionary:
	var found := WeaponCatalog.get_editable()
	for dir: String in sources:
		var kind := _admitted(ResourceCatalog.by_name(dir, Item))
		for key in kind:
			if not (kind[key] is WeaponData or kind[key] is WeaponInstance):
				found[key] = kind[key]
	return found


# filename -> Item, the roster's shape: the file is what an ext_resource line names, so it is the
# identity a stored pick has to survive a display-name edit on.
static func by_file(sources: Array[String] = SOURCES) -> Dictionary:
	var found := {}
	for dir: String in sources:
		var kind := _admitted(ResourceCatalog.by_file(dir, Item))
		for key in kind:
			found[key] = kind[key]
	return found


# One folder's items minus what its own kind's catalog refuses. ONE filter under all three
# projections, so a refusal reaches every caller at once: an illegal rune is RuneCatalog's to refuse.
static func _admitted(kind: Dictionary) -> Dictionary:
	var found := {}
	for key in kind:
		var item: Item = kind[key]
		if item is RuneData and RuneCatalog.refuses(item, key):
			continue
		found[key] = item
	return found
