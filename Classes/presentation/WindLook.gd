extends Resource
class_name WindLook

# How one wind strength looks (#1286), one file per Wind.Kind under Resources/WindLooks/ named for the
# strength -- WeatherLook's shape. Dumb data: the weathers, WindMirror, the plants and the gas all read
# it, and the dev tools' Weather page tunes it live and saves it. CALM has no file and blows nothing.
#
# vector() is the ONE composition of the board's wind: every reader asks it rather than multiplying a
# speed by a heading itself.

const FOLDER := "res://Resources/WindLooks/"

@export_group("Wind")
@export var speed := 1.5                    # world units a second it blows
@export var gust := 0.35                    # 0..1: how far the wind rises and falls
@export var gust_period := 4.0              # seconds from one gust to the next

@export_group("Sway")
@export var sway_lean := 0.12               # how far a plant's top leans along the wind, times its height
@export var sway_flutter := 0.04            # how far it rocks back and forth, times its height
@export var sway_speed := 1.6               # rocks a second

@export_group("Specks")
@export var speck_rate := 0.25              # specks born per cell of view per second
@export var speck_speed := 1.0              # times the wind a speck flies at
@export var speck_life := 2.5               # seconds a speck lives
@export var speck_flutter := 0.6            # world units a second it tumbles side to side
@export var speck_height := 1.2             # world units above the ground a speck flies, at most
@export var speck_leaves := 0.5             # 0..1: the share drawn as leaves rather than dust
@export var leaf_color := Color(0.62, 0.66, 0.3, 0.95)
@export var dust_color := Color(0.85, 0.8, 0.68, 0.7)

@export_group("Cloud shadows")
@export var cloud_cover := 0.35             # 0..1: the share of the ground under shadow
@export var cloud_darkness := 0.22          # 0..1: how dark a shadow is at its heart
@export var cloud_size := 10.0              # cells across one cloud
@export var cloud_softness := 0.12          # 0..1: how soft a shadow's edge is
@export var cloud_speed := 0.2              # share of the wind the shadows drift at
@export var cloud_pixels := true            # edges snapped to the ground's art pixels


# The Weather page's rows, in the order drawn. Declared beside the fields they name, WeatherLook.ROWS's
# shape; `test_weather_tool` refuses a field with none.
const ROWS: Array[Dictionary] = [
	{"prop": "speed", "label": "Wind speed", "min": 0.0, "max": 12.0, "step": 0.05,
		"tip": "How fast this wind blows, in cells a second. Slants the rain, carries the snow and the fog, and drives everything else on this page."},
	{"prop": "gust", "label": "Gusts", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How far the wind rises and falls. The plants lean harder in a gust and the specks thicken. 0 blows steady."},
	{"prop": "gust_period", "label": "Gust time", "min": 0.5, "max": 20.0, "step": 0.1,
		"tip": "Seconds from one gust to the next."},
	{"prop": "sway_lean", "label": "Plant lean", "min": 0.0, "max": 0.6, "step": 0.005,
		"tip": "How far grass, flowers and trees lean along the wind, times their own height."},
	{"prop": "sway_flutter", "label": "Plant rock", "min": 0.0, "max": 0.3, "step": 0.005,
		"tip": "How far a plant rocks back and forth on top of its lean, times its height."},
	{"prop": "sway_speed", "label": "Rock speed", "min": 0.1, "max": 6.0, "step": 0.05,
		"tip": "How many times a second a plant rocks."},
	{"prop": "speck_rate", "label": "Specks", "min": 0.0, "max": 4.0, "step": 0.01,
		"tip": "Leaves and dust blown across the board, born per cell of view every second. 0 is none."},
	{"prop": "speck_speed", "label": "Speck speed", "min": 0.1, "max": 3.0, "step": 0.05,
		"tip": "How fast a speck flies, times the wind."},
	{"prop": "speck_life", "label": "Speck time", "min": 0.3, "max": 8.0, "step": 0.05,
		"tip": "Seconds a speck lives; it fades in and out."},
	{"prop": "speck_flutter", "label": "Speck tumble", "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How far a speck tumbles side to side as it flies, cells a second."},
	{"prop": "speck_height", "label": "Speck height", "min": 0.1, "max": 4.0, "step": 0.05,
		"tip": "How high over the ground a speck flies, in cells, at most."},
	{"prop": "speck_leaves", "label": "Leaf share", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "The share of specks drawn as leaves rather than dust. 1 is all leaves, 0 all dust."},
	{"prop": "leaf_color", "label": "Leaf colour", "tip": "Colour and opacity of a blown leaf."},
	{"prop": "dust_color", "label": "Dust colour", "tip": "Colour and opacity of a blown dust mote."},
	{"prop": "cloud_cover", "label": "Cloud cover", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "The share of the ground under a passing cloud's shadow. 0 is none."},
	{"prop": "cloud_darkness", "label": "Shadow darkness", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How dark a cloud's shadow is at its heart."},
	{"prop": "cloud_size", "label": "Cloud size", "min": 2.0, "max": 40.0, "step": 0.5,
		"tip": "Roughly how many cells across one cloud's shadow is."},
	{"prop": "cloud_softness", "label": "Shadow softness", "min": 0.0, "max": 0.5, "step": 0.005,
		"tip": "How soft a shadow's edge is. 0 is a hard edge."},
	{"prop": "cloud_speed", "label": "Cloud drift", "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "The share of the wind the shadows drift at. Clouds are far off, so their shadows move slower than the specks."},
	{"prop": "cloud_pixels", "label": "Pixel shadows",
		"tip": "Snaps a shadow's edge to the ground's art pixels, so it reads as pixel art."},
]


static var _looks_by_kind: Dictionary = {}


# This strength's look, or null when it has none (CALM). Cached for the process, so the Weather page
# edits the object everything draws from.
static func for_kind(kind: Wind.Kind) -> WindLook:
	if kind == Wind.Kind.CALM:
		return null
	if not _looks_by_kind.has(kind):
		var path := path_of(kind)
		_looks_by_kind[kind] = load(path) as WindLook if ResourceLoader.exists(path) else null
	return _looks_by_kind[kind]


static func path_of(kind: Wind.Kind) -> String:
	return FOLDER + Wind.name_of(kind) + ".tres"


# The board's wind, world units a second on x / z: this strength's speed along the direction. Zero
# when calm, or when the strength has no look.
static func vector(kind: Wind.Kind, direction: Wind.Direction) -> Vector2:
	var look := for_kind(kind)
	return Wind.heading(direction) * look.speed if look != null else Vector2.ZERO
