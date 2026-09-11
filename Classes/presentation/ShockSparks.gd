class_name ShockSparks
extends GPUParticles3D

# The sparks a body throws when the current reaches it (#887 slice 2). One resident emitter for the
# whole board, handed a world point per victim -- `StagingDust`'s shape, on #656's rules, and it
# exists because those rules make a second emitter cheap while a second per-cell node would not be.
#
# WHAT IT MARKS IS A BODY, which is the half the bolts cannot say. The arcs draw the current over
# the ground, so they answer *which tiles are live*; a burst on each caught unit answers *who was
# caught*, and the two together are the whole readout. It stands in for the sprite blowout the plan
# opened with: `UnitMirror` rewrites every unit sprite's modulate each frame from the 2D authority,
# so tinting a body would be a second writer on a single-driver channel -- an effect tint channel on
# the mirror belongs to #358.
#
# The three rules it inherits from #656, each measured there rather than assumed here: ONE emitter
# rather than one per cell (restart() on a shared emitter kills the burst already in the air, while
# emit_particle spawns on a resident system); `emitting` STAYS FALSE forever (setting it true CLEARS
# every live particle on the next emit); and the cull box is the board plus the diorama, or the
# whole effect is drawn nowhere at all.


# What a burst is made of. Every one is a Game-tab row on the Elemental page, beside the bolts.
static var sparks := true
static var sparks_per_victim := 18
static var spark_speed := 3.6
static var spark_spread := 0.28
static var spark_upward := 1.1
static var spark_lifetime := 0.5
static var spark_size := 0.055
static var spark_color := Color(0.85, 0.78, 1.0, 0.95)
static var spark_gravity := 7.0
static var spark_drag := 1.2


# How many bursts may be in the air at once, for sizing the emission buffer. With `amount` full,
# further emit_particle() calls are DROPPED with no error and no warning (#656's measurement), and
# a shock's whole point is catching several bodies at once -- so this is sized for a volley far
# larger than the rules can produce rather than for the typical one. A particle slot is a few bytes.
const CONCURRENT_BURSTS := 12

# How far past the reachable volume the box is grown, in cells. A spark is thrown outward and up and
# then falls, so it leaves the surface it was born on; generous on purpose, because an over-large
# box costs nothing and a small one costs the entire effect.
const CULL_MARGIN := 8.0


# What the last burst was thrown at, and how many have been thrown. The ONLY observable this node
# has: a GPU particle is simulated on the card and never read back, so without this the wire from a
# caught body to a burst is a transparent surface no case could see (#506).
var last_origin := Vector3.ZERO
var last_key := 0
var burst_count := 0


func _ready() -> void:
	emitting = false
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	process_material = _process_material()
	draw_pass_1 = _spark_mesh()
	apply(EffectLook.new())


# Where the sparks can be, so the renderer does not cull them. BoardSpace owns the volume since
# #887 -- see its own note, which is #656's finding written down where a second emitter can reach
# it.
func cover(board: AABB) -> void:
	var both := BoardSpace.effect_volume(board, CULL_MARGIN)
	visibility_aabb = AABB(both.position - global_position, both.size)


# Re-push everything a knob can move: `amount` and the material's fields are node state rather than
# values a burst reads as it goes, so a knob that only applied to the NEXT burst is not a knob
# (#324's rule).
func apply(look: EffectLook) -> void:
	amount = maxi(1, look.whole("sparks_per_victim", sparks_per_victim) * CONCURRENT_BURSTS)
	lifetime = maxf(look.num("spark_lifetime", spark_lifetime), 0.05)
	var drag := look.num("spark_drag", spark_drag)
	var mat := process_material as ParticleProcessMaterial
	if mat != null:
		mat.gravity = Vector3(0.0, -look.num("spark_gravity", spark_gravity), 0.0)
		mat.damping_min = drag
		mat.damping_max = drag
		mat.color = look.tint("spark_color", spark_color)
		mat.scale_min = 1.0
		mat.scale_max = 1.0
	var mesh := draw_pass_1 as QuadMesh
	if mesh != null:
		var size := look.num("spark_size", spark_size)
		mesh.size = Vector2(size, size)


# Throw a burst at `origin` -- a world point, already carrying whatever offset the tear-out has put
# the ground under. `key` separates one burst from another; the caller derives it, this spends it.
func burst(origin: Vector3, key: int, look: EffectLook) -> void:
	if not look.flag("sparks", sparks):
		return
	last_origin = origin
	last_key = key
	burst_count += 1
	var flags := EMIT_FLAG_POSITION | EMIT_FLAG_VELOCITY
	for spark in fan(origin, key, look):
		emit_particle(Transform3D(Basis(), spark["position"]), spark["velocity"],
				Color.WHITE, Color.BLACK, flags)


# One burst, as data -- the only part of it a headless case can see. The scatter itself is
# ParticleFan's, shared with the slam dust; what is this effect's own is every number handed in.
static func fan(origin: Vector3, key: int, look: EffectLook) -> Array[Dictionary]:
	return ParticleFan.scatter(origin, key, look.whole("sparks_per_victim", sparks_per_victim),
			look.num("spark_spread", spark_spread), look.num("spark_speed", spark_speed),
			look.num("spark_upward", spark_upward), look.num("spark_size", spark_size) * 0.5)


# The seed for one victim's burst: the cell it was standing on and which strike this was, so two
# shocks catching the same body do not throw the identical sparks and a replay of the same orders
# throws them identically. #656's second seed policy (per occurrence), since a shock has no
# staging_version of its own to borrow.
static func burst_key(cell: Vector2i, occurrence: int) -> int:
	return hash(Vector3i(cell.x, cell.y, occurrence))


func _process_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	# Every spawn value arrives through emit_particle, so the material's own emission shape and
	# velocity ranges are deliberately inert.
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3.UP
	mat.spread = 0.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.0
	# Sparks die out rather than vanishing at full brightness.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	mat.color_ramp = ramp_texture
	return mat


func _spark_mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	# ADD rather than plain ALPHA, which is the one place this differs from the dust it is built
	# beside: a spark is light, so overlapping ones get brighter instead of merely more opaque, and
	# a bright one blooms through the same glow pass the bolts do.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.render_priority = BoardOverlays.EFFECT_RENDER_PRIORITY
	mesh.material = mat
	return mesh
