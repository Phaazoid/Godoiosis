class_name StagingDust
extends GPUParticles3D

# The dust a tile throws when it lands (#656). One resident emitter for the whole board, handed a
# world point per landing; the tear-out's own driver decides WHEN, this decides what a puff is.
#
# THE PROJECT'S FIRST PARTICLE SYSTEM, so three things it settles are worth reading before the next
# one is written (the rules are in docs/design/presentation-effects.md).
#
# ONE EMITTER, NOT ONE PER CELL. restart() on a shared emitter kills the burst already in the air,
# so a per-cell effect would need a pool of nodes round-robined -- HealthBlockDebris's slot shape.
# emit_particle() spawns at an arbitrary transform on a system that is already resident, so twenty
# tiles landing across three seconds cost one node and one draw. Per-EMITTER overhead is the only
# real cost a GPU particle has, and this keeps it at exactly one.
#
# `emitting` STAYS FALSE FOREVER. Measured on 4.7.1 rather than assumed: emit_particle() fires
# perfectly well on an emitter that is not emitting, and setting `emitting = true` CLEARS every
# live particle on the next emit -- a burst in the air is wiped. There is no state where this node
# wants the process material spawning on its own.
#
# THE SCATTER IS DERIVED, NEVER randf(). Position and velocity are computed here and handed to
# emit_particle, so a case can assert where a grain went -- HealthBlockDebris's doctrine, kept on a
# GPU system. The seed is the cell and BoardSpace.staging_version, which already bumps per landing
# step and per flight, so a tile puffs differently every Execute and identically on a replay. Colour
# and size are NOT per grain: ParticleProcessMaterial overwrites COLOR and scale, so those two are
# one material value each and EMIT_FLAG_COLOR is never passed.


# What the grains are made of, and what one puff looks like. Every one is a Game-tab row (the
# tear-out's own section, dev 2026-09-04: everything about the battle zoom findable in one place).
static var grains_per_tile := 14
static var burst_speed := 2.4
static var burst_spread := 0.42
static var upward_bias := 0.55
static var grain_lifetime := 0.8
static var grain_size := 0.16
static var grain_color := Color(0.78, 0.72, 0.62, 0.85)
static var grain_gravity := 3.2
static var grain_damping := 2.0

# How many bursts may be in the air at once, for sizing the emission buffer.
#
# THE FAILURE THIS EXISTS TO PREVENT IS SILENT. Measured: with `amount` full, further
# emit_particle() calls are dropped with no error and no warning -- the dust simply stops on a busy
# board and nothing says why. StagingFlight packs tiles into TEAR_OUT_ARRIVAL, so the gap between
# landings shrinks as a stage grows and the overlap is a property of the board, not of these knobs.
# A particle slot is a few bytes of buffer, so this is sized for a stage far larger than the game
# has, rather than for the typical one. Changing `amount` restarts the system, so it is set once in
# _ready and again only when a knob moves it.
const CONCURRENT_BURSTS := 16

# The golden angle spreads consecutive grains evenly around the circle instead of clumping --
# HealthBlockDebris's constant, and the same reason.
const GOLDEN_ANGLE := 2.39996323


# How far past the reachable volume the box is grown, in cells. A grain is thrown outward and up
# and then falls, so it leaves the surface it was born on; this is that travel plus slack, and it
# is deliberately generous because the cost of an over-large box is nothing and the cost of a
# small one is the effect vanishing entirely.
const CULL_MARGIN := 8.0


func _ready() -> void:
	emitting = false
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	process_material = _process_material()
	draw_pass_1 = _grain_mesh()
	apply()


# Where the puffs can be, so the renderer does not cull them (#656 round 2).
#
# THIS IS THE ONE THING NO TEST COULD SEE AND NO KNOB COULD BEAT. A GPUParticles3D is culled by its
# own visibility_aabb, which defaults to eight cells around the emitter's origin -- and this node
# sits at the Battle3D origin while the diorama it draws into is STAGE_LIFT (40) cells overhead. So
# every entry puff was emitted correctly, simulated correctly, and drawn nowhere: measured at ZERO
# lit pixels, against 1248 for the identical burst inside a box that contains it. The dev found it
# the only way it could be found -- "I even bumped up the dials a bunch, and still saw nothing",
# which is the signature of a value multiplied by zero rather than tuned too low.
#
# BOTH LEVELS, because the effect is direction-blind: an exit lands on the board and an entry in the
# diorama, one lift apart. The volume is the CALLER'S -- battle3d._board_volume() is already the one
# answer to how big this board is, and its own comment says a second copy of that is Law #4.
func cover(board: AABB) -> void:
	var lifted := AABB(board.position + BoardSpace.stage_offset(), board.size)
	var both := board.merge(lifted).grow(CULL_MARGIN)
	# Local space, and this node sits at the origin -- but say so rather than assume it, since a
	# node moved later would silently re-break exactly what this function exists to fix.
	visibility_aabb = AABB(both.position - global_position, both.size)


# Re-push everything a knob can move. Called by the Game tab's write path, because a knob that only
# applies to the NEXT puff built is not a knob (#324's rule) -- and because `amount` and the
# material's own fields are node state rather than values a burst reads as it goes.
func apply() -> void:
	amount = maxi(1, grains_per_tile * CONCURRENT_BURSTS)
	lifetime = maxf(grain_lifetime, 0.05)
	var mat := process_material as ParticleProcessMaterial
	if mat != null:
		mat.gravity = Vector3(0.0, -grain_gravity, 0.0)
		mat.damping_min = grain_damping
		mat.damping_max = grain_damping
		mat.color = grain_color
		mat.scale_min = 1.0
		mat.scale_max = 1.0
	var mesh := draw_pass_1 as QuadMesh
	if mesh != null:
		mesh.size = Vector2(grain_size, grain_size)


# What the last puff was thrown at, and how many have been thrown. The ONLY observable this node
# has: a GPU particle is simulated on the card and never read back, so without this the wire from a
# landing to a burst is a transparent surface and no case could see it (#506). HealthBlockDebris
# keeps its cube origins for the same reason and says so in the same words.
var last_origin := Vector3.ZERO
var last_key := 0
var puff_count := 0


# Throw a puff at `origin` -- a world point, already carrying the tear-out's staged offset. `key`
# separates one burst from another; the caller derives it, this only spends it.
func puff(origin: Vector3, key: int) -> void:
	last_origin = origin
	last_key = key
	puff_count += 1
	var flags := EMIT_FLAG_POSITION | EMIT_FLAG_VELOCITY
	for grain in grains(origin, key):
		emit_particle(Transform3D(Basis(), grain["position"]), grain["velocity"],
				Color.WHITE, Color.BLACK, flags)


# One puff, as data. PURE AND STATIC, and that is the whole reason it is separate: a GPU-simulated
# particle cannot be read back, so this is the only part of the effect a headless case can see. It
# is also what makes the scatter assertable rather than merely deterministic.
static func grains(origin: Vector3, key: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count := maxi(1, grains_per_tile)
	var rng := RandomNumberGenerator.new()
	rng.seed = key
	# One rotation for the whole burst, so two puffs of the same tile are not the same fan turned --
	# the fan itself is even by construction and only its phase and per-grain jitter vary.
	var phase := rng.randf() * TAU
	for i in count:
		var angle := phase + GOLDEN_ANGLE * float(i)
		var reach := burst_spread * sqrt((float(i) + 0.5) / float(count)) * rng.randfn(1.0, 0.18)
		var speed := burst_speed * rng.randfn(1.0, 0.25)
		out.append({
			# Lifted by half a grain so the quad sits ON the surface rather than half inside it.
			# A clearance, not a proportion -- fire pays the same toll at flame_base_lift_for().
			"position": origin + Vector3(cos(angle) * reach, grain_size * 0.5, sin(angle) * reach),
			# Outward, with a rise: dust rolls off a landing rather than fountaining from its
			# centre, so the horizontal term carries the speed and the lift is a fraction of it.
			"velocity": Vector3(cos(angle) * speed, speed * upward_bias * rng.randfn(1.0, 0.3),
					sin(angle) * speed),
		})
	return out


# The seed for one tile's puff. staging_version rather than a counter of this file's own: it
# already bumps once per landing step and once per begin_flight, so it separates tiles within an
# Execute AND one Execute from the next, and there is no second thing to keep in step or to reset.
static func burst_key(cell: Vector2i, version: int) -> int:
	return hash(Vector3i(cell.x, cell.y, version))


func _process_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	# Every spawn value this node cares about arrives through emit_particle, so the material's own
	# emission shape and velocity ranges are deliberately inert.
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3.UP
	mat.spread = 0.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.0
	# Grains thin out as they settle instead of vanishing at full opacity.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	mat.color_ramp = ramp_texture
	return mat


func _grain_mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	# Plain ALPHA, no depth write -- so unlike fire (#236) a grain never needs its base lift
	# clamped against the ground it stands on, and dust in front of a tile edge is what dust does.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# A standing effect, above every markup layer and below the units -- fire's band, claimed by
	# fire only because it got here first. The constant is worth renaming when a third arrives.
	mat.render_priority = BoardOverlays.FLAME_RENDER_PRIORITY
	mesh.material = mat
	return mesh
