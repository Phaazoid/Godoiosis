extends Object
class_name SnowGround

# What the snow does to the ground's LOOK (#1269): one texture for a board-sized decal, painted at the
# ground art's own density like WetGround's, so its edges step with the tiles.
#
# Snow lies where rain wets (WetGround.is_wettable: ground, and not water) and each cell paints only
# inside its own block, so nothing lies past its tile or over a hole (dev, 2026-10-09: "no patch past
# its tile or over nothing"). Within that, three knobs make the strengths:
#
#   - COVER: a board-space value noise sampled per art pixel, so patches flow across neighbouring
#     cells and stop dead at water and holes; cover is how much of it lies under snow, with a dithered
#     edge. Low leaves clumps, mid lies in patches, high covers nearly all.
#   - FROST: a faint whitening over every cell the snow could lie on.
#   - FLECKS: a sparse sprinkle of single white pixels between the patches.
#
# Pure and static, and fixed per art pixel (fire's seed policy): a board snows in the same places at
# every rebuild, and a higher cover is a SUPERSET of a lower one, so a slider grows the patches rather
# than reshuffling them. The decal's texture is a REASSIGNED ImageTexture of what this returns.

const PX := WetGround.PX
# The noise's two lattices, in art pixels: the patches, and a finer ragging of their edges.
const PATCH := 9
const RAG := 3
const RAG_WEIGHT := 0.3
# How wide the dithered edge is, in noise units.
const EDGE := 0.06
# How opaque full frost is: frost whitens, it never covers.
const FROST_ALPHA := 0.45
# A patch's lower rim is shaded by this much, so a patch reads as lying ON the ground.
const RIM_SHADE := 0.1

const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


static func paint_cover(grid: TileMapLayer, rect: Rect2i, cover: float, frost: float, flecks: float,
		color: Color) -> Image:
	var size := WetGround.image_size(rect)
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y * 4)
	var origin := rect.position * PX
	var patch := _lattice(origin, size, PATCH, "snow-patch")
	var rag := _lattice(origin, size, RAG, "snow-rag")
	var threshold := (1.0 - clampf(cover, 0.0, 1.0)) * (1.0 + 2.0 * EDGE) - 2.0 * EDGE
	var rim := color.darkened(RIM_SHADE)
	var frost_a := clampf(frost, 0.0, 1.0) * FROST_ALPHA
	var ground := PackedByteArray()
	ground.resize(rect.size.x * rect.size.y)
	for cy in rect.size.y:
		for cx in rect.size.x:
			ground[cy * rect.size.x + cx] = 1 if WetGround.is_wettable(grid, rect.position + Vector2i(cx, cy)) else 0
	for cy in rect.size.y:
		for cx in rect.size.x:
			if ground[cy * rect.size.x + cx] == 0:
				continue
			# The patch runs on into the cell below unless that cell takes no snow, where its edge is a rim.
			var runs_on := cy + 1 < rect.size.y and ground[(cy + 1) * rect.size.x + cx] == 1
			for py in PX:
				for px in PX:
					var x := cx * PX + px
					var y := cy * PX + py
					var paint := Color(0, 0, 0, 0)
					if _snowy(patch, rag, origin, size, x, y, threshold):
						var below := (py + 1 < PX or runs_on) and _snowy(patch, rag, origin, size, x, y + 1, threshold)
						paint = color if below else rim
						paint.a = 1.0
					elif _fleck(origin + Vector2i(x, y)) < flecks:
						paint = Color(color.r, color.g, color.b, 1.0)
					elif frost_a > 0.0:
						paint = Color(color.r, color.g, color.b, frost_a)
					var at := (y * size.x + x) * 4
					bytes[at] = paint.r8
					bytes[at + 1] = paint.g8
					bytes[at + 2] = paint.b8
					bytes[at + 3] = paint.a8
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)


# Is this image pixel under snow? The noise against the threshold, dithered within EDGE of it.
static func _snowy(patch: Dictionary, rag: Dictionary, origin: Vector2i, size: Vector2i, x: int, y: int,
		threshold: float) -> bool:
	var n := (_sample(patch, x, y) + _sample(rag, x, y) * RAG_WEIGHT) / (1.0 + RAG_WEIGHT)
	var level := (n - threshold) / (2.0 * EDGE)
	if level >= 1.0:
		return true
	if level <= 0.0:
		return false
	var b := Vector2i(origin.x + x, origin.y + y)
	return level > (float(BAYER[(posmod(b.y, 4) << 2) + posmod(b.x, 4)]) + 0.5) / 16.0


# One art pixel's fleck roll, [0, 1), fixed per BOARD pixel.
static func _fleck(board_pixel: Vector2i) -> float:
	return float(hash([board_pixel, "snow-fleck"]) % 10000) / 10000.0


# A value-noise lattice over the image, one hashed value per `step` board pixels, keyed by BOARD
# position so the same ground snows the same however the rect is cut.
static func _lattice(origin: Vector2i, size: Vector2i, step: int, salt: String) -> Dictionary:
	var first := Vector2i(floori(float(origin.x) / step), floori(float(origin.y) / step))
	var last := Vector2i(floori(float(origin.x + size.x) / step) + 1, floori(float(origin.y + size.y) / step) + 1)
	var span := last - first + Vector2i.ONE
	var values := PackedFloat32Array()
	values.resize(span.x * span.y)
	for j in span.y:
		for i in span.x:
			values[j * span.x + i] = float(hash([first + Vector2i(i, j), salt]) % 10000) / 10000.0
	return {"first": first, "span": span, "step": step, "origin": origin, "values": values}


static func _sample(lattice: Dictionary, x: int, y: int) -> float:
	var step: int = lattice["step"]
	var origin: Vector2i = lattice["origin"]
	var first: Vector2i = lattice["first"]
	var span: Vector2i = lattice["span"]
	var values: PackedFloat32Array = lattice["values"]
	var bx := (float(origin.x + x) + 0.5) / step
	var by := (float(origin.y + y) + 0.5) / step
	var i := floori(bx) - first.x
	var j := floori(by) - first.y
	var u := _smooth(bx - floorf(bx))
	var v := _smooth(by - floorf(by))
	var a := values[j * span.x + i]
	var b := values[j * span.x + i + 1]
	var c := values[(j + 1) * span.x + i]
	var d := values[(j + 1) * span.x + i + 1]
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
