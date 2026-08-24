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
# There is deliberately NO depth field: how deep the flat preview draws is not a preference, it is
# the slab a paint makes, so the renderer states it. The knob that DOES exist answers for the hover
# SELECTOR (BoardOverlays.selector_depth) -- a different object, in normal play, and one question.

var cell: Vector2i
var height: int
var source: TileMapLayer
var rise: Terrain.RampRise
var climb: int


static func make(cell_: Vector2i, height_: int, source_: TileMapLayer,
		rise_: Terrain.RampRise = Terrain.RampRise.NONE,
		climb_ := Terrain.UNITS_PER_LEVEL) -> BrushGhost:
	var ghost := BrushGhost.new()
	ghost.cell = cell_
	ghost.height = height_
	ghost.source = source_
	ghost.rise = rise_
	ghost.climb = climb_
	return ghost
