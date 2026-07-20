extends Resource
class_name AbilityData

# A single ability's identity + taxonomy. Effects are dispatched elsewhere (docs/design/jobs.md
# "The ability chassis") via hardcoded per-id checks against UnitInstance.has_live_ability() —
# this resource carries no effect payload, just enough to classify and label.

# Fixed taxonomy, append-only (jobs.md "four-slot taxonomy"): every ability from every
# source (job/gear/story) classifies as one of these, regardless of what it does.
enum AbilityKind { ACTION, REACTION, PASSIVE, MOVEMENT }

@export var id: Abilities.Id = Abilities.Id.NONE
@export var display_name: String = ""
@export var kind: AbilityKind = AbilityKind.ACTION
@export var description: String = ""
