class_name SightTrace2D
extends Node2D

# The flat projection of the aim's sight line (#258): the trace Reach computed for the hovered
# aim, drawn as a laser line ("a bead ON someone" -- dev, 2026-08-20) so the player sees exactly
# where a blocked shot dies. Pure renderer -- OverlayManager owns the store (show_sight_trace /
# clear_sight_trace) and this node only draws what it is handed; heights are a 3D fact, so the
# flat view shows the path and the verdict while the diorama shows the arc (a declared #292
# asymmetry).

const LINE_WIDTH := 1.5
const CLEAR_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const BLOCKED_COLOR := Color(1.0, 0.25, 0.2, 0.95)

var trace: Reach.SightTrace = null


func _draw() -> void:
	if trace == null or trace.points.size() < 2:
		return
	var color := BLOCKED_COLOR if trace.blocked else CLEAR_COLOR
	var line := PackedVector2Array()
	for p in trace.points:
		line.append(Vector2(p.x, p.z) * float(GridUtils.TILE_SIZE))
	draw_polyline(line, color, LINE_WIDTH)
