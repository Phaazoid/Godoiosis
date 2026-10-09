extends Object
class_name WetGround

# What the rain does to the ground's LOOK (#1260): two textures for two board-sized decals, painted at
# the ground art's own density (BoardOverlays.ART_PIXELS_PER_CELL) so their edges step with the tiles.
#
#   - the WET layer: every cell with ground and no water, opaque, so the decal's albedo_mix darkens it
#     and its ORM gloss is masked in at full strength (a decal's ORM rides its albedo ALPHA -- measured
#     on 4.7.1, an ORM with no albedo moves nothing);
#   - the PUDDLES: on flat, walkable, dry ground only, one per chosen cell and drawn INSIDE that cell's
#     own block with an inset, so a puddle past its tile or over a hole cannot be drawn at all (dev,
#     2026-10-08: "some of the puddles were appearing past their tiles, over nothing").
#
# Which cells puddle is fixed per CELL (fire's seed policy): a board always puddles in the same places,
# and a rebuild never reshuffles them. Pure and static; the decal's texture is a REASSIGNED
# ImageTexture of what these return, never update()d -- the decal atlas copies on assignment.

const PX := int(BoardOverlays.ART_PIXELS_PER_CELL)
# Art pixels kept clear inside a cell's block on every side, so neighbouring puddles never touch.
const INSET := 2
const STAMPS := 6


static func image_size(rect: Rect2i) -> Vector2i:
	return Vector2i(maxi(rect.size.x, 1) * PX, maxi(rect.size.y, 1) * PX)


# Can rain darken this cell? Ground that is not a hole and not water.
static func is_wettable(grid: TileMapLayer, cell: Vector2i) -> bool:
	return GridUtils.has_surface(grid, cell) \
		and GridUtils.get_terrain_kind_at_cell(grid, cell) != Terrain.Kind.WATER


# Can it hold a puddle? Wettable, walkable, and FLAT: water on a slope runs off, and a decal projects
# straight down, so a puddle on a ramp would stretch.
static func is_puddle_ground(grid: TileMapLayer, heights: BoardHeights, cell: Vector2i) -> bool:
	if not is_wettable(grid, cell) or not GridUtils.walkable_of(grid.get_cell_tile_data(cell)):
		return false
	return heights == null or Terrain.climb_of_corners(heights.corners_at(cell)) == 0


# This cell's own roll, in [0, 1): the same cell answers the same at every rebuild.
static func roll(cell: Vector2i) -> float:
	return float(hash([cell, "puddle"]) % 1000) / 1000.0


static func puddle_cells(grid: TileMapLayer, heights: BoardHeights, rect: Rect2i,
		coverage: float) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in rect.size.y:
		for x in rect.size.x:
			var cell := rect.position + Vector2i(x, y)
			if roll(cell) < coverage and is_puddle_ground(grid, heights, cell):
				cells.append(cell)
	return cells


static func paint_wet(grid: TileMapLayer, rect: Rect2i, tint: Color) -> Image:
	var size := image_size(rect)
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var fill := Color(tint.r, tint.g, tint.b, 1.0)
	for y in rect.size.y:
		for x in rect.size.x:
			if is_wettable(grid, rect.position + Vector2i(x, y)):
				image.fill_rect(Rect2i(x * PX, y * PX, PX, PX), fill)
	return image


static func paint_puddles(grid: TileMapLayer, heights: BoardHeights, rect: Rect2i,
		coverage: float, color: Color) -> Image:
	var size := image_size(rect)
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var stamps: Array[Image] = []
	for variant in STAMPS:
		stamps.append(stamp(variant, color))
	for cell in puddle_cells(grid, heights, rect, coverage):
		var source := stamps[hash([cell, "shape"]) % STAMPS]
		var at := (cell - rect.position) * PX
		image.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), at)
	return image


# One puddle on a cell-sized canvas: two overlapping lobes, a lit far rim and a sky glint, every
# pixel inside the INSET. Pixel art, so a lobe is a test per art pixel rather than a smooth ellipse.
static func stamp(variant: int, color: Color) -> Image:
	var image := Image.create_empty(PX, PX, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([variant, "puddle-stamp"])
	var room := float(PX - 2 * INSET)
	var lobes: Array[Vector4] = []   # centre x, centre y, radius x, radius y, in art pixels
	for i in 2:
		var rx := room * rng.randf_range(0.22, 0.34)
		var ry := rx * rng.randf_range(0.55, 0.8)
		var cx := rng.randf_range(INSET + rx, PX - INSET - rx)
		var cy := rng.randf_range(INSET + ry, PX - INSET - ry)
		lobes.append(Vector4(cx, cy, rx, ry))
	var rim := color.lerp(Color(1, 1, 1, color.a), 0.45)
	for y in range(INSET, PX - INSET):
		for x in range(INSET, PX - INSET):
			if not _inside(lobes, x, y):
				continue
			var lit := not _inside(lobes, x, y - 1)
			image.set_pixel(x, y, rim if lit else color)
	var glint := Color(1, 1, 1, color.a * 0.6)
	var g := lobes[0]
	for dx in range(-1, 1):
		var gx := int(g.x) + dx
		var gy := int(g.y - g.w * 0.3)
		if image.get_pixel(gx, gy).a > 0.0:
			image.set_pixel(gx, gy, glint)
	return image


static func _inside(lobes: Array[Vector4], x: int, y: int) -> bool:
	for lobe in lobes:
		var dx := (float(x) + 0.5 - lobe.x) / lobe.z
		var dy := (float(y) + 0.5 - lobe.y) / lobe.w
		if dx * dx + dy * dy <= 1.0:
			return true
	return false
