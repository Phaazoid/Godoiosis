class_name ThreatLines2D
extends Node2D

# The flat projection of the hover tier's threat lines (#710): one straight line from every enemy
# that could reach the hovered cell. Pure renderer -- OverlayManager owns the store
# (show_threat_lines / clear_threat_lines) and OverlayMirror lifts the same points into the diorama.

const LINE_WIDTH := 1.5
# The one answer to "what colour is a threat line"; the 3D beam copies it. A static var so
# GameKnobs' CLASS_KNOBS can write it.
static var THREAT_LINE_COLOR := Color(1.0, 0.35, 0.2, 0.9)

var segments: Array[PackedVector3Array] = []


# A line between two cells in trace space (x, rule-height, y), the SightTrace convention, so both
# views lift it the way they lift a sight trace.
static func segment(from_cell: Vector2i, to_cell: Vector2i, board: BoardContext) -> PackedVector3Array:
	var points := PackedVector3Array()
	for cell in [from_cell, to_cell]:
		var h := 0.0 if board == null else float(board.elevation_at(cell))
		points.append(Vector3(float(cell.x) + 0.5, h + Reach.EYE_HEIGHT, float(cell.y) + 0.5))
	return points


func _draw() -> void:
	for seg in segments:
		if seg.size() < 2:
			continue
		var line := PackedVector2Array()
		for p in seg:
			line.append(Vector2(p.x, p.z) * float(GridUtils.TILE_SIZE))
		draw_polyline(line, THREAT_LINE_COLOR, LINE_WIDTH)
