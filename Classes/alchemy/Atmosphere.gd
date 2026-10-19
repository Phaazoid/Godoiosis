class_name Atmosphere
extends Object

# What the AIR over a board holds, and how hard that makes a carving hit (#1324; docs/design/
# deep-alchemy.md -> What is built). Every cell holds the ambient substances below at any
# concentration, so the reading never refuses a cast: a board authors a percentage per substance,
# and a carving moves one damage per STEP away from Normal for each substance its recipe draws from
# the air (CarvingRecipe.drawn_from). Damage, never a fizzle (Phaazoid@, 2026-10-14).
#
# A reading is a Dictionary of substance id -> percent, authored on ScenarioData. A missing key reads
# Normal, so an empty reading is a Normal board. What the rules play on is the EFFECTIVE reading, the
# authored one with its weather's nudge applied (effective, below); BoardContext carries that one.
#
# Static on the reading passed in, Materia's shape: a carving has no board and must not grow one.

# Every ambient substance, in display order. The one answer to "what is in every cell's air".
const SUBSTANCES: Array[String] = ["inert_air", "vital_air", "vapor", "atom_fire", "atom_aether"]

# The two headings a reading is shown under (c3potheds@ and Phaazoid@, 2026-10-13).
const GROUPS: Dictionary[String, Array] = {
	"Atmosphere": ["inert_air", "vital_air", "vapor"],
	"Ambient": ["atom_fire", "atom_aether"],
}

# A Normal board's percentages, and how many points make one step. Balance numbers, tuned here
# (Materia.REACH's idiom).
const NORMAL: Dictionary[String, int] = {
	"inert_air": 75, "vital_air": 20, "vapor": 5, "atom_fire": 20, "atom_aether": 10,
}
const STEP: Dictionary[String, int] = {
	"inert_air": 10, "vital_air": 5, "vapor": 5, "atom_fire": 10, "atom_aether": 5,
}


static func percent_of(id: String, reading: Dictionary) -> int:
	return int(reading.get(id, NORMAL.get(id, 0)))


# The reading a board plays under: what it authors, moved by its weather (WeatherRules.air). THE one
# composition -- the resolver, every readout and the Play API take this, never the authored reading
# alone. ScenarioManager.air_reading is the game's door onto it.
static func effective(authored: Dictionary, weather: Weather.Kind) -> Dictionary[String, int]:
	return nudged(authored, WeatherRules.air_of(weather))


# A reading moved by a nudge (substance id -> percentage points), each substance held to 0..100. The
# arithmetic of every source that moves the air; the weather is the first.
static func nudged(reading: Dictionary, nudge: Dictionary) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	out.assign(reading)
	for id: String in nudge:
		out[id] = clampi(percent_of(id, reading) + int(nudge[id]), 0, 100)
	return out


# Whole steps away from Normal, truncated toward zero: heat at Normal 20 with a step of 10 reads
# +1 at 30, 0 at 29, -1 at 10.
static func steps_of(id: String, reading: Dictionary) -> int:
	var step: int = STEP.get(id, 0)
	if step <= 0:
		return 0
	return (percent_of(id, reading) - int(NORMAL.get(id, 0))) / step


# The non-zero steps of everything `recipe` draws from the air, by substance id.
static func steps_for(recipe: CarvingRecipe, reading: Dictionary) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	if recipe == null or not recipe.is_legal():
		return out
	for id: String in recipe.drawn_from(SUBSTANCES):
		var steps := steps_of(id, reading)
		if steps != 0:
			out[id] = steps
	return out


# The damage those steps add, one per step.
static func bonus_of(steps: Dictionary[String, int]) -> int:
	var total := 0
	for id: String in steps:
		total += steps[id]
	return total


static func is_normal(reading: Dictionary) -> bool:
	return off_normal(reading).is_empty()


# The substances whose percent is not Normal, in SUBSTANCES order. The one answer to "what is off
# Normal": the corner HUD lists these, and the bug report names them.
static func off_normal(reading: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in SUBSTANCES:
		if percent_of(id, reading) != int(NORMAL[id]):
			out.append(id)
	return out


# How a reading is worded, for every surface that shows one: "30%", and its steps from Normal as
# "+2", or nothing at Normal's own step (Weather.display_name's shape).
static func percent_text(id: String, reading: Dictionary) -> String:
	return "%d%%" % percent_of(id, reading)


static func steps_text(id: String, reading: Dictionary) -> String:
	var steps := steps_of(id, reading)
	return "%+d" % steps if steps != 0 else ""


# Whether this weather moves this substance, so a readout can name the weather beside it.
static func weather_moves(id: String, weather: Weather.Kind) -> bool:
	return int(WeatherRules.air_of(weather).get(id, 0)) != 0


# What this weather does to this substance, as a readout says it: "Rain adds 10% vapor", "Snow lowers
# heat by 20%", or nothing when it does not move it.
static func weather_text(id: String, weather: Weather.Kind) -> String:
	var points := int(WeatherRules.air_of(weather).get(id, 0))
	if points == 0:
		return ""
	var substance := SubstanceCatalog.name_of(id).to_lower()
	if points > 0:
		return "%s adds %d%% %s" % [Weather.display_name(weather), points, substance]
	return "%s lowers %s by %d%%" % [Weather.display_name(weather), substance, -points]


# Every substance this weather moves, worded, in SUBSTANCES order: one line each for a tooltip.
static func weather_lines(weather: Weather.Kind) -> Array[String]:
	var lines: Array[String] = []
	for id: String in SUBSTANCES:
		var line := weather_text(id, weather)
		if line != "":
			lines.append(line + ".")
	return lines
