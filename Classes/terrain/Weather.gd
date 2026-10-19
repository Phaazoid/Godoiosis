extends Object
class_name Weather

# The weather's vocabulary (#1260): which weathers exist. A board names one (ScenarioData.weather),
# what it DOES is its WeatherRules file and how it LOOKS is its WeatherLook file, one of each per
# kind and named for it -- Gas's split, for Gas's reason. A kind with no rules file does nothing: the
# sands and ashes (#1302) are looks only. The rains soak and move the air; the snows (#1269), the fogs
# (#1285) and the auroras (#1298) only move the air (#1324, WeatherRules.air).
#
# A kind's int is what a save holds, so Kind is APPEND-ONLY: rename a member freely, never reorder
# or delete one. CLEAR is the default and does nothing.

enum Kind { CLEAR, LIGHT_RAIN, RAIN, HEAVY_RAIN, THUNDERSTORM, LIGHT_SNOW, SNOW, BLIZZARD, MIST, FOG, THICK_FOG,
		FAINT_AURORA, AURORA, AETHERIC_STORM, DUST, SANDSTORM, DUST_WALL, LIGHT_ASHFALL, ASHFALL, ASH_STORM }


static func name_of(kind: Kind) -> String:
	return Kind.keys()[kind]


# What the PLAYER calls this weather ("Heavy Rain") -- Gas.display_name's rule.
static func display_name(kind: Kind) -> String:
	return name_of(kind).capitalize()
