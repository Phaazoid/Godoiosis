extends Object
class_name FogGround

# Where fog may stand on the board (#1285), for WeatherMirror's fog pass and cards: one texel per cell
# over WeatherMask's rect, read LINEAR so it eases from cell to cell.
#
#   R -- the edge fade: a third on a cell beside a hole or off the board, rising to full `edge_fade`
#        cells further in, so fog thins out before it would hang over nothing (the share the dev picked
#        it at on 2026-10-09, which kept the fog up to the board edge without a wall there).
#   G -- the pooled depth, world units: `pool_depth` on the low ground, easing to 0 just above the pool
#        level. It is a depth over the cell's OWN ground, never a level the fog fills up to, so pooled
#        fog cannot stand as a box over a drop (dev, 2026-10-09: the rectangle over the ramp off the
#        stage).
#
# The pool level is the height `pool_share` of the board's surfaces lie at or under, so a board's low
# ground is its own and no number here is a fact about one map. What has ground is GridUtils.has_surface,
# the mask's own test. Pure and static.

# How far above the pool level the pooled fog eases out, world units: half a level.
const POOL_EASE := 0.5


static func field(grid: TileMapLayer, heights: BoardHeights, rect: Rect2i, pool_share: float,
		pool_depth: float, edge_fade: float) -> Image:
	var w := maxi(rect.size.x, 1)
	var h := maxi(rect.size.y, 1)
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGF)
	if grid == null:
		return image
	var level := pool_level(grid, heights, rect, pool_share)
	var steps := edge_steps(grid, rect)
	for y in rect.size.y:
		for x in rect.size.x:
			var cell := rect.position + Vector2i(x, y)
			if not GridUtils.has_surface(grid, cell):
				continue
			var fade := clampf((float(steps[y * w + x]) - 0.5) / (maxf(edge_fade, 0.0) + 0.5), 0.0, 1.0)
			var pooled := maxf(pool_depth, 0.0) * (1.0 - smoothstep(level, level + POOL_EASE, ground_of(cell, heights)))
			image.set_pixel(x, y, Color(fade, pooled, 0.0))
	return image


# The height `share` of the board's surfaces lie at or under, lowest first, world units.
static func pool_level(grid: TileMapLayer, heights: BoardHeights, rect: Rect2i, share: float) -> float:
	var grounds: Array[float] = []
	for y in rect.size.y:
		for x in rect.size.x:
			var cell := rect.position + Vector2i(x, y)
			if GridUtils.has_surface(grid, cell):
				grounds.append(ground_of(cell, heights))
	if grounds.is_empty():
		return 0.0
	grounds.sort()
	return grounds[roundi(clampf(share, 0.0, 1.0) * float(grounds.size() - 1))]


# A cell's ground at its centre, world units.
static func ground_of(cell: Vector2i, heights: BoardHeights) -> float:
	return BoardSpace.surface_height_at(cell, cell.x + 0.5, cell.y + 0.5, heights)


# Per cell of `rect`, row by row: how many steps (diagonals count as one) to the nearest cell with no
# ground, the ring around the rect counting as none. A cell beside a hole or the edge is 1.
static func edge_steps(grid: TileMapLayer, rect: Rect2i) -> PackedInt32Array:
	var w := rect.size.x
	var h := rect.size.y
	var steps := PackedInt32Array()
	steps.resize(maxi(w * h, 0))
	steps.fill(-1)
	var frontier: Array[Vector2i] = []
	for y in h:
		for x in w:
			if not GridUtils.has_surface(grid, rect.position + Vector2i(x, y)):
				steps[y * w + x] = 0
				frontier.append(Vector2i(x, y))
	# The ring outside the rect is no ground: seed the cells along it.
	for y in h:
		for x in w:
			if steps[y * w + x] == -1 and (x == 0 or y == 0 or x == w - 1 or y == h - 1):
				steps[y * w + x] = 1
	for y in h:
		for x in w:
			if steps[y * w + x] == 1:
				frontier.append(Vector2i(x, y))
	var head := 0
	while head < frontier.size():
		var at := frontier[head]
		head += 1
		var next := steps[at.y * w + at.x] + 1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := at + Vector2i(dx, dy)
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h or steps[n.y * w + n.x] != -1:
					continue
				steps[n.y * w + n.x] = next
				frontier.append(n)
	return steps
