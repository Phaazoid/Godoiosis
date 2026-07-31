extends Resource
class_name StatEffect

# One temporary contribution to a unit's effective stats: the Crisis surge today, tonics and
# transmutation buffs next (#112). Replaces UnitInstance.stat_modifiers, a stateful add/subtract
# bag whose only writer was a hand-balanced +5/-5 pair — the leak shape. An effect is RETIRED,
# never subtracted, so forgetting to remove one leaves an effect rather than a corrupted number.
#
# AUTHORED as a template (a tonic points at one); a unit carries a COPY, because turns_remaining is
# per-application state. Two units drinking the same tonic must not share a countdown.
#
# Lives on Unit, never UnitInstance: every temporary effect is battle-scoped. Sources that are
# DERIVED from state that already exists — worn armour, and terrain if it ever moves an input stat
# — are deliberately NOT stored as effects; see Unit.get_effective_stat.

const PERMANENT := -1

@export var source_name: String = ""                       # provenance: "+3 CON — Steady Tonic"
@export var modifiers: Dictionary[Stats.Stat, int] = {}
@export var duration: int = PERMANENT                      # in the owner's turns; PERMANENT = until retired

# Live countdown, seeded on apply. @export so a mid-battle save can restore it mid-count (#87).
@export var turns_remaining: int = PERMANENT

static func make(source: String, mods: Dictionary[Stats.Stat, int], turns: int = PERMANENT) -> StatEffect:
	var effect := StatEffect.new()
	effect.source_name = source
	effect.modifiers = mods
	effect.duration = turns
	return effect

# A fresh application. Unit.apply_stat_effect calls this, so callers may freely hand it an
# authored template without forking it.
func instantiate() -> StatEffect:
	var live: StatEffect = duplicate(true)
	live.turns_remaining = duration
	return live

func get_modifier(stat: Stats.Stat) -> int:
	return modifiers.get(stat, 0)

# One turn passes. Returns TRUE when this effect is spent and should be retired.
func tick() -> bool:
	if turns_remaining == PERMANENT:
		return false
	turns_remaining -= 1
	return turns_remaining <= 0

func modifier_text() -> String:
	return Stats.modifier_text(modifiers)
