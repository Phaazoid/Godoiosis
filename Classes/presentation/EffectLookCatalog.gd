extends Object
class_name EffectLookCatalog

# Registry for authored EffectLook content (#900) -- the named looks an attack picks from, shared
# BY REFERENCE, so this folder is a census: every look in use is in it, and editing one reaches
# every attack that names it.
#
# One tier, AttackShapeCatalog's shape and for its reason: nothing OWNS a look the way a family
# owns its main attack, so there is no main/pool split to make.
#
# THE FOLDER MAY NOT EXIST, and that is not an error state -- `(none)` is the default for every
# attack, so a project that has never saved a look has nothing to scan. ResourceDir answers an
# absent directory with an empty list and DevWidgets.save_over makes the directory on the first
# save, so neither end needs a check of its own.
const LIBRARY_DIR := "res://Resources/EffectLooks/"

static func get_library() -> Dictionary:
	return ResourceCatalog.by_name(LIBRARY_DIR, EffectLook)


# Only the looks that describe THIS element. What makes a picker honest: a shock slot offered a
# look authored for another element would produce exactly the mismatch AttackLint's second finding
# exists to report, so the control refuses to create it in the first place.
static func for_element(element: Elemental.Element) -> Dictionary:
	return matching(get_library(), element)


# The filter itself, over a library HANDED IN. Split from the scan so the rule can be exercised
# without authoring a file into Resources/ -- a test that has to write shipped content to check a
# filter is testing the scan, which is ResourceCatalog's own answer and already pinned there.
static func matching(library: Dictionary, element: Elemental.Element) -> Dictionary:
	var found := {}
	for key in library:
		var look: EffectLook = library[key]
		if look != null and look.element == element:
			found[key] = look
	return found
