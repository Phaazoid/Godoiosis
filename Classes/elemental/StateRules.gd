extends Resource
class_name StateRules

# What a PAIRED unit state does while held (#1534): its stat change and its default clock, one file per
# paired state under Resources/StateRules/ named for the state. Which states pair is code
# (Elemental.paired_stat_mods' match arms); how much and how long is this file, tuned on the dev tools'
# Air & gas page or in the inspector. GasRules' shape.

const FOLDER := "res://Resources/StateRules/"

# The temporary stat change the state carries (Unit's element-state doors make it a StatEffect).
@export var stat_mods: Dictionary[Stats.Stat, int] = {}
# The default clock in turns when something ADDS the state; a reaction may author a longer one
# (ElementalReaction.add_state_turns). A state held while standing in a gas stores no clock.
@export var turns := 2


static var _rules_by_state: Dictionary = {}


# This state's rules, or null when it has no file. Cached for the process.
static func for_state(state: Elemental.State) -> StateRules:
	if not _rules_by_state.has(state):
		var path: String = FOLDER + Elemental.State.keys()[state] + ".tres"
		_rules_by_state[state] = load(path) as StateRules if ResourceLoader.exists(path) else null
	return _rules_by_state[state]
