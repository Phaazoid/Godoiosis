extends Resource
class_name WindRules

# What one wind strength DOES (#1660), one file per kind under Resources/WindRules/ named for the kind,
# edited on the dev tools' Weather page or in the inspector. WeatherRules' shape: WindLook is how the
# wind is DRAWN (WindLook.vector, its speed), and the two never share a file. Its direction is the
# board's (BoardContext.wind_direction), stepped on the grid by Wind.step.
#
# A kind with no file has no rules. CALM has none.

const FOLDER := "res://Resources/WindRules/"

# Tiles every gas drifts downwind each round (GasSpread._drift), after it spills and fades.
@export_range(0, 4) var drift := 0

# Tiles a shove gains going with the wind and loses going against it, never below none
# (PlanResolver._shove_length). A shove across the wind keeps its length.
@export_range(0, 3) var shove := 0


static var _rules_by_kind: Dictionary = {}


# This kind's rules, or null when it has none. Cached for the process, so the Weather page edits the
# object every reader holds.
static func for_kind(kind: Wind.Kind) -> WindRules:
	if not _rules_by_kind.has(kind):
		var path := FOLDER + Wind.name_of(kind) + ".tres"
		_rules_by_kind[kind] = load(path) as WindRules if ResourceLoader.exists(path) else null
	return _rules_by_kind[kind]


# Tiles the board's wind drifts gas each round, 0 when it drifts none.
static func drift_of(board: BoardContext) -> int:
	var rules := for_kind(board.wind)
	return rules.drift if rules != null else 0


# The most tiles the board's wind can add to a shove: what the threat field dilates by.
static func shove_of(board: BoardContext) -> int:
	var rules := for_kind(board.wind)
	return rules.shove if rules != null else 0


# Tiles the board's wind adds to a shove going `dir` (a cardinal step): +shove with it, -shove against
# it, 0 across it. A diagonal wind leans on both of its sides.
static func shove_along(board: BoardContext, dir: Vector2i) -> int:
	return lean(board.wind, board.wind_direction, dir)


# The same lean, of a wind named outright rather than a board's: what the conditions box words.
static func lean(kind: Wind.Kind, direction: Wind.Direction, dir: Vector2i) -> int:
	var rules := for_kind(kind)
	if rules == null or rules.shove == 0:
		return 0
	var step := Wind.step(direction)
	return rules.shove * signi(dir.x * step.x + dir.y * step.y)
