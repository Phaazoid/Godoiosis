extends Node3D
class_name HealthBlockDebris

# The cubes a unit loses (#314). When HP falls, the blocks that were standing in the readout are
# knocked out of it: they pop up and away, tumble, bounce once off the board under them and fade.
#
# WHY THIS IS ITS OWN NODE AND NOT PART OF THE READOUT. UnitHealthBar is a dumb idempotent sink --
# told an HP pair, draws it, no history. A falling cube is the opposite: it has velocity and a
# lifetime, and it must outlive the thing it fell off. The readout hides the instant the pointer
# moves, the plan settles, or the unit dies, and a cube parented to it would wink out mid-air. So
# these live in WORLD space under UnitMirror, and a burst is handed positions rather than a bar.
#
# NO PHYSICS BODIES. A RigidBody3D per cube would put a dozen bodies in the physics world for half a
# second of decoration, and would collide with things this has no business touching. Integration
# here is six lines and the only surface it knows about is the board height directly beneath, asked
# of BoardSpace like everything else in this stack.
#
# THE SCATTER IS DERIVED FROM THE CUBE INDEX, NEVER randf(). Law #1 is about gameplay, so a random
# sparkle would not break it -- but a deterministic scatter costs nothing, keeps RNG out of
# presentation entirely, and means a test can assert where a cube went. The golden angle spreads
# consecutive indices evenly around the circle, so a nine-cube burst fans out instead of clumping.
const GOLDEN_ANGLE := 2.39996323

# What a bounce keeps, sideways. A cube that kept its full horizontal speed after hitting the ground
# would skate away from the unit it belongs to; this is what makes it settle instead.
const BOUNCE_DRAG := 0.6

# The elevation store, pushed in beside UnitMirror's own (#273). Null reads as a flat board at y=0,
# which is what a bare Main.tscn launch and a headless fixture both are.
var heights: BoardHeights

var burst_speed := 2.2
var burst_spread := 0.8
var spin_speed := 9.0
var gravity := 9.0
var bounce := 0.45
var lifetime := 0.75

var _pool: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
# Per-slot flight state, index-aligned with _pool. Parallel arrays rather than a class per cube:
# every field is written every frame for every live cube, and a dictionary per cube would allocate
# on a path that runs during resolution.
var _velocity: Array[Vector3] = []
var _spin: Array[Vector3] = []
var _age: Array[float] = []
var _delay: Array[float] = []   # how long this cube sits in its socket before it launches
# Where each cube STARTED, kept so a test can ask which socket the first cube out came from -- the
# march order is otherwise unobservable once everything has moved.
var _origin: Array[Vector3] = []
var _bounced: Array[bool] = []
var _live: Array[bool] = []


# Knock `positions.size()` cubes out of a readout. `facing` is the readout's own basis, so a cube
# leaves along the axes it was sitting on and the burst reads as coming OUT of the display rather
# than off in some world direction. `power` scales the whole thing -- 1.0 for an ordinary hit, more
# for the detonation a death gets.
func burst(positions: Array[Vector3], colors: PackedColorArray, facing: Basis,
		power := 1.0, stagger := 0.0) -> void:
	var mesh := UnitHealthBar.cube_mesh()
	if mesh == null:
		return   # nothing has drawn a readout yet, so there is no cube shape to throw
	for i in positions.size():
		var slot := _take_slot()
		var cube: MeshInstance3D = _pool[slot]
		cube.mesh = mesh
		cube.visible = true
		cube.global_position = positions[i]
		cube.global_rotation = Vector3.ZERO
		var material: StandardMaterial3D = _materials[slot]
		material.albedo_texture = UnitHealthBar.cage_texture()
		# A colour PER CUBE, because a killing hit throws the whole grid at once and the red sockets
		# must leave as red while the standing ones leave as green -- one sweep, two colours.
		material.albedo_color = colors[i] if i < colors.size() else Color.WHITE
		# Up and outward, in the readout's OWN frame: +Y is up the grid, and the X/Z fan is what
		# stops a multi-cube burst leaving as one clump.
		var angle := float(i) * GOLDEN_ANGLE
		var local := Vector3(cos(angle) * burst_spread, 1.0, sin(angle) * burst_spread).normalized()
		_velocity[slot] = (facing * local) * burst_speed * power
		_spin[slot] = Vector3(sin(angle * 1.7), cos(angle * 1.3), sin(angle * 2.1)) * spin_speed
		_age[slot] = 0.0
		_delay[slot] = float(i) * maxf(stagger, 0.0)
		_origin[slot] = positions[i]
		_bounced[slot] = false
		_live[slot] = true


# How many cubes are in the air. The pool only ever grows, so its size answers a different question.
func live_count() -> int:
	var count := 0
	for alive: bool in _live:
		if alive:
			count += 1
	return count


func has_bounced(slot: int) -> bool:
	return slot >= 0 and slot < _bounced.size() and _bounced[slot]


# Where the cube in this slot started. Slots are filled in launch order, so slot 0 is the first cube
# out and its origin is the socket the march begins at.
func origin_of(slot: int) -> Vector3:
	if slot < 0 or slot >= _origin.size():
		return Vector3.ZERO
	return _origin[slot]


# How many cubes have actually LAUNCHED, as against how many are still waiting their turn in the
# socket. The two differ only while a stagger is playing, which is exactly what a test of it needs.
func launched_count() -> int:
	var count := 0
	for i in _pool.size():
		if _live[i] and _age[i] >= _delay[i]:
			count += 1
	return count


func _process(delta: float) -> void:
	for i in _pool.size():
		if not _live[i]:
			continue
		_advance(i, delta)


func _advance(slot: int, delta: float) -> void:
	var cube: MeshInstance3D = _pool[slot]
	_age[slot] += delta
	# THE STAGGER: a cube SITS in the socket it came from until its turn rather than being hidden, so
	# the grid visibly breaks apart in sequence instead of a gap opening ahead of the cubes (dev,
	# 2026-08-22: "march through the bricks that blast out, from start to finish").
	var flight := _age[slot] - _delay[slot]
	if flight < 0.0:
		return
	# Lifetime runs from LAUNCH, not from spawn, or the last cube out gets the least air.
	if flight >= lifetime:
		_retire(slot)
		return
	var velocity: Vector3 = _velocity[slot]
	velocity.y -= gravity * delta
	var position := cube.global_position + velocity * delta
	# ONE bounce, then it rides through. The floor is the board surface under wherever the cube has
	# drifted to, not under where it started -- asked of BoardSpace so ramps answer for themselves.
	var floor_y := _surface_under(position) + _half_cube()
	if not _bounced[slot] and velocity.y < 0.0 and position.y <= floor_y:
		position.y = floor_y
		velocity.y = -velocity.y * bounce
		velocity.x *= BOUNCE_DRAG
		velocity.z *= BOUNCE_DRAG
		_bounced[slot] = true
	_velocity[slot] = velocity
	cube.global_position = position
	cube.global_rotation += _spin[slot] * delta
	# Fades over the back half of its life, so the bounce is seen at full strength and only the
	# settle is what disappears.
	var fade: float = clampf((flight / lifetime - 0.5) * 2.0, 0.0, 1.0)
	var material: StandardMaterial3D = _materials[slot]
	var tint := material.albedo_color
	tint.a = 1.0 - fade
	material.albedo_color = tint


func _retire(slot: int) -> void:
	_live[slot] = false
	_pool[slot].visible = false


# Hidden slots are reused before the pool grows -- the same contract BoardOverlays and
# UnitMirror.set_ghosts follow, and for the same reason: a burst happens on a frame that is already
# doing resolution work.
func _take_slot() -> int:
	for i in _pool.size():
		if not _live[i]:
			return i
	var cube := MeshInstance3D.new()
	cube.layers = BoardOverlays.UNIT_RENDER_LAYER
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := _make_material()
	cube.material_override = material
	add_child(cube)
	_pool.append(cube)
	_materials.append(material)
	_velocity.append(Vector3.ZERO)
	_spin.append(Vector3.ZERO)
	_age.append(0.0)
	_delay.append(0.0)
	_origin.append(Vector3.ZERO)
	_bounced.append(false)
	_live.append(false)
	return _pool.size() - 1


func _surface_under(position: Vector3) -> float:
	if heights == null:
		return 0.0
	var cell := BoardSpace.flat(BoardSpace.cell_of(position))
	return BoardSpace.surface_height_at(cell, position.x, position.z, heights)


func _half_cube() -> float:
	return UnitHealthBar.cube_world_size() * 0.5


# ALPHA here, where the readout's own cubes are opaque: these fade out, and that is the one thing a
# cube in the grid never does. Everything else matches, including the fog and ambient exemptions --
# a knocked-off cube that suddenly caught the scene lighting would announce that it had stopped
# being part of the readout.
func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true   # the mesh darkens the top face; see UnitHealthBar
	material.disable_fog = true
	material.disable_ambient_light = true
	material.disable_receive_shadows = true
	material.render_priority = BoardOverlays.UNIT_HUD_RENDER_PRIORITY
	return material
