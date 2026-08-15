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
# `level` is the level the previewed block would OCCUPY, and `rise` is set only when the click
# would author a ramp -- a renderer draws the wedge one level above, mirroring BoardMirror's own
# column rule.

var cell: Vector2i
var level: int
var source: TileMapLayer
var rise: Terrain.RampRise


static func make(cell_: Vector2i, level_: int, source_: TileMapLayer,
		rise_: Terrain.RampRise = Terrain.RampRise.NONE) -> BrushGhost:
	var ghost := BrushGhost.new()
	ghost.cell = cell_
	ghost.level = level_
	ghost.source = source_
	ghost.rise = rise_
	return ghost
