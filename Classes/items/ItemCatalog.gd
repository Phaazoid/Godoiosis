extends Object
class_name ItemCatalog

# "What items exist at all?" -- the union of the four folders a carryable thing is authored in
# (#812). There is no other answer to this in the codebase: WeaponCatalog, ArmorCatalog,
# RuneCatalog and VialCatalog each own one kind, and nothing had ever needed the whole set until a
# second caller appeared.
#
# It was UnitEditorTool._item_catalog(), private to the tool that asked first, and the promotion is
# Law #4 rather than tidiness -- the roster editor asks the same question, and a second walk over
# the same four catalogs would be the second answer that drifts the day a fifth kind lands.
#
# NOT equippables only, and that is #697's ruling carried forward: a vial is CARRIED and never
# slotted, and leaving the kind out made the authored ones unreachable from any editor.
#
# WEAPONS ARE THE SAVED VARIANTS, never the family templates -- WeaponCatalog.get_editable's own
# rule. A bare family template is shared identity rather than a real carryable weapon, so it belongs
# in no list of things a unit or a stash can hold.


# The four folders, declared once. A fifth carryable kind is one line here and reaches both
# projections and every caller -- which is the whole reason this is a class rather than a helper
# copied into whoever needs it next.
const SOURCES: Array[String] = [
	WeaponCatalog.SAVED_DIR,
	ArmorCatalog.VARIANT_DIR,
	RuneCatalog.VARIANT_DIR,
	VialCatalog.VARIANT_DIR,
]

# Every authored item, in no particular order. The unkeyed form, because the two callers key it
# DIFFERENTLY and neither key is the catalog's business (ResourceCatalog's own by_name/by_file
# split, one layer up): the Unit Editor's dropdown reads display names, while a roster stores files.
static func everything() -> Array[Item]:
	var found: Array[Item] = []
	for dir: String in SOURCES:
		for item: Item in ResourceCatalog.load_all(dir, Item):
			found.append(item)
	return found


# display_name -> Item, the Unit Editor's shape. Two items sharing a display name COLLAPSE here,
# which is by_name's documented behaviour and is why the roster tool uses the pair below instead.
static func by_name() -> Dictionary:
	var found := {}
	for dir: String in SOURCES:
		var kind := ResourceCatalog.by_name(dir, Item)
		for key in kind:
			found[key] = kind[key]
	return found


# filename -> Item, the roster's shape: the file is what an ext_resource line names, so it is the
# identity a stored pick has to survive a display-name edit on.
static func by_file() -> Dictionary:
	var found := {}
	for dir: String in SOURCES:
		var kind := ResourceCatalog.by_file(dir, Item)
		for key in kind:
			found[key] = kind[key]
	return found


# What a list of these should be LABELLED. The display name where one is authored, the filename
# where it is not -- ResourceCatalog._key_for's fallback, said once here so every surface listing
# items agrees about what an unnamed one is called.
static func label_for(item: Item, file: String) -> String:
	if item != null and item.display_name != "":
		return item.display_name
	return file
