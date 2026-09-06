class_name VialData
extends Item

# CARRIED PURE MATERIA (#697): the portable half of empowerment. Canon:
# docs/design/alchemy-kit.md -> Materia -> Carried pure -- the vial.
#
# THE ONE LAW applies here as it does to the source layer -- materia never gates function, it
# supercharges it. Nothing on this class can refuse a cast. Using a vial ATTUNES its holder in one
# element, and a cast that draws on that attunement burns it; a unit carrying nothing casts exactly
# as it always did.
#
# It is an Item, not an EquippableData, because a vial is CARRIED and never slotted. That is the
# whole reason #697 widened the three authoring doors: the pipeline used to admit only slottable
# things, and Item has always been the class that means "anything a unit can hold".
#
# It grants EXACTLY what a source grants, never more (dev, at the grill). Portability IS the
# premium: the vial buys empowerment where there is no source, and that is enough. "Carried is
# stronger" was considered and rejected -- it breaks the binary empowered read and quietly tells
# the player that the terrain game is the budget option.

# What this vial attunes its user to. NONE is authoring noise -- a vial that grants nothing.
@export var element: Elemental.Element = Elemental.Element.NONE

# Alkahest-pure: matches ANY element, mirroring the vein split. Overrides `element` entirely, so an
# alkahest vial needs no element authored on it.
@export var is_alkahest := false


static func property_tips() -> Dictionary:
	var tips := Item.property_tips()
	tips["element"] = "Which element this vial attunes its user to. Ignored entirely when Alkahest is on."
	tips["is_alkahest"] = "Alkahest-pure: attunes to EVERY element at once. The rare kind -- authored sparingly."
	return tips


# Everything a holder of this vial would be empowered in. The same shape Materia.empowered_at
# answers for terrain, so the resolver can union the two without either side knowing about the
# other -- which is exactly what Materia.gd's header reserved this spot for.
func granted_elements() -> Array[Elemental.Element]:
	if is_alkahest:
		# duplicate(): SIGIL_ELEMENTS is a const Array and therefore READ-ONLY, and that flag
		# travels with assignment -- handing the const out directly would hand out a list the
		# caller cannot union into.
		return Elemental.SIGIL_ELEMENTS.duplicate()
	var only: Array[Elemental.Element] = []
	if element != Elemental.Element.NONE:
		only.append(element)
	return only


# WHY this unit may not use this vial -- "" means they may. can_equip_reason's shape (#744): the
# REASON is the rule and any boolean is derived from it, so the button's label and the refusal can
# never drift apart.
#
# This is NOT a second answer to can_equip_reason -- that one asks "may this be slotted", and a vial
# is never slotted. And it is not a gate on any cast: the only thing it refuses is a burn that would
# buy the holder nothing they do not already have, which is a kindness rather than a rule.
func use_block_reason(user: Unit) -> String:
	if user == null:
		return "There is nobody to use it."
	var held := user.attunement
	if held == null:
		return ""
	if held.is_alkahest:
		# Alkahest already covers every element, so nothing can improve on it -- not even another
		# alkahest vial.
		return "%s is already attuned to %s." % [user.get_unit_name(), held.display_name]
	if not is_alkahest and held.element == element:
		return "%s is already attuned to %s." % [user.get_unit_name(), Elemental.display_name(element)]
	return ""


# What using this REPLACES -- "" when it replaces nothing. Separate from the refusal above because
# an overwrite is allowed and merely worth saying out loud: the panel prints it on the button so the
# trade is visible BEFORE the item is spent, never after.
func use_replaces(user: Unit) -> String:
	if user == null or user.attunement == null:
		return ""
	return user.attunement.display_name
