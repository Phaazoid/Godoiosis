class_name ArcLightning
extends Node3D

# What a SHOCK attack LOOKS like (#887): a bolt out of the sky onto the aim, and the current arcing
# over every conductor it reaches. Owned by battle3d exactly as StagingDust is -- a resident node
# with its own clock, handed one event and left to play it out.
#
# THE MECHANIC SHIPPED BLIND. #884 gave shock a real rule -- a hit on water pulls everything else in
# that water into the volley -- and on screen it read as three unrelated lunges. This draws the rule:
# the strike, then the hops, in the order the flood made them, over every cell the current reached
# whether or not anyone was standing there (dev, 2026-09-10: "the only thing that's missing is
# arcing above water tiles it effects as well"). A player should be able to see which tiles are live.
#
# ONE MESH FOR THE WHOLE STORM, twice. Every bolt is a SURFACE on a shared ImmediateMesh rebuilt each
# frame, so a twenty-cell current is two draws and there is no pool to grow, round-robin or run out
# of -- the failure mode a per-node effect has. The two meshes are the CORE (narrow, near-white, past
# the glow threshold so it blooms) and the CORONA (wide, the element's violet, dim). Two instances
# rather than two materials, because the width is a shader UNIFORM and the whole point of the pair is
# two widths; the per-bolt AGE rides in the vertex colour, which is the only channel that varies
# within one draw.
#
# WHY IT REBUILDS RATHER THAN TWEENS: a bolt's shape is not a property that eases, it is re-rolled
# several times a second, and that is what separates electricity from a glowing stick. It costs a few
# hundred vertices on the frames a shock is in the air and nothing at all otherwise -- _process
# returns on its first line while no bolt is alive.
#
# EVERY LOOK VALUE IS A KNOB, on the dev's own terms (2026-09-10): "happy to try folding in all the
# possible options, to play around with and see what I like". Two things deliberately are NOT. The
# corona's HUE is ElementPalette's answer for SHOCK -- the colour is semantic and a copy defaulting to
# the same violet would be a second store of it (#422). And the ORDER the hops light in is the rule
# showing, not a look: it is the flood's own step count.


# --- The knobs (Game tab -> Elemental -> Shock) -------------------------------------

# THE SKY STRIKE. Drawn down the shot's OWN trajectory, which the aim gate already computed
# (Reach.sight_trace) -- so an attack authored to clear any height, as Zap is, descends almost
# vertically, and one authored flat draws a horizontal rod instead. That is the effect describing
# the content rather than overriding it, and it is why there is no "angle" knob here.
static var sky_strike := true
# How much of that trajectory is drawn, in cells above where it lands. Zap's authored clearance puts
# the apex some fifty cells up; this is the part of the fall you see.
static var strike_height := 8.0
static var strike_life := 0.45

# THE CURRENT. One bolt per hop of the conduction flood, lifted off the surface -- above the water,
# which is the dev's ruling about what this effect IS (2026-09-10: "I definitely want the arcing to
# be above the water, at least visually").
static var arcs := true
static var bolt_lift := 0.35
static var bolt_life := 0.5
# How long the current waits after the strike before it starts travelling, and how long each ring of
# the flood waits behind the one before it. The second is the whole of "the current travels" -- at 0
# the entire network lights at once and reads as a shape rather than a spread.
static var strike_delay := 0.06
static var arc_step_delay := 0.05

# THE SHAPE OF ONE BOLT. `jag` is a FRACTION of the bolt's own length, so a one-cell hop and an
# eight-cell strike kink by the same amount relative to themselves.
static var bolt_segments := 6
static var bolt_jag := 0.16
# How many times a second the kinks are re-rolled. This is the only channel that reads as a flicker,
# and it is the one the photosensitivity setting freezes.
static var flicker_rate := 20.0

# THE FADE. 0 is a hard flash that is gone the moment it has decayed; 1 is a straight linear fade
# over the whole life, which is what leaves the network readable after the pop -- the afterimage is
# the tail of one curve rather than a second effect with its own schedule.
static var afterimage := 0.35

# THE COLOUR AND THE WEIGHT. Only the CORE's colour is authored here; the corona takes the element's.
static var core_color := Color(1.0, 0.97, 0.86)
static var bolt_width := 0.09
static var corona_scale := 3.2
static var core_intensity := 6.0
static var corona_intensity := 2.4
# The ribbon's edge falloff, shared by both meshes -- 1.0 fades linearly to the rim, higher keeps a
# hot line down the middle. It is the sight beam's own knob, spelled again here because that one is
# an @export on a node this does not own.
static var bolt_softness := 1.1


# How far past the drawn geometry the instances are grown, in cells. An ImmediateMesh reports its own
# bounds, so unlike a particle system this cannot be culled to nothing by a stale box (#656) -- the
# margin is only slack for the width the shader adds in the vertex stage, which the mesh's own bounds
# know nothing about.
const CULL_MARGIN := 1.0


# One bolt in the air: the centreline it runs along before any kink, when it lights, and how long it
# lasts. The `key` is what makes its shape reproducible.
class Bolt extends RefCounted:
	var path := PackedVector3Array()
	var born := 0.0
	var life := 0.0
	var key := 0


# Cell -> the world point on that cell's surface, pushed by the host (battle3d) because only it knows
# the mirror and the board's heights, and because the answer moves when the fight is torn out onto a
# diorama. StagingDust takes its origins the same way and for the same reason.
var point_of := Callable()

# What is in the air, and the clock they are measured against. The clock advances only while
# something is alive, which is what makes a strike's own timestamps self-consistent.
var _bolts: Array[Bolt] = []
var _elapsed := 0.0
# How many strikes this node has played. The seed's occurrence term (#656's second seed policy): two
# shocks at the same aim must not draw the identical bolt, and a replay of the same orders from a
# fresh launch must. Never reset, exactly as BoardSpace.staging_version is not.
var _strikes := 0

# What the last rebuild actually drew. THE ONLY OBSERVABLE A HEADLESS CASE HAS for the fact that an
# event reached the mesh -- and unlike a GPU particle, the mesh itself can be read back, so a case
# can go further and ask where the bolt was put.
var bolts_drawn := 0

var _core: MeshInstance3D
var _corona: MeshInstance3D


func _ready() -> void:
	_core = _make_ribbon()
	_corona = _make_ribbon()


# Is this blow one of ours? Asked by the HOST before it builds a trajectory for us, so an ordinary
# sword swing costs one element read instead of a sight trace -- and asked again inside strike(), so
# the node owns the question either way. PlanResolver.elements_of is the one answer to "what does this
# attack carry", the same one Conduction's own gate asks.
static func draws(attack: AttackAction) -> bool:
	if attack == null:
		return false
	return PlanResolver.elements_of(attack.actor, attack.fired_attack).has(Elemental.Element.SHOCK)


# Play one blast. `sky` is the shot's trajectory in WORLD space, already carrying whatever offset the
# tear-out has put the ground under -- the host converts it, because the trace is a fact about the
# board and where the board currently IS is not the trace's question (BoardSpace.trace_point says so
# too).
func strike(attack: AttackAction, sky: PackedVector3Array) -> void:
	if not draws(attack) or not point_of.is_valid():
		return
	_strikes += 1
	var key := hash([attack.origin_cell, attack.target_cell, _strikes])
	var born := _elapsed
	if sky_strike:
		var tail := strike_tail(sky, strike_height)
		if tail.size() >= 2:
			_bolts.append(_bolt(tail, born, strike_life, hash([key, -1])))
	if arcs:
		var lift := Vector3.UP * bolt_lift
		for i in attack.arc_links.size():
			var link: Conduction.Link = attack.arc_links[i]
			var from: Vector3 = point_of.call(link.from)
			var to: Vector3 = point_of.call(link.to)
			var path := PackedVector3Array([from + lift, to + lift])
			# The hop's own depth is its delay, which is the current travelling. Nothing else in
			# this file knows the flood's shape and nothing needs to.
			_bolts.append(_bolt(path, born + strike_delay + float(link.step) * arc_step_delay,
					bolt_life, hash([key, i])))


# Where the drawn bolts actually ARE. The second observable, and the one that can answer the ruling
# this effect exists to satisfy -- that the current is drawn ABOVE the water rather than on it --
# without any case having to pin the lift knob's own number.
func drawn_bounds() -> AABB:
	return (_core.mesh as ImmediateMesh).get_aabb()


func _bolt(path: PackedVector3Array, born: float, life: float, key: int) -> Bolt:
	var bolt := Bolt.new()
	bolt.path = path
	bolt.born = born
	bolt.life = maxf(life, 0.01)
	bolt.key = key
	return bolt


func _process(delta: float) -> void:
	if _bolts.is_empty():
		return
	_elapsed += delta
	var live: Array[Bolt] = []
	for bolt in _bolts:
		if _elapsed - bolt.born < bolt.life:
			live.append(bolt)
	_bolts = live
	_rebuild()


# Both meshes, from scratch, this frame. Wholesale rather than incremental because every bolt's
# shape and brightness moved: there is nothing to keep.
func _rebuild() -> void:
	var core := _core.mesh as ImmediateMesh
	var corona := _corona.mesh as ImmediateMesh
	core.clear_surfaces()
	corona.clear_surfaces()
	var frozen: bool = PlayerSettings.is_on(PlayerSettings.Setting.PHOTOSENSITIVITY)
	for bolt in _bolts:
		var age := _elapsed - bolt.born
		if age < 0.0:
			continue          # this hop has not been reached yet -- the stagger
		var alpha := envelope(age / bolt.life, afterimage)
		if alpha <= 0.002:
			continue
		var line := jagged(bolt.path, _shape_key(bolt, frozen), bolt_segments, bolt_jag)
		var tint := Color(1.0, 1.0, 1.0, alpha)
		if BoardOverlays.add_beam_strip(core, line, tint):
			BoardOverlays.add_beam_strip(corona, line, tint)
	# Counted off the MESH rather than off the loop's own intent, which is the difference between an
	# observable and a hopeful one: a case reading this is reading what was really built.
	bolts_drawn = core.get_surface_count()
	_core.visible = bolts_drawn > 0
	_corona.visible = bolts_drawn > 0
	_style()


# Which roll of the dice this bolt is wearing this frame.
#
# #217'S READING, and the only one this effect owes: what strobes is the RE-ROLL, so the safe mode
# freezes it at the bolt's first shape and everything else -- the strike, the spread, the fade -- is
# untouched. A bolt that appears and fades is not a flash, and the setting's promise is a steady
# state rather than a missing effect.
func _shape_key(bolt: Bolt, frozen: bool) -> int:
	if frozen or flicker_rate <= 0.0:
		return bolt.key
	return hash([bolt.key, int((_elapsed - bolt.born) * flicker_rate)])


# The knobs, pushed at both materials. EVERY FRAME a bolt is drawn, which is why there is no
# re-apply hook on the Game tab's side: nothing about this effect stands still long enough to go
# stale, so a slider moved mid-flash is already showing.
func _style() -> void:
	_shade(_core, core_color, bolt_width, core_intensity)
	_shade(_corona, ElementPalette.color_for_element(Elemental.Element.SHOCK),
			bolt_width * corona_scale, corona_intensity)


func _shade(node: MeshInstance3D, color: Color, width: float, intensity: float) -> void:
	var material := node.material_override as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("beam_color", color)
	material.set_shader_parameter("beam_width", width)
	material.set_shader_parameter("beam_intensity", intensity)
	material.set_shader_parameter("beam_softness", bolt_softness)


func _make_ribbon() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = ImmediateMesh.new()
	var material := ShaderMaterial.new()
	material.shader = load(BoardOverlays.SIGHT_BEAM_SHADER_PATH) as Shader
	# Fire's band (#245), whose name says "effect" rather than "flame" since this arrived: a bolt is
	# a standing effect in the world, over every markup layer and under the bodies.
	material.render_priority = BoardOverlays.EFFECT_RENDER_PRIORITY
	instance.material_override = material
	instance.extra_cull_margin = CULL_MARGIN
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.layers = BoardOverlays.WORLD_RENDER_LAYER
	instance.visible = false
	add_child(instance)
	return instance


# --- The shapes, all pure ------------------------------------------------------------
#
# Everything below is static and takes no node state, which is what lets a headless case assert the
# geometry rather than the fact that something was called.


# How bright a bolt is at `t` of its life, and what it leaves behind.
#
# ONE CURVE WITH A DIAL rather than a flash plus a separate afterimage: two effects would need two
# schedules that have to agree about when the first ends. `tail` slides between a hard pop (a sixth
# power, essentially gone a third of the way through) and a straight linear fade that keeps the
# network readable for the whole life.
static func envelope(t: float, tail: float) -> float:
	if t < 0.0 or t >= 1.0:
		return 0.0
	var remaining := 1.0 - t
	return lerpf(pow(remaining, 6.0), remaining, clampf(tail, 0.0, 1.0))


# The DESCENDING TAIL of a trajectory: the last `height` cells of it, measured above where it lands.
#
# This is what turns an authored attack into a sky strike without either end inventing a number. A
# shot authored to clear anything (Zap's arc_clearance of 99) has an apex tens of cells up, and this
# takes the part of the fall worth watching; a shot authored FLAT never breaks the ceiling at all, so
# the whole line comes back and it draws as a horizontal rod from the shooter. Both are correct, and
# neither is a special case here.
#
# The break is INTERPOLATED rather than snapped to the sample that crossed it, so the strike is
# exactly as tall as the knob says however coarsely the trace was sampled.
static func strike_tail(points: PackedVector3Array, height: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count := points.size()
	if count < 2:
		return out
	var landing := points[count - 1]
	var ceiling := landing.y + maxf(height, 0.0)
	out.append(landing)
	for i in range(count - 2, -1, -1):
		var point := points[i]
		if point.y <= ceiling:
			out.append(point)
			continue
		var below := points[i + 1]
		var span := point.y - below.y
		if span > 0.0:
			var cut := below.lerp(point, (ceiling - below.y) / span)
			# Unless the sample was already sitting ON the ceiling, in which case the cut IS it and
			# appending it again would leave the ribbon a coincident pair to take a tangent from.
			if cut.distance_squared_to(below) > 0.000001:
				out.append(cut)
		break
	out.reverse()
	return out


# A polyline redrawn as `count` evenly spaced points along its own length. The strike arrives as a
# curve sampled at the trace's resolution and a hop arrives as two points; both come out of here as
# the same thing, which is what lets one jag function serve both.
static func resample(path: PackedVector3Array, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if path.size() < 2 or count < 2:
		return path.duplicate()
	var spans := PackedFloat32Array()
	var total := 0.0
	for i in range(path.size() - 1):
		var span := path[i].distance_to(path[i + 1])
		spans.append(span)
		total += span
	if total <= 0.0:
		return path.duplicate()
	var step := total / float(count - 1)
	var walked := 0.0
	var segment := 0
	var consumed := 0.0
	out.append(path[0])
	for i in range(1, count - 1):
		walked = float(i) * step
		while segment < spans.size() - 1 and consumed + spans[segment] < walked:
			consumed += spans[segment]
			segment += 1
		var into: float = 0.0 if spans[segment] <= 0.0 else (walked - consumed) / spans[segment]
		out.append(path[segment].lerp(path[segment + 1], clampf(into, 0.0, 1.0)))
	out.append(path[path.size() - 1])
	return out


# One bolt's actual shape: the centreline resampled and then kicked sideways at every interior point.
#
# The displacement TAPERS to nothing at both ends, because a bolt is pinned to the two things it
# joins -- a kink at the endpoint would leave the tile it is supposed to be touching. It is scaled by
# the bolt's OWN length, so a one-cell hop and an eight-cell strike bend by the same amount relative
# to themselves and one knob governs both.
#
# Derived from the key, never randf(): the same bolt at the same instant of a replay is the same
# bolt, and a case can assert where it went. StagingDust's doctrine, one effect over.
static func jagged(path: PackedVector3Array, key: int, segments: int, jag: float) -> PackedVector3Array:
	var count := maxi(segments, 1)
	var line := resample(path, count + 1)
	if jag <= 0.0 or line.size() < 3:
		return line
	var total := 0.0
	for i in range(line.size() - 1):
		total += line[i].distance_to(line[i + 1])
	if total <= 0.0:
		return line
	var rng := RandomNumberGenerator.new()
	rng.seed = key
	var out := PackedVector3Array()
	out.append(line[0])
	for i in range(1, line.size() - 1):
		# The local tangent, from the neighbours rather than from the whole line: a strike is a CURVE,
		# and a kink measured against the chord would drift off it near the apex.
		var along := line[i + 1] - line[i - 1]
		var axes := _across(along)
		# Zero at both ends, one in the middle.
		var taper := sin(float(i) / float(count) * PI)
		var kick := axes[0] * rng.randfn(0.0, 1.0) + axes[1] * rng.randfn(0.0, 1.0)
		out.append(line[i] + kick * jag * total * taper)
	out.append(line[line.size() - 1])
	return out


# Two unit vectors across a direction. UP is the preferred reference, so a bolt travelling over the
# water kinks in HEIGHT as well as sideways rather than wriggling flat on the surface; a bolt that is
# already vertical -- the sky strike -- has to reach for another axis or the cross product collapses.
static func _across(along: Vector3) -> Array[Vector3]:
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.BACK]
	if along.length_squared() <= 0.0:
		return axes
	var direction := along.normalized()
	var reference := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	var side := direction.cross(reference).normalized()
	axes[0] = side
	axes[1] = side.cross(direction).normalized()
	return axes
