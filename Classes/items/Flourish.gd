extends Object
class_name Flourish

# Shaping marks carved around a transmutation's sigil core — they DIRECT power, never add
# it (docs/design/transmutation-model-proposal.md, provisional pending co-dev).
# Slots come from sigil count (TransmutationData.flourish_slots); flourishes cost no rune
# capacity. APPEND-ONLY (serialized as ints in .tres).

enum Type {
	NONE,
	PUSH,
	SPREAD,
	FOCUS,
	STILLNESS,
	QUICKENING,
}

# Opposing pairs cancel on the same circle (solve et coagula) — authoring rejects the
# second rather than computing a net zero.
const OPPOSITES: Dictionary[Type, Type] = {
	Type.SPREAD: Type.FOCUS,
	Type.FOCUS: Type.SPREAD,
	Type.STILLNESS: Type.QUICKENING,
	Type.QUICKENING: Type.STILLNESS,
}

# (sigil element × flourish) -> derived outgoing tag. The exotic space is a fixed lookup,
# not chemistry (Law #1). Inner dicts are {Type: Elemental.Element}.
const DERIVED: Dictionary[Elemental.Element, Dictionary] = {
	Elemental.Element.WATER: {Type.STILLNESS: Elemental.Element.ICE},
	Elemental.Element.FIRE: {Type.QUICKENING: Elemental.Element.SHOCK},
}

static func derive(sigil: Elemental.Element, flourish: Type) -> Elemental.Element:
	if DERIVED.has(sigil) and DERIVED[sigil].has(flourish):
		return DERIVED[sigil][flourish]
	return Elemental.Element.NONE
