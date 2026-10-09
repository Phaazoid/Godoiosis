extends Resource
class_name WeatherLook

# How one weather looks (#1260), one file per Weather.Kind under Resources/WeatherLooks/ named for the
# kind -- GasLook's shape, for the reason WeatherRules is GasRules': a look and a rule have different
# owners. Dumb data: WeatherMirror draws it, and the dev tools' Weather page tunes it live and saves it.
#
# What falls is the FALL field (#1269): rain draws drops, splashes, a wet sheen and puddles; snow draws
# flakes, a snow cover, caps, drift and breath. The fields of the other fall are ignored, and the page
# hides their rows. The grade is either fall's.
#
# Every number is a feel value, so every one is a row (ROWS) on that page. A kind with no file draws
# nothing; CLEAR has none.

const FOLDER := "res://Resources/WeatherLooks/"

enum Fall { RAIN, SNOW }

@export var fall := Fall.RAIN

@export_group("Falling")
@export var density := 3.0                  # drops or flakes born per cell of view per second
@export var fall_speed := 14.0              # world units a second
@export var wind_x := 0.8                   # sideways drift, world units a second (east)
@export var wind_z := 0.3                   # (south)

@export_group("Drops")
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

@export_group("Flakes")
@export var flake_sway := 0.3               # world units a second a flake wanders side to side
@export var flake_swirl := 0.0              # world units a second of eddy: a blizzard loops its flakes
@export var swirl_scale := 1.5              # world units across one eddy
@export var big_flakes := 0.15              # share of flakes drawn as a plus rather than one pixel
@export var flake_color := Color(0.96, 0.98, 1.0, 0.9)
@export var flake_settle := 0.8             # seconds a landed flake lies before it melts away

@export_group("Snow ground")
@export var snow_cover := 0.5               # 0..1: how much of the ground lies under snow
@export var slope_cover := 1.0              # 0..1: the share of that cover a ramp or hillside keeps
@export var snow_frost := 0.2               # 0..1: the faint whitening over all of it
@export var snow_flecks := 0.04             # share of the ground's art pixels flecked white
@export var snow_color := Color(0.93, 0.95, 0.99)
@export var snow_roughness := 0.85
@export var snow_relief := 6.0              # how hard the patches' edges and lumps catch the light; 0 is flat
@export var relief_softness := 1.0          # art pixels a patch's edge slopes over
@export var snow_bumps := 0.3               # 0..1: how lumpy the snow's top is
@export var bump_size := 5.0                # art pixels across one lump

@export_group("Settles")
@export var caps_props := false             # snow on the tops of rocks, walls, crates and trees
@export var caps_units := false             # ...and on the units' heads and shoulders
@export var unit_cap_color := Color(0.32, 0.58, 0.98)   # the units' caps: ice blue, to read against white ground
@export var breath := false                 # every standing unit's breath fogs

@export_group("Drift")
@export var drift_rate := 0.0               # streaks of loose snow per cell of view per second
@export var drift_speed := 5.0              # world units a second along the wind
@export var drift_texels := 5               # how long a streak is, in art pixels
@export var drift_life := 0.6               # seconds a streak lives
@export var drift_color := Color(0.95, 0.97, 1.0, 0.5)

@export_group("Grade")
@export var grade_saturation := 1.0         # 1 leaves the board's colours; lower greys them
@export var grade_brightness := 1.0
@export var grade_tint := Color(1.0, 1.0, 1.0, 0.0)   # mixed in; its alpha is how much
@export var veil := 0.0                     # 0..1: the whiteout drifting across the view
@export var veil_speed := 0.06              # screen widths a second the whiteout drifts
@export var veil_color := Color(0.92, 0.94, 0.97)
@export var grade_fade := 1.5               # seconds the grade takes to come and go


# The Weather page's rows, in the order drawn. Declared beside the fields they name, where a field
# added later is one line away from its row; `test_weather_tool` refuses a field with none. A row
# with a "fall" key shows only on a look of that fall.
const ROWS: Array[Dictionary] = [
	{"prop": "fall", "label": "Falls as", "options": ["Rain", "Snow"],
		"tip": "What this weather draws: drops, splashes and a wet sheen, or flakes, snow cover and caps."},
	{"prop": "density", "label": "Density", "min": 0.0, "max": 12.0, "step": 0.1,
		"tip": "How many drops or flakes are born over each cell of the view every second."},
	{"prop": "fall_speed", "label": "Fall speed", "min": 0.5, "max": 40.0, "step": 0.1,
		"tip": "How fast it falls, in cells a second. Rain reads heavier faster; snow drifts slow."},
	{"prop": "wind_x", "label": "Wind east", "min": -8.0, "max": 8.0, "step": 0.1,
		"tip": "Sideways drift, cells a second. Slants the rain, carries the snow, and drives the ground drift."},
	{"prop": "wind_z", "label": "Wind south", "min": -8.0, "max": 8.0, "step": 0.1,
		"tip": "Sideways drift toward the bottom of the map, cells a second."},
	{"prop": "streak_texels", "label": "Streak length", "min": 1.0, "max": 16.0, "step": 1.0, "fall": Fall.RAIN,
		"tip": "How long a drop is, in art pixels -- the same pixels the sprites are drawn in."},
	{"prop": "drop_color", "label": "Drop colour", "fall": Fall.RAIN, "tip": "Colour and opacity of a drop."},
	{"prop": "splashes", "label": "Splashes", "fall": Fall.RAIN, "tip": "Rings where drops land."},
	{"prop": "splash_rate", "label": "Splashes per cell", "min": 0.0, "max": 8.0, "step": 0.1, "fall": Fall.RAIN,
		"tip": "How many rings open on each cell of ground in view every second."},
	{"prop": "splash_life", "label": "Splash time", "min": 0.05, "max": 1.5, "step": 0.01, "fall": Fall.RAIN,
		"tip": "Seconds a ring takes to spread and fade."},
	{"prop": "splash_color", "label": "Splash colour", "fall": Fall.RAIN, "tip": "Colour and opacity of a ring."},
	{"prop": "wet_darkness", "label": "Wet darkness", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.RAIN,
		"tip": "How far the ground's colour is pulled toward the wet tint. Water tiles are never touched."},
	{"prop": "wet_tint", "label": "Wet tint", "fall": Fall.RAIN, "tip": "The colour wet ground darkens toward."},
	{"prop": "wet_roughness", "label": "Wet gloss", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.RAIN,
		"tip": "The wet ground's roughness: 1 is dry and matte, lower catches the light and the sky."},
	{"prop": "puddles", "label": "Puddles", "fall": Fall.RAIN,
		"tip": "Puddles on flat open ground. Never on water, a slope or a hole, and never past their own tile."},
	{"prop": "puddle_coverage", "label": "Puddle share", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.RAIN,
		"tip": "The share of flat open cells holding a puddle. Which cells is fixed per cell, so a board always puddles in the same places."},
	{"prop": "puddle_color", "label": "Puddle colour", "fall": Fall.RAIN,
		"tip": "The puddle's colour; its alpha is how opaque the water reads."},
	{"prop": "puddle_roughness", "label": "Puddle gloss", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.RAIN,
		"tip": "The puddle's roughness: lower is more mirror-like."},
	{"prop": "lightning", "label": "Lightning", "fall": Fall.RAIN,
		"tip": "Strikes in the sky and beyond the board's edge. Never onto a cell."},
	{"prop": "strike_every_min", "label": "Strike every (min)", "min": 0.5, "max": 30.0, "step": 0.1, "fall": Fall.RAIN,
		"tip": "The shortest wait between strikes, seconds."},
	{"prop": "strike_every_max", "label": "Strike every (max)", "min": 0.5, "max": 60.0, "step": 0.1, "fall": Fall.RAIN,
		"tip": "The longest wait between strikes, seconds."},
	{"prop": "flash_peak", "label": "Screen flash", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.RAIN,
		"tip": "The screen's white-out at a strike. The photosensitivity setting caps it."},
	{"prop": "side_light_energy", "label": "Strike light", "min": 0.0, "max": 12.0, "step": 0.1, "fall": Fall.RAIN,
		"tip": "How bright the strike lights the board from the side it hit, with long shadows."},
	{"prop": "side_light_color", "label": "Strike light colour", "fall": Fall.RAIN, "tip": "The colour of the strike's light."},
	{"prop": "side_light_elevation", "label": "Strike light angle", "min": 2.0, "max": 60.0, "step": 1.0, "fall": Fall.RAIN,
		"tip": "Degrees above the horizon the strike's light comes in at. Lower throws longer shadows."},
	{"prop": "cloud_glow", "label": "Cloud glow", "min": 0.0, "max": 6.0, "step": 0.05, "fall": Fall.RAIN,
		"tip": "How much brighter the sky gets at a strike."},
	{"prop": "bolt_life", "label": "Bolt time", "min": 0.05, "max": 2.0, "step": 0.01, "fall": Fall.RAIN,
		"tip": "Seconds a bolt takes to fade."},
	{"prop": "bolt_width_scale", "label": "Bolt width", "min": 0.5, "max": 20.0, "step": 0.1, "fall": Fall.RAIN,
		"tip": "Times the shock attack's own bolt width. A sky bolt is far off, so it needs more."},
	{"prop": "bolt_distance", "label": "Bolt distance", "min": 1.0, "max": 40.0, "step": 0.5, "fall": Fall.RAIN,
		"tip": "Cells beyond the board's edge a bolt lands."},
	{"prop": "bolt_height", "label": "Bolt height", "min": 4.0, "max": 120.0, "step": 1.0, "fall": Fall.RAIN,
		"tip": "How far above the board a bolt starts."},
	{"prop": "flake_sway", "label": "Flake sway", "min": 0.0, "max": 3.0, "step": 0.05, "fall": Fall.SNOW,
		"tip": "How far a flake wanders side to side as it falls, cells a second."},
	{"prop": "flake_swirl", "label": "Swirl", "min": 0.0, "max": 8.0, "step": 0.05, "fall": Fall.SNOW,
		"tip": "Eddies that loop the flakes rather than letting them fall straight -- what keeps a blizzard from reading as rain."},
	{"prop": "swirl_scale", "label": "Swirl size", "min": 0.2, "max": 8.0, "step": 0.05, "fall": Fall.SNOW,
		"tip": "How wide one eddy is, in cells."},
	{"prop": "big_flakes", "label": "Big flakes", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.SNOW,
		"tip": "The share of flakes drawn as a plus rather than a single art pixel."},
	{"prop": "flake_color", "label": "Flake colour", "fall": Fall.SNOW, "tip": "Colour and opacity of a flake."},
	{"prop": "flake_settle", "label": "Flake settle", "min": 0.0, "max": 4.0, "step": 0.05, "fall": Fall.SNOW,
		"tip": "Seconds a landed flake lies on the ground before it melts away. 0 is gone on landing."},
	{"prop": "snow_cover", "label": "Snow cover", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.SNOW,
		"tip": "How much of the ground lies under snow: low leaves clumps, mid lies in patches, high covers nearly all. Never on water or a hole, and never past a tile."},
	{"prop": "slope_cover", "label": "Slopes keep", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.SNOW,
		"tip": "The share of the cover a ramp or a hillside keeps: snow slides off, so a low value shows the hills by their thin sides. 1 treats a slope like flat ground."},
	{"prop": "snow_frost", "label": "Frost", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.SNOW,
		"tip": "A faint whitening over all the ground the snow could lie on."},
	{"prop": "snow_flecks", "label": "Flecks", "min": 0.0, "max": 0.3, "step": 0.005, "fall": Fall.SNOW,
		"tip": "The share of the ground's art pixels flecked white between the patches."},
	{"prop": "snow_color", "label": "Snow colour", "fall": Fall.SNOW,
		"tip": "The settled snow's colour: on the ground and on the props' caps. The units' caps have their own colour."},
	{"prop": "snow_roughness", "label": "Snow gloss", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.SNOW,
		"tip": "The snow's roughness: 1 is matte powder, lower catches the light like a crust."},
	{"prop": "snow_relief", "label": "Relief", "min": 0.0, "max": 20.0, "step": 0.1, "fall": Fall.SNOW,
		"tip": "How much the snow stands up off the ground: patch edges and lumps catch the light and cast a little shade. 0 is flat."},
	{"prop": "relief_softness", "label": "Edge softness", "min": 0.0, "max": 3.0, "step": 0.1, "fall": Fall.SNOW,
		"tip": "How many art pixels a patch's edge slopes over. 0 is a sharp step."},
	{"prop": "snow_bumps", "label": "Lumps", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.SNOW,
		"tip": "How lumpy the top of the snow is. 0 is smooth."},
	{"prop": "bump_size", "label": "Lump size", "min": 2.0, "max": 16.0, "step": 0.5, "fall": Fall.SNOW,
		"tip": "How wide one lump is, in art pixels."},
	{"prop": "caps_props", "label": "Caps on props", "fall": Fall.SNOW,
		"tip": "Snow on the tops of rocks, walls, crates, barrels, trees and lanterns. Tall grass and flowers hide in any snow."},
	{"prop": "caps_units", "label": "Caps on units", "fall": Fall.SNOW,
		"tip": "Snow on every unit's head and shoulders. A look only: no rule is behind it yet."},
	{"prop": "unit_cap_color", "label": "Unit cap colour", "fall": Fall.SNOW,
		"tip": "The colour of the snow on the units' heads. Blue reads as ice and stands out against a white ground."},
	{"prop": "breath", "label": "Breath", "fall": Fall.SNOW,
		"tip": "Every standing unit's breath fogs, the puff a Chilled unit breathes. A look only."},
	{"prop": "drift_rate", "label": "Ground drift", "min": 0.0, "max": 8.0, "step": 0.05, "fall": Fall.SNOW,
		"tip": "Streaks of loose snow blown along the ground, per cell of view per second. 0 is none."},
	{"prop": "drift_speed", "label": "Drift speed", "min": 0.5, "max": 20.0, "step": 0.1, "fall": Fall.SNOW,
		"tip": "How fast the loose snow streams along the wind, cells a second."},
	{"prop": "drift_texels", "label": "Drift length", "min": 1.0, "max": 16.0, "step": 1.0, "fall": Fall.SNOW,
		"tip": "How long a streak of loose snow is, in art pixels."},
	{"prop": "drift_life", "label": "Drift time", "min": 0.1, "max": 3.0, "step": 0.05, "fall": Fall.SNOW,
		"tip": "Seconds a streak lives; it fades in and out."},
	{"prop": "drift_color", "label": "Drift colour", "fall": Fall.SNOW, "tip": "Colour and opacity of the loose snow."},
	{"prop": "grade_saturation", "label": "Grade saturation", "min": 0.0, "max": 1.5, "step": 0.01,
		"tip": "The weather's own grade over the board's look: 1 leaves the colours, lower greys them. The HUD is never graded."},
	{"prop": "grade_brightness", "label": "Grade brightness", "min": 0.5, "max": 1.5, "step": 0.01,
		"tip": "The weather's grade: how much brighter or darker the board is drawn."},
	{"prop": "grade_tint", "label": "Grade tint", "tip": "A colour mixed over the board; its alpha is how much. The cold of a snowfall."},
	{"prop": "veil", "label": "Whiteout", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "A whiteout drifting across the view, in slow bands. 0 is none."},
	{"prop": "veil_speed", "label": "Whiteout speed", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "How fast the whiteout's bands drift, screen widths a second. They drift with the wind."},
	{"prop": "veil_color", "label": "Whiteout colour", "tip": "The whiteout's colour."},
	{"prop": "grade_fade", "label": "Grade fade", "min": 0.0, "max": 6.0, "step": 0.05,
		"tip": "Seconds the grade and whiteout take to come in when the weather changes, and to go."},
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


# Whether a ROWS entry belongs on a look of this fall.
static func row_shows(row: Dictionary, fall: Fall) -> bool:
	return not row.has("fall") or int(row["fall"]) == fall


# Whether this look grades the picture at all: identity draws nothing.
func grades() -> bool:
	return not is_equal_approx(grade_saturation, 1.0) or not is_equal_approx(grade_brightness, 1.0) \
			or grade_tint.a > 0.001 or veil > 0.001
