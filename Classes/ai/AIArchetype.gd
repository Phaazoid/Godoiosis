extends Object
class_name AIArchetype

# The fixed vocabulary of squad AI patterns (append-only -- Squad.archetype and
# ScenarioUnitEntry.squad_archetype persist this as a plain int).
enum Type {
	FACTION_DEFAULT,   # sentinel: squad has no override, use the faction's default archetype
	RUSHDOWN,
	HOLD,
	SENTRY,
}

const DEFAULT := Type.RUSHDOWN

static var _implementations := {
	Type.RUSHDOWN: Callable(RushdownArchetype, "take_squad_turn"),
	Type.HOLD: Callable(HoldArchetype, "take_squad_turn"),
	Type.SENTRY: Callable(SentryArchetype, "take_squad_turn"),
}

# FACTION_DEFAULT resolves to DEFAULT -- it's a sentinel, not an implementation of its own.
static func resolve(t: Type) -> Callable:
	var key: Type = t if t != Type.FACTION_DEFAULT else DEFAULT
	return _implementations[key]
