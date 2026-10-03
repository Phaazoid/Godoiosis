extends Resource
class_name GasLook

# How one gas looks (#508), in every mix the Experiments page can switch between: the volume's
# medium (what the march draws) and the pixel art (the puffs, their motion and the fog floor). One
# file per Gas.Kind under Resources/GasLooks/, named for the kind, so a look is found where the kind
# is spelled. Tuned in the inspector for now.
#
# Dumb data. GasMirror packs the volume half for the GPU and GasPuffArt draws the pixel half.

const FOLDER := "res://Resources/GasLooks/"

enum PuffShape { CUMULUS, PLUME, MOUND, STRATUS, STORM, CURL }
enum FloorPattern { DOTS, HATCH, BUBBLES, FLAKES, ZIGZAG, WAVES }
enum Extra { WISP, SOOT, BUBBLE, SNOW, BOLT, CURL }

@export_group("Volume")
@export var albedo := Color(0.96, 0.97, 1.0)
@export var extinction := 5.0             # how thick a unit of it is
@export var base_height := 0.2            # world units the thinnest gas stands
@export var column_height := 1.8          # extra height at full amount
@export var top_softness := 0.75          # how much of the column fades out up top
@export var shape_scale := 0.32           # billow noise frequency
@export var stretch := 0.65               # < 1 plumes, > 1 flat sheets
@export var erosion := 0.7                # how ragged the billow edges are
@export var rise_speed := 0.35            # world units a second the billows climb (negative sinks)
@export var coverage_boost := 1.4         # how much of the column the billows fill
@export var pool_height := 0.12           # the crisp layer on the cells, world units deep
@export var pool_density := 0.35
@export var wind := Vector2(0.05, 0.03)   # drift on x / z, world units a second
@export var emission := Color(0, 0, 0)    # a gas's own glow
@export var flash := 0.0                  # 1 = lightning strikes inside it

@export_group("Pixel art")
@export var palette_light := Color(1, 1, 1)
@export var palette_mid := Color(0.88, 0.91, 0.97)
@export var palette_dark := Color(0.74, 0.79, 0.90)
@export var palette_ink := Color(0.58, 0.64, 0.78)
@export var puff_shape := PuffShape.CUMULUS
@export var floor_pattern := FloorPattern.DOTS
@export var extra := Extra.WISP
@export var soft := false                 # no outline, a dithered fringe instead (dark gases)
@export var boil_seconds := 0.8           # how often a puff swaps to its next drawing
@export var bob := Vector2(1.2, 1.6)      # art pixels of bob, and its rate
@export var sway := 0.0                   # art pixels of side-to-side drift


static var _looks_by_kind: Dictionary = {}


static func for_kind(kind: Gas.Kind) -> GasLook:
	if not _looks_by_kind.has(kind):
		var path := FOLDER + Gas.name_of(kind) + ".tres"
		var look := load(path) as GasLook if ResourceLoader.exists(path) else null
		if look == null:
			push_error("GasLook: no look at %s" % path)
			look = GasLook.new()
		_looks_by_kind[kind] = look
	return _looks_by_kind[kind]


func palette() -> Array[Color]:
	return [palette_light, palette_mid, palette_dark, palette_ink]
