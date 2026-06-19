extends RefCounted
class_name ResolvedOutcome

# One action's resolved consequences — the single source of truth for its damage (R8).
# Every stage annotates this same object: base damage -> elemental (-> Will, Phase 3).

var base_damage: int = 0
var damage: int = 0                              # final, post-elemental
var states_added: Array[Elemental.State] = []
var states_removed: Array[Elemental.State] = []
var popups: Array[String] = []
var target_hp_after: int = 0                     # threaded hypothetical HP after this hit (R4)
# Phase 3 (Will) reads damage + target_hp_after to set a lifecycle result here.
