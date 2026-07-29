extends Resource
class_name AbilityData

# A single ability's identity + taxonomy. Effects are dispatched elsewhere (docs/design/jobs.md
# "The ability chassis") via hardcoded per-id checks against Unit.has_live_ability() — this
# resource carries no effect payload, just enough to classify and label.
#
# Unit, not UnitInstance, since #90: the kit is innate + jobs + worn gear, and only Unit can see
# the gear half. UnitInstance.get_live_abilities() is the persistent inner layer.

# Fixed taxonomy, append-only (jobs.md "four-slot taxonomy"): every ability from every
# source (job/gear/story) classifies as one of these, regardless of what it does.
enum AbilityKind { ACTION, REACTION, PASSIVE, MOVEMENT }

@export var id: Abilities.Id = Abilities.Id.NONE
@export var display_name: String = ""
@export var kind: AbilityKind = AbilityKind.ACTION
@export var description: String = ""

# THE merge for the whole chassis: append `pool` to `live`, first id wins, nulls and NONE never
# go live. Jobs come through here (UnitInstance), gear joins through the same door (Unit) — one
# implementation, so a second source can never dedup differently. Lives here rather than on
# Abilities: AbilityData already depends on Abilities, and the return edge would be a cycle.
static func add_live(live: Array[AbilityData], pool: Array[AbilityData]) -> void:
	for ability in pool:
		if ability == null or ability.id == Abilities.Id.NONE:
			continue
		var held := false
		for existing in live:
			if existing.id == ability.id:
				held = true
				break
		if not held:
			live.append(ability)
