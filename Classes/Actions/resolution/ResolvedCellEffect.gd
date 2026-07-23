extends RefCounted
class_name ResolvedCellEffect

# One cell's resolved terrain consequences from a pass — the #47 cell-effect channel, now
# living under #50. Sibling of ResolvedOutcome but tile-facing. Preview AND execution consume
# the same object (R3): the resolver derives it at plan time, execution plays it back.

var cell: Vector2i
var states_added: Array[Terrain.TileState] = []
var states_removed: Array[Terrain.TileState] = []
var popups: Array[String] = []
var icons: Array[Texture2D] = []
