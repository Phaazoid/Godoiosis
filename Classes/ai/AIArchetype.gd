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

# (The per-archetype Crisis stance table lived here until #158: with Crisis an equipped ability
# that always fires past the will gate, there is no accept/decline left to answer. An enemy gets
# Crisis by carrying the ability — author it onto the units that should have it; the balance lever
# is still authored WIL.)

# FACTION_DEFAULT resolves to DEFAULT -- it's a sentinel, not an implementation of its own.
static func resolve(t: Type) -> Callable:
	var key: Type = t if t != Type.FACTION_DEFAULT else DEFAULT
	return _implementations[key]
	
# Main-action policy (#78): per archetype, an ordered try-list the shared chooser walks --
# first type that yields a buildable candidate wins -- plus an explicit NEVER set. Every
# MAIN_ACTION_TYPES member must land in exactly one, pinned by tests/law/
# test_ai_action_coverage.gd: a new verb can't silently skip the AI -- declare a stance
# (even NEVER) or the suite goes red.
#
# WHAT an archetype will ever do lives here; WHEN a weapon verb is worth doing is the family's own
# call (AIWeaponRoutine, #726), asked by the chooser before the builder runs. REV and BURROW joined
# Hold/Sentry 2026-09-03 (dev: a defender at its post revs, digs in, tops off) ahead of INTIMIDATE,
# which stays last per the ratified sentence "menace only when nothing better exists". Rushdown
# keeps BURROW NEVER: a rusher does not entrench.
const MAIN_ACTION_PRIORITY := {
	Type.RUSHDOWN: [BaseAction.ActionType.ATTACK, BaseAction.ActionType.RELOAD, BaseAction.ActionType.REV],
	Type.HOLD: [BaseAction.ActionType.ATTACK, BaseAction.ActionType.RESCUE,
			BaseAction.ActionType.OVERWATCH, BaseAction.ActionType.RELOAD, BaseAction.ActionType.REV,
			BaseAction.ActionType.BURROW, BaseAction.ActionType.GUARD,
			BaseAction.ActionType.INTIMIDATE],
	Type.SENTRY: [BaseAction.ActionType.ATTACK, BaseAction.ActionType.RESCUE,
			BaseAction.ActionType.OVERWATCH, BaseAction.ActionType.RELOAD, BaseAction.ActionType.REV,
			BaseAction.ActionType.BURROW, BaseAction.ActionType.GUARD,
			BaseAction.ActionType.INTIMIDATE],
}

# CAPTURE everywhere (#96 slice 3): not deferred like the others — there is nothing for an AI
# faction to WIN by capturing, because enemy objectives are out of #96's scope. The point is the
# player's. The AI contests it positionally, which it already does: Rushdown walks into the
# approach, and a Sentry squad zoned over the point defends it with no AI code at all. Revisit
# only when non-player factions get objectives of their own.
# GUARD and OVERWATCH were NEVER everywhere until #751 (2026-09-04): Hold and Sentry take both now
# (dev), Rushdown keeps NEVER for both -- a rusher that stops to shield somebody is not a rusher,
# the same reason it refuses rescue, intimidate and burrow. Both sit BELOW attack, because both are
# PREPARATIONS whose payoff lands on somebody else's turn and #726's ruling covers that case: a
# preparation is a rule, never a score term.
#
# Two of the five items #117 filed came off that list without code: defended-target deprioritization
# turned out to be REPRICING the resolver already does (an armed ward retargets the hit, so the AI
# cannot kill through an intact shield and already sees that), and the Sentry watch stance falls out
# of the fallback walk #726 gave a sentry at its post. Watch-aware pathing and crossing-order smarts
# are still open -- the first is the same `_approach_beats` danger term the fire/cover work wants.
const MAIN_ACTION_NEVER := {
	Type.RUSHDOWN: [BaseAction.ActionType.RESCUE, BaseAction.ActionType.RALLY,
			BaseAction.ActionType.INTIMIDATE, BaseAction.ActionType.BURROW,
			BaseAction.ActionType.CAPTURE, BaseAction.ActionType.GUARD,
			BaseAction.ActionType.OVERWATCH],
	Type.HOLD: [BaseAction.ActionType.RALLY, BaseAction.ActionType.CAPTURE],
	Type.SENTRY: [BaseAction.ActionType.RALLY, BaseAction.ActionType.CAPTURE],
}

static func main_action_priority(t: Type) -> Array:
	var key: Type = t if t != Type.FACTION_DEFAULT else DEFAULT
	return MAIN_ACTION_PRIORITY[key]
