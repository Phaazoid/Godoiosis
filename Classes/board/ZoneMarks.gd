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
# and LIGHT_WALL adds ZoneWalls standing on the perimeter. The flat 2D view keeps the wash under
# every look while this is an experiment -- a declared #292 asymmetry, owed to the winner.
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

# The resolution the art is authored at and generated in: the diorama's tile.
const TEXELS := 32

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
# A/B/C: the dark outline on each side of an edge, in texels of the 32-texel tile. 0 is none.
static var ZONE_EDGE_OUTLINE := 1.0
# B: how far in the glow reaches, as a fraction of a cell.
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
static var version := 0

static var _cache: Dictionary = {}


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
	_cache.clear()
	version += 1


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
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(image(which, mask))
	return _cache[key] as Texture2D


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
		Look.SOFT_RIM:
			var line := size / float(TEXELS) * 1.5
			if past < line:
				return Color(1, 1, 1, 0.95)
			var reach := ZONE_RIM_WIDTH * size
			if past < line + reach:
				var t := 1.0 - (past - line) / reach
				return Color(1, 1, 1, lerpf(ZONE_FILL_ALPHA, 0.75, t * t))
		Look.LIGHT_WALL:
			if past < size / float(TEXELS) * 1.5:
				return Color(1, 1, 1, 0.95)
	return fill
