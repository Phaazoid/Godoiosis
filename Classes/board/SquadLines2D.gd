class_name SquadLines2D
extends Node2D

# A squad's LINES (#1070): a TETHER from each member to its leader, and a dashed stroke round the
# COHESION RANGE -- one system, so they are drawn alike (dev: "orange, dashed, with the dashes slowly
# moving... so the player knows they are part of the same system"). They replaced the orange cohesion
# fill, which the move layer's show_overlay ERASED wherever the two met, so the range was only ever
# visible where you could not walk.
#
# The flat view's renderer AND the owner of the values both views read -- ThreatLines2D's and
# MoveGrid's shape: OverlayManager holds the store, OverlayMirror lifts the same points into the
# diorama, and a Game-tab row moves both.
#
# EVERY TETHER POINTS AT THE LEADER (dev: "Arrows should always go towards the squad leader. For all
# these tethers"), with the same solid cone the reach marks end in. So a stroke always runs member ->
# leader, and the dashes march that way too, because they move toward the end a stroke runs to.
#
# THREE STATES, one layer each in the diorama because a layer is one material: SOLID for a member,
# GHOST for a unit that COULD join (Squad Up's candidates, Join Squad's squads), STRAIN for the
# tether a hovered move would break -- the one that SHAKES when that move is clicked anyway.
#
# The dashes MOVE, which spends the repeating-dash motion #674 had reserved for the aim's sight line.
# The dev ruled it SHARED, told apart by colour (2026-09-22), so this does not claim it outright.

enum Strain { SOLID, GHOST, STRAIN }

# The flat view's stroke, in pixels at 16 to a cell. Wider than a reach mark's 1.5 because a dash
# pattern loses its read at a pixel and a half.
const LINE_WIDTH := 2.0

# One ORANGE for the tether and the range, which is what makes them read as one system. The cohesion
# fill wore Color(1, 0.5, 0) for the project's whole life, so the hue is not new -- only its form is.
static var TETHER_COLOR := Color(1.0, 0.55, 0.12, 0.95)
# A tether that MIGHT be: dimmer in its RGB as well as its alpha, because the diorama's cone is a
# SOLID on an opaque shader that reads no alpha at all -- a ghost there is darker, not see-through.
static var TETHER_GHOST_COLOR := Color(0.72, 0.42, 0.16, 0.5)
static var TETHER_STRAIN_COLOR := Color(1.0, 0.18, 0.14, 0.95)
# DASHES PER TILE, not a dash length, and that is what lets the range's stroke stay one pattern
# without being chained into loops: the stroke is one segment per outward cell edge, so a period that
# divides an edge meets the next edge in phase. A free length would restart visibly at every corner.
static var DASHES_PER_TILE := 3
# How much of each period is ink, 0-1.
static var DASH_FILL := 0.55
# Cells per second, toward the leader on a tether and clockwise round the range.
static var DASH_SPEED := 0.35
# How far short of the leader's centre the cone's tip stops, in cells -- so the arrow meets the body
# instead of vanishing behind it. The MEMBER end starts at its centre: the sprite draws over what it
# covers there, which is what "connect the middle of the sprites" looks like.
static var TETHER_INSET := 0.25
# The refused click's pluck (#1070, dev: "if they try clicking, the tether gives a shake"). How far the
# middle swings, in cells; how long it rings; and how many times it swings in that time.
static var SHAKE_AMPLITUDE := 0.12
static var SHAKE_SECONDS := 0.4
static var SHAKE_SWINGS := 3.0

# What this node draws, handed down by OverlayManager (the store). Trace space, like ThreatLines2D.
var outline: Array[PackedVector3Array] = []
var tethers: Array[Dictionary] = []   # {"strokes": Array[PackedVector3Array], "state": Strain}
var shake_started_msec := -1


# The body's middle, in the RULE height units trace space carries (UnitSprite3D.body_middle is world).
static func body_middle_rule() -> float:
	return UnitSprite3D.body_middle() / BoardSpace.ROW_HEIGHT


# A tether's CHORD: the middles of the two bodies, member first. Measured from each cell's CENTRE
# surface for ThreatLines2D.segment's reason -- a body on a ramp stands at the slope's midpoint.
static func chord(member_cell: Vector2i, leader_cell: Vector2i, board: BoardContext) -> PackedVector3Array:
	var points := PackedVector3Array()
	for cell in [member_cell, leader_cell]:
		var h := 0.0 if board == null else Terrain.height_at_uv(board.corners_at(cell), 0.5, 0.5)
		points.append(Vector3(float(cell.x) + 0.5, h + body_middle_rule(), float(cell.y) + 0.5))
	return points


# The tether as the strokes that draw it -- the shaft, then the cone at the leader's end -- in
# ThreatLines2D.mark's shape, so its cone_of and mark_widths read a tether exactly as they read a
# reach mark and the two arrows cannot be built two ways.
#
# The shaft is SAMPLED rather than two points, because the shake is a vertex offset pinned at both
# ends: a two-point ribbon has nothing between its ends to bend. The reach arc's own density.
static func tether(tether_chord: PackedVector3Array) -> Array[PackedVector3Array]:
	var strokes: Array[PackedVector3Array] = []
	if tether_chord.size() < 2:
		return strokes
	var span := tether_chord[1] - tether_chord[0]
	var length := span.length()
	if length <= 0.0:
		return strokes
	var dir := span / length
	var tip := tether_chord[1] - dir * minf(TETHER_INSET, length)
	var run := (tip - tether_chord[0]).length()
	var cone := ThreatLines2D.CONE_LENGTH
	# No room for the arrow: the bare shaft still says who is tied to whom.
	var shaft_end := tip if cone <= 0.0 or run <= cone else tip - dir * cone
	var shaft_length := (shaft_end - tether_chord[0]).length()
	var count := maxi(2, ceili(shaft_length * float(Reach.TRACE_SAMPLES_PER_CELL)) + 1)
	var shaft := PackedVector3Array()
	for i in count:
		shaft.append(tether_chord[0].lerp(shaft_end, float(i) / float(count - 1)))
	strokes.append(shaft)
	if shaft_end != tip:
		strokes.append(PackedVector3Array([shaft_end, tip]))
	return strokes


# The dash period, in cells. At least one dash per tile, whatever the knob says.
static func dash_period() -> float:
	return 1.0 / float(maxi(DASHES_PER_TILE, 1))


# Where the ink falls along a stroke of `length` cells, as [start, end] pairs. `shift` is how far the
# pattern has marched -- DASH_SPEED times the clock -- so a dash sits wherever
# (distance - shift) mod period lands inside the ink. The diorama's shader asks the same question of
# its UV2.x, which is why the two views march in step.
static func dash_spans(length: float, shift: float) -> PackedVector2Array:
	var spans := PackedVector2Array()
	var period := dash_period()
	var ink := period * clampf(DASH_FILL, 0.0, 1.0)
	if length <= 0.0 or ink <= 0.0:
		return spans
	var start := fposmod(shift, period) - period
	while start < length:
		var a := maxf(start, 0.0)
		var b := minf(start + ink, length)
		if b > a:
			spans.append(Vector2(a, b))
		start += period
	return spans


# How far the middle of a strained tether is displaced `elapsed` seconds into a shake, in cells. A
# decaying swing, so the pluck rings and settles; zero outside the shake. The one envelope both views
# read, so the flat line and the ribbon swing together.
static func shake_offset(elapsed: float) -> float:
	if elapsed < 0.0 or SHAKE_SECONDS <= 0.0 or elapsed >= SHAKE_SECONDS:
		return 0.0
	var t := elapsed / SHAKE_SECONDS
	return SHAKE_AMPLITUDE * (1.0 - t) * (1.0 - t) * sin(TAU * SHAKE_SWINGS * t)


# ...and the same, asked of a store's stamp. A shake is motion, so #217's rule stills it -- the RED is
# what carries the refusal, and it does not move.
static func shake_now(started_msec: int) -> float:
	if started_msec < 0 or not BoardOverlays.beams_animating():
		return 0.0
	return shake_offset(float(Time.get_ticks_msec() - started_msec) / 1000.0)


static func color_of(state: int) -> Color:
	match state:
		Strain.GHOST:
			return TETHER_GHOST_COLOR
		Strain.STRAIN:
			return TETHER_STRAIN_COLOR
	return TETHER_COLOR


# The store has changed: redraw now, and keep redrawing while there is anything to march.
func refresh() -> void:
	set_process(not (outline.is_empty() and tethers.is_empty()))
	queue_redraw()


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	# A frozen board redraws only when the store changes (refresh), never per frame.
	if BoardOverlays.beams_animating():
		queue_redraw()


func _draw() -> void:
	var shift := 0.0
	if BoardOverlays.beams_animating():
		shift = DASH_SPEED * float(Time.get_ticks_msec()) / 1000.0
	for segment in outline:
		if segment.size() >= 2:
			_dashed(_flat(segment[0]), _flat(segment[segment.size() - 1]), TETHER_COLOR, shift, 0.0)
	var shake := shake_now(shake_started_msec)
	for entry in tethers:
		var strokes: Array[PackedVector3Array] = []
		strokes.assign(entry["strokes"])
		if strokes.is_empty():
			continue
		var state: int = entry["state"]
		var color := color_of(state)
		var shaft := strokes[0]
		var bend := shake if state == Strain.STRAIN else 0.0
		_dashed(_flat(shaft[0]), _flat(shaft[shaft.size() - 1]), color, shift, bend)
		var cone := ThreatLines2D.cone_of(strokes)
		if not cone.is_empty():
			_cone(_flat(cone["base"]), _flat(cone["tip"]), float(cone["scale"]), color)


# One straight stroke, dashed. `bend` plucks it: every point moves sideways by bend * sin(pi * u),
# so both ends stay pinned -- which is why a dash is drawn as a short polyline rather than a segment.
func _dashed(from: Vector2, to: Vector2, color: Color, shift: float, bend: float) -> void:
	var span := to - from
	var length_px := span.length()
	if length_px <= 0.0:
		return
	var cell_px := float(GridUtils.TILE_SIZE)
	var dir := span / length_px
	var side := Vector2(-dir.y, dir.x) * bend * cell_px
	for dash in dash_spans(length_px / cell_px, shift):
		var line := PackedVector2Array()
		for k in 4:
			var d: float = lerpf(dash.x, dash.y, float(k) / 3.0) * cell_px
			var u := d / length_px
			line.append(from + dir * d + side * sin(PI * u))
		draw_polyline(line, color, LINE_WIDTH)


# The arrowhead: a filled triangle, the flat twin of the diorama's solid cone.
func _cone(base: Vector2, tip: Vector2, scale: float, color: Color) -> void:
	var span := tip - base
	if span.length_squared() <= 0.0:
		return
	var dir := span.normalized()
	var side := Vector2(-dir.y, dir.x) * LINE_WIDTH * scale * 0.5
	draw_colored_polygon(PackedVector2Array([base + side, tip, base - side]), color)


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) * float(GridUtils.TILE_SIZE)
