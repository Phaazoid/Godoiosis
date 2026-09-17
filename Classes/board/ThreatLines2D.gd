class_name ThreatLines2D
extends Node2D

# The flat projection of the threat preview's lines (#710). Two channels: the REACH tier's
# "who could reach this cell" (segments) and the PLAN tier's "who will attack whom", which carries
# a damage number (intents + labels). Pure renderer -- OverlayManager owns both stores and
# OverlayMirror lifts the same points into the diorama.

const LINE_WIDTH := 1.5
# The one answer to "what colour is a threat line"; the 3D beam copies it. A static var so
# GameKnobs' CLASS_KNOBS can write it.
static var THREAT_LINE_COLOR := Color(1.0, 0.35, 0.2, 0.9)
# The exact tier's own pair: a plain intention, and one that FELLS. Distinct from the reach colour
# because "this enemy could hit here" and "this enemy is going to kill you" must not read alike.
static var INTENT_LINE_COLOR := Color(1.0, 0.8, 0.2, 0.95)
static var INTENT_FELL_COLOR := Color(1.0, 0.2, 0.15, 1.0)
static var INTENT_LABEL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
static var INTENT_LABEL_SIZE := 14

var segments: Array[PackedVector3Array] = []
var intents: Array[PackedVector3Array] = []
var labels: Array[Dictionary] = []


# The colour an intent draws in -- one answer, read by this node and copied by the 3D beam.
static func intent_color(fells: bool) -> Color:
	return INTENT_FELL_COLOR if fells else INTENT_LINE_COLOR


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
		_polyline(seg, THREAT_LINE_COLOR)
	for i in intents.size():
		var fells: bool = i < labels.size() and bool(labels[i].get("fells", false))
		_polyline(intents[i], intent_color(fells))
	var font := ThemeDB.fallback_font
	if font == null:
		return
	for entry: Dictionary in labels:
		var pos: Vector3 = entry["pos"]
		draw_string(font, _flat(pos), str(entry["text"]),
				HORIZONTAL_ALIGNMENT_CENTER, -1, INTENT_LABEL_SIZE, INTENT_LABEL_COLOR)


func _polyline(seg: PackedVector3Array, color: Color) -> void:
	if seg.size() < 2:
		return
	var line := PackedVector2Array()
	for p in seg:
		line.append(_flat(p))
	draw_polyline(line, color, LINE_WIDTH)


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) * float(GridUtils.TILE_SIZE)
