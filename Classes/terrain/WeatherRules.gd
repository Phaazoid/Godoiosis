extends Resource
class_name WeatherRules

# What one weather DOES (#1260), one file per kind under Resources/WeatherRules/ named for the kind,
# edited on the dev tools' Weather page or in the inspector. GasRules' shape: WeatherLook is how it
# is DRAWN, and the two never share a file, because a rule and a look have different owners.
#
# A kind with no file has no rules. CLEAR has none.

const FOLDER := "res://Resources/WeatherRules/"

# What a unit gains when its OWN side's turn ends while this weather falls (dev, 2026-10-08: "in the
# rain, units get the wet status") -- steam's soak, from the sky instead of a cell. NONE soaks nobody.
@export var state: Elemental.State = Elemental.State.NONE


static var _rules_by_kind: Dictionary = {}


# This kind's rules, or null when it has none. Cached for the process, so the Weather page edits the
# object every reader holds.
static func for_kind(kind: Weather.Kind) -> WeatherRules:
	if not _rules_by_kind.has(kind):
		var path := FOLDER + Weather.name_of(kind) + ".tres"
		_rules_by_kind[kind] = load(path) as WeatherRules if ResourceLoader.exists(path) else null
	return _rules_by_kind[kind]
