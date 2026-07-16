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

# Crisis stance per archetype (will-and-death.md "AI Crisis policy", grilled 2026-07-04):
# declared at authoring time, deterministic — the resolver predicts enemy Crisis EXACTLY
# (R9: never a BREAK). true = always accept when eligible; false = never take the gambit.
# The balance lever is authored enemy WIL, not code.
const CRISIS_STANCES := {
	Type.RUSHDOWN: true,
	Type.HOLD: false,
	Type.SENTRY: false,
}

static func accepts_crisis(t: Type) -> bool:
	var key: Type = t if t != Type.FACTION_DEFAULT else DEFAULT
	return CRISIS_STANCES[key]

# FACTION_DEFAULT resolves to DEFAULT -- it's a sentinel, not an implementation of its own.
static func resolve(t: Type) -> Callable:
	var key: Type = t if t != Type.FACTION_DEFAULT else DEFAULT
	return _implementations[key]
