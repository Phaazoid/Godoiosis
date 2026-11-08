extends Object
class_name Vein

# A materia vein's vocabulary (#696): which kinds exist and which elements each empowers. The store is
# VeinField; Materia.sources_at reads `empowers`, and what a vein is MADE of is SubstanceMap's authored
# `veins` row, read by CellSubstances.
#
# A kind's int is what a save holds, so Kind is APPEND-ONLY: rename a member freely, never reorder or
# delete one. NONE is no vein, which is why the store holds no untagged vein to lint.
#
# A tagged vein empowers its own element; ALKAHEST empowers every sigil element, the alkahest vial's
# answer (Materia.alkahest). LIGHTNING empowers nothing: it makes lightning PRESENT and is never used up,
# a conduit's job in the ground (#1312's ruling).

enum Kind { NONE, FIRE, WATER, EARTH, AIR, AETHER, ALKAHEST, LIGHTNING }

const _ELEMENT_OF: Dictionary[Kind, Elemental.Element] = {
	Kind.FIRE: Elemental.Element.FIRE,
	Kind.WATER: Elemental.Element.WATER,
	Kind.EARTH: Elemental.Element.EARTH,
	Kind.AIR: Elemental.Element.AIR,
	Kind.AETHER: Elemental.Element.AETHER,
}


# The elements a caster beside a vein of this kind may draw on.
static func empowers(kind: Kind) -> Array[Elemental.Element]:
	if kind == Kind.ALKAHEST:
		return Materia.alkahest()
	var out: Array[Elemental.Element] = []
	if _ELEMENT_OF.has(kind):
		out.append(_ELEMENT_OF[kind])
	return out


static func display_name(kind: Kind) -> String:
	return Kind.keys()[kind].capitalize()
