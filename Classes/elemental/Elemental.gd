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
	ICE
}

enum State {
	NONE,
	WET,
}
