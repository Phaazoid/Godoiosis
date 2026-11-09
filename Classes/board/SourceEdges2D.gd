class_name SourceEdges2D
extends Node2D

# The flat view's stroke round the aimed carving's materia sources (#699): one outline per element, in
# that element's ElementPalette colour. Pure renderer -- OverlayManager owns the store (source_edges) and
# OverlayMirror lifts the same trace-space points onto BoardOverlays.Layer.SOURCE_EDGE. Its own node
# rather than a TileMapLayer, because a layer holds one tile per cell and the reach is already there.

# A GameKnobs row, in the flat view's pixels (a cell is GridUtils.TILE_SIZE).
static var SOURCE_LINE_WIDTH := 1.5

var groups: Array[Dictionary] = []   # OverlayManager.source_edges


func _draw() -> void:
	for group: Dictionary in groups:
		var color := ElementPalette.color_for_element(group["element"])
		for segment: PackedVector3Array in group["segments"]:
			if segment.size() < 2:
				continue
			var line := PackedVector2Array()
			for p: Vector3 in segment:
				line.append(Vector2(p.x, p.z) * float(GridUtils.TILE_SIZE))
			draw_polyline(line, color, SOURCE_LINE_WIDTH)
