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
static var TETHER_COLOR := Color(1.0, 0.55, 0.12, 1.0)
# ...and an ENEMY squad's range and tethers (#1109): the threat field's purple, lightened so it reads
# over that field and over bare ground alike. Standing lines and moments both; is_hostile picks the side.
static var ENEMY_TETHER_COLOR := Color(1.0, 0.43, 0.59, 1.0)
# The dark CASING round every squad line, both sides' (#1109 round 2): the rose vanished into its own
# pink field over pale stone, and a dark edge reads on any floor. Its alpha is multiplied by the line's,
# so a ghost's casing is as see-through as the ghost.
static var CASING_COLOR := Color(0.13, 0.03, 0.1, 1.0)
# ...and its width in the flat view, in pixels each side. The diorama's is a BoardOverlays export, in
# world units, which this class cannot see -- ARROW_WIDTH_SCALE's reason.
const CASING_PX := 1.0
# A tether that MIGHT be: dimmer than a standing one. Its alpha fades the arrowhead with the shaft.
static var TETHER_GHOST_COLOR := Color(0.72, 0.42, 0.16, 1.0)
static var TETHER_STRAIN_COLOR := Color(1.0, 0.18, 0.14, 1.0)
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

# MEMBERSHIP MOMENTS (#367): a join DRAWS the tether in, a voluntary leave REELS it into the leader,
# a forced one BREAKS it. A moment is its own short-lived drawing, never a state on a standing
# tether, because tethers stand only while something is selected and membership changes when nothing
# may be. A DEATH plays one of the last four (#1104) -- see DEATH_LOOKS.
enum Moment { DRAW_IN, REEL_IN, BREAK, DRAIN, SLACK, PULSE, MOTES }

# The four a death picks between (#1104; the dev: all of them, a different one each time). In each the
# dashes stop where they stood and the tether turns to ash: DRAIN runs the ash from the dead end to the
# other, SLACK sags and drops the dead end to the ground, PULSE runs a warm light to whoever is left, and
# MOTES crumbles into pale motes that drift up.
const DEATH_LOOKS: Array[int] = [Moment.DRAIN, Moment.SLACK, Moment.PULSE, Moment.MOTES]

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
# The break (#367 part 2B, the dev's "snap, sparks, and shatter"): the tether STRAINS toward the
# strain red and shivers, SNAPS at the middle of its shaft, and its dashes and arrowhead SHATTER --
# kicked apart along the chord, tumbling, landing on the ground under it as they fade. How long the
# strain builds; how long the pieces take to land and fade.
static var BREAK_STRAIN_SECONDS := 0.35
static var BREAK_SHATTER_SECONDS := 0.7
# How fast the pieces fly apart from the snap, in cells per second, and how many times each turns
# over on the way down.
static var BREAK_KICK := 0.8
static var BREAK_TUMBLE_TURNS := 1.0
# The sparks at the snap: how many, how fast they fly (cells per second), and how long they last.
static var BREAK_SPARKS := 8
static var BREAK_SPARK_SPEED := 2.5
static var BREAK_SPARK_SECONDS := 0.3
# A spark's streak is how far it travels in this long -- a motion trail, so a fast spark reads longer.
const SPARK_TRAIL_SECONDS := 0.04
# HealthBlockDebris's scatter: derived per index, never rolled.
const GOLDEN_ANGLE := 2.39996323

# A DEATH's moment (#1104). Which look plays: 0 picks one per death (death_look), 1-4 pins DRAIN, SLACK,
# PULSE or MOTES, for tuning one at a time.
static var DEATH_LOOK := 0
# The ash every look turns to, whichever side the tether was.
static var DEATH_ASH_COLOR := Color(0.59, 0.56, 0.53, 1.0)
# How long the ash takes to come in (PULSE and MOTES; DRAIN and SLACK grey as they go), how long a look
# holds it, and how long the fade that closes it takes.
static var DEATH_GREY_SECONDS := 0.2
static var DEATH_HOLD_SECONDS := 0.25
static var DEATH_FADE_SECONDS := 0.45
# DRAIN: how long the ash takes to run the tether's length.
static var DRAIN_SECONDS := 0.55
# SLACK: how long the fall takes, and how far the middle sags below where it hung, in cells.
static var SLACK_SECONDS := 0.5
static var SLACK_SAG := 0.2
# PULSE: how long the light takes to reach whoever is left, its colour, and its length in cells.
static var PULSE_SECONDS := 0.55
static var PULSE_COLOR := Color(1.0, 0.72, 0.38, 1.0)
static var PULSE_LENGTH := 0.35
# MOTES: how many each dash crumbles into, how far they rise (cells), and how long one lasts at most.
static var MOTES_PER_DASH := 4
static var MOTE_RISE := 0.5
static var MOTE_SECONDS := 0.9
# How far the ash front's edge blends, in cells, and how long a crumbling dash takes to go.
const DRAIN_BLEND := 0.5
const CRUMBLE_SECONDS := 0.1
# A mote's own length, in cells: a speck, drawn as the shortest stroke that still reads.
const MOTE_SIZE := 0.05

# What this node draws, handed down by OverlayManager (the store). Trace space, like ThreatLines2D.
var outline: Array[PackedVector3Array] = []
var tethers: Array[Dictionary] = []   # {"strokes": Array[PackedVector3Array], "state": Strain}
var moments: Array[Dictionary] = []   # OverlayManager.squad_tether_moments
var shake_started_msec := -1
# Whose squad the standing lines belong to (#1109) -- one side per draw, OverlayManager.squad_lines_hostile.
var hostile := false


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


# A sampled shaft plucked sideways by `bend` cells, pinned at both ends -- the flat view's _dashed
# offset, for a view that draws the points themselves. The side is the chord's own in the ground plane.
static func bent(shaft: PackedVector3Array, bend: float) -> PackedVector3Array:
	if is_zero_approx(bend) or shaft.size() < 2:
		return shaft
	var span := shaft[shaft.size() - 1] - shaft[0]
	var side := Vector3(-span.z, 0.0, span.x).normalized()
	var out := PackedVector3Array()
	for i in shaft.size():
		out.append(shaft[i] + side * bend * sin(PI * float(i) / float(shaft.size() - 1)))
	return out


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
# of the shaft, its scale about its own tip, its tint -- and whether the moment is over. `hostile_side`
# is whose squad it is (#1109): an enemy's moment wears the enemy colour, and a break still strains to
# the one strain red, which means "breaking" for either side. `snap` is when a break snaps (#1104) --
# snap_seconds' answer, negative for the strain's own end.
static func moment_at(moment: int, tether_chord: PackedVector3Array, elapsed: float, standing: bool,
		flash := true, hostile_side := false, snap := -1.0) -> Dictionary:
	var m := measure(tether_chord)
	var base := tether_color(hostile_side)
	var drawn := {"u0": 0.0, "u1": 0.0, "tint": base, "cone_grow": 0.0, "cone_scale": 1.0,
			"cone_tint": base, "done": false}
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
					drawn["cone_tint"] = _brighten(base, POP_BRIGHTEN * settle)
				after -= maxf(POP_SECONDS, 0.0)
				if after >= 0.0:
					if standing:
						drawn["done"] = true
					else:
						after -= maxf(DRAWN_HOLD_SECONDS, 0.0)
						var fade := _phase(after, DRAWN_FADE_SECONDS) if after >= 0.0 else 0.0
						drawn["tint"] = _faded(base, 1.0 - fade)
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
		Moment.BREAK:
			# Whole until it snaps, reddening over the strain and holding red past it; after the snap the
			# tether is its pieces (moment_drawing).
			var strain := maxf(BREAK_STRAIN_SECONDS, 0.0)
			var at := snap if snap >= 0.0 else strain
			if elapsed < at:
				var tint := base.lerp(TETHER_STRAIN_COLOR, _phase(maxf(elapsed, 0.0), strain))
				drawn["u1"] = shaft_end
				drawn["cone_grow"] = 1.0 if has_cone else 0.0
				drawn["tint"] = tint
				drawn["cone_tint"] = tint
			drawn["done"] = elapsed >= at + _break_tail()
		Moment.DRAIN, Moment.SLACK, Moment.PULSE, Moment.MOTES:
			# A death is its pieces from the first frame (moment_drawing): no shaft, no cone here.
			drawn["done"] = elapsed >= moment_seconds(moment)
		_:
			push_error("moment_at: no arm for moment %d" % moment)
			drawn["done"] = true
	return drawn


# How long a moment lasts at most, for a caller that has to know when to stop asking.
static func moment_seconds(moment: int) -> float:
	match moment:
		Moment.DRAW_IN:
			return maxf(DRAW_IN_SECONDS, 0.0) + maxf(POP_SECONDS, 0.0) + maxf(DRAWN_HOLD_SECONDS, 0.0) \
					+ maxf(DRAWN_FADE_SECONDS, 0.0)
		Moment.REEL_IN:
			return maxf(REEL_IN_SECONDS, 0.0)
		Moment.BREAK:
			return maxf(BREAK_STRAIN_SECONDS, 0.0) + _break_tail()
		Moment.DRAIN, Moment.SLACK, Moment.PULSE:
			return _death_fade_start(moment) + maxf(DEATH_FADE_SECONDS, 0.0)
		Moment.MOTES:
			return maxf(DEATH_GREY_SECONDS, 0.0) + maxf(MOTE_SECONDS, 0.0)
	push_error("moment_seconds: no arm for moment %d" % moment)
	return 0.0


# When a death look's closing fade begins: DRAIN and SLACK hold their ash once it has run or fallen,
# PULSE fades as its light arrives. MOTES has no fade of its own -- every mote fades as it rises.
static func _death_fade_start(moment: int) -> float:
	match moment:
		Moment.DRAIN:
			return maxf(DRAIN_SECONDS, 0.0) + maxf(DEATH_HOLD_SECONDS, 0.0)
		Moment.SLACK:
			return maxf(SLACK_SECONDS, 0.0) + maxf(DEATH_HOLD_SECONDS, 0.0)
		Moment.PULSE:
			return maxf(maxf(PULSE_SECONDS, 0.0), maxf(DEATH_GREY_SECONDS, 0.0))
	return 0.0


# When a stored break SNAPS, in seconds after it starts (#1104): the strain's end, unless the entry
# says otherwise -- a break at the ledge HOLDS (INF) until the body lets go, then snaps then. The one
# answer both views and the moments' clock read.
static func snap_seconds(entry: Dictionary) -> float:
	return float(entry.get("snap", maxf(BREAK_STRAIN_SECONDS, 0.0)))


# What a break plays after it snaps: the shatter, or the sparks if they outlast it.
static func _break_tail() -> float:
	return maxf(maxf(BREAK_SHATTER_SECONDS, 0.0), maxf(BREAK_SPARK_SECONDS, 0.0))


# How long a moment takes to SAY what it says -- a draw-in once its cone has popped, the others at
# their end. What a pass that plays one at the blow waits for; a draw-in's hold and fade need no one
# watching.
static func shown_seconds(moment: int) -> float:
	if moment == Moment.DRAW_IN:
		return maxf(DRAW_IN_SECONDS, 0.0) + maxf(POP_SECONDS, 0.0)
	return moment_seconds(moment)


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
# scale, tint -- or {} while there is none; plus a break's `bend` (the shiver, in cells), its and a
# death's `pieces` (solid two-point strokes, each with its own tint), and a PULSE's `glow` (its light:
# `points`, a stroke along the chord, and `tint`) or {}. The one conversion both views read.
# The entry's `hostile` (#1109) says whose squad the link was, which picks the colour; a death's
# `leader_died` says which end is gone (#1104).
static func moment_drawing(entry: Dictionary, now_msec: int, flash: bool) -> Dictionary:
	var tether_chord: PackedVector3Array = entry["chord"]
	var elapsed := float(now_msec - int(entry["start_msec"])) / 1000.0
	var hostile_side := bool(entry.get("hostile", false))
	var snap := snap_seconds(entry)
	var drawn := moment_at(int(entry["moment"]), tether_chord, elapsed, bool(entry.get("standing", false)),
			flash, hostile_side, snap)
	var no_pieces: Array[Dictionary] = []
	var out := {"origin": tether_chord[0], "shaft": PackedVector3Array(), "tint": drawn["tint"],
			"cone": {}, "done": drawn["done"], "bend": 0.0, "pieces": no_pieces, "glow": {}}
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
	if int(entry["moment"]) == Moment.BREAK:
		# The dashes shatter where they stood at the snap, so the march is frozen at that instant.
		var snap_shift := 0.0
		if flash and elapsed >= snap:
			snap_shift = DASH_SPEED * (float(int(entry["start_msec"])) / 1000.0 + snap)
		_break_drawing(out, tether_chord, elapsed, snap_shift, flash, hostile_side, snap)
	elif DEATH_LOOKS.has(int(entry["moment"])):
		# ...and a death's stop where they stood at the death.
		var death_shift := DASH_SPEED * float(int(entry["start_msec"])) / 1000.0 if flash else 0.0
		_death_drawing(out, int(entry["moment"]), tether_chord, elapsed, death_shift, flash, hostile_side,
				bool(entry.get("leader_died", false)))
	return out


# The break's own geometry, written into a moment's drawing (#367 part 2B). Before the snap: the
# shiver, as a `bend` both views apply to the shaft the way the pluck does. After it: `pieces` -- each
# dash on screen at the snap, and the sparks -- as two-point strokes with their own tints, and the
# arrowhead falling in `cone`. Every piece is kicked away from the snap along the chord, scattered
# sideways, tumbled about the chord's side axis, and lands on the ground under the chord (its body-
# middle height taken back off) exactly as its time runs out, eased in like a fall. A break HELD past
# its strain (#1104, the ledge) keeps shivering at the strain's full swing until `snap_at`.
static func _break_drawing(out: Dictionary, tether_chord: PackedVector3Array, elapsed: float,
		snap_shift: float, flash: bool, hostile_side := false, snap_at := -1.0) -> void:
	var m := measure(tether_chord)
	if m.is_empty():
		return
	var strain := maxf(BREAK_STRAIN_SECONDS, 0.0)
	var at := snap_at if snap_at >= 0.0 else strain
	if elapsed < at:
		# A shake is motion, so #217 stills it (the pluck's own rule); the red still says it.
		if flash and elapsed < strain:
			var t := _phase(maxf(elapsed, 0.0), strain)
			out["bend"] = SHAKE_AMPLITUDE * t * sin(TAU * SHAKE_SWINGS * t)
		elif flash and strain > 0.0:
			out["bend"] = SHAKE_AMPLITUDE * sin(TAU * SHAKE_SWINGS * elapsed / strain)
		return
	var after := elapsed - at
	var length: float = m["length"]
	var shaft_end: float = m["shaft_end"]
	var tip: float = m["tip"]
	var snap_u := shaft_end * 0.5
	var along := (tether_chord[1] - tether_chord[0]) / length
	var side := Vector3(-along.z, 0.0, along.x).normalized()
	var fall := _phase(after, BREAK_SHATTER_SECONDS)
	var shard_tint := _faded(TETHER_STRAIN_COLOR, 1.0 - clampf(fall * 2.0 - 1.0, 0.0, 1.0))
	var pieces: Array[Dictionary] = []
	var spans := dash_spans(shaft_end, snap_shift)
	for i in spans.size():
		var span := spans[i]
		var points := _falling(tether_chord, span.x, span.y, snap_u, i, fall, along, side)
		pieces.append({"points": points, "tint": shard_tint})
	if shaft_end < tip:
		var head := _falling(tether_chord, shaft_end, tip, snap_u, spans.size(), fall, along, side)
		out["cone"] = {"base": head[0], "tip": head[1], "scale": ARROW_WIDTH_SCALE, "tint": shard_tint}
	var spark_life := maxf(BREAK_SPARK_SECONDS, 0.0)
	if after < spark_life:
		var age := _phase(after, spark_life)
		var base := tether_color(hostile_side)
		var spark_tint := _faded(_brighten(base, 1.0 - age) if flash else base, 1.0 - age)
		var snap := point_along(tether_chord, snap_u)
		for i in maxi(BREAK_SPARKS, 0):
			var turn := float(i) * GOLDEN_ANGLE
			var heading := (side * cos(turn) + along * sin(turn) * 0.6 + Vector3.UP * 0.7).normalized()
			var reach := BREAK_SPARK_SPEED * after
			var trail := minf(BREAK_SPARK_SPEED * SPARK_TRAIL_SECONDS, reach)
			pieces.append({"points": PackedVector3Array([snap + heading * (reach - trail),
					snap + heading * reach]), "tint": spark_tint})
	out["pieces"] = pieces


# One falling piece: the stretch [u0, u1] of the chord as it stands `fall` (0-1) of the way through
# the shatter, as its two end points. `index` scatters it (sideways, and which way it turns).
static func _falling(tether_chord: PackedVector3Array, u0: float, u1: float, snap_u: float,
		index: int, fall: float, along: Vector3, side: Vector3) -> PackedVector3Array:
	var a := point_along(tether_chord, u0)
	var b := point_along(tether_chord, u1)
	var centre := (a + b) * 0.5
	var half := (b - a) * 0.5
	var mid := (u0 + u1) * 0.5
	var away := 1.0 if mid >= snap_u else -1.0
	var time := fall * maxf(BREAK_SHATTER_SECONDS, 0.0)
	var drift := (along * away + side * sin(float(index) * GOLDEN_ANGLE) * 0.5) * BREAK_KICK * time
	var ground := lerpf(tether_chord[0].y, tether_chord[1].y, mid / (tether_chord[1] - tether_chord[0]).length()) \
			- body_middle_rule()
	var landed := centre + drift
	landed.y = lerpf(centre.y, ground, fall * fall)
	var spin := TAU * BREAK_TUMBLE_TURNS * fall * (1.0 if index % 2 == 0 else -1.0)
	var turned := half.rotated(side, spin)
	return PackedVector3Array([landed - turned, landed + turned])


# WHICH look a death plays (#1104; the dev: "make it random each time"). DERIVED, never rolled -- the
# presentation's scatter rule (HealthBlockDebris, ParticleFan) -- from where the body fell and how many
# deaths the board has seen, so a replay of the same fight plays the same looks and a case can state
# what it expects. It never repeats the look before it. DEATH_LOOK pins one while it is tuned.
static func death_look(cell: Vector2i, count: int, last: int) -> int:
	var looks := DEATH_LOOKS.size()
	if DEATH_LOOK >= 1 and DEATH_LOOK <= looks:
		return DEATH_LOOKS[DEATH_LOOK - 1]
	var pick := posmod(hash(Vector3i(cell.x, cell.y, count)), looks)
	if DEATH_LOOKS[pick] == last:
		pick = (pick + 1) % looks
	return DEATH_LOOKS[pick]


# A death's own geometry (#1104), written into its moment's drawing. The dashes stop where they stood
# (`shift`) and each is a solid piece with its own tint; the arrowhead is `cone`; every look turns them
# to DEATH_ASH_COLOR. `leader_died` says which end is gone: the ash runs FROM it, the slack DROPS it,
# and the light runs AWAY from it, to whoever is left. Distances run to the arrowhead's tip, where the
# tether meets the leader.
static func _death_drawing(out: Dictionary, look: int, tether_chord: PackedVector3Array, elapsed: float,
		shift: float, flash: bool, hostile_side: bool, leader_died: bool) -> void:
	var m := measure(tether_chord)
	if m.is_empty():
		return
	var shaft_end: float = m["shaft_end"]
	var tip: float = m["tip"]
	var has_cone := shaft_end < tip
	var head_mid := (shaft_end + tip) * 0.5
	var base := tether_color(hostile_side)
	var ash := DEATH_ASH_COLOR
	var fade := 1.0 - _phase(elapsed - _death_fade_start(look), DEATH_FADE_SECONDS)
	var spans := dash_spans(shaft_end, shift)
	var pieces: Array[Dictionary] = []
	match look:
		Moment.DRAIN:
			# How far from the dead end the ash has reached, run past the far end by its own blend so the
			# last dash turns too.
			var front := _ease_out(_phase(elapsed, DRAIN_SECONDS)) * (tip + DRAIN_BLEND)
			for span: Vector2 in spans:
				var mid := (span.x + span.y) * 0.5
				var ashen := clampf((front - _from_dead(mid, tip, leader_died)) / DRAIN_BLEND, 0.0, 1.0)
				pieces.append(_death_piece(tether_chord, span.x, span.y, _faded(base.lerp(ash, ashen), fade)))
			if has_cone:
				var ashen := clampf((front - _from_dead(head_mid, tip, leader_died)) / DRAIN_BLEND, 0.0, 1.0)
				out["cone"] = _death_cone(tether_chord, shaft_end, tip, _faded(base.lerp(ash, ashen), fade))
		Moment.SLACK:
			var fall := _ease_out(_phase(elapsed, SLACK_SECONDS))
			var tint := _faded(base.lerp(ash, _phase(elapsed, SLACK_SECONDS)), fade)
			for span: Vector2 in spans:
				pieces.append({"points": PackedVector3Array([slack_point(tether_chord, span.x, fall, leader_died),
						slack_point(tether_chord, span.y, fall, leader_died)]), "tint": tint})
			# The arrow lets go as the tension does.
			var holding := 1.0 - _phase(elapsed, SLACK_SECONDS)
			if has_cone and holding > 0.0:
				out["cone"] = {"base": slack_point(tether_chord, shaft_end, fall, leader_died),
						"tip": slack_point(tether_chord, tip, fall, leader_died), "scale": ARROW_WIDTH_SCALE,
						"tint": _faded(tint, holding)}
		Moment.PULSE:
			var tint := _faded(base.lerp(ash, _phase(elapsed, DEATH_GREY_SECONDS)), fade)
			# The light's centre, measured from the dead end, and everything behind it is gone.
			var run := _ease_in(_phase(elapsed, PULSE_SECONDS)) * tip
			var half := maxf(PULSE_LENGTH, 0.0) * 0.5
			for span: Vector2 in spans:
				if _from_dead((span.x + span.y) * 0.5, tip, leader_died) >= run - half:
					pieces.append(_death_piece(tether_chord, span.x, span.y, tint))
			if has_cone and _from_dead(head_mid, tip, leader_died) >= run - half:
				out["cone"] = _death_cone(tether_chord, shaft_end, tip, tint)
			# The light is motion, so #217 stills it; the ash and the fade still say what happened.
			if flash and elapsed < PULSE_SECONDS:
				var centre := tip - run if leader_died else run
				out["glow"] = {"points": PackedVector3Array([
						point_along(tether_chord, clampf(centre - half, 0.0, tip)),
						point_along(tether_chord, clampf(centre + half, 0.0, tip))]), "tint": PULSE_COLOR}
		Moment.MOTES:
			var tint := base.lerp(ash, _phase(elapsed, DEATH_GREY_SECONDS))
			var grey := maxf(DEATH_GREY_SECONDS, 0.0)
			var crumble := 1.0 - _phase(elapsed - grey, CRUMBLE_SECONDS)
			if crumble > 0.0:
				for span: Vector2 in spans:
					pieces.append(_death_piece(tether_chord, span.x, span.y, _faded(tint, crumble)))
				if has_cone:
					out["cone"] = _death_cone(tether_chord, shaft_end, tip, _faded(tint, crumble))
			var after := elapsed - grey
			if after >= 0.0:
				var ranges: Array[Vector2] = []
				for span: Vector2 in spans:
					ranges.append(span)
				if has_cone:
					ranges.append(Vector2(shaft_end, tip))
				pieces.append_array(_motes(tether_chord, ranges, after))
	out["pieces"] = pieces


# Where a SLACK tether's point `u` (from the member end) hangs `fall` (0-1) of the way down: sagged below
# the straight chord, the dead end dropped to the ground under it -- the body-middle height taken back
# off, as the break's pieces land -- and never below that ground. Public for the case that pins it.
static func slack_point(tether_chord: PackedVector3Array, u: float, fall: float, leader_died: bool) -> Vector3:
	var p := point_along(tether_chord, u)
	var length := (tether_chord[1] - tether_chord[0]).length()
	var t := clampf(u / length, 0.0, 1.0) if length > 0.0 else 0.0
	var ground := lerpf(tether_chord[0].y, tether_chord[1].y, t) - body_middle_rule()
	var sag := _cells_to_rule(maxf(SLACK_SAG, 0.0)) * sin(PI * t)
	var drop := body_middle_rule() * (t if leader_died else 1.0 - t)
	p.y = maxf(p.y - (sag + drop) * clampf(fall, 0.0, 1.0), ground)
	return p


# The MOTES a crumbled tether leaves, `after` seconds past the crumble: MOTES_PER_DASH along each range,
# each rising and drifting and fading on a life scattered by its index (never rolled). A mote is a speck
# laid along the chord, so the flat view -- which has no height -- still sees it drift and fade.
static func _motes(tether_chord: PackedVector3Array, ranges: Array[Vector2], after: float) -> Array[Dictionary]:
	var motes: Array[Dictionary] = []
	var length := (tether_chord[1] - tether_chord[0]).length()
	if length <= 0.0:
		return motes
	var along := (tether_chord[1] - tether_chord[0]) / length
	var side := Vector3(-along.z, 0.0, along.x).normalized()
	var speck := along * MOTE_SIZE * 0.5
	var rise := _cells_to_rule(maxf(MOTE_RISE, 0.0))
	var tint := _brighten(DEATH_ASH_COLOR, 0.5)
	var per := maxi(MOTES_PER_DASH, 0)
	var index := 0
	for span: Vector2 in ranges:
		for j in per:
			index += 1
			var life := maxf(MOTE_SECONDS, 0.0) * (0.6 + 0.4 * fposmod(float(index) * GOLDEN_ANGLE / TAU, 1.0))
			if life <= 0.0 or after >= life:
				continue
			var k := after / life
			var p := point_along(tether_chord, lerpf(span.x, span.y, (float(j) + 0.5) / float(per)))
			p += side * sin(float(index) * GOLDEN_ANGLE) * 0.1 * k
			p.y += rise * _ease_out(k)
			motes.append({"points": PackedVector3Array([p - speck, p + speck]), "tint": _faded(tint, 1.0 - k * k)})
	return motes


# A stretch of the chord at rest, as one death piece.
static func _death_piece(tether_chord: PackedVector3Array, u0: float, u1: float, tint: Color) -> Dictionary:
	return {"points": PackedVector3Array([point_along(tether_chord, u0), point_along(tether_chord, u1)]),
			"tint": tint}


static func _death_cone(tether_chord: PackedVector3Array, base_u: float, tip_u: float, tint: Color) -> Dictionary:
	return {"base": point_along(tether_chord, base_u), "tip": point_along(tether_chord, tip_u),
			"scale": ARROW_WIDTH_SCALE, "tint": tint}


# How far `u` (from the member end) is from the end that died, the tip standing for the leader's end.
static func _from_dead(u: float, tip: float, leader_died: bool) -> float:
	return tip - u if leader_died else u


# A length in cells as trace space's height units (body_middle_rule's conversion).
static func _cells_to_rule(cells: float) -> float:
	return cells * BoardSpace.CELL_SIZE / BoardSpace.ROW_HEIGHT


# Whose side a squad's lines are drawn for (#1109): hostile to the player or not. WHOSE SIDE, never who
# is in control -- a hotseat enemy squad still wears the enemy colour (MusicDirector's ruling).
static func is_hostile(faction: Team.Faction) -> bool:
	return Team.is_enemy(Team.Faction.PLAYER, faction)


# The colour a side's tethers and range wear -- the range, a SOLID tether and every moment.
static func tether_color(hostile_side: bool) -> Color:
	return ENEMY_TETHER_COLOR if hostile_side else TETHER_COLOR


# A tether state's colour. GHOST and STRAIN ignore the side: an enemy never draws either, and the
# strain red means "breaking" whoever's tether it is.
static func color_of(state: int, hostile_side := false) -> Color:
	match state:
		Strain.GHOST:
			return TETHER_GHOST_COLOR
		Strain.STRAIN:
			return TETHER_STRAIN_COLOR
	return tether_color(hostile_side)


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
			_dashed(_flat(segment[0]), _flat(segment[segment.size() - 1]), tether_color(hostile), shift, 0.0)
	var shake := shake_now(shake_started_msec)
	for entry in tethers:
		var strokes: Array[PackedVector3Array] = []
		strokes.assign(entry["strokes"])
		if strokes.is_empty():
			continue
		var state: int = entry["state"]
		var color := color_of(state, hostile)
		var shaft := strokes[0]
		var bend := shake if state == Strain.STRAIN else 0.0
		var cone := ThreatLines2D.cone_of(strokes, ARROW_WIDTH_SCALE)
		# The arrowhead's casing goes down FIRST, so the shaft's last dash lies over it -- the diorama's
		# order, where the hull sits a render priority under the tether.
		if not cone.is_empty():
			_cone_casing(_flat(cone["base"]), _flat(cone["tip"]), float(cone["scale"]), color)
		_dashed(_flat(shaft[0]), _flat(shaft[shaft.size() - 1]), color, shift, bend)
		if not cone.is_empty():
			_cone(_flat(cone["base"]), _flat(cone["tip"]), float(cone["scale"]), color)
	var now := Time.get_ticks_msec()
	var flash := BoardOverlays.beams_animating()
	for entry in moments:
		var drawing := moment_drawing(entry, now, flash)
		var shaft: PackedVector3Array = drawing["shaft"]
		var cone: Dictionary = drawing["cone"]
		if not cone.is_empty():
			_cone_casing(_flat(cone["base"]), _flat(cone["tip"]), float(cone["scale"]), cone["tint"])
		if shaft.size() >= 2:
			var origin := _flat(drawing["origin"])
			var from := _flat(shaft[0])
			_dashed(from, _flat(shaft[shaft.size() - 1]), drawing["tint"], shift, float(drawing["bend"]),
					from.distance_to(origin) / float(GridUtils.TILE_SIZE))
		if not cone.is_empty():
			_cone(_flat(cone["base"]), _flat(cone["tip"]), float(cone["scale"]), cone["tint"])
		# A break's pieces are SOLID -- each is one dash already. This view has no height, so their
		# fall reads as a scatter and fade here (declared on #292); a death's SLACK sag and rising
		# MOTES likewise read as their fade and drift alone (#1104).
		for piece: Dictionary in drawing["pieces"]:
			var points: PackedVector3Array = piece["points"]
			var a := _flat(points[0])
			var b := _flat(points[1])
			_cased_line(PackedVector2Array([a, b]), piece["tint"])
			draw_line(a, b, piece["tint"], LINE_WIDTH)
		var glow: Dictionary = drawing["glow"]
		if not glow.is_empty():
			var ends: PackedVector3Array = glow["points"]
			_soft_light((_flat(ends[0]) + _flat(ends[1])) * 0.5,
					_flat(ends[0]).distance_to(_flat(ends[1])) * 0.5, glow["tint"])


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
	var lines: Array[PackedVector2Array] = []
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
		lines.append(line)
	# Every casing before any dash, so no dash's outline lands over its neighbour's ink.
	for line in lines:
		_cased_line(line, color)
	for line in lines:
		draw_polyline(line, color, LINE_WIDTH)


# One stroke's CASING: the same polyline wider by CASING_PX a side and longer by it at each end, so
# the ends are outlined as well as the sides.
func _cased_line(line: PackedVector2Array, color: Color) -> void:
	var count := line.size()
	if count < 2:
		return
	var cased := line.duplicate()
	var head := line[0] - line[1]
	var tail := line[count - 1] - line[count - 2]
	if head.length_squared() > 0.0:
		cased[0] = line[0] + head.normalized() * CASING_PX
	if tail.length_squared() > 0.0:
		cased[count - 1] = line[count - 1] + tail.normalized() * CASING_PX
	draw_polyline(cased, _casing_of(color), LINE_WIDTH + CASING_PX * 2.0)


# The arrowhead: a filled triangle, the flat twin of the diorama's solid cone.
func _cone(base: Vector2, tip: Vector2, scale: float, color: Color) -> void:
	var triangle := _arrow_triangle(base, tip, scale)
	if not triangle.is_empty():
		draw_colored_polygon(triangle, color)


# ...and its casing: the same triangle grown about its incentre until every edge sits CASING_PX out,
# which keeps its angles -- the flat twin of the diorama's casing_cone.
func _cone_casing(base: Vector2, tip: Vector2, scale: float, color: Color) -> void:
	var triangle := _arrow_triangle(base, tip, scale)
	if triangle.is_empty():
		return
	var a := triangle[1].distance_to(triangle[2])
	var b := triangle[2].distance_to(triangle[0])
	var c := triangle[0].distance_to(triangle[1])
	var perimeter := a + b + c
	var area := absf((triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])) * 0.5
	if perimeter <= 0.0 or area <= 0.0:
		return
	var incentre := (triangle[0] * a + triangle[1] * b + triangle[2] * c) / perimeter
	var inradius := area / (perimeter * 0.5)
	var grow := (inradius + CASING_PX) / inradius
	var grown := PackedVector2Array()
	for p in triangle:
		grown.append(incentre + (p - incentre) * grow)
	draw_colored_polygon(grown, _casing_of(color))


func _arrow_triangle(base: Vector2, tip: Vector2, scale: float) -> PackedVector2Array:
	var span := tip - base
	if span.length_squared() <= 0.0:
		return PackedVector2Array()
	var dir := span.normalized()
	var side := Vector2(-dir.y, dir.x) * LINE_WIDTH * scale * 0.5
	return PackedVector2Array([base + side, tip, base - side])


# A PULSE's light in the flat view (#1104): rings of the light's colour, fainter outward -- the soft
# ribbon the diorama draws, as far as a canvas without bloom goes.
func _soft_light(centre: Vector2, radius: float, color: Color) -> void:
	var r := maxf(radius, 1.5)
	for ring: Vector2 in [Vector2(1.0, 0.2), Vector2(0.65, 0.45), Vector2(0.35, 1.0)]:
		draw_circle(centre, r * ring.x, Color(color.r, color.g, color.b, color.a * ring.y))


# The casing colour at the line's own alpha, so a ghost's casing fades with the ghost.
static func _casing_of(color: Color) -> Color:
	return Color(CASING_COLOR.r, CASING_COLOR.g, CASING_COLOR.b, CASING_COLOR.a * color.a)


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) * float(GridUtils.TILE_SIZE)
