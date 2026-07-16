extends Resource
class_name AbilityData

# A single ability's identity — what it IS, not what it does yet. Effects/runtime land in
# prompt 12; for now this only classifies (jobs.md), so job pools and the dev editor have
# something concrete to point at.

# Fixed taxonomy, append-only (jobs.md "four-slot taxonomy"): every ability from every
# source (job/gear/story) classifies as one of these, regardless of what it does.
enum AbilityKind { ACTION, REACTION, PASSIVE, MOVEMENT }
enum Tier { MAIN, SUB }   # live only from the main slot vs live from any sub slot

@export var id: String = ""
@export var display_name: String = ""
@export var kind: AbilityKind = AbilityKind.ACTION
@export var tier: Tier = Tier.MAIN
@export var description: String = ""
