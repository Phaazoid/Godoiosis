extends Resource
class_name ElementReaction

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

# Feedback hooks, surfaced in preview + playback.
@export var popup: String = ""        # e.g. "Electrocuted!"
@export var vfx_tag: String = ""
