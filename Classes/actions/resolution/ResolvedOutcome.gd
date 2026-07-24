extends RefCounted
class_name ResolvedOutcome

# One action's resolved consequences — the single source of truth for its damage (R8).
# Every stage annotates this same object: base damage -> elemental (-> Will, Phase 3).

var base_damage: int = 0
var damage: int = 0                              # final, post-elemental
var states_added: Array[Elemental.State] = []
var states_removed: Array[Elemental.State] = []
var popups: Array[String] = []
var reaction_icons: Array[Texture2D] = []        # icons of reactions that FIRED this hit — drawn behind the target in the queue
var target_hp_after: int = 0                     # threaded hypothetical HP after this hit (R4)
var knockback_applied: bool = false               # #84: this hit shoved the target (Kinetic Mace Blowback)
var knockback_to: Vector2i = Vector2i.ZERO         # the cell it lands in — previewed and applied verbatim (Law #2)


# Predicted lifecycle result for this hit's TARGET (R8's "lifecycle result"). Mirrors
# Unit.take_damage + _go_downed so the queue previews down/maim/kill (Law #2). MAIMED is a
# DOWN the target can't pay for in Will (will-and-death.md 2026-06-24) — same lifecycle as
# DOWNED, flagged separately so the preview can say so.
enum Lethality { NONE, DOWNED, KILLED, MAIMED, CRISIS }
var lethality: Lethality = Lethality.NONE

var skipped: bool = false                        # counter-er downed/killed earlier in the pass (R7) — no-op: don't play or preview
