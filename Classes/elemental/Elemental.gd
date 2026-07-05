extends Object
class_name Elemental

# Elemental vocabulary for the Combinatrix — docs/design/elemental-system.md.
# Two separate vocabularies (kept apart so the data stays clean):
#   Element = a tag on an OUTGOING hit (what an attack IS).  Lives on the weapon/attack.
#   State   = a condition HELD by a target.                  Lives on the transient Unit.
#
# APPEND-ONLY. These serialize as ints in saved .tres; reordering or deleting a value
# silently corrupts existing resources (enum note in elemental-system.md). Always add
# new values at the END. NONE = 0 is the unset default, so an omitted/default .tres
# field loads cleanly as "no element / no state".

enum Element {
	NONE,
	FIRE,
	WATER,
	SHOCK,
	ICE,
	EARTH,
	AIR,
	AETHER,
}

enum State {
	NONE,
	WET,
}

# The five base elements: the only Sigils, the only aura carriers. Exotics (ICE, SHOCK,
# ...) are DERIVED result tags — docs/design/transmutation-model-proposal.md.
const SIGIL_ELEMENTS: Array[Element] = [
	Element.FIRE, Element.WATER, Element.EARTH, Element.AIR, Element.AETHER,
]

static func is_sigil_element(e: Element) -> bool:
	return SIGIL_ELEMENTS.has(e)
