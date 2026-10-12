class_name ConduitData
extends Item

# A CONDUIT (#1312): carried materia that is never used up. Canon: docs/design/alchemy-kit.md ->
# Materia -> Conduits.
#
# The materia law's amendment (Phaazoid, 2026-10-11): a strong or rare carving MAY be gated by
# materia, as long as that materia is not consumed -- a store the carving draws from, like the yellow
# diamond holding the lightning Zap pushes. It supplies an ARGUMENT, never a verb, and only to the
# unit carrying it: CellSubstances counts its substance as present for that unit's casts, so a carving
# needing it fizzles without it and holds with it.
#
# Its own kind rather than a VialData flag, because a vial is consumed: using one attunes its holder,
# an empowered cast burns that, and the Chemical Spitter injects vials as fuel. Every one of those
# doors casts `as VialData`, so a conduit cannot be used, burned or injected by construction.

# What the conduit holds. Its id is what CellSubstances counts as present.
@export var substance: Substance


static func property_tips() -> Dictionary:
	var tips := Item.property_tips()
	tips["substance"] = "What this conduit holds. Its carrier's carvings count it as present, so one that needs it no longer fizzles. Never used up."
	return tips


# What this conduit DOES, in one line -- VialData.mechanical_text's role for a carried thing (#137).
func mechanical_text() -> String:
	if substance == null:
		return ""
	return "Holds: %s" % substance.display_name
