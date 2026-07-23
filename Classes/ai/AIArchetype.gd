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
	
# Main-action policy (#78): per archetype, an ordered try-list the shared chooser walks --
# first type that yields a buildable candidate wins -- plus an explicit NEVER set. Every
# MAIN_ACTION_TYPES member must land in exactly one, pinned by tests/law/
# test_ai_action_coverage.gd: a new verb can't silently skip the AI -- declare a stance
# (even NEVER) or the suite goes red.
const MAIN_ACTION_PRIORITY := {
	Type.RUSHDOWN: [BaseAction.ActionType.ATTACK, BaseAction.ActionType.SPRING_LOAD],
	Type.HOLD: [BaseAction.ActionType.ATTACK, BaseAction.ActionType.RESCUE,
			BaseAction.ActionType.SPRING_LOAD, BaseAction.ActionType.INTIMIDATE],
	Type.SENTRY: [BaseAction.ActionType.ATTACK, BaseAction.ActionType.RESCUE,
			BaseAction.ActionType.SPRING_LOAD, BaseAction.ActionType.INTIMIDATE],
}

# RALLY everywhere (dev call 2026-07-22): early rallies burn the strong falloff steps while
# idling -- revisit with real Will-awareness. RESCUE/INTIMIDATE on Rushdown: pure aggression.
const MAIN_ACTION_NEVER := {
	Type.RUSHDOWN: [BaseAction.ActionType.RESCUE, BaseAction.ActionType.RALLY,
			BaseAction.ActionType.INTIMIDATE],
	Type.HOLD: [BaseAction.ActionType.RALLY],
	Type.SENTRY: [BaseAction.ActionType.RALLY],
}

static func main_action_priority(t: Type) -> Array:
	var key: Type = t if t != Type.FACTION_DEFAULT else DEFAULT
	return MAIN_ACTION_PRIORITY[key]
