extends Object
class_name Wind

# The wind's vocabulary (#1286): how hard it blows and which way. A board names one strength and one
# direction (ScenarioData.wind, ScenarioData.wind_direction) beside its weather and independent of it,
# so any weather can blow at any strength -- a second axis, not a stack. How each strength LOOKS, and
# how fast it blows, is its WindLook file. Wind is a look only: no rule reads it.
#
# Both enums' ints are what a save holds, so they are APPEND-ONLY: rename a member freely, never
# reorder or delete one. CALM is the default and blows nothing; EAST is the default direction.

enum Kind { CALM, BREEZE, STRONG_WIND, GALE }

# Which way the wind blows TOWARD, on the board: east is +x and south is +z, so north is grid up.
enum Direction { EAST, SOUTH_EAST, SOUTH, SOUTH_WEST, WEST, NORTH_WEST, NORTH, NORTH_EAST }


static func name_of(kind: Kind) -> String:
	return Kind.keys()[kind]


# What a player would call this wind ("Strong Wind") -- Weather.display_name's rule.
static func display_name(kind: Kind) -> String:
	return name_of(kind).capitalize()


static func direction_name(direction: Direction) -> String:
	return Direction.keys()[direction].capitalize()


# The unit vector the wind blows along, on the board's x / z.
static func heading(direction: Direction) -> Vector2:
	return Vector2.RIGHT.rotated(float(direction) * PI / 4.0)
