extends Resource
class_name Substance

# One substance of Deep Alchemy (docs/design/deep-alchemy.md): what a thing is MADE of, as a formula
# over the five elements. One .tres per substance in Resources/Substances/, and its id is the FILE
# NAME, which is how an equation names a compound (SubstanceCatalog).
#
# The atoms are Elemental.SIGIL_ELEMENTS -- Q aether, F fire, A air, W water, E earth -- not a second
# vocabulary. AlchemyFormula owns the notation.
#
# `formula` is EITHER a molecule, in alchemical order (`FW`) or as a `*` composition (`QE*FE*WE`),
# OR a compound: other substances joined by `+`, with optional counts (`AE + A2`). A compound is
# something dissolved in something else; a molecule is one thing.

# UNBOUND is not an ordinary phase: the free elements, and the energetic substances (flame,
# lightning, essence) that the doc never gives a solid, liquid or gas form.
enum Phase { UNBOUND, SOLID, LIQUID, GAS }

@export var display_name: String = ""
@export_placeholder("FW, QE*FE*WE or AE + A2") var formula: String = ""
@export var phase: Phase = Phase.UNBOUND

# Does a cast beside this compound find its PARTS as well as it (CellSubstances)? Plant matter does
# not (c3potheds@): organic matter is too complex to Break or Bind, so a grass field holds no water.
# A molecule has no parts, so the tick says nothing there.
@export var lends_its_parts := true


# The file name: what an equation writes to name this substance outright.
func id() -> String:
	return resource_path.get_file().get_basename()


func is_compound() -> bool:
	return formula.contains("+")


# Per-field text for the dev tools' reflective editor (#473), on Project > Alchemy > Substances.
static func property_tips() -> Dictionary:
	return {
		"display_name": "What a player reads, e.g. Vital air. Equations, recipes and Sources rows name the FILE (its id), never this.",
		"formula": "What it is made of. A molecule in Q F A W E order (FW), or a * composition (QE*FE*WE); or a compound, other substance ids joined by + with optional counts (dirt + W2).",
		"phase": "Solid, liquid or gas; Unbound for the free elements and the energetic substances (flame, lightning, essence).",
		"lends_its_parts": "On: a cast beside this compound finds its parts as well as it (mud lends dirt and water). Off: it is present as itself alone, as plant matter is. A molecule has no parts either way.",
	}
