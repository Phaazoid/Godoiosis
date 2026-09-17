class_name ThreatLines2D
extends Node2D

# The flat projection of the threat preview's intent lines (#710): who the enemy will attack, and
# whether that blow fells. Pure renderer -- OverlayManager owns the store and OverlayMirror lifts
# the same points into the diorama.
#
# The REACH tier's lines are gone as of slice 3 (dev: "a bit too much"). What answers "who can
# reach this cell" now is the two-tone range fill, which says it for the whole board at once
# rather than as a beam per attacker. The damage NUMBER went with them in the same pass -- it is
# drawn as the predicted span on the victim's own health bar instead.

const LINE_WIDTH := 1.5
# A plain intention, and one that FELLS. The distinction rides the LINE rather than a number,
# because "this enemy is going to attack you" and "this enemy is going to kill you" are different
# warnings and the second must not have to be read to be noticed.
static var INTENT_LINE_COLOR := Color(1.0, 0.8, 0.2, 0.95)
static var INTENT_FELL_COLOR := Color(1.0, 0.2, 0.15, 1.0)

# Paired BY INDEX with `intents`, and written in one pass by OverlayManager so they cannot get out
# of step. They used to be `labels`, which was appended only for an intent worth a number while
# the lines were appended for every intent -- so one silent intent shifted every later line's
# lethal colour onto its neighbour.
var intents: Array[PackedVector3Array] = []
var fells: Array[bool] = []


# The colour an intent draws in -- one answer, read by this node and copied by the 3D beam.
static func intent_color(is_fatal: bool) -> Color:
	return INTENT_FELL_COLOR if is_fatal else INTENT_LINE_COLOR


# A line between two cells in trace space (x, rule-height, y), the SightTrace convention, so both
# views lift it the way they lift a sight trace.
static func segment(from_cell: Vector2i, to_cell: Vector2i, board: BoardContext) -> PackedVector3Array:
	var points := PackedVector3Array()
	for cell in [from_cell, to_cell]:
		var h := 0.0 if board == null else float(board.elevation_at(cell))
		points.append(Vector3(float(cell.x) + 0.5, h + Reach.EYE_HEIGHT, float(cell.y) + 0.5))
	return points


func _draw() -> void:
	for i in intents.size():
		_polyline(intents[i], intent_color(i < fells.size() and fells[i]))


func _polyline(seg: PackedVector3Array, color: Color) -> void:
	if seg.size() < 2:
		return
	var line := PackedVector2Array()
	for p in seg:
		line.append(_flat(p))
	draw_polyline(line, color, LINE_WIDTH)


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) * float(GridUtils.TILE_SIZE)
