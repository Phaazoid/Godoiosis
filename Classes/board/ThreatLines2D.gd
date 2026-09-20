class_name ThreatLines2D
extends Node2D

# The flat projection of the threat preview's intent marks (#710, re-dressed by #1042): who the
# enemy will attack, and which way the blow runs. Pure renderer -- OverlayManager owns the store and
# OverlayMirror lifts the same points into the diorama.
#
# ONE COLOUR FOR BOTH (dev, 2026-09-19: "I don't think the color should change for lethal intent --
# perhaps the whole line can flash?"). A felling intent is the same pink and FLASHES to white; the
# two 3D layers survive because a flash is a per-material time term, not because they are tinted
# differently. That REPEALS slice 3's "the beam has to say it" -- an argument for a second HUE, made
# when the damage number that used to carry lethality was deleted.
#
# The flash and the travelling bead are diorama-only: the flat view draws a plain stroke, the
# declared #292 asymmetry SightTrace2D already carries and #674 ruled for the sight trace.
#
# The REACH tier's lines are gone as of slice 3 (dev: "a bit too much"). What answers "who can
# reach this cell" now is the two-tone range fill, which says it for the whole board at once
# rather than as a beam per attacker. The damage NUMBER went with them in the same pass -- it is
# drawn as the predicted span on the victim's own health bar instead.

const LINE_WIDTH := 1.5
# Pink, because it is the one hue nothing else on this board owns (#1042, settled against a drawn
# mockup): the aim footprint is yellow, the sight bead white, the enemy's own tones red and blue,
# the zones cyan/violet/amber. Amber and the old lethal red were both neighbours of an AIM colour,
# which is the confusion this ticket exists to fix.
static var INTENT_LINE_COLOR := Color(1.0, 0.251, 0.784, 0.95)
# The arrowhead, in CELLS. It stops short of the victim rather than landing on it -- the mark hangs
# at Reach.EYE_HEIGHT and the crown / guard ward hang at BoardOverlays.billboard_lift (0.85) just
# under it, so a head drawn at the victim sits on the marker saying what that unit IS (#346).
# #450's measured 0.4 is right here too, which the mockup confirmed against a real ward.
static var HEAD_SIZE := 0.45
static var HEAD_INSET := 0.4
static var HEAD_SPREAD := 0.62   # how wide it opens, as a fraction of its own length

# One entry per intent, each the STROKES that draw it (shaft, then the two head legs). Grouped
# rather than flat so `fells` pairs 1:1 with intents instead of with strokes -- slice 3's bug was
# two arrays appended at different rates, and this shape makes that unrepresentable.
var marks: Array[Array] = []
# The stroke round the hovered enemy's whole footprint (slice 4) -- one segment per outward-facing
# cell edge, in the same trace space the intents use, so it flattens through the same _polyline.
# This node is #710's flat LINE markup entire rather than the intent lines alone now; the class name
# stays, because renaming it is churn across four suites for no behaviour.
var outlines: Array[PackedVector3Array] = []


# A line between two cells in trace space (x, rule-height, y), the SightTrace convention, so both
# views lift it the way they lift a sight trace.
static func segment(from_cell: Vector2i, to_cell: Vector2i, board: BoardContext) -> PackedVector3Array:
	var points := PackedVector3Array()
	for cell in [from_cell, to_cell]:
		var h := 0.0 if board == null else float(board.elevation_at(cell))
		points.append(Vector3(float(cell.x) + 0.5, h + Reach.EYE_HEIGHT, float(cell.y) + 0.5))
	return points


# One intent as the strokes that draw it: the shaft, then each arrowhead leg SEPARATELY.
#
# Three strokes rather than one polyline with a corner, and that is measured rather than tidy:
# BoardOverlays.beam_tangents averages the two directions at a joint, so at an arrowhead's apex the
# average points across the mark -- and since the ribbon's width is built perpendicular to that, the
# strip twists open at exactly the point the arrow exists for.
#
# A mark shorter than its own inset keeps the bare shaft: who and whom still reads, and a head
# longer than the line it dresses reads as a blob.
#
# Takes the SHAFT rather than two cells and a board, so the store can keep the shafts and re-derive
# every mark when a head knob moves -- without holding a `BoardContext` (and the live `Unit`s inside
# it) across frames for the sake of a slider.
static func mark(shaft: PackedVector3Array) -> Array[PackedVector3Array]:
	var strokes: Array[PackedVector3Array] = []
	if shaft.size() < 2:
		return strokes
	var span := shaft[1] - shaft[0]
	var length := span.length()
	if length <= HEAD_INSET or HEAD_SIZE <= 0.0:
		strokes.append(shaft)
		return strokes
	var dir := span / length
	var tip := shaft[1] - dir * HEAD_INSET
	strokes.append(PackedVector3Array([shaft[0], tip]))
	# A mark that runs straight up a cliff has no sideways to open into; any perpendicular will do.
	var side := dir.cross(Vector3.UP)
	side = Vector3.RIGHT if side.length_squared() <= 0.0 else side.normalized()
	var back := tip - dir * HEAD_SIZE
	var wing := side * HEAD_SIZE * HEAD_SPREAD
	strokes.append(PackedVector3Array([back + wing, tip]))
	strokes.append(PackedVector3Array([back - wing, tip]))
	return strokes


func _draw() -> void:
	# The outline first: it lies on the ground, an intent hangs at eye height, and a beam crossing
	# the stroke should read over it.
	for segment in outlines:
		_polyline(segment, OverlayManager.FOCUS_OUTLINE_COLOR)
	for strokes in marks:
		for stroke: PackedVector3Array in strokes:
			_polyline(stroke, INTENT_LINE_COLOR)


func _polyline(seg: PackedVector3Array, color: Color) -> void:
	if seg.size() < 2:
		return
	var line := PackedVector2Array()
	for p in seg:
		line.append(_flat(p))
	draw_polyline(line, color, LINE_WIDTH)


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) * float(GridUtils.TILE_SIZE)
