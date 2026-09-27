extends Object
class_name ZoneMarks

# How an objective zone is MARKED on the board (#955 part 1) -- the edge a zone wears and the emblem
# that says what kind it is. MoveGrid's shape: a board/ class of statics both views read and
# GameKnobs.CLASS_KNOBS tunes, with the art GENERATED here rather than baked, so a knob moves it.
#
# THE LOOK IS AN EXPERIMENT (Experiments.Flag.ZONE_LOOK): the dev asked to see three edges in the
# real game before choosing. look() is the one read of that flag, so promoting a winner is one
# function and a flag deletion. TINT is today's flat wash, drawn by the zone FILL layers as ever; the
# three edges replace that wash in the diorama with per-cell art on BoardOverlays.Layer.ZONE_MARKS,
# and LIGHT_WALL wears SOFT_RIM's art with ZoneWalls standing just inside the perimeter. The flat
# 2D view keeps the wash under every look while this is an experiment -- a declared #292 asymmetry,
# owed to the winner.
#
# The EMBLEM is not an experiment: one mark per zone, on the board and heading the card's section
# for its kind (the watch reticle's one-texture, one-colour shape).
#
# Cell art is WHITE-WITH-ALPHA plus BLACK outline, tinted per kind by the marker's modulate: black
# survives any tint, so one texture serves every kind (the squad ring's trick, #325).

enum Look { TINT, PAINTED_EDGE, SOFT_RIM, LIGHT_WALL }

# Which sides of a cell face out of its zone, and which inner corners need a notch (a cell whose two
# neighbours on a corner are in the zone while the diagonal between them is not).
enum Side { N = 1, E = 2, S = 4, W = 8, NE = 16, SE = 32, SW = 64, NW = 128 }

# The art's texels across a cell: the 3D view sizes a ground mark by its pixels, so it is that metric.
const TEXELS := int(BoardOverlays.ART_PIXELS_PER_CELL)
# How far look C's wall stands inside the zone, in cells: half a texel, onto the rim's outline. A
# separation, not a look -- it keeps the wall out of the plane a border block's face stands in.
const WALL_INSET := 0.5 / TEXELS

# Which layer's colour a kind wears -- the colour the tint, the knob and the card all read.
const LAYER_OF_KIND: Dictionary[ZoneManager.Kind, BoardOverlays.Layer] = {
	ZoneManager.Kind.CAPTURE: BoardOverlays.Layer.ZONE_CAPTURE,
	ZoneManager.Kind.EXTRACTION: BoardOverlays.Layer.ZONE_EXTRACTION,
	ZoneManager.Kind.DEPLOYMENT: BoardOverlays.Layer.ZONE_DEPLOYMENT,
	ZoneManager.Kind.DEFEND: BoardOverlays.Layer.ZONE_DEFEND,
}

# Placeholder art, one 16px cell each, white ink with a black outline. The dev's to redraw.
const EMBLEMS: Dictionary[ZoneManager.Kind, Texture2D] = {
	ZoneManager.Kind.CAPTURE: preload("res://Art/Icons/BoardIcons/ZoneCaptureIcon.png"),
	ZoneManager.Kind.EXTRACTION: preload("res://Art/Icons/BoardIcons/ZoneExtractionIcon.png"),
	ZoneManager.Kind.DEPLOYMENT: preload("res://Art/Icons/BoardIcons/ZoneDeploymentIcon.png"),
	ZoneManager.Kind.DEFEND: preload("res://Art/Icons/BoardIcons/ZoneDefendIcon.png"),
}

# A: the band's width, as a fraction of a cell.
static var ZONE_BAND_WIDTH := 0.13
# A/B/C: the dark outline on each side of an edge, in art texels. 0 is none.
static var ZONE_EDGE_OUTLINE := 1.0
# B/C: how far in the glow reaches, as a fraction of a cell.
static var ZONE_RIM_WIDTH := 0.45
# A/B/C: the faint wash left inside the zone, as an alpha. 0 is an edge alone.
static var ZONE_FILL_ALPHA := 0.16
# C: how tall the wall stands, in cells.
static var ZONE_WALL_HEIGHT := 0.45
# C: how strong the wall is at its foot, as an alpha.
static var ZONE_WALL_ALPHA := 0.8
# C: how fast the shimmer rises, in cycles a second. 0 holds it still.
static var ZONE_SHIMMER_SPEED := 0.45

# Moved by restyle(), so a reader holding generated art knows to ask again.
static var art_version := 0

static var _art_cache: Dictionary = {}


# THE one read of the experiment.
static func look() -> Look:
	return Experiments.choice_of(Experiments.Flag.ZONE_LOOK) as Look


# Whether zones draw as today's wash rather than as marks.
static func draws_tint() -> bool:
	return look() == Look.TINT


# A kind's colour at full strength, read off its layer's authored entry.
static func colour_of(kind: ZoneManager.Kind) -> Color:
	var colour: Color = BoardOverlays.LAYERS[LAYER_OF_KIND[kind]]["color"]
	colour.a = 1.0
	return colour


static func emblem_of(kind: ZoneManager.Kind) -> Texture2D:
	return EMBLEMS[kind] if EMBLEMS.has(kind) else null


# A knob moved: every generated texture is stale.
static func restyle() -> void:
	_art_cache.clear()
	art_version += 1


# Each cell of a zone -> the Side bits it needs. Membership is THIS zone's, so two zones of one kind
# that touch still draw their own edges.
static func cell_masks(cells: Array[Vector2i]) -> Dictionary[Vector2i, int]:
	var inside := {}
	for cell in cells:
		inside[cell] = true
	var masks: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in inside:
		var n := not inside.has(cell + Vector2i.UP)
		var e := not inside.has(cell + Vector2i.RIGHT)
		var s := not inside.has(cell + Vector2i.DOWN)
		var w := not inside.has(cell + Vector2i.LEFT)
		var mask := 0
		if n: mask |= Side.N
		if e: mask |= Side.E
		if s: mask |= Side.S
		if w: mask |= Side.W
		if not n and not e and not inside.has(cell + Vector2i(1, -1)): mask |= Side.NE
		if not s and not e and not inside.has(cell + Vector2i(1, 1)): mask |= Side.SE
		if not s and not w and not inside.has(cell + Vector2i(-1, 1)): mask |= Side.SW
		if not n and not w and not inside.has(cell + Vector2i(-1, -1)): mask |= Side.NW
		masks[cell] = mask
	return masks


# The zone cell nearest the zone's middle, ties to the first in board order, so an L-shaped zone still
# wears its emblem inside itself.
static func emblem_cell(cells: Array[Vector2i]) -> Vector2i:
	if cells.is_empty():
		return Vector2i.ZERO
	var middle := Vector2.ZERO
	for cell in cells:
		middle += Vector2(cell)
	middle /= float(cells.size())
	var ordered := cells.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var best: Vector2i = ordered[0]
	for cell: Vector2i in ordered:
		if Vector2(cell).distance_squared_to(middle) < Vector2(best).distance_squared_to(middle):
			best = cell
	return best


# One cell of a look's art for a cell wearing `mask`, cached.
static func texture(which: Look, mask: int) -> Texture2D:
	var key := Vector2i(which, mask)
	if not _art_cache.has(key):
		_art_cache[key] = ImageTexture.create_from_image(image(which, mask))
	return _art_cache[key] as Texture2D


# A texel's distance in from the nearest thing the zone ends at -- an outward side, or the corner of
# a notch -- in texels, judged at its centre. Texel row 0 is the cell's NORTH edge, as the path arrows
# already read in both views.
static func edge_distance(mask: int, x: int, y: int, size: int) -> float:
	var cx := float(x) + 0.5
	var cy := float(y) + 0.5
	var far := float(size)
	var d := INF
	if mask & Side.N: d = minf(d, cy)
	if mask & Side.S: d = minf(d, far - cy)
	if mask & Side.W: d = minf(d, cx)
	if mask & Side.E: d = minf(d, far - cx)
	if mask & Side.NE: d = minf(d, maxf(far - cx, cy))
	if mask & Side.SE: d = minf(d, maxf(far - cx, far - cy))
	if mask & Side.SW: d = minf(d, maxf(cx, far - cy))
	if mask & Side.NW: d = minf(d, maxf(cx, cy))
	return d


static func image(which: Look, mask: int, size: int = TEXELS) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var scale := float(size) / float(TEXELS)
	var outline := ZONE_EDGE_OUTLINE * scale
	for y in size:
		for x in size:
			var d := edge_distance(mask, x, y, size)
			img.set_pixel(x, y, _texel(which, d, outline, float(size)))
	return img


static func _texel(which: Look, d: float, outline: float, size: float) -> Color:
	var fill := Color(1, 1, 1, ZONE_FILL_ALPHA)
	if which == Look.TINT or d == INF:
		return fill
	if d < outline:
		return Color(0, 0, 0, 0.8)
	var past := d - outline
	match which:
		Look.PAINTED_EDGE:
			var band := ZONE_BAND_WIDTH * size
			if past < band:
				return Color(1, 1, 1, 1)
			if past < band + outline:
				return Color(0, 0, 0, 0.8)
		Look.SOFT_RIM, Look.LIGHT_WALL:   # the wall stands on the rim (dev, 2026-09-27)
			var line := size / float(TEXELS) * 1.5
			if past < line:
				return Color(1, 1, 1, 0.95)
			var reach := ZONE_RIM_WIDTH * size
			if past < line + reach:
				var t := 1.0 - (past - line) / reach
				return Color(1, 1, 1, lerpf(ZONE_FILL_ALPHA, 0.75, t * t))
	return fill


# The perimeter look C's wall stands on: OverlayManager's outline, in its trace space, each strip moved
# WALL_INSET into the zone. Its ends are trimmed at an outer corner and run on at an inner one, judged
# from the zone's own cells, so the ring stays closed.
static func wall_outline(cells: Array[Vector2i], board: BoardContext) -> Array[PackedVector3Array]:
	var inside := {}
	for cell in cells:
		inside[cell] = true
	var strips: Array[PackedVector3Array] = []
	for segment in OverlayManager.outline_segments(cells, board):
		var from := segment[0]
		var to := segment[1]
		var along := Vector3(to.x - from.x, 0.0, to.z - from.z)   # one cell, x east, z south
		var inward := Vector3(-along.z, 0.0, along.x)             # the zone is on the stroke's right
		var step := Vector2i(roundi(along.x), roundi(along.z))
		var out := Vector2i(-roundi(inward.x), -roundi(inward.z))
		var cell := Vector2i(floori((from.x + to.x + inward.x) * 0.5), floori((from.z + to.z + inward.z) * 0.5))
		strips.append(PackedVector3Array([
			from + (inward - along * _corner_turn(inside, cell - step, out)) * WALL_INSET,
			to + (inward + along * _corner_turn(inside, cell + step, out)) * WALL_INSET]))
	return strips


# Which way a strip's end moves along it where the outline turns: -1 back at an outer corner (the
# next cell along is outside), +1 on at an inner one (it and the cell beyond it are both inside).
static func _corner_turn(inside: Dictionary, next: Vector2i, out: Vector2i) -> float:
	if not inside.has(next):
		return -1.0
	return 1.0 if inside.has(next + out) else 0.0
