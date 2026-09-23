extends Node3D

# The render probe for the world half of a worn element state (#358 slice 2). The suite pins every
# decision StatusWorld makes on the CPU, and none of what the card then does with it: a GPU particle
# is never read back, a decal is never read back, and the dummy renderer draws nothing. This renders
# it on the real art and measures what a headless run cannot:
#
#   - that the drips, splashes, mist and breath DRAW at all (lit pixels against a control frame with
#     the sprite's own tint off, so what differs is the world half alone);
#   - that particles already in the air FREEZE while Engine.time_scale is 0, the way a hitstop sets it;
#   - that the damp blot paints the ground and NOTHING ELSE: an unshaded quad on WORLD_RENDER_LAYER,
#     standing in for the squad ring, keeps every pixel while the ground around it darkens.
#
#     godot --path . res://tools/status_world_probe/status_world_probe.tscn
#
# It needs a real window, prints one verdict line per check, and saves what a Wet and a Chilled unit
# look like, on flat ground, on a ramp and across a step, to user://status_world/ for an eye check.
# It writes nothing under res://.

const ART := preload("res://Art/Units/MapSprites/Knight Templar.png")
const OUT_DIR := "user://status_world"

var _camera: Camera3D
var _world: StatusWorld
var _sprite: UnitSprite3D
var _clock := 0.0
var _level := Vector4.ZERO
var _floor_y := 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_stage()
	var failures := 0
	var control := await _grab()
	failures += await _draws("wet", Vector4(1.0, 0.0, 0.0, 1.0), control)
	failures += await _draws("chilled", Vector4(0.0, 1.0, 1.0, 0.0), control)
	failures += await _freezes()
	failures += await _ring_untouched()
	await _blot_looks()
	print("STATUS WORLD: %s" % ("OK" if failures == 0 else "%d CHECK(S) FAILED" % failures))
	get_tree().quit(1 if failures > 0 else 0)


# Always advanced, so a unit that stops wearing a state is RETIRED and its blot freed -- the mirror's
# own contract, which a probe that skipped the call would not honour.
func _process(delta: float) -> void:
	_clock += delta
	if _world == null:
		return
	if _level != Vector4.ZERO:
		_world.wear(1, _sprite, Vector2i.ZERO, _level, 0.3)
	_world.advance(delta, _clock, null)


func _stage() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.12, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	# The ground StatusWorld lands on with no board: a height-0 surface. Layer 1 by default, i.e. the
	# ground layer, which is what the blot's decal is allowed to paint.
	_floor_y = BoardSpace.world_y_of_height(0.0)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	plane.material = _grass()
	ground.mesh = plane
	ground.position = Vector3(0.5, _floor_y, 0.5)
	add_child(ground)
	_sprite = UnitSprite3D.new()
	_sprite.show_still(ART)
	add_child(_sprite)
	_sprite.position = Vector3(0.5, _floor_y, 0.5)
	_world = StatusWorld.new()
	add_child(_world)
	_world.cover(AABB(Vector3(-4, -4, -4), Vector3(9, 9, 9)))
	# Roughly the game's own pitch, close enough that a texel is several pixels.
	_camera = Camera3D.new()
	add_child(_camera)
	_frame(Vector3(0.5, _floor_y, 0.5))
	# The default rates are tuned for a board, where some unit is always mid-drip. One frame of one
	# unit may catch none in the air, so the probe raises them; the look it saves says so.
	StatusLook.wet_drip_rate = 8.0
	StatusLook.chill_mist_rate = 12.0


func _grass() -> StandardMaterial3D:
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.22, 0.34, 0.16)   # a board's grass, not the default white slab
	return grass


func _frame(at: Vector3) -> void:
	_camera.position = at + Vector3(0.0, 1.1, 1.05)
	_camera.look_at(at + Vector3(0.0, 0.25, 0.0))


# A state thrown into the world for long enough to fill the air, grabbed twice: once with the
# sprite's own tint on (the look, saved) and once with it off (the world half alone, counted).
func _draws(label: String, level: Vector4, control: Image) -> int:
	_level = level
	await _wait(1.5)
	_sprite.show_status(level.x, level.y, level.z, _clock, 0.3)
	var look := await _grab()
	_save(look, label)
	_sprite.show_status(0.0, 0.0, 0.0, _clock, 0.3)
	var bare := await _grab()
	var lit := _diff(control, bare, Rect2i())
	var thrown: Array[String] = []
	for emitter in _world.emitters():
		thrown.append("%s %d" % [emitter.name, emitter.emitted])
	print("  %s: %d px of the world half against the control (thrown so far: %s)"
			% [label, lit, ", ".join(thrown)])
	_level = Vector4.ZERO
	await _wait(2.0)   # let the last of it land and fade before the next case
	return 0 if lit > 0 else 1


# Particles in the air, then time stopped: two frames apart must be identical, and they must differ
# again once time runs -- or the hold proved nothing.
func _freezes() -> int:
	_level = Vector4(1.0, 1.0, 0.0, 0.0)
	await _wait(1.0)
	Engine.time_scale = 0.0
	for i in 3:
		await RenderingServer.frame_post_draw   # a new time_scale reaches the frame late
	var held := await _grab()
	for i in 10:
		await RenderingServer.frame_post_draw
	var later := await _grab()
	Engine.time_scale = 1.0
	var frozen := _diff(held, later, Rect2i())
	await _wait(0.3)
	var moving := _diff(later, await _grab(), Rect2i())
	_level = Vector4.ZERO
	await _wait(1.0)
	print("  frozen: %d px moved while time was stopped; %d px moved once it ran" % [frozen, moving])
	return 0 if frozen == 0 and moving > 0 else 1


# The layer split, on the real renderer: an unshaded quad on WORLD_RENDER_LAYER under the unit, the
# way the squad ring lies, must keep every pixel when the blot is laid under it, while the ground
# around it darkens. The sprite is hidden so nothing in front of the quad can move.
func _ring_untouched() -> int:
	await _wait(StatusLook.chill_mist_life + 1.0)   # the last check's puffs must have died, or they move
	_sprite.visible = false
	var ring := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.18, 0.18)
	var mark := StandardMaterial3D.new()
	mark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark.albedo_color = Color(0.35, 0.7, 1.0)
	quad.material = mark
	ring.mesh = quad
	ring.layers = BoardOverlays.WORLD_RENDER_LAYER
	ring.position = _sprite.position + Vector3(0.0, 0.01, 0.0)
	add_child(ring)
	var before := await _grab()
	_level = Vector4(0.0, 0.0, 0.0, 1.0)
	await _wait(0.2)
	var after := await _grab()
	# The quad's OWN pixels, read off the frame before: its projection is a trapezoid, so a bounding
	# rect would also count the corners of ground around it, which are meant to darken.
	var on_ring := _changed_where_blue(before, after)
	var anywhere := _diff(before, after, Rect2i())
	print("  ring: %d px of the WORLD-layer quad changed under the blot; %d px of ground darkened"
			% [on_ring, anywhere])
	_level = Vector4.ZERO
	await _wait(0.2)
	ring.queue_free()
	_sprite.visible = true
	return 0 if on_ring == 0 and anywhere > 0 else 1


# The blot on a ramp and across a step, for the eye: a tilted plane, and two slabs a level apart
# (one full level) with the unit standing on the edge between them.
func _blot_looks() -> void:
	var ramp := MeshInstance3D.new()
	var slope := PlaneMesh.new()
	slope.size = Vector2(1.0, 1.0)
	slope.material = _grass()
	ramp.mesh = slope
	ramp.position = Vector3(3.5, _floor_y + 0.25, 0.5)
	ramp.rotation_degrees = Vector3(0.0, 0.0, 26.6)
	add_child(ramp)
	await _look_at_blot(Vector3(3.5, _floor_y + 0.25, 0.5), "blot_ramp")
	var high := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(1.0, 1.0, 1.0)
	slab.material = _grass()
	high.mesh = slab
	high.position = Vector3(-2.0, _floor_y + 0.5, 0.5)
	add_child(high)
	await _look_at_blot(Vector3(-1.5, _floor_y + 1.0, 0.5), "blot_step")
	await _look_at_blot(Vector3(0.5, _floor_y, 0.5), "blot_flat")


func _look_at_blot(feet: Vector3, label: String) -> void:
	_sprite.position = feet
	_frame(feet)
	_level = Vector4(1.0, 0.0, 0.0, 1.0)
	_sprite.show_status(1.0, 0.0, 0.0, _clock, 0.3)
	await _wait(0.6)
	_save(await _grab(), label)
	_level = Vector4.ZERO
	_sprite.show_status(0.0, 0.0, 0.0, _clock, 0.3)
	await _wait(0.6)


func _save(image: Image, label: String) -> void:
	var path := "%s/%s.png" % [OUT_DIR, label]
	image.save_png(path)
	print("  saved %s" % ProjectSettings.globalize_path(path))


func _wait(seconds: float) -> void:
	var until := _clock + seconds
	while _clock < until:
		await get_tree().process_frame


func _grab() -> Image:
	for i in 3:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# Pixels that moved between two frames, inside `within` (or anywhere for an empty rect).
func _diff(a: Image, b: Image, within: Rect2i) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if within.has_area() and not within.has_point(Vector2i(x, y)):
				continue
			var d := a.get_pixel(x, y) - b.get_pixel(x, y)
			if maxf(maxf(absf(d.r), absf(d.g)), absf(d.b)) > 2.0 / 255.0:
				count += 1
	return count


# Pixels the blue quad covered in `before` that moved in `after`. -1 if it covered none, so an
# empty frame cannot pass.
func _changed_where_blue(before: Image, after: Image) -> int:
	var count := 0
	var covered := 0
	for y in before.get_height():
		for x in before.get_width():
			var c := before.get_pixel(x, y)
			if c.b < 0.5 or c.b < c.g or c.b < c.r:
				continue
			covered += 1
			var d := c - after.get_pixel(x, y)
			if maxf(maxf(absf(d.r), absf(d.g)), absf(d.b)) > 2.0 / 255.0:
				count += 1
	print("  ring: the quad covers %d px" % covered)
	return count if covered > 0 else -1
