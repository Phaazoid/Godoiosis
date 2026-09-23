class_name StatusParticles
extends GPUParticles3D

# One kind of particle a worn element state throws into the world (#358 slice 2): a Wet unit's
# drip and the splash it makes, a Chilled unit's cold mist and its frost breath. One resident
# emitter per KIND for the whole board, handed a world point and a velocity per particle -- #656's
# rules, ShockSparks' shape. WHEN and FROM WHERE is StatusWorld's; this node only draws.
#
# The rules it inherits, each measured at #656 rather than assumed here: `emitting` STAYS FALSE
# (setting it true clears every live particle), `amount` is sized from the knobs because emissions
# past it are dropped in silence, the material overwrites COLOR so colour and size are one material
# value each, and the cull box is the board plus the diorama or nothing draws at all.
#
# Unshaded, so a drip or a puff holds its brightness on a night board -- the grill's "bright marks
# glow". On WORLD_RENDER_LAYER, which is what keeps a ground decal from painting it.

enum Kind { DRIP, SPLASH, MIST, BREATH }

# How many units may wear a state at once, for sizing the emission buffer. Generous on purpose: a
# particle slot is a few bytes, and a buffer that fills drops the next drip without a word.
const WEARERS := 24
const CULL_MARGIN := 8.0

var kind := Kind.DRIP

# What was last thrown, and how many. The ONLY observable this node has: a GPU particle is simulated
# on the card and never read back (ShockSparks.burst_count's reason).
var emitted := 0
var last_position := Vector3.ZERO
var last_velocity := Vector3.ZERO

# The amount and lifetime last written. Writing either restarts the system, so each is written only
# when a knob has actually moved it.
var _amount_written := -1
var _lifetime_written := -1.0


static func make(of: Kind) -> StatusParticles:
	var emitter := StatusParticles.new()
	emitter.kind = of
	emitter.name = Kind.keys()[of].capitalize()
	return emitter


func _ready() -> void:
	emitting = false
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = BoardOverlays.WORLD_RENDER_LAYER
	process_material = _process_material()
	draw_pass_1 = _mesh()
	apply()


# Where these particles can be, so the renderer does not cull them.
func cover(board: AABB) -> void:
	var both := BoardSpace.effect_volume(board, CULL_MARGIN)
	visibility_aabb = AABB(both.position - global_position, both.size)


# Everything a knob can move. Called every frame by StatusWorld; the colour and size writes are
# cheap, and the two that restart the system are guarded.
func apply() -> void:
	var life := maxf(lifetime_of(kind), 0.05)
	var wanted := maxi(1, ceili(per_wearer(kind)) * WEARERS)
	if wanted != _amount_written:
		_amount_written = wanted
		amount = wanted
	if not is_equal_approx(life, _lifetime_written):
		_lifetime_written = life
		lifetime = life
	var mat := process_material as ParticleProcessMaterial
	if mat != null:
		mat.color = colour_of(kind)
		mat.gravity = Vector3(0.0, -StatusLook.wet_splash_gravity, 0.0) if kind == Kind.SPLASH else Vector3.ZERO
	var mesh := draw_pass_1 as QuadMesh
	if mesh != null:
		mesh.size = size_of(kind)


func throw(at: Vector3, velocity: Vector3) -> void:
	emitted += 1
	last_position = at
	last_velocity = velocity
	emit_particle(Transform3D(Basis(), at), velocity, Color.WHITE, Color.BLACK,
			EMIT_FLAG_POSITION | EMIT_FLAG_VELOCITY)


static func lifetime_of(of: Kind) -> float:
	match of:
		Kind.DRIP:
			return StatusLook.wet_drip_fall_time
		Kind.SPLASH:
			return StatusLook.wet_splash_time
		Kind.MIST:
			return StatusLook.chill_mist_life
	return StatusLook.chill_breath_life


# How many of this kind one wearer can have in the air at once, from the knobs that decide it.
static func per_wearer(of: Kind) -> float:
	match of:
		Kind.DRIP:
			return StatusLook.wet_drip_rate * StatusLook.wet_drip_fall_time + 1.0
		Kind.SPLASH:
			return float(StatusLook.wet_splash_count) \
					* (StatusLook.wet_drip_rate * StatusLook.wet_splash_time + 1.0)
		Kind.MIST:
			return StatusLook.chill_mist_rate * StatusLook.chill_mist_life + 1.0
	return float(StatusLook.chill_breath_count) \
			* (StatusLook.chill_breath_life / maxf(StatusLook.chill_breath_period, 0.05) + 1.0)


# The state's own hue, lifted toward white: the hue says which state, the lift says water or frost
# rather than paint. ElementPalette is the one answer to what colour a state is.
static func colour_of(of: Kind) -> Color:
	var wet := of == Kind.DRIP or of == Kind.SPLASH
	var hue := ElementPalette.color_for_state(Elemental.State.WET if wet else Elemental.State.CHILLED)
	var tint := hue.lerp(Color.WHITE, StatusLook.wet_drip_whiten if wet else StatusLook.chill_whiten)
	match of:
		Kind.DRIP, Kind.SPLASH:
			tint.a = StatusLook.wet_drip_alpha
		Kind.MIST:
			tint.a = StatusLook.chill_mist_alpha
		Kind.BREATH:
			tint.a = StatusLook.chill_breath_alpha
	return tint


# In world units, off the one texel density every unit sprite is drawn at (#176).
static func size_of(of: Kind) -> Vector2:
	var texel := 1.0 / UnitSprite3D.texels_per_unit
	match of:
		Kind.DRIP:
			return Vector2(texel, texel * StatusLook.wet_drip_length)
		Kind.SPLASH:
			return Vector2(texel, texel)
		Kind.MIST:
			return Vector2.ONE * texel * StatusLook.chill_mist_size
	return Vector2.ONE * texel * StatusLook.chill_breath_size


func _process_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	# Every spawn value arrives through emit_particle, so the material's own emission is inert.
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3.DOWN
	mat.spread = 0.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.0
	mat.scale_min = 1.0
	mat.scale_max = 1.0
	match kind:
		Kind.SPLASH:
			mat.color_ramp = _ramp([0.0, 1.0], [1.0, 0.0])
		Kind.MIST:
			# In, then out: a puff that popped in at full strength would read as a sprite, not a mist.
			mat.color_ramp = _ramp([0.0, 0.25, 1.0], [0.0, 1.0, 0.0])
			mat.scale_curve = _swell(0.4)
		Kind.BREATH:
			mat.color_ramp = _ramp([0.0, 1.0], [1.0, 0.0])
			mat.scale_curve = _swell(0.3)
	# A drip has no ramp: it lives exactly as long as its fall and ends on the ground.
	return mat


func _mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.render_priority = BoardOverlays.EFFECT_RENDER_PRIORITY
	if kind == Kind.MIST or kind == Kind.BREATH:
		mat.albedo_texture = _puff_texture()
	mesh.material = mat
	return mesh


static func _ramp(offsets: Array[float], alphas: Array[float]) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	var colours := PackedColorArray()
	for alpha in alphas:
		colours.append(Color(1.0, 1.0, 1.0, alpha))
	gradient.colors = colours
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


# Born at `from` of its full size, full at the end of its life.
static func _swell(from: float) -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, from))
	curve.add_point(Vector2(1.0, 1.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


# A 4x4 disc with its corners cut, drawn nearest, so a puff is a pixel shape rather than a square.
static func _puff_texture() -> ImageTexture:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]:
		image.set_pixelv(corner, Color(1.0, 1.0, 1.0, 0.0))
	return ImageTexture.create_from_image(image)
