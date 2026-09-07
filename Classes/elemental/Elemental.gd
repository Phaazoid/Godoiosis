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
	# Not a sigil and not aura-bearing -- an exotic result tag like ICE and SHOCK, and inert for
	# now: no reaction, no paired State, no terrain source (#97). It exists because the Chemical
	# Spitter's identity is corrosion and its Spray had nothing to be tagged with.
	# NOT the same thing as AttackData.Kind.CORROSION, which is the DELIVERY axis (#424) -- the two
	# vocabularies already share FIRE and SHOCK for the same reason, so a grep hits both.
	CORROSION,
}

enum State {
	NONE,
	WET,
	CHILLED,  # cold-slowed: carries a paired StatEffect (see the pairing block below)
}

# The five base elements: the only Sigils, the only aura carriers. Exotics (ICE, SHOCK,
# ...) are DERIVED result tags — docs/design/transmutation-model-proposal.md.
const SIGIL_ELEMENTS: Array[Element] = [
	Element.FIRE, Element.WATER, Element.EARTH, Element.AIR, Element.AETHER,
]

static func is_sigil_element(e: Element) -> bool:
	return SIGIL_ELEMENTS.has(e)

# What the PLAYER calls this element ("Fire"). Three UI sites hand-rolled the same
# keys()[e].capitalize() before this existed. Dev readouts that deliberately show the raw
# enum key keep doing so — this is the player-facing spelling, not a general stringifier.
static func display_name(e: Element) -> String:
	return Element.keys()[e].capitalize()

# The State twin ("Wet") — same rule, same reason (StateIcons' fallback label and the Glossary's
# composed reaction lines both need it).
static func state_display_name(s: State) -> String:
	return State.keys()[s].capitalize()

# --- Paired stat debuffs ------------------------------------------------------------------------
# A paired state carries a temporary stat change while held. The marker on Unit.element_states is
# the authority for "does the unit hold it"; a paired StatEffect carries the stat change AND is
# the state's clock. Unit's element-state doors own the pairing — nothing else creates or retires
# these effects, and the effect's countdown expiring ends the state itself.
#
# Turn math: StatEffect ticks at the OWNER's turn start (game._run_turn_start_ticks), before the
# unit acts — so 2 turns = debuffed for exactly its next activation, 3 covers two.

const CHILL_STAT_MODS: Dictionary[Stats.Stat, int] = { Stats.Stat.DEX: -1 }

# Default clock per paired state; a reaction may author a longer one (ElementalReaction.add_state_turns).
const STATE_DEFAULT_TURNS: Dictionary[State, int] = { State.CHILLED: 2 }

# The pairing registry: one match arm per paired state (a nested typed const dictionary isn't
# expressible in GDScript). Empty result = not a paired state.
static func paired_stat_mods(s: State) -> Dictionary[Stats.Stat, int]:
	match s:
		State.CHILLED:
			return CHILL_STAT_MODS
	var none: Dictionary[Stats.Stat, int] = {}
	return none

# Provenance tag for the paired StatEffect ("Chilled") — what Unit.remove_stat_effects_from keys on.
static func state_effect_source(s: State) -> String:
	return state_display_name(s)
