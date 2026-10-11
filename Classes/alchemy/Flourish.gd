extends Object
class_name Flourish

# The verbs a carving is written in (docs/design/deep-alchemy.md -> What is built, Phase 2): codev's
# action runes, each taking substances as its arguments. A carving's recipe names them in order,
# `Break(F, A) + Push(F2)`, and CarvingRecipe parses that line into these.
#
# Five apart/together pairs (solve et coagula). Opposites COMBINE rather than cancel: Push + Pull is a
# Twister, Spread + Focus a ring. Not serialized -- recipes are text -- so the order is free.

enum Type {
	BREAK,     # a bond: split it
	BIND,      # a bond: join it
	EXTRACT,   # a body (a unit or a materia): draw out
	INFUSE,    # a body: put in
	PUSH,      # along the line of the cast: away from the caster
	PULL,      # along the line of the cast: toward the caster
	SPREAD,    # around the target: outward
	FOCUS,     # around the target: inward
	QUICKEN,   # time: sooner
	STILL,     # time: held
}

# The word a recipe spells each verb with.
const NAMES: Dictionary[Type, String] = {
	Type.BREAK: "Break",
	Type.BIND: "Bind",
	Type.EXTRACT: "Extract",
	Type.INFUSE: "Infuse",
	Type.PUSH: "Push",
	Type.PULL: "Pull",
	Type.SPREAD: "Spread",
	Type.FOCUS: "Focus",
	Type.QUICKEN: "Quicken",
	Type.STILL: "Still",
}

# Break and Bind name a bond, so both halves; every other verb acts on one substance. No defaults
# (c3potheds + Phaazoid, 2026-10-11): a missing argument is an illegal recipe, never a guess.
static func arity(verb: Type) -> int:
	return 2 if verb == Type.BREAK or verb == Type.BIND else 1


static func from_name(word: String) -> int:
	for verb: Type in NAMES:
		if NAMES[verb] == word:
			return verb
	return -1
