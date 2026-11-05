extends Resource
class_name AtmosphereRules

# The air every board starts from (#1534): each ambient substance's Normal percentage and how many
# points make one step. One file, Resources/AtmosphereRules.tres, tuned live on the dev tools' Air &
# gas page. Atmosphere is the rule that reads it (normal_of, step_of); WeatherRules.air and GasRules.air
# are the nudges that move a reading off it, in the same points.
#
# Keyed by Atmosphere.SUBSTANCES. The defaults are empty so the numbers live in the file alone.

const PATH := "res://Resources/AtmosphereRules.tres"

# Substance id -> the percentage a board reads when it does not author that substance.
@export var normal: Dictionary[String, int] = {}
# Substance id -> how many points away from Normal make one step (one damage on a carving).
@export var step: Dictionary[String, int] = {}


static var _authored: AtmosphereRules


# The file every reader shares. Cached for the process, so the Air & gas page edits the object the
# rules read.
static func authored() -> AtmosphereRules:
	if _authored == null:
		_authored = load(PATH) as AtmosphereRules
		if _authored == null:
			push_error("AtmosphereRules: %s did not load; every substance reads 0" % PATH)
			_authored = AtmosphereRules.new()
	return _authored
