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
# The arrowhead is the reach mark's SHAPE, not its knobs: ARROW_LENGTH and ARROW_WIDTH_SCALE are the
# tethers' own, and the diorama draws it on the see-through twin of the reach cone's shader, so a
# tether colour's alpha fades the arrow with the shaft (dev, 2026-09-22).
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
# A tether that MIGHT be: dimmer and see-through, arrowhead included.
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
# The arrowhead at the leader's end: its length in cells (zero leaves a bare line), and its base as a
# MULTIPLE of the tether's own width -- ThreatLines2D.CONE_WIDTH_SCALE's reason, since the 3D width is
# a BoardOverlays export this class cannot see.
static var ARROW_LENGTH := 0.4
static var ARROW_WIDTH_SCALE := 2.4
# The refused click's pluck (#1070, dev: "if they try clicking, the tether gives a shake"). How far the
# middle swings, in cells; how long it rings; and how many times it swings in that time.
static var SHAKE_AMPLITUDE := 0.12
static var SHAKE_SECONDS := 0.4
static var SHAKE_SWINGS := 3.0

# MEMBERSHIP MOMENTS (#367): a join DRAWS the tether in, a voluntary leave REELS it into the leader.
# A moment is its own short-lived drawing, never a state on a standing tether, because tethers stand
# only while something is selected and membership changes when nothing may be.
enum Moment { DRAW_IN, REEL_IN }

# The draw-in: how long the shaft takes to reach the leader, then the cone's pop -- how far past its
# own size it swells (a multiple) and how long it takes to settle. With a standing tether to hand over
# to (mid-Squad Up) the moment ends there; with none it holds, then fades.
static var DRAW_IN_SECONDS := 0.4
static var POP_SCALE := 1.8
static var POP_SECONDS := 0.22
static var DRAWN_HOLD_SECONDS := 0.6
static var DRAWN_FADE_SECONDS := 0.3
# How far the popping cone whitens, 0-1. A flash, so #217's setting drops it.
static var POP_BRIGHTEN := 0.8
# The reel-in: how long the tether takes to be pulled into the leader. A new leader's links wait
# this long before they draw in, which is the dev's "then".
static var REEL_IN_SECONDS := 0.45

# What this node draws, handed down by OverlayManager (the store). Trace space, like ThreatLines2D.
var outline: Array[PackedVector3Array] = []
var tethers: Array[Dictionary] = []   # {"strokes": Array[PackedVector3Array], "state": Strain}
var moments: Array[Dictionary] = []   # OverlayManager.squad_tether_moments
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
	var m := measure(tether_chord)
	if m.is_empty():
		return strokes
	strokes.append(shaft_between(tether_chord, 0.0, m["shaft_end"]))
	if m["shaft_end"] < m["tip"]:
		strokes.append(PackedVector3Array([point_along(tether_chord, m["shaft_end"]),
				point_along(tether_chord, m["tip"])]))
	return strokes


# Where a tether's parts fall along its chord, as distances from the MEMBER end: the cone's tip and
# where the shaft stops for it. THE one derivation, read by tether() and by every membership moment,
# so a moment's arrow cannot sit anywhere the standing one would not. Empty for a chord of no length.
static func measure(tether_chord: PackedVector3Array) -> Dictionary:
	if tether_chord.size() < 2:
		return {}
	var length := (tether_chord[1] - tether_chord[0]).length()
	if length <= 0.0:
		return {}
	var tip := length - minf(TETHER_INSET, length)
	# No room for the arrow: the bare shaft still says who is tied to whom.
	var shaft_end := tip if ARROW_LENGTH <= 0.0 or tip <= ARROW_LENGTH else tip - ARROW_LENGTH
	return {"length": length, "tip": tip, "shaft_end": shaft_end}


# The point `distance` along the chord from the member end.
static func point_along(tether_chord: PackedVector3Array, distance: float) -> Vector3:
	var span := tether_chord[1] - tether_chord[0]
	return tether_chord[0] + span.normalized() * distance


# The shaft from `from` to `to` along the chord, SAMPLED rather than two points, because the shake is
# a vertex offset pinned at both ends: a two-point ribbon has nothing between its ends to bend. The
# reach arc's own density.
static func shaft_between(tether_chord: PackedVector3Array, from: float, to: float) -> PackedVector3Array:
	var a := point_along(tether_chord, from)
	var b := point_along(tether_chord, to)
	var count := maxi(2, ceili(maxf(to - from, 0.0) * float(Reach.TRACE_SAMPLES_PER_CELL)) + 1)
	var shaft := PackedVector3Array()
	for i in count:
		shaft.append(a.lerp(b, float(i) / float(count - 1)))
	return shaft


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


# What a membership moment draws `elapsed` seconds in (#367) -- THE one answer both views read.
# `standing` says a standing tether exists for the same pair (a draw-in hands over to it rather than
# fading); `flash` is #217's composed read. Returns the shaft as a range along the chord, [u0, u1],
# measured from the member end (empty when u1 <= u0), its tint, the cone -- how far it has grown out
# of the shaft, its scale about its own tip, its tint -- and whether the moment is over.
static func moment_at(moment: int, tether_chord: PackedVector3Array, elapsed: float, standing: bool,
		flash := true) -> Dictionary:
	var m := measure(tether_chord)
	var drawn := {"u0": 0.0, "u1": 0.0, "tint": TETHER_COLOR, "cone_grow": 0.0, "cone_scale": 1.0,
			"cone_tint": TETHER_COLOR, "done": false}
	if m.is_empty():
		drawn["done"] = true
		return drawn
	var tip: float = m["tip"]
	var shaft_end: float = m["shaft_end"]
	var has_cone := shaft_end < tip
	match moment:
		Moment.DRAW_IN:
			if elapsed < 0.0:
				return drawn   # waiting its turn: a new leader's link, behind the old ones' exit
			var front := _ease_out(_phase(elapsed, DRAW_IN_SECONDS)) * tip
			drawn["u1"] = minf(front, shaft_end)
			if has_cone and front > shaft_end:
				drawn["cone_grow"] = clampf((front - shaft_end) / (tip - shaft_end), 0.0, 1.0)
			var after := elapsed - DRAW_IN_SECONDS
			if after >= 0.0:
				var settle := 1.0 - _phase(after, POP_SECONDS)
				drawn["cone_scale"] = 1.0 + (maxf(POP_SCALE, 1.0) - 1.0) * settle
				if flash:
					drawn["cone_tint"] = _brighten(TETHER_COLOR, POP_BRIGHTEN * settle)
				after -= maxf(POP_SECONDS, 0.0)
				if after >= 0.0:
					if standing:
						drawn["done"] = true
					else:
						after -= maxf(DRAWN_HOLD_SECONDS, 0.0)
						var fade := _phase(after, DRAWN_FADE_SECONDS) if after >= 0.0 else 0.0
						drawn["tint"] = _faded(TETHER_COLOR, 1.0 - fade)
						drawn["cone_tint"] = _faded(drawn["cone_tint"], 1.0 - fade)
						drawn["done"] = after >= 0.0 and fade >= 1.0
		Moment.REEL_IN:
			drawn["cone_grow"] = 1.0 if has_cone else 0.0
			var pulled := _ease_in(_phase(maxf(elapsed, 0.0), REEL_IN_SECONDS)) * tip
			drawn["u0"] = pulled
			drawn["u1"] = shaft_end
			if has_cone and pulled > shaft_end:
				drawn["cone_scale"] = clampf((tip - pulled) / (tip - shaft_end), 0.0, 1.0)
			drawn["done"] = elapsed >= maxf(REEL_IN_SECONDS, 0.0)
	return drawn


# How long a moment lasts at most, for a caller that has to know when to stop asking.
static func moment_seconds(moment: int) -> float:
	if moment == Moment.REEL_IN:
		return maxf(REEL_IN_SECONDS, 0.0)
	return maxf(DRAW_IN_SECONDS, 0.0) + maxf(POP_SECONDS, 0.0) + maxf(DRAWN_HOLD_SECONDS, 0.0) \
			+ maxf(DRAWN_FADE_SECONDS, 0.0)


# 0 to 1 through `seconds`. A zero duration is already over, never a division.
static func _phase(elapsed: float, seconds: float) -> float:
	if seconds <= 0.0:
		return 1.0
	return clampf(elapsed / seconds, 0.0, 1.0)


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


static func _ease_in(t: float) -> float:
	return t * t


static func _brighten(color: Color, amount: float) -> Color:
	var lit := color.lerp(Color.WHITE, clampf(amount, 0.0, 1.0))
	lit.a = color.a
	return lit


static func _faded(color: Color, alpha: float) -> Color:
	var faded := color
	faded.a = color.a * clampf(alpha, 0.0, 1.0)
	return faded


# A stored moment (OverlayManager.squad_tether_moments) as the geometry that draws it NOW, in trace
# space: the shaft's points, the chord's origin (each view measures its own dash offset from it, so
# the dashes stay where the standing tether's would be), its tint, and the cone -- base, tip, width
# scale, tint -- or {} while there is none. The one conversion both views read.
static func moment_drawing(entry: Dictionary, now_msec: int, flash: bool) -> Dictionary:
	var tether_chord: PackedVector3Array = entry["chord"]
	var elapsed := float(now_msec - int(entry["start_msec"])) / 1000.0
	var drawn := moment_at(int(entry["moment"]), tether_chord, elapsed, bool(entry.get("standing", false)),
			flash)
	var out := {"origin": tether_chord[0], "shaft": PackedVector3Array(), "tint": drawn["tint"],
			"cone": {}, "done": drawn["done"]}
	var u0: float = drawn["u0"]
	var u1: float = drawn["u1"]
	if u1 > u0:
		out["shaft"] = shaft_between(tether_chord, u0, u1)
	var grow: float = drawn["cone_grow"]
	var scale: float = drawn["cone_scale"]
	if grow > 0.0 and scale > 0.0:
		var m := measure(tether_chord)
		var base_u: float = m["shaft_end"]
		var tip := point_along(tether_chord, base_u + (float(m["tip"]) - base_u) * grow)
		var base := tip + (point_along(tether_chord, base_u) - tip) * scale
		out["cone"] = {"base": base, "tip": tip, "scale": ARROW_WIDTH_SCALE * scale,
				"tint": drawn["cone_tint"]}
	return out


static func color_of(state: int) -> Color:
	match state:
		Strain.GHOST:
			return TETHER_GHOST_COLOR
		Strain.STRAIN:
			return TETHER_STRAIN_COLOR
	return TETHER_COLOR


# The store has changed: redraw now, and keep redrawing while there is anything to march.
func refresh() -> void:
	set_process(not (outline.is_empty() and tethers.is_empty() and moments.is_empty()))
	queue_redraw()


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	# A frozen board redraws only when the store changes (refresh), never per frame. A moment is the
	# exception: it plays on the clock whatever #217 says, since only its flash is motion to be stilled.
	if BoardOverlays.beams_animating() or not moments.is_empty():
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
		var cone := ThreatLines2D.cone_of(strokes, ARROW_WIDTH_SCALE)
		if not cone.is_empty():
			_cone(_flat(cone["base"]), _flat(cone["tip"]), float(cone["scale"]), color)
	var now := Time.get_ticks_msec()
	var flash := BoardOverlays.beams_animating()
	for entry in moments:
		var drawing := moment_drawing(entry, now, flash)
		var shaft: PackedVector3Array = drawing["shaft"]
		if shaft.size() >= 2:
			var origin := _flat(drawing["origin"])
			var from := _flat(shaft[0])
			_dashed(from, _flat(shaft[shaft.size() - 1]), drawing["tint"], shift, 0.0,
					from.distance_to(origin) / float(GridUtils.TILE_SIZE))
		var cone: Dictionary = drawing["cone"]
		if not cone.is_empty():
			_cone(_flat(cone["base"]), _flat(cone["tip"]), float(cone["scale"]), cone["tint"])


# One straight stroke, dashed. `bend` plucks it: every point moves sideways by bend * sin(pi * u),
# so both ends stay pinned -- which is why a dash is drawn as a short polyline rather than a segment.
# `start` is how far along its tether the stroke begins, in cells, so a part-drawn tether's dashes
# sit where the whole one's would.
func _dashed(from: Vector2, to: Vector2, color: Color, shift: float, bend: float, start := 0.0) -> void:
	var span := to - from
	var length_px := span.length()
	if length_px <= 0.0:
		return
	var cell_px := float(GridUtils.TILE_SIZE)
	var dir := span / length_px
	var side := Vector2(-dir.y, dir.x) * bend * cell_px
	var length := length_px / cell_px
	for dash in dash_spans(start + length, shift):
		var a := maxf(dash.x - start, 0.0)
		var b := dash.y - start
		if b <= a:
			continue
		var line := PackedVector2Array()
		for k in 4:
			var d: float = lerpf(a, b, float(k) / 3.0) * cell_px
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
