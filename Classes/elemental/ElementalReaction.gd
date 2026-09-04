extends Resource
class_name ElementalReaction

# A data rule: when an attack carrying `incoming_element` hits a target holding
# `required_state`, the reaction fires — changing damage and/or adding/removing
# states. docs/design/elemental-system.md ("Reactions as data").
#
# Resolution collects EVERY matching reaction and composes them per E8:
#   final = round(base * Π(damage_mult) + Σ(damage_bonus))   (state-deltas union)
#
# v1 = a single (element × state) trigger per reaction. The doc's "collection of
# triggers" (multiple routes to one reaction) is a later generalization — for now,
# author one reaction per route. Stacking ACROSS reactions (E8) works regardless.
#
# `required_state = NONE` means "no pre-existing state needed" — the reaction fires
# on the element alone. That's the SETUP half of a combo (e.g. WATER -> WET).

@export var incoming_element: Elemental.Element = Elemental.Element.NONE
@export var required_state: Elemental.State = Elemental.State.NONE

# Deterministic damage change (Law #1 — no chance).
@export var damage_mult: float = 1.0
@export var damage_bonus: int = 0

# State changes applied when the reaction fires.
@export var add_states: Array[Elemental.State] = []
@export var remove_states: Array[Elemental.State] = []   # omit to NOT consume the state

# Optional duration override for `add_states` entries that expire (paired states — see
# Elemental.STATE_DEFAULT_TURNS). Absent/0 = the state's default. When several fired reactions
# add the same state, the LONGEST authored duration wins — max is commutative, so E8's
# order-independence holds.
@export var add_state_turns: Dictionary[Elemental.State, int] = {}

# Feedback hooks, surfaced in preview + playback.
@export var popup: String = ""        # e.g. "Electrocuted!"
@export var vfx_tag: String = ""
@export var icon: Texture2D           # queue/board symbol shown when this reaction FIRES (e.g. the spark)


# A COMBO needs a state already on the target; a NONE-requirement reaction is the SETUP half that
# deposits one (see the header). The queue row asks this to decide whether a fired reaction earns its
# own named line, or is already fully said by the state chip it produced (#685).
func is_combo() -> bool:
	return required_state != Elemental.State.NONE

# The BADGE word, for a surface with no room for the dramatic one. A DECLARED second representation
# (Law #4): `popup` is what a reaction SHOUTS -- the glossary's composed interaction line and the bug
# report read it -- and this is what fits a ~40px chip in the action queue's row, measured. Blank
# means the popup already fits, so a reaction needs this only when its word is long.
@export var short_name: String = ""

func badge_name() -> String:
	return short_name if short_name != "" else popup
