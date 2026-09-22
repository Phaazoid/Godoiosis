class_name ThreatLines2D
extends Node2D

# The flat projection of the threat preview's REACH marks (#710, re-dressed by #1042 and #1059,
# re-pointed by #1069): which enemies can reach the cell you are hovering a move onto, and which way
# the blow would run. Pure renderer -- OverlayManager owns the store and OverlayMirror lifts the same
# points into the diorama.
#
# WHAT THESE MARKS SAY CHANGED AT #1069 AND THE SHAPE DID NOT. They were slice 2's INTENT lines --
# a real AI turn per engaged squad, answering who will attack whom -- until the dev looked at 3D FE
# again: "they aren't conveying enemy intent at all, just who can reach who. And they don't show all
# the time, just during move hover mode." So the geometry below is untouched and only the trigger and
# the source moved, which is why none of this file's shape rulings were re-opened.
#
# ONE COLOUR, and there is no longer a second layer to differ from. #1042 settled that lethality is
# not a hue ("I don't think the color should change for lethal intent -- perhaps the whole line can
# flash?") and #1069 removed the question: reachability cannot know lethality without running the
# ladder, so the felling FLASH and the layer that carried it are both gone.
#
# The travelling bead is diorama-only: the flat view draws a plain stroke, the declared #292
# asymmetry SightTrace2D already carries and #674 ruled for the sight trace. The mark's GEOMETRY is
# not diorama-only -- the arc and the cone are drawn in both views, though since #1069 the diorama
# draws the cone as a SOLID (BoardOverlays.add_beam_cone) where this view keeps its filled polygon.
# That is the same answer wearing each view's own means: `_taper` was always opaque.
#
# THE MARK HANGS AT ITS OWN HEIGHT, NOT AT Reach.EYE_HEIGHT (#1059). That constant is a RULE: it
# defines what a wall is for the sight trace and the vertical aim gate, so it cannot move for a look.
# The declared split (Law #4) is that a sight trace draws the TRAJECTORY the rule judges and must hang
# where the rule says, while an intent mark is a statement about who attacks whom and may hang where
# the body is.
#
# SLICE 3 DELETED THESE LINES AND #1069 BROUGHT THEM BACK, which is worth knowing before anyone
# deletes them again. The reason given then -- the dev's "a bit too much" -- was about a board-wide
# beam channel standing up AT REST beside the range fill, not about the channel itself. Bound to
# move hover, they answer a question the fill cannot: not "who can reach here" for the whole board,
# but "who reaches ME if I stop on this tile", which is the question a player is actually asking
# while the cursor is on a destination.

const LINE_WIDTH := 1.5
# Pink, because it is the one hue nothing else on this board owns (#1042, settled against a drawn
# mockup): the aim footprint is yellow, the sight bead white, the enemy's own tones red and blue,
# the zones cyan/violet/amber. Amber and the old lethal red were both neighbours of an AIM colour,
# which is the confusion that ticket existed to fix.
static var MARK_LINE_COLOR := Color(1.0, 0.251, 0.784, 0.95)

# --- The mark's shape (#1059, settled against a drawn mockup) -----------------------------------
#
# Where the mark hangs, in RULE height units above the cell's own surface. 0.625 rule units is
# 0.3125 world, which is the middle of a map sprite's ink: MapSpriteInk.INK_RECT stands 20 texels
# tall at UnitSprite3D.texels_per_unit 32, so a body reaches 0.625 WORLD above its feet. That is the
# dev's own 2026-08-20 ruling ("the line should originate from the center of the sprite") measured
# rather than assumed -- Reach.EYE_HEIGHT put it at 80% of body height, which he read as over the head.
static var MARK_HEIGHT := 0.625
# How far the arc lifts above its own chord, in rule units PER CELL of run. Proportional rather than
# absolute, because "shallow" is a property of the shape and not of a distance: a fixed lift is a hump
# on an adjacent-cell mark and nearly flat on a nine-cell one. 0.25 reproduces the card the dev ruled
# on (0.45 world over a 3.58-cell chord).
static var MARK_BOW_PER_CELL := 0.25
# How far short of the victim the mark stops, in cells. A taste value -- NOT a clearance. #1042's
# record claimed the inset had to clear the crown; the crown hangs at BoardOverlays.billboard_lift
# 0.85 world, which is well ABOVE this mark, so nothing is being cleared.
static var MARK_INSET := 0.25
# The cone that replaces #1042's arrowhead (dev, 2026-09-20: the arrows "just don't look great in
# practice... perhaps a narrow cone at the end instead?", then "about half of what it is, too. It
# should be subtle"). Length in cells, measured in ARC LENGTH back from the tip so it cannot shrink
# as the bow deepens.
static var CONE_LENGTH := 0.4
# ...and how wide its base is, AS A MULTIPLE OF THE SHAFT rather than as an absolute width. The shaft's
# width is BoardOverlays.mark_width, a node export this 2D node cannot see -- and an absolute would
# go stale anyway, since that setter re-pushes material parameters without bumping the mark version,
# so a baked ratio would outlive the change. A multiple also makes the two knobs behave together.
static var CONE_WIDTH_SCALE := 2.4

# One entry per mark, each the STROKES that draw it (the arc, then the cone). Grouped rather than
# flat so a mark's own facts -- its cone, its widths -- pair 1:1 with the MARK instead of with a
# stroke: slice 3's bug was two arrays appended at different rates, and this shape makes that
# unrepresentable.
var marks: Array[Array] = []
# The stroke round the hovered enemy's whole footprint (slice 4) -- one segment per outward-facing
# cell edge, in the same trace space the intents use, so it flattens through the same _polyline.
# This node is #710's flat LINE markup entire rather than the intent lines alone now; the class name
# stays, because renaming it is churn across four suites for no behaviour.
var outlines: Array[PackedVector3Array] = []


# The mark's CHORD between two cells, in trace space (x, rule-height, y) -- the SightTrace convention,
# so both views lift it through BoardSpace.trace_point exactly as they lift a sight trace.
#
# MEASURED FROM THE CELL'S CENTRE SURFACE, never from board.elevation_at (#1059). That accessor is a
# cell's LOW side -- BoardHeights says so, and for a ramp it is the floor the ramp climbs FROM -- while
# a body on that ramp stands at the slope's visual midpoint, half a level higher (verticality.md, and
# the reason BoardSpace.surface_point exists). Reach.EYE_HEIGHT's 1.0 happened to equal that half
# level exactly, so the old mark left a ramp at the feet BY COINCIDENCE; at any other height it would
# sink into the slope. Terrain.height_at_uv is #427's one surface and agrees with elevation_at on flat
# ground, so a flat board is untouched by construction.
static func segment(from_cell: Vector2i, to_cell: Vector2i, board: BoardContext) -> PackedVector3Array:
	var points := PackedVector3Array()
	for cell in [from_cell, to_cell]:
		var h := 0.0 if board == null else Terrain.height_at_uv(board.corners_at(cell), 0.5, 0.5)
		points.append(Vector3(float(cell.x) + 0.5, h + MARK_HEIGHT, float(cell.y) + 0.5))
	return points


# One intent as the strokes that draw it: the bowed ARC, then the CONE at the victim's end.
#
# TWO STROKES rather than one polyline, and that is measured rather than tidy: BoardOverlays.
# beam_tangents averages the two directions at a joint, and the arc-to-cone join is a deliberate WIDTH
# discontinuity -- the cone flares past the shaft before it converges -- which a smoothed joint would
# blur away. #1042 split the arrowhead's legs off for the same reason.
#
# The two strokes SHARE the base point, so the bead's world measure (set_marks chains _stroke_length
# across a mark) stays continuous across the join with nothing double-counted.
#
# A mark with no room for its own cone keeps the bare arc: who and whom still reads, and a cone longer
# than the line it dresses reads as a blob.
#
# Takes the CHORD rather than two cells and a board, so the store can keep the chords and re-derive
# every mark when a shape knob moves -- without holding a `BoardContext` (and the live `Unit`s inside
# it) across frames for the sake of a slider.
static func mark(chord: PackedVector3Array) -> Array[PackedVector3Array]:
	var strokes: Array[PackedVector3Array] = []
	if chord.size() < 2:
		return strokes
	var span := chord[1] - chord[0]
	var length := span.length()
	if length <= MARK_INSET:
		strokes.append(chord)
		return strokes
	var tip := chord[1] - (span / length) * MARK_INSET
	var run := tip - chord[0]
	var run_length := run.length()
	# The control point that puts the curve's own midpoint `lift` above the chord's: a quadratic's
	# B(0.5) is (a + 2c + b) / 4, so the control has to be twice as far out as the sag wanted.
	var lift := maxf(MARK_BOW_PER_CELL, 0.0) * run_length
	var control := chord[0] + run * 0.5 + Vector3.UP * lift * 2.0
	var points := _sample_curve(chord[0], control, tip, run_length)
	if CONE_LENGTH <= 0.0:
		strokes.append(points)
		return strokes
	var split := _split_at_tail(points, CONE_LENGTH)
	if split.is_empty():
		strokes.append(points)
		return strokes
	strokes.append(split[0])
	strokes.append(split[1])
	return strokes


# The per-point WIDTH SCALE for a mark's strokes, paired with `mark` above: the arc is drawn at the
# shaft's own width and the cone flares to CONE_WIDTH_SCALE and converges to nothing.
#
# A SEPARATE FUNCTION rather than a second return value, because the two views need it at different
# moments -- OverlayMirror hands it to the ribbon builder, _draw uses it to lay out a polygon -- and
# because it is a pure function of the strokes, so there is no stored copy to drift. The coupling it
# DOES carry is that a mark is arc-then-cone; that is stated here, owned by this one class, and
# pinned by a case rather than left for two files to agree on by luck.
# The cone of a mark as a SOLID's terms rather than as a stroke's: where its base sits, where its
# tip does, and how wide the base is as a multiple of the shaft. Empty when the mark has no cone --
# too short to carry one, or CONE_LENGTH turned off -- which is the same "a lone stroke is a bare
# arc" rule `mark_widths` reads, stated once here so the two cannot disagree about which mark has a
# cone (#1069).
#
# THE SCALE, NOT A RADIUS, for CONE_WIDTH_SCALE's own reason: the shaft's width is a BoardOverlays
# export this 2D class cannot see. Whoever draws the solid multiplies it by the width it is drawing
# the shaft at, which is the same composition the ribbon does through UV2.y.
#
# The scale is PASSED since a squad tether's arrow (#1070) took its own knob: a reach mark hands in
# CONE_WIDTH_SCALE, a tether SquadLines2D.ARROW_WIDTH_SCALE, and neither reaches the other's.
static func cone_of(strokes: Array[PackedVector3Array], scale: float) -> Dictionary:
	if strokes.size() < 2:
		return {}
	var tail := strokes[strokes.size() - 1]
	if tail.size() < 2:
		return {}
	return {"base": tail[0], "tip": tail[tail.size() - 1], "scale": scale}


static func mark_widths(strokes: Array[PackedVector3Array], scale: float) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	for i in strokes.size():
		var scales := PackedFloat32Array()
		var points := strokes[i]
		# Only the LAST stroke of a two-stroke mark is a cone; a lone stroke is a bare arc.
		if i == strokes.size() - 1 and strokes.size() > 1:
			var total := _length_of(points)
			var walked := 0.0
			for j in points.size():
				if j > 0:
					walked += points[j].distance_to(points[j - 1])
				var t := 0.0 if total <= 0.0 else walked / total
				scales.append(lerpf(scale, 0.0, t))
		else:
			for _j in points.size():
				scales.append(1.0)
		out.append(scales)
	return out


# The curve, sampled at the sight trace's own density (Reach.TRACE_SAMPLES_PER_CELL) rather than at a
# second number nobody can compare against.
static func _sample_curve(from: Vector3, control: Vector3, to: Vector3, run_length: float) -> PackedVector3Array:
	var count := maxi(2, ceili(run_length * float(Reach.TRACE_SAMPLES_PER_CELL)) + 1)
	var points := PackedVector3Array()
	for i in count:
		var t := float(i) / float(count - 1)
		var mt := 1.0 - t
		points.append(from * (mt * mt) + control * (2.0 * mt * t) + to * (t * t))
	return points


# Split a sampled polyline into [head, tail] where the TAIL is exactly `tail_length` of ARC LENGTH.
# The split point is interpolated between samples and appears in BOTH halves, so the cone's base is
# crisp rather than landing wherever a sample happened to fall. Empty when the line is too short to
# carry a tail at all.
static func _split_at_tail(points: PackedVector3Array, tail_length: float) -> Array[PackedVector3Array]:
	var total := _length_of(points)
	if points.size() < 2 or total <= tail_length:
		return []
	var want := total - tail_length
	var walked := 0.0
	for i in range(1, points.size()):
		var step := points[i].distance_to(points[i - 1])
		if walked + step >= want:
			var t := 0.0 if step <= 0.0 else (want - walked) / step
			var base := points[i - 1].lerp(points[i], t)
			var head := points.slice(0, i)
			head.append(base)
			var tail := PackedVector3Array([base])
			tail.append_array(points.slice(i))
			var out: Array[PackedVector3Array] = []
			out.append(head)
			out.append(tail)
			return out
		walked += step
	return []


static func _length_of(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


func _draw() -> void:
	# The outline first: it lies on the ground, an intent hangs above it, and a mark crossing the
	# stroke should read over it.
	for segment in outlines:
		_polyline(segment, OverlayManager.FOCUS_OUTLINE_COLOR)
	for strokes: Array[PackedVector3Array] in marks:
		var widths := mark_widths(strokes, CONE_WIDTH_SCALE)
		for i in strokes.size():
			# A constant-width stroke is a polyline; a tapering one has to be a polygon, because
			# draw_polyline carries ONE width for the whole line.
			if i == strokes.size() - 1 and strokes.size() > 1:
				_taper(strokes[i], widths[i], MARK_LINE_COLOR)
			else:
				_polyline(strokes[i], MARK_LINE_COLOR)


func _polyline(seg: PackedVector3Array, color: Color) -> void:
	if seg.size() < 2:
		return
	var line := PackedVector2Array()
	for p in seg:
		line.append(_flat(p))
	draw_polyline(line, color, LINE_WIDTH)


# The flat twin of the ribbon's taper: one rim walked out and the other walked back, so the polygon
# closes without a seam. Built from the SAME scales the diorama pushes into UV2.y.
func _taper(seg: PackedVector3Array, scales: PackedFloat32Array, color: Color) -> void:
	if seg.size() < 2 or scales.size() != seg.size():
		return
	var line := PackedVector2Array()
	for p in seg:
		line.append(_flat(p))
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in line.size():
		var ahead := line[mini(i + 1, line.size() - 1)]
		var back := line[maxi(i - 1, 0)]
		var dir := (ahead - back)
		dir = Vector2.RIGHT if dir.length_squared() <= 0.0 else dir.normalized()
		var side := Vector2(-dir.y, dir.x) * LINE_WIDTH * scales[i] * 0.5
		left.append(line[i] + side)
		right.append(line[i] - side)
	right.reverse()
	left.append_array(right)
	draw_colored_polygon(left, color)


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) * float(GridUtils.TILE_SIZE)
