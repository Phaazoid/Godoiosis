extends Resource
class_name WeatherLook

# How one weather looks (#1260), one file per Weather.Kind under Resources/WeatherLooks/ named for the
# kind -- GasLook's shape, for the reason WeatherRules is GasRules': a look and a rule have different
# owners. Dumb data: WeatherMirror draws it, and the dev tools' Weather page tunes it live and saves it.
#
# Every number is a feel value, so every one is a row (ROWS) on that page. A kind with no file draws
# nothing; CLEAR has none.

const FOLDER := "res://Resources/WeatherLooks/"

@export_group("Drops")
@export var density := 3.0                  # drops born per cell of view per second
@export var fall_speed := 14.0              # world units a second
@export var wind_x := 0.8                   # sideways drift, world units a second (east)
@export var wind_z := 0.3                   # (south)
@export var streak_texels := 6              # how long a drop is, in art pixels
@export var drop_color := Color(0.8, 0.87, 1.0, 0.6)

@export_group("Splashes")
@export var splashes := true
@export var splash_rate := 1.2              # rings per cell of view per second
@export var splash_life := 0.28             # seconds a ring takes to spread and fade
@export var splash_color := Color(0.88, 0.93, 1.0, 0.75)

@export_group("Ground")
@export var wet_darkness := 0.3             # how far the ground's own colour is pulled toward the tint
@export var wet_tint := Color(0.07, 0.09, 0.12)
@export var wet_roughness := 0.22           # 1 is dry; lower is glossier
@export var puddles := true
@export var puddle_coverage := 0.25         # share of flat open ground holding one
@export var puddle_color := Color(0.3, 0.37, 0.48, 0.85)   # alpha is how opaque the water is
@export var puddle_roughness := 0.05

@export_group("Storm")
@export var lightning := false
@export var strike_every_min := 3.5         # seconds between strikes, at least...
@export var strike_every_max := 8.0         # ...and at most
@export var flash_peak := 0.3               # the screen's white-out at the strike, 0..1
@export var side_light_energy := 2.5        # the strike's own light across the board
@export var side_light_color := Color(0.82, 0.86, 1.0)
@export var side_light_elevation := 16.0    # degrees above the horizon it comes in at
@export var cloud_glow := 1.2               # how much brighter the sky gets at a strike
@export var bolt_life := 0.5                # seconds a bolt takes to fade
@export var bolt_width_scale := 5.0         # times the shock bolt's own width (a sky bolt is far off)
@export var bolt_distance := 7.0            # cells beyond the board's edge a bolt lands
@export var bolt_height := 32.0             # world units above the board it falls from


# The Weather page's rows, in the order drawn. Declared beside the fields they name, where a field
# added later is one line away from its row; `test_weather_tool` refuses a field with none.
const ROWS: Array[Dictionary] = [
	{"prop": "density", "label": "Drops per cell", "min": 0.0, "max": 12.0, "step": 0.1,
		"tip": "How many drops are born over each cell of the view every second."},
	{"prop": "fall_speed", "label": "Fall speed", "min": 2.0, "max": 40.0, "step": 0.5,
		"tip": "How fast a drop falls, in cells a second. Faster reads heavier."},
	{"prop": "wind_x", "label": "Wind east", "min": -8.0, "max": 8.0, "step": 0.1,
		"tip": "Sideways drift, cells a second. Slants the streaks too."},
	{"prop": "wind_z", "label": "Wind south", "min": -8.0, "max": 8.0, "step": 0.1,
		"tip": "Sideways drift toward the bottom of the map, cells a second."},
	{"prop": "streak_texels", "label": "Streak length", "min": 1.0, "max": 16.0, "step": 1.0,
		"tip": "How long a drop is, in art pixels -- the same pixels the sprites are drawn in."},
	{"prop": "drop_color", "label": "Drop colour", "tip": "Colour and opacity of a drop."},
	{"prop": "splashes", "label": "Splashes", "tip": "Rings where drops land."},
	{"prop": "splash_rate", "label": "Splashes per cell", "min": 0.0, "max": 8.0, "step": 0.1,
		"tip": "How many rings open on each cell of ground in view every second."},
	{"prop": "splash_life", "label": "Splash time", "min": 0.05, "max": 1.5, "step": 0.01,
		"tip": "Seconds a ring takes to spread and fade."},
	{"prop": "splash_color", "label": "Splash colour", "tip": "Colour and opacity of a ring."},
	{"prop": "wet_darkness", "label": "Wet darkness", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How far the ground's colour is pulled toward the wet tint. Water tiles are never touched."},
	{"prop": "wet_tint", "label": "Wet tint", "tip": "The colour wet ground darkens toward."},
	{"prop": "wet_roughness", "label": "Wet gloss", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "The wet ground's roughness: 1 is dry and matte, lower catches the light and the sky."},
	{"prop": "puddles", "label": "Puddles", "tip": "Puddles on flat open ground. Never on water, a slope or a hole, and never past their own tile."},
	{"prop": "puddle_coverage", "label": "Puddle share", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "The share of flat open cells holding a puddle. Which cells is fixed per cell, so a board always puddles in the same places."},
	{"prop": "puddle_color", "label": "Puddle colour", "tip": "The puddle's colour; its alpha is how opaque the water reads."},
	{"prop": "puddle_roughness", "label": "Puddle gloss", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "The puddle's roughness: lower is more mirror-like."},
	{"prop": "lightning", "label": "Lightning", "tip": "Strikes in the sky and beyond the board's edge. Never onto a cell."},
	{"prop": "strike_every_min", "label": "Strike every (min)", "min": 0.5, "max": 30.0, "step": 0.1,
		"tip": "The shortest wait between strikes, seconds."},
	{"prop": "strike_every_max", "label": "Strike every (max)", "min": 0.5, "max": 60.0, "step": 0.1,
		"tip": "The longest wait between strikes, seconds."},
	{"prop": "flash_peak", "label": "Screen flash", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "The screen's white-out at a strike. The photosensitivity setting caps it."},
	{"prop": "side_light_energy", "label": "Strike light", "min": 0.0, "max": 12.0, "step": 0.1,
		"tip": "How bright the strike lights the board from the side it hit, with long shadows."},
	{"prop": "side_light_color", "label": "Strike light colour", "tip": "The colour of the strike's light."},
	{"prop": "side_light_elevation", "label": "Strike light angle", "min": 2.0, "max": 60.0, "step": 1.0,
		"tip": "Degrees above the horizon the strike's light comes in at. Lower throws longer shadows."},
	{"prop": "cloud_glow", "label": "Cloud glow", "min": 0.0, "max": 6.0, "step": 0.05,
		"tip": "How much brighter the sky gets at a strike."},
	{"prop": "bolt_life", "label": "Bolt time", "min": 0.05, "max": 2.0, "step": 0.01,
		"tip": "Seconds a bolt takes to fade."},
	{"prop": "bolt_width_scale", "label": "Bolt width", "min": 0.5, "max": 20.0, "step": 0.1,
		"tip": "Times the shock attack's own bolt width. A sky bolt is far off, so it needs more."},
	{"prop": "bolt_distance", "label": "Bolt distance", "min": 1.0, "max": 40.0, "step": 0.5,
		"tip": "Cells beyond the board's edge a bolt lands."},
	{"prop": "bolt_height", "label": "Bolt height", "min": 4.0, "max": 120.0, "step": 1.0,
		"tip": "How far above the board a bolt starts."},
]


static var _looks_by_kind: Dictionary = {}


# This kind's look, or null when it has none. Cached for the process, so the Weather page edits the
# object the mirror draws from.
static func for_kind(kind: Weather.Kind) -> WeatherLook:
	if not _looks_by_kind.has(kind):
		var path := FOLDER + Weather.name_of(kind) + ".tres"
		_looks_by_kind[kind] = load(path) as WeatherLook if ResourceLoader.exists(path) else null
	return _looks_by_kind[kind]


static func path_of(kind: Weather.Kind) -> String:
	return FOLDER + Weather.name_of(kind) + ".tres"
