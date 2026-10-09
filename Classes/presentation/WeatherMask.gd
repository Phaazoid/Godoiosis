extends Object
class_name WeatherMask

# Where rain LANDS (#1260): one texel per cell holding its four corner heights in WORLD units, staged
# lift included, so the rain and splash shaders can end a drop on the surface it is falling onto and
# let one over a hole fall on out of the frame. The board-mask route BoardMirror's water mask took
# (#552), for the reason presentation-effects.md names: a continuous per-cell effect reads a mask,
# never an emitter per cell.
#
# A texel is (NW, NE, SE, SW) -- BoardHeights' own corner order -- and a hole or a cell off the board
# is every corner at VOID, which no surface reaches. surface_at() is the shader's lookup in GDScript:
# the one place the encoding and Terrain.height_at_uv are proved to agree.

const VOID := -100000.0
# Anything below this is a hole; the shaders spell the same threshold.
const VOID_BELOW := -10000.0


# The mask over `rect` (cells). `offset_of` answers where a cell renders relative to the board --
# BoardSpace.staged_offset in the game -- so a fight torn out onto the stage is rained on up there.
static func build(grid: TileMapLayer, heights: BoardHeights, rect: Rect2i,
		offset_of: Callable) -> Image:
	var w := maxi(rect.size.x, 1)
	var h := maxi(rect.size.y, 1)
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBAF)
	image.fill(Color(VOID, VOID, VOID, VOID))
	if grid == null:
		return image
	for y in rect.size.y:
		for x in rect.size.x:
			var cell := rect.position + Vector2i(x, y)
			if not GridUtils.has_surface(grid, cell):
				continue
			var corners := heights.corners_at(cell) if heights != null else Vector4i.ZERO
			var lift := 0.0
			if offset_of.is_valid():
				lift = (offset_of.call(cell) as Vector3).y
			image.set_pixel(x, y, Color(
				BoardSpace.world_y_of_height(corners.x) + lift,
				BoardSpace.world_y_of_height(corners.y) + lift,
				BoardSpace.world_y_of_height(corners.z) + lift,
				BoardSpace.world_y_of_height(corners.w) + lift))
	return image


# The lowest and highest ground a mask holds, world units, as (low, high): the slab the fog pass
# marches (#1285). (0, 0) when the mask holds no ground.
static func span(image: Image) -> Vector2:
	var low := INF
	var high := -INF
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.r < VOID_BELOW:
				continue
			low = minf(low, minf(minf(c.r, c.g), minf(c.b, c.a)))
			high = maxf(high, maxf(maxf(c.r, c.g), maxf(c.b, c.a)))
	return Vector2.ZERO if low == INF else Vector2(low, high)


# The surface a drop at world (x, z) falls onto, or VOID. Terrain.height_at_uv on the texel's corners,
# exactly as rain.gdshader and splash.gdshader evaluate it.
static func surface_at(image: Image, rect: Rect2i, x: float, z: float) -> float:
	var col := floori(x / BoardSpace.CELL_SIZE) - rect.position.x
	var row := floori(z / BoardSpace.CELL_SIZE) - rect.position.y
	if col < 0 or row < 0 or col >= image.get_width() or row >= image.get_height():
		return VOID
	var c := image.get_pixel(col, row)
	if c.r < VOID_BELOW:
		return VOID
	var u := x / BoardSpace.CELL_SIZE - floorf(x / BoardSpace.CELL_SIZE)
	var v := z / BoardSpace.CELL_SIZE - floorf(z / BoardSpace.CELL_SIZE)
	if is_equal_approx(c.g, c.a):
		if u + v <= 1.0:
			return c.r + (c.g - c.r) * u + (c.a - c.r) * v
		return c.b + (c.a - c.b) * (1.0 - u) + (c.g - c.b) * (1.0 - v)
	if v <= u:
		return c.r + (c.g - c.r) * u + (c.b - c.g) * v
	return c.r + (c.a - c.r) * v + (c.b - c.a) * u
