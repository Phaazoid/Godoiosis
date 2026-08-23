extends RefCounted
class_name BrushGhost

# What the next brush click would PRODUCE (#285) -- one answer, for any renderer.
#
# It replaces a pair of accessors on DevController that a 3D host had to call separately and then
# trust to agree (`brush_ghost_cell` + `brush_ghost_layer`). They could not describe an ELEVATION
# paint at all: the level came from the cell's CURRENT height rather than the brush's, and the
# mesh came from the 2D ghost TileMapLayer, which elevation never writes to. Widening the
# TERRAIN-shaped predicate would only have let a caller past the gate with nothing to draw.
#
# `source` is the layer the tile is READ from, never a decoded property of it -- a renderer
# resolves it with the same call it uses on the real grid (BoardMirror.item_for_cell), so the
# ghost and the board cannot drift about what a cell looks like. TERRAIN points it at the 2D
# ghost layer (which holds the brush's pick as a real placed tile); ELEVATION points it at the
# grid itself, because raising a cell keeps the art it already has.
#
# `height` is the brush's own rule HEIGHT, in the store's half-level units -- it was called `level`
# and #427 slice 1 quietly made that a LIE, since the brush started authoring in units while
# show_brush_ghost still read the field as a whole level and previewed every raised cell twice as
# high. Renamed rather than converted at the call site, because the word is what caused it.
#
# `rise` is set only when the click would author a ramp, and `climb` is how far that ramp rises --
# a renderer draws the wedge directly above the surface, mirroring BoardMirror's own column rule.
#
# `depth` is the ONE display preference this answer carries, and it lives here rather than being read
# off the brush because a 3D host reaching past brush_ghost() into game.dev_overlay.tile_brush is the
# "ask the question, not the field it happens to live in" trap this class exists to close. It is how
# many ROWS -- one height unit each -- the flat preview reaches DOWN from the surface the click
# authors, a LEVEL by default because that is the slab a paint actually makes. A ramp ignores it: a
# wedge already draws the volume it authors, and its extent is geometry rather than a matter of taste.

var cell: Vector2i
var height: int
var source: TileMapLayer
var rise: Terrain.RampRise
var climb: int
var depth: int


static func make(cell_: Vector2i, height_: int, source_: TileMapLayer,
		rise_: Terrain.RampRise = Terrain.RampRise.NONE,
		climb_ := Terrain.UNITS_PER_LEVEL,
		depth_ := Terrain.UNITS_PER_LEVEL) -> BrushGhost:
	var ghost := BrushGhost.new()
	ghost.cell = cell_
	ghost.height = height_
	ghost.source = source_
	ghost.rise = rise_
	ghost.climb = climb_
	ghost.depth = depth_
	return ghost
