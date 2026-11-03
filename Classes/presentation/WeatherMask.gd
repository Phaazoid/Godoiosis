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
# the one place the encoding and Terrain.height_at_uv are proved to agree. texel() is the one
# encoding, which a whole build and WeatherMirror's per-cell placement (#1562) both write.

const VOID := -100000.0
# Anything below this is a hole; the shaders spell the same threshold.
const VOID_BELOW := -10000.0

# Whole-mask passes (a build or a gather), counted for the suite (#1562): a flight must re-place its
# own cells, never walk the board.
static var board_walks := 0


# The mask over `rect` (cells). `offset_of` answers where a cell renders relative to the board --
# BoardSpace.drawn_offset in the game -- so a fight torn out onto the stage is rained on up there.
static func build(grid: TileMapLayer, heights: BoardHeights, rect: Rect2i,
		offset_of: Callable) -> Image:
	board_walks += 1
	var w := maxi(rect.size.x, 1)
	var h := maxi(rect.size.y, 1)
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBAF)
	image.fill(Color(VOID, VOID, VOID, VOID))
	if grid == null:
		return image
	for y in rect.size.y:
		for x in rect.size.x:
			var cell := rect.position + Vector2i(x, y)
			if GridUtils.has_surface(grid, cell):
				image.set_pixel(x, y, _surface_texel(heights, cell, offset_of))
	return image


# One cell's texel: its corners where it is drawn, or VOID with no surface.
static func texel(grid: TileMapLayer, heights: BoardHeights, cell: Vector2i, offset_of: Callable) -> Color:
	if grid == null or not GridUtils.has_surface(grid, cell):
		return Color(VOID, VOID, VOID, VOID)
	return _surface_texel(heights, cell, offset_of)


static func _surface_texel(heights: BoardHeights, cell: Vector2i, offset_of: Callable) -> Color:
	var corners := heights.corners_at(cell) if heights != null else Vector4i.ZERO
	var lift := 0.0
	if offset_of.is_valid():
		lift = (offset_of.call(cell) as Vector3).y
	return Color(
		BoardSpace.world_y_of_height(corners.x) + lift,
		BoardSpace.world_y_of_height(corners.y) + lift,
		BoardSpace.world_y_of_height(corners.z) + lift,
		BoardSpace.world_y_of_height(corners.w) + lift)


# Re-write one cell of a mask built over `rect`, as build() would: a cell whose only change is where
# it is drawn. A cell off the rect is left alone.
static func write(image: Image, grid: TileMapLayer, heights: BoardHeights, rect: Rect2i,
		offset_of: Callable, cell: Vector2i) -> void:
	if rect.has_point(cell):
		image.set_pixelv(cell - rect.position, texel(grid, heights, cell, offset_of))


# The lowest and highest ground a mask holds, world units, as (low, high): the slab the fog pass
# marches (#1285). (0, 0) when the mask holds no ground.
static func span(image: Image) -> Vector2:
	return settled(gather(image, Rect2i(), {}))


# span() before settling -- (INF, -INF) holds no ground -- with `skip`'s cells (over `rect`) left out.
# _fold_texel inlined: this is the whole-board loop.
static func gather(image: Image, rect: Rect2i, skip: Dictionary[Vector2i, bool]) -> Vector2:
	board_walks += 1
	var low := INF
	var high := -INF
	var skipping := not skip.is_empty()
	for y in image.get_height():
		for x in image.get_width():
			if skipping and skip.has(rect.position + Vector2i(x, y)):
				continue
			var c := image.get_pixel(x, y)
			if c.r < VOID_BELOW:
				continue
			low = minf(low, minf(minf(c.r, c.g), minf(c.b, c.a)))
			high = maxf(high, maxf(maxf(c.r, c.g), maxf(c.b, c.a)))
	return Vector2(low, high)


# One cell's texel folded into a gathered span.
static func fold(image: Image, rect: Rect2i, cell: Vector2i, into: Vector2) -> Vector2:
	if not rect.has_point(cell):
		return into
	return _fold_texel(image.get_pixelv(cell - rect.position), into)


# A gathered span as span() answers it.
static func settled(gathered: Vector2) -> Vector2:
	return Vector2.ZERO if gathered.x == INF else gathered


static func _fold_texel(c: Color, into: Vector2) -> Vector2:
	if c.r < VOID_BELOW:
		return into
	return Vector2(minf(into.x, minf(minf(c.r, c.g), minf(c.b, c.a))),
			maxf(into.y, maxf(maxf(c.r, c.g), maxf(c.b, c.a))))


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
