extends Resource
class_name WeatherLook

# How one weather looks (#1260), one file per Weather.Kind under Resources/WeatherLooks/ named for the
# kind -- GasLook's shape, for the reason WeatherRules is GasRules': a look and a rule have different
# owners. Dumb data: WeatherMirror draws it, and the dev tools' Weather page tunes it live and saves it.
#
# What falls is the FALL field (#1269): rain draws drops, splashes, a wet sheen and puddles; snow draws
# flakes, a snow cover, caps, drift and breath; fog (#1285) draws a thin fog pass and drifting pixel
# cards; an aurora (#1298) draws glowing curtains on the ground, its own light and rising motes; sand
# (#1302) draws specks, airborne grit, a sand cover, drift and dust (the fog's pass and cards); ash draws
# flakes, a soot cover, caps and rising embers (the aurora's motes). Which falls draw a PART is the part
# lists below, read by WeatherMirror and by the page's rows alike, so a row shows exactly where its part
# is drawn. The grade is any fall's, and the storm's strikes are rain's and the aurora's.
#
# Every number is a feel value, so every one is a row (ROWS) on that page. A kind with no file draws
# nothing; CLEAR has none. The wind is not a weather's own (#1286): it is the board's, a WindLook,
# and a look only says how much of it a part takes (the fog's drift share, the flakes' and the grit's).

const FOLDER := "res://Resources/WeatherLooks/"
# Elemental.Element's members in order, for the bolt colour's picker; test_weather_tool keeps the two equal.
const ELEMENT_NAMES := ["None", "Fire", "Water", "Shock", "Ice", "Earth", "Air", "Aether", "Corrosion"]

enum Fall { RAIN, SNOW, FOG, AURORA, SAND, ASH }
enum MoteShape { DOTS, STREAKS }

# The parts, each the falls that draw it.
const FLAKES := [Fall.SNOW, Fall.SAND, Fall.ASH]      # snow's flakes, sand's specks, falling ash
const FALLING := [Fall.RAIN] + FLAKES                 # what is born above the view and falls through it
const COVER := [Fall.SNOW, Fall.SAND, Fall.ASH]       # the ground cover (SnowGround)
const CAPS := [Fall.SNOW, Fall.ASH]                   # caps on props and units; the tufts buried
const DRIFT := [Fall.SNOW, Fall.SAND, Fall.ASH]       # loose stuff streaming along the ground
const HAZE := [Fall.FOG, Fall.SAND]                   # the fog pass and cards: fog, or a sandstorm's dust
const GRIT := [Fall.SAND]                             # airborne grit streaks
const MOTES := [Fall.AURORA, Fall.ASH]                # rising motes: an aurora's, or an ashfall's embers
const STORM := [Fall.RAIN, Fall.AURORA]               # the strikes beyond the board

@export var fall := Fall.RAIN

@export_group("Falling")
@export var density := 3.0                  # drops or flakes born per cell of view per second
@export var fall_speed := 14.0              # world units a second

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
@export var bolt_element := Elemental.Element.SHOCK   # whose colour a bolt's corona glows (ElementPalette)

@export_group("Flakes")
@export var flake_sway := 0.3               # world units a second a flake wanders side to side
@export var flake_swirl := 0.0              # world units a second of eddy: a blizzard loops its flakes
@export var swirl_scale := 1.5              # world units across one eddy
@export var flake_wind := 1.0               # the share of the board's wind a flake drifts with
@export var big_flakes := 0.15              # share of flakes drawn as a plus rather than one pixel
@export var flake_color := Color(0.96, 0.98, 1.0, 0.9)
@export var flake_settle := 0.8             # seconds a landed flake lies before it melts away

@export_group("Ground cover")
@export var snow_cover := 0.5               # 0..1: how much of the ground lies under snow, sand or ash
@export var slope_cover := 1.0              # 0..1: the share of that cover a ramp or hillside keeps
@export var snow_frost := 0.2               # 0..1: the faint whitening over all of it
@export var snow_flecks := 0.04             # share of the ground's art pixels flecked with it
@export var snow_color := Color(0.93, 0.95, 0.99)
@export var snow_roughness := 0.85
@export var snow_relief := 6.0              # how hard the patches' edges and lumps catch the light; 0 is flat
@export var relief_softness := 1.0          # art pixels a patch's edge slopes over
@export var snow_bumps := 0.3               # 0..1: how lumpy the snow's top is
@export var bump_size := 5.0                # art pixels across one lump

@export_group("Settles")
@export var caps_props := false             # the cover on the tops of rocks, walls, crates and trees
@export var caps_units := false             # ...and on the units' heads and shoulders
@export var unit_cap_color := Color(0.32, 0.58, 0.98)   # the units' caps: ice blue, to read against white ground
@export var breath := false                 # every standing unit's breath fogs

@export_group("Drift")
@export var drift_rate := 0.0               # streaks of loose snow, sand or ash per cell of view per second
@export var drift_speed := 5.0              # world units a second along the wind
@export var drift_texels := 5               # how long a streak is, in art pixels
@export var drift_life := 0.6               # seconds a streak lives
@export var drift_color := Color(0.95, 0.97, 1.0, 0.5)

@export_group("Grit")
@export var grit_rate := 0.0                # airborne streaks born per cell of the board per second
@export var grit_share := 3.0               # times the board's wind a streak flies at; none on a calm board
@export var grit_height := 1.6              # world units over the ground a streak flies, at most
@export var grit_texels := 6                # how long a streak is, in art pixels
@export var grit_life := 1.2                # seconds a streak lives
@export var grit_color := Color(0.98, 0.9, 0.72, 0.85)

@export_group("Fog")
@export var fog_strength := 0.55            # the thin fog pass's density
@export var layer_amount := 0.0             # 0..1: the sheet over every surface
@export var layer_depth := 0.8              # world units the sheet stands over its own ground
@export var pool_amount := 1.0              # 0..1: the fog lying in the low ground
@export var pool_share := 0.45              # 0..1: the share of the board's ground that counts as low
@export var pool_depth := 0.3               # world units it stands over its own ground, at most
@export var bank_amount := 0.0              # 0..1: drifting banks that swallow units
@export var bank_height := 1.5              # world units a bank stands
@export var bank_size := 7.0                # cells across one bank
@export var fog_breakup := 0.6              # 0..1: how much drifting noise breaks the fog up
@export var edge_fade := 1.0                # cells over which fog thins before the board's edge or a hole
@export var water_haze := 1.0               # 0..1: the share of it that stands over water
@export var pixel_steps := false            # the pass snapped to the ground's art grid, its opacity in steps
@export var fog_color := Color(0.86, 0.89, 0.93)
@export var sky_tint := 0.3                 # 0..1: how far the fog takes the sky's horizon colour
@export var card_amount := 0.8              # pixel cards per cell of the board
@export var card_opacity := 0.45
@export var card_size := 1.0                # times a wisp's own size, 44x14 ground art pixels
@export var card_life := 8.0                # seconds a card takes to fade in and out
@export var card_lift := 0.4                # world units above the ground a card floats, at most
@export var card_sink := 0.25               # world units a second a card sinks off higher ground, at most
@export var card_dissolve := 1.0            # seconds a card takes to dissolve against a rise or past the edge
@export var fog_speed := 0.3                # the share of the wind the fog drifts with, its cards and banks alike

@export_group("Aurora")
@export var glow_strength := 0.7            # how bright the curtains of light on the ground are
@export var bands := 3                      # how many curtains
@export var band_width := 1.4               # world units across one curtain
@export var band_spacing := 6.0             # world units between curtains
@export var band_wave := 2.5                # world units a curtain swings either side of its line
@export var wave_length := 14.0             # world units along one swing
@export var band_angle := 28.6              # degrees the curtains lie at across the board
@export var ripple_speed := 0.8             # how fast the curtains ripple and their rays drift
@export var ray_strength := 0.6             # 0..1: how much the rays break a curtain up
@export var ray_spacing := 0.6              # world units between rays
@export var curtain_pixels := true          # snapped to the ground's art grid and glowing in steps; off is soft
@export var scheme_a_low := Color(0.25, 1.0, 0.55)
@export var scheme_a_fringe := Color(1.0, 0.35, 0.7)
@export var scheme_b_low := Color(0.878, 0.486, 0.753)
@export var scheme_b_fringe := Color(0.55, 0.4, 1.0)
@export var scheme_c_low := Color(0.2, 0.85, 0.85)
@export var scheme_c_fringe := Color(0.878, 0.486, 0.753)
@export var scheme_seconds := 12.0          # seconds each colour scheme lasts
@export var scheme_blend := 0.34            # 0..1: the share of a scheme spent blending into the next
@export var light_energy := 1.2             # the aurora's own light on units, props and ground
@export var light_pulse := 0.25             # 0..1: how far the light and the curtains swell and ebb
@export var light_elevation := 40.0         # degrees above the horizon the light comes in at

@export_group("Motes")
@export var mote_shape := MoteShape.DOTS
@export var mote_rate := 0.15               # motes born per cell of the board per second
@export var mote_rise := 0.3                # world units a second a mote rises
@export var mote_life := 4.0                # seconds a mote lives
@export var mote_height := 0.6              # world units over the ground a mote is born, at most
@export var mote_size := 1.0                # times a mote's own art size
@export var mote_color := Color(1.0, 0.51, 0.35)   # an ashfall's embers; an aurora's motes take its colour cycle

@export_group("Grade")
@export var grade_saturation := 1.0         # 1 leaves the board's colours; lower greys them
@export var grade_brightness := 1.0
@export var grade_tint := Color(1.0, 1.0, 1.0, 0.0)   # mixed in; its alpha is how much
@export var veil := 0.0                     # 0..1: the whiteout drifting across the view
@export var veil_speed := 0.06              # screen widths a second the whiteout drifts
@export var veil_color := Color(0.92, 0.94, 0.97)
@export var grade_fade := 1.5               # seconds the grade and an aurora take to come and go


# The Weather page's rows, in the order drawn. Declared beside the fields they name, where a field
# added later is one line away from its row; `test_weather_tool` refuses a field with none. A row
# with a "fall" key shows only on a look of that fall, or of a fall in that list -- a part's list above.
const ROWS: Array[Dictionary] = [
	{"prop": "fall", "label": "Draws as", "options": ["Rain", "Snow", "Fog", "Aurora", "Sand", "Ash"],
		"tip": "What this weather draws: drops, splashes and a wet sheen; flakes, snow cover and caps; fog and drifting fog cards; an aurora's curtains of light, its glow and rising motes; sand's specks, grit, cover and dust (the fog rows); or ash's flakes, soot, caps and embers (the mote rows)."},
	{"prop": "density", "label": "Density", "min": 0.0, "max": 12.0, "step": 0.1, "fall": FALLING,
		"tip": "How many drops, flakes or specks are born over each cell of the view every second."},
	{"prop": "fall_speed", "label": "Fall speed", "min": 0.5, "max": 40.0, "step": 0.1, "fall": FALLING,
		"tip": "How fast it falls, in cells a second. Rain reads heavier faster; snow drifts slow."},
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
	{"prop": "lightning", "label": "Lightning", "fall": STORM,
		"tip": "Strikes in the sky and beyond the board's edge. Never onto a cell."},
	{"prop": "strike_every_min", "label": "Strike every (min)", "min": 0.5, "max": 30.0, "step": 0.1, "fall": STORM,
		"tip": "The shortest wait between strikes, seconds."},
	{"prop": "strike_every_max", "label": "Strike every (max)", "min": 0.5, "max": 60.0, "step": 0.1, "fall": STORM,
		"tip": "The longest wait between strikes, seconds."},
	{"prop": "flash_peak", "label": "Screen flash", "min": 0.0, "max": 1.0, "step": 0.01, "fall": STORM,
		"tip": "The screen's white-out at a strike. The photosensitivity setting caps it."},
	{"prop": "side_light_energy", "label": "Strike light", "min": 0.0, "max": 12.0, "step": 0.1, "fall": STORM,
		"tip": "How bright the strike lights the board from the side it hit, with long shadows."},
	{"prop": "side_light_color", "label": "Strike light colour", "fall": STORM, "tip": "The colour of the strike's light."},
	{"prop": "side_light_elevation", "label": "Strike light angle", "min": 2.0, "max": 60.0, "step": 1.0, "fall": STORM,
		"tip": "Degrees above the horizon the strike's light comes in at. Lower throws longer shadows."},
	{"prop": "cloud_glow", "label": "Cloud glow", "min": 0.0, "max": 6.0, "step": 0.05, "fall": STORM,
		"tip": "How much brighter the sky gets at a strike."},
	{"prop": "bolt_life", "label": "Bolt time", "min": 0.05, "max": 2.0, "step": 0.01, "fall": STORM,
		"tip": "Seconds a bolt takes to fade."},
	{"prop": "bolt_width_scale", "label": "Bolt width", "min": 0.5, "max": 20.0, "step": 0.1, "fall": STORM,
		"tip": "Times the shock attack's own bolt width. A sky bolt is far off, so it needs more."},
	{"prop": "bolt_distance", "label": "Bolt distance", "min": 1.0, "max": 40.0, "step": 0.5, "fall": STORM,
		"tip": "Cells beyond the board's edge a bolt lands."},
	{"prop": "bolt_height", "label": "Bolt height", "min": 4.0, "max": 120.0, "step": 1.0, "fall": STORM,
		"tip": "How far above the board a bolt starts."},
	{"prop": "bolt_element", "label": "Bolt colour", "options": ELEMENT_NAMES, "fall": STORM,
		"tip": "Whose colour a bolt's glow takes: a thunderstorm's is Shock, an aetheric storm's Aether."},
	{"prop": "flake_sway", "label": "Flake sway", "min": 0.0, "max": 3.0, "step": 0.05, "fall": FLAKES,
		"tip": "How far a flake wanders side to side as it falls, cells a second."},
	{"prop": "flake_swirl", "label": "Swirl", "min": 0.0, "max": 8.0, "step": 0.05, "fall": FLAKES,
		"tip": "Eddies that loop the flakes rather than letting them fall straight -- what keeps a blizzard from reading as rain."},
	{"prop": "swirl_scale", "label": "Swirl size", "min": 0.2, "max": 8.0, "step": 0.05, "fall": FLAKES,
		"tip": "How wide one eddy is, in cells."},
	{"prop": "flake_wind", "label": "Flake wind", "min": 0.0, "max": 4.0, "step": 0.05, "fall": FLAKES,
		"tip": "The share of the board's wind a flake drifts with. 1 is the wind itself; a sandstorm's specks fly faster."},
	{"prop": "big_flakes", "label": "Big flakes", "min": 0.0, "max": 1.0, "step": 0.01, "fall": FLAKES,
		"tip": "The share of flakes drawn as a plus rather than a single art pixel."},
	{"prop": "flake_color", "label": "Flake colour", "fall": FLAKES, "tip": "Colour and opacity of a flake."},
	{"prop": "flake_settle", "label": "Flake settle", "min": 0.0, "max": 4.0, "step": 0.05, "fall": FLAKES,
		"tip": "Seconds a landed flake lies on the ground before it melts away. 0 is gone on landing."},
	{"prop": "snow_cover", "label": "Ground cover", "min": 0.0, "max": 1.0, "step": 0.01, "fall": COVER,
		"tip": "How much of the ground lies under the snow, sand or ash: low leaves clumps, mid lies in patches, high covers nearly all. Never on water or a hole, and never past a tile."},
	{"prop": "slope_cover", "label": "Slopes keep", "min": 0.0, "max": 1.0, "step": 0.01, "fall": COVER,
		"tip": "The share of the cover a ramp or a hillside keeps: it slides off, so a low value shows the hills by their thin sides. 1 treats a slope like flat ground."},
	{"prop": "snow_frost", "label": "Frost", "min": 0.0, "max": 1.0, "step": 0.01, "fall": COVER,
		"tip": "A faint wash of the cover's colour over all the ground it could lie on."},
	{"prop": "snow_flecks", "label": "Flecks", "min": 0.0, "max": 0.3, "step": 0.005, "fall": COVER,
		"tip": "The share of the ground's art pixels flecked with the cover's colour between the patches."},
	{"prop": "snow_color", "label": "Cover colour", "fall": COVER,
		"tip": "The cover's colour: on the ground and on the props' caps. The units' caps have their own colour."},
	{"prop": "snow_roughness", "label": "Cover gloss", "min": 0.0, "max": 1.0, "step": 0.01, "fall": COVER,
		"tip": "The cover's roughness: 1 is matte powder, lower catches the light like a crust."},
	{"prop": "snow_relief", "label": "Relief", "min": 0.0, "max": 20.0, "step": 0.1, "fall": COVER,
		"tip": "How much the cover stands up off the ground: patch edges and lumps catch the light and cast a little shade. 0 is flat."},
	{"prop": "relief_softness", "label": "Edge softness", "min": 0.0, "max": 3.0, "step": 0.1, "fall": COVER,
		"tip": "How many art pixels a patch's edge slopes over. 0 is a sharp step."},
	{"prop": "snow_bumps", "label": "Lumps", "min": 0.0, "max": 1.0, "step": 0.01, "fall": COVER,
		"tip": "How lumpy the top of the cover is. 0 is smooth."},
	{"prop": "bump_size", "label": "Lump size", "min": 2.0, "max": 16.0, "step": 0.5, "fall": COVER,
		"tip": "How wide one lump is, in art pixels."},
	{"prop": "caps_props", "label": "Caps on props", "fall": CAPS,
		"tip": "The cover on the tops of rocks, walls, crates, barrels, trees and lanterns. Tall grass and flowers hide in any snow or ash."},
	{"prop": "caps_units", "label": "Caps on units", "fall": CAPS,
		"tip": "The cover on every unit's head and shoulders. A look only: no rule is behind it yet."},
	{"prop": "unit_cap_color", "label": "Unit cap colour", "fall": CAPS,
		"tip": "The colour of the cover on the units' heads, chosen to stand out against the ground: snow's is ice blue."},
	{"prop": "breath", "label": "Breath", "fall": Fall.SNOW,
		"tip": "Every standing unit's breath fogs, the puff a Chilled unit breathes. A look only."},
	{"prop": "drift_rate", "label": "Ground drift", "min": 0.0, "max": 8.0, "step": 0.05, "fall": DRIFT,
		"tip": "Streaks of loose snow, sand or ash blown along the ground, per cell of view per second. 0 is none."},
	{"prop": "drift_speed", "label": "Drift speed", "min": 0.5, "max": 20.0, "step": 0.1, "fall": DRIFT,
		"tip": "How fast the loose stuff streams along the wind, cells a second."},
	{"prop": "drift_texels", "label": "Drift length", "min": 1.0, "max": 16.0, "step": 1.0, "fall": DRIFT,
		"tip": "How long a streak of it is, in art pixels."},
	{"prop": "drift_life", "label": "Drift time", "min": 0.1, "max": 3.0, "step": 0.05, "fall": DRIFT,
		"tip": "Seconds a streak lives; it fades in and out."},
	{"prop": "drift_color", "label": "Drift colour", "fall": DRIFT, "tip": "Colour and opacity of the loose stuff."},
	{"prop": "grit_rate", "label": "Grit", "min": 0.0, "max": 12.0, "step": 0.05, "fall": GRIT,
		"tip": "Streaks of sand flying through the air, born per cell of the board per second. None on a calm board, where only the specks swirl."},
	{"prop": "grit_share", "label": "Grit speed", "min": 0.0, "max": 8.0, "step": 0.05, "fall": GRIT,
		"tip": "Times the board's wind a streak flies at."},
	{"prop": "grit_height", "label": "Grit height", "min": 0.0, "max": 4.0, "step": 0.05, "fall": GRIT,
		"tip": "How high over the ground a streak flies, in cells, at most. Most fly low."},
	{"prop": "grit_texels", "label": "Grit length", "min": 1.0, "max": 16.0, "step": 1.0, "fall": GRIT,
		"tip": "How long a streak is, in art pixels."},
	{"prop": "grit_life", "label": "Grit time", "min": 0.1, "max": 4.0, "step": 0.05, "fall": GRIT,
		"tip": "Seconds a streak lives; it fades in and out."},
	{"prop": "grit_color", "label": "Grit colour", "fall": GRIT, "tip": "Colour and opacity of a streak."},
	{"prop": "fog_strength", "label": "Fog strength", "min": 0.0, "max": 6.0, "step": 0.05, "fall": HAZE,
		"tip": "How thick the fog pass under the cards is. The cards carry the look; this is the soft body between them. On a sandstorm, the dust."},
	{"prop": "layer_amount", "label": "Ground layer", "min": 0.0, "max": 1.0, "step": 0.01, "fall": HAZE,
		"tip": "A low sheet of fog over every surface, high ground and low alike. 0 is none."},
	{"prop": "layer_depth", "label": "Layer depth", "min": 0.05, "max": 3.0, "step": 0.05, "fall": HAZE,
		"tip": "How high the sheet stands over its own ground, in cells. A unit is about one tall."},
	{"prop": "pool_amount", "label": "Pooling", "min": 0.0, "max": 1.0, "step": 0.01, "fall": HAZE,
		"tip": "Fog lying in the low ground, with the high ground standing clear. 0 is none."},
	{"prop": "pool_share", "label": "Low ground share", "min": 0.0, "max": 1.0, "step": 0.01, "fall": HAZE,
		"tip": "How much of the board counts as low ground, lowest first: the fog pools on that share of its surfaces."},
	{"prop": "pool_depth", "label": "Pool depth", "min": 0.05, "max": 3.0, "step": 0.05, "fall": HAZE,
		"tip": "How deep the pooled fog stands over its own ground, in cells -- at most, so it never stands as a box over a drop."},
	{"prop": "bank_amount", "label": "Banks", "min": 0.0, "max": 1.0, "step": 0.01, "fall": HAZE,
		"tip": "Big drifting patches of fog, tall enough to swallow units, with clearer ground between. 0 is none."},
	{"prop": "bank_height", "label": "Bank height", "min": 0.2, "max": 4.0, "step": 0.05, "fall": HAZE,
		"tip": "How tall a bank stands over its ground, in cells."},
	{"prop": "bank_size", "label": "Bank size", "min": 2.0, "max": 24.0, "step": 0.5, "fall": HAZE,
		"tip": "Roughly how many cells across one bank is."},
	{"prop": "fog_breakup", "label": "Breakup", "min": 0.0, "max": 1.0, "step": 0.01, "fall": HAZE,
		"tip": "How much drifting noise thins the fog in places. 0 is an even sheet."},
	{"prop": "edge_fade", "label": "Edge fade", "min": 0.0, "max": 6.0, "step": 0.1, "fall": HAZE,
		"tip": "Over how many cells the fog thins out before the board's edge or a hole, so it never hangs over nothing."},
	{"prop": "water_haze", "label": "Over water", "min": 0.0, "max": 1.0, "step": 0.01, "fall": HAZE,
		"tip": "The share of the fog that stands over water. 1 is as thick as over ground; lower keeps the river clear."},
	{"prop": "pixel_steps", "label": "Pixel steps", "fall": HAZE,
		"tip": "Snaps the fog pass to the ground's art pixels and steps its opacity, so its edges read as pixel art."},
	{"prop": "fog_color", "label": "Fog colour", "fall": HAZE, "tip": "The colour of the fog, the cards and the pass alike. On a sandstorm, the dust's."},
	{"prop": "sky_tint", "label": "Takes the sky", "min": 0.0, "max": 1.0, "step": 0.01, "fall": HAZE,
		"tip": "How far the fog takes the colour of the board's sky at the horizon, so a night fog darkens and a dusk one warms. The sky is read, never changed."},
	{"prop": "card_amount", "label": "Cards", "min": 0.0, "max": 6.0, "step": 0.05, "fall": HAZE,
		"tip": "How many pixel fog cards drift over each cell of the board. They only show where there is fog."},
	{"prop": "card_opacity", "label": "Card opacity", "min": 0.0, "max": 1.0, "step": 0.01, "fall": HAZE,
		"tip": "How solid a card is at its thickest."},
	{"prop": "card_size", "label": "Card size", "min": 0.25, "max": 4.0, "step": 0.05, "fall": HAZE,
		"tip": "Times a wisp's own size. 1 draws it at the ground tiles' pixel size."},
	{"prop": "card_life", "label": "Card life", "min": 1.0, "max": 30.0, "step": 0.5, "fall": HAZE,
		"tip": "Seconds a card takes to fade in, drift and fade out."},
	{"prop": "card_lift", "label": "Card height", "min": 0.0, "max": 3.0, "step": 0.05, "fall": HAZE,
		"tip": "How high over the ground a card floats, in cells, at most. Higher cards cross more of a unit."},
	{"prop": "card_sink", "label": "Card sink", "min": 0.02, "max": 3.0, "step": 0.01, "fall": HAZE,
		"tip": "How fast a card sinks when it drifts off higher ground, in cells a second at most. Low values let fog spill slowly off a ledge."},
	{"prop": "card_dissolve", "label": "Card dissolve", "min": 0.1, "max": 5.0, "step": 0.05, "fall": HAZE,
		"tip": "Seconds a card takes to fade out when it meets higher ground or drifts past the board's edge."},
	{"prop": "fog_speed", "label": "Fog drift", "min": 0.0, "max": 2.0, "step": 0.01, "fall": HAZE,
		"tip": "The share of the wind the fog drifts with, its cards and its banks alike. 0 hangs still."},
	{"prop": "glow_strength", "label": "Glow", "min": 0.0, "max": 3.0, "step": 0.01, "fall": Fall.AURORA,
		"tip": "How bright the curtains of light on the ground are. They add light; they never darken."},
	{"prop": "bands", "label": "Curtains", "min": 1.0, "max": 6.0, "step": 1.0, "fall": Fall.AURORA,
		"tip": "How many curtains of light lie across the board."},
	{"prop": "band_width", "label": "Curtain width", "min": 0.2, "max": 6.0, "step": 0.05, "fall": Fall.AURORA,
		"tip": "How wide one curtain is, in cells."},
	{"prop": "band_spacing", "label": "Curtain spacing", "min": 1.0, "max": 20.0, "step": 0.1, "fall": Fall.AURORA,
		"tip": "How far apart the curtains lie, in cells."},
	{"prop": "band_wave", "label": "Curtain swing", "min": 0.0, "max": 10.0, "step": 0.05, "fall": Fall.AURORA,
		"tip": "How far a curtain swings either side of its line, in cells. 0 lays it straight."},
	{"prop": "wave_length", "label": "Swing length", "min": 2.0, "max": 60.0, "step": 0.5, "fall": Fall.AURORA,
		"tip": "How long one swing of a curtain is, in cells."},
	{"prop": "band_angle", "label": "Curtain angle", "min": 0.0, "max": 180.0, "step": 1.0, "fall": Fall.AURORA,
		"tip": "The angle the curtains lie at across the board, in degrees."},
	{"prop": "ripple_speed", "label": "Ripple speed", "min": 0.0, "max": 5.0, "step": 0.01, "fall": Fall.AURORA,
		"tip": "How fast the curtains ripple and their rays drift along them. The aetheric storm's run fastest."},
	{"prop": "ray_strength", "label": "Rays", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.AURORA,
		"tip": "How much bright and dim rays break a curtain up along its length. 0 is an even band."},
	{"prop": "ray_spacing", "label": "Ray spacing", "min": 0.1, "max": 4.0, "step": 0.05, "fall": Fall.AURORA,
		"tip": "How far apart the rays are, in cells."},
	{"prop": "curtain_pixels", "label": "Curtain pixel steps", "fall": Fall.AURORA,
		"tip": "Snaps the curtains to the ground's art pixels and steps their glow, so they read as pixel art. Off draws them soft."},
	{"prop": "scheme_a_low", "label": "Scheme A colour", "fall": Fall.AURORA,
		"tip": "The first colour scheme: the colour at a curtain's heart."},
	{"prop": "scheme_a_fringe", "label": "Scheme A fringe", "fall": Fall.AURORA,
		"tip": "The first colour scheme: the colour at a curtain's edge, which the motes take too."},
	{"prop": "scheme_b_low", "label": "Scheme B colour", "fall": Fall.AURORA,
		"tip": "The second colour scheme: the colour at a curtain's heart."},
	{"prop": "scheme_b_fringe", "label": "Scheme B fringe", "fall": Fall.AURORA,
		"tip": "The second colour scheme: the colour at a curtain's edge."},
	{"prop": "scheme_c_low", "label": "Scheme C colour", "fall": Fall.AURORA,
		"tip": "The third colour scheme: the colour at a curtain's heart."},
	{"prop": "scheme_c_fringe", "label": "Scheme C fringe", "fall": Fall.AURORA,
		"tip": "The third colour scheme: the colour at a curtain's edge."},
	{"prop": "scheme_seconds", "label": "Scheme time", "min": 1.0, "max": 120.0, "step": 0.5, "fall": Fall.AURORA,
		"tip": "Seconds each colour scheme lasts before the next, A then B then C and round again. The curtains, the light and the motes change together."},
	{"prop": "scheme_blend", "label": "Scheme blend", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.AURORA,
		"tip": "The share of a scheme's time spent blending into the next. 0 cuts straight across; 1 is always blending."},
	{"prop": "light_energy", "label": "Aurora light", "min": 0.0, "max": 8.0, "step": 0.05, "fall": Fall.AURORA,
		"tip": "How brightly the aurora lights the units, props and ground, in its own colours."},
	{"prop": "light_pulse", "label": "Pulse", "min": 0.0, "max": 1.0, "step": 0.01, "fall": Fall.AURORA,
		"tip": "How far the light and the curtains slowly swell and ebb. The photosensitivity setting holds it still."},
	{"prop": "light_elevation", "label": "Light angle", "min": 5.0, "max": 85.0, "step": 1.0, "fall": Fall.AURORA,
		"tip": "Degrees above the horizon the aurora's light comes in at, always from in front of the camera so it reaches the units' faces."},
	{"prop": "mote_shape", "label": "Motes", "options": ["Dots", "Streaks"], "fall": MOTES,
		"tip": "What rises off the ground: slow dots, or thin streaks that rise fast."},
	{"prop": "mote_rate", "label": "Motes per cell", "min": 0.0, "max": 3.0, "step": 0.01, "fall": MOTES,
		"tip": "How many motes rise off each cell of the board every second: an aurora's motes, an ashfall's embers. 0 is none."},
	{"prop": "mote_rise", "label": "Mote rise", "min": 0.02, "max": 4.0, "step": 0.01, "fall": MOTES,
		"tip": "How fast a mote rises, in cells a second. It drifts with the wind too."},
	{"prop": "mote_life", "label": "Mote life", "min": 0.2, "max": 12.0, "step": 0.1, "fall": MOTES,
		"tip": "Seconds a mote takes to fade in, rise and fade out."},
	{"prop": "mote_height", "label": "Mote height", "min": 0.0, "max": 3.0, "step": 0.05, "fall": MOTES,
		"tip": "How high over the ground a mote is born, in cells, at most."},
	{"prop": "mote_size", "label": "Mote size", "min": 0.5, "max": 4.0, "step": 0.25, "fall": MOTES,
		"tip": "Times a mote's own size, a dot of two art pixels or a thin streak."},
	{"prop": "mote_color", "label": "Mote colour", "fall": [Fall.ASH],
		"tip": "The embers' colour. An aurora's motes take its colour cycle instead."},
	{"prop": "grade_saturation", "label": "Grade saturation", "min": 0.0, "max": 1.5, "step": 0.01,
		"tip": "The weather's own grade over the board's look: 1 leaves the colours, lower greys them. The HUD is never graded."},
	{"prop": "grade_brightness", "label": "Grade brightness", "min": 0.5, "max": 1.5, "step": 0.01,
		"tip": "The weather's grade: how much brighter or darker the board is drawn."},
	{"prop": "grade_tint", "label": "Grade tint", "tip": "A colour mixed over the board; its alpha is how much. The cold of a snowfall, the warmth of a sandstorm."},
	{"prop": "veil", "label": "Whiteout", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "A whiteout drifting across the view, in slow bands. 0 is none."},
	{"prop": "veil_speed", "label": "Whiteout speed", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "How fast the whiteout's bands drift, screen widths a second. They drift with the wind."},
	{"prop": "veil_color", "label": "Whiteout colour", "tip": "The whiteout's colour."},
	{"prop": "grade_fade", "label": "Grade fade", "min": 0.0, "max": 6.0, "step": 0.05,
		"tip": "Seconds the grade, the whiteout and an aurora take to come in when the weather changes, and to go."},
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


# Whether a ROWS entry belongs on a look of this fall: a row names one fall, or a list of them.
static func row_shows(row: Dictionary, fall: Fall) -> bool:
	if not row.has("fall"):
		return true
	if row["fall"] is Array:
		return (row["fall"] as Array).has(fall)
	return int(row["fall"]) == fall


# Whether this look grades the picture at all: identity draws nothing.
func grades() -> bool:
	return not is_equal_approx(grade_saturation, 1.0) or not is_equal_approx(grade_brightness, 1.0) \
			or grade_tint.a > 0.001 or veil > 0.001
