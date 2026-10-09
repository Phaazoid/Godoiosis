extends Object
class_name SnowGround

# What the snow does to the ground's LOOK (#1269, #1278): one texture for a board-sized decal, painted at
# the ground art's own density like WetGround's, so its edges step with the tiles, and a normal map for
# the same decal so the patches stand up off the ground.
#
# Snow lies where rain wets (WetGround.is_wettable: ground, and not water) and each cell paints only
# inside its own block, so nothing lies past its tile or over a hole (dev, 2026-10-09: "no patch past
# its tile or over nothing"). Within that, three knobs make the strengths:
#
#   - COVER: a board-space noise sampled per art pixel, so patches flow across neighbouring cells and
#     stop dead at water and holes; cover is how much of it lies under snow, with a dithered edge. Low
#     leaves clumps, mid lies in patches, high covers nearly all.
#   - FROST: a faint whitening over every cell the snow could lie on.
#   - FLECKS: a sparse sprinkle of single white pixels between the patches.
#
# A slope (any cell whose corners differ) keeps only slope_cover of the cover: snow slides off a ramp or
# a hill's flank, so the hills read by their thin sides (#1278). relief() then raises what lies under
# snow, roughens its top with bumps, and turns that height into the decal's normal map.
#
# Fixed per art pixel (fire's seed policy): a board snows in the same places at every rebuild, and a
# higher cover is a SUPERSET of a lower one, so a slider grows the patches rather than reshuffling
# them. The noise is the engine's (FastNoiseLite.get_image, native, offset to the board pixel) because
# a per-pixel GDScript noise cost seconds on a large board; what is left here is one threshold pass.
# The decal's texture is a REASSIGNED ImageTexture of what this returns.

const PX := WetGround.PX
# The noise's patch size in art pixels, and the finer ragging of its edges (a second octave).
const PATCH := 9.0
const RAG := 3.0
const RAG_WEIGHT := 0.3
const SEED := 1269
# How wide the dithered edge is, in noise units (0..1).
const EDGE := 0.06
# How opaque full frost is: frost whitens, it never covers.
const FROST_ALPHA := 0.45
# A patch's lower rim is shaded by this much, so a patch reads as lying ON the ground.
const RIM_SHADE := 0.1

const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const BUMP_SEED := 1278


# heights may be null: a board with no heights has no slopes.
static func paint_cover(grid: TileMapLayer, heights: BoardHeights, rect: Rect2i, cover: float,
		slope_cover: float, frost: float, flecks: float, color: Color) -> Image:
	var size := WetGround.image_size(rect)
	var w := size.x
	var origin := rect.position * PX
	var field := _noise(origin, size, 1.0 / PATCH, 2).get_data()
	var specks := _noise(origin, size, 1.0, 1).get_data()
	# Thresholds in the 0..255 the noise images hold.
	var flat_threshold := _threshold(cover)
	var slope_threshold := _threshold(cover * clampf(slope_cover, 0.0, 1.0))
	var band := 2.0 * EDGE * 255.0
	var fleck_below := clampf(flecks, 0.0, 1.0) * 255.0
	var dither: Array[float] = []
	for b: int in BAYER:
		dither.append((float(b) + 0.5) / 16.0)
	# Pass 1: which art pixels lie under snow, and which only take frost or a fleck. 0 = untouched.
	var state := PackedByteArray()
	state.resize(w * size.y)
	var ground := PackedByteArray()
	ground.resize(rect.size.x * rect.size.y)
	for cy in rect.size.y:
		for cx in rect.size.x:
			var cell := rect.position + Vector2i(cx, cy)
			if not WetGround.is_wettable(grid, cell):
				continue
			ground[cy * rect.size.x + cx] = 1
			var threshold := slope_threshold if heights != null and heights.is_ramp(cell) else flat_threshold
			for py in PX:
				var y := cy * PX + py
				var by := origin.y + y
				var row := y * w
				for px in PX:
					var x := cx * PX + px
					var i := row + x
					var level := (float(field[i]) - threshold) / band
					var snowy := level >= 1.0 or (level > 0.0 and level > dither[((by & 3) << 2) | ((origin.x + x) & 3)])
					if snowy:
						state[i] = 3
					elif float(specks[i]) < fleck_below:
						state[i] = 2
					else:
						state[i] = 1
	# Pass 2: colour. A snow pixel with no snow under it is the patch's lower rim.
	var bytes := PackedByteArray()
	bytes.resize(w * size.y * 4)
	var snow := [color.r8, color.g8, color.b8]
	var rim_color := color.darkened(RIM_SHADE)
	var rim := [rim_color.r8, rim_color.g8, rim_color.b8]
	var frost_a := int(clampf(frost, 0.0, 1.0) * FROST_ALPHA * 255.0)
	var height := size.y
	for i in state.size():
		var s := state[i]
		if s == 0:
			continue
		var at := i * 4
		if s == 3:
			var below := i + w
			var lies := below < w * height and state[below] == 3
			var ink: Array = snow if lies else rim
			bytes[at] = ink[0]
			bytes[at + 1] = ink[1]
			bytes[at + 2] = ink[2]
			bytes[at + 3] = 255
		elif s == 2 or frost_a > 0:
			bytes[at] = snow[0]
			bytes[at + 1] = snow[1]
			bytes[at + 2] = snow[2]
			bytes[at + 3] = 255 if s == 2 else frost_a
	return Image.create_from_data(w, height, false, Image.FORMAT_RGBA8, bytes)


# The cover's normal map: every pixel under snow (full alpha) stands up, its top roughened by bumps
# (0..1, lumps bump_size art pixels across, keyed to the board like the patches), its edge sloped over
# softness art pixels, and strength how hard the slopes tilt. origin is the cover's top-left board pixel.
static func relief(cover_image: Image, origin: Vector2i, strength: float, softness: float, bumps: float,
		bump_size: float) -> Image:
	var size := cover_image.get_size()
	var cover := cover_image.duplicate() as Image
	if cover.get_format() != Image.FORMAT_RGBA8:
		cover.convert(Image.FORMAT_RGBA8)
	var data := cover.get_data()
	var lumps := _bumps(origin, size, bump_size).get_data()
	var depth := clampf(bumps, 0.0, 1.0)
	var height := PackedByteArray()
	height.resize(size.x * size.y)
	for i in height.size():
		if data[i * 4 + 3] == 255:
			height[i] = int(255.0 - depth * float(lumps[i]))
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, height)
	if softness > 0.0:
		var scale := 1.0 + softness
		image.resize(maxi(1, roundi(size.x / scale)), maxi(1, roundi(size.y / scale)), Image.INTERPOLATE_BILINEAR)
		image.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	# The engine's bump pass wraps its last row and column onto the first; a bare margin stops that.
	image.crop(size.x + 1, size.y + 1)
	image.bump_map_to_normal_map(strength)
	image.crop(size.x, size.y)
	return image


static func _threshold(cover: float) -> float:
	return ((1.0 - clampf(cover, 0.0, 1.0)) * (1.0 + 2.0 * EDGE) - 2.0 * EDGE) * 255.0


# Smooth lumps for relief(), at board position like _noise, 0..255 in an L8 image.
static func _bumps(origin: Vector2i, size: Vector2i, bump_size: float) -> Image:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = BUMP_SEED
	noise.frequency = 1.0 / maxf(bump_size, 1.0)
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.offset = Vector3(origin.x, origin.y, 0.0)
	var image := noise.get_image(size.x, size.y, false, false, false)
	if image.get_format() != Image.FORMAT_L8:
		image.convert(Image.FORMAT_L8)
	return image


# The engine's value noise over this image, one sample per art pixel at its BOARD position, 0..255 in
# an L8 image. Not normalised to the image (that would re-scale with the rect it was cut from).
static func _noise(origin: Vector2i, size: Vector2i, frequency: float, octaves: int) -> Image:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE
	noise.seed = SEED + octaves
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = PATCH / RAG
	noise.fractal_gain = RAG_WEIGHT
	noise.offset = Vector3(origin.x, origin.y, 0.0)
	var image := noise.get_image(size.x, size.y, false, false, false)
	if image.get_format() != Image.FORMAT_L8:
		image.convert(Image.FORMAT_L8)
	return image
