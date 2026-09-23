extends Node3D

# The render probe for the world half of a worn element state (#358 slice 2). The suite pins every
# decision StatusWorld makes on the CPU, and none of what the card then does with it: a GPU particle
# is never read back, and the dummy renderer draws nothing. This renders it on the real art and
# measures two things a headless run cannot:
#
#   - that the drips, splashes, mist and breath DRAW at all (lit pixels against a control frame with
#     the sprite's own tint off, so what differs is the particles alone), and
#   - that particles already in the air FREEZE while Engine.time_scale is 0, the way a hitstop sets
#     it. The engine hands the renderer the scaled step; this is where that is confirmed on 4.7.1.
#
#     godot --path . res://tools/status_world_probe/status_world_probe.tscn
#
# It needs a real window, prints one verdict line per check, and saves what a Wet and a Chilled unit
# look like to user://status_world/ for an eye check. It writes nothing under res://.

const ART := preload("res://Art/Units/MapSprites/Knight Templar.png")
const OUT_DIR := "user://status_world"

var _camera: Camera3D
var _world: StatusWorld
var _sprite: UnitSprite3D
var _clock := 0.0
var _level := Vector3.ZERO


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_stage()
	var failures := 0
	var control := await _grab()
	failures += await _draws("wet", Vector3(1.0, 0.0, 0.0), control)
	failures += await _draws("chilled", Vector3(0.0, 1.0, 1.0), control)
	failures += await _freezes()
	print("STATUS WORLD: %s" % ("OK" if failures == 0 else "%d CHECK(S) FAILED" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _process(delta: float) -> void:
	_clock += delta
	if _world == null or _level == Vector3.ZERO:
		return
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
	# The ground StatusWorld lands on with no board: a height-0 surface.
	var floor_y := BoardSpace.world_y_of_height(0.0)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.22, 0.34, 0.16)   # a board's grass, not the default white slab
	plane.material = grass
	ground.mesh = plane
	ground.position = Vector3(0.5, floor_y, 0.5)
	add_child(ground)
	_sprite = UnitSprite3D.new()
	_sprite.show_still(ART)
	add_child(_sprite)
	_sprite.position = Vector3(0.5, floor_y, 0.5)
	_world = StatusWorld.new()
	add_child(_world)
	_world.cover(AABB(Vector3(-4, -4, -4), Vector3(9, 9, 9)))
	# Roughly the game's own pitch, close enough that a texel is several pixels.
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.position = Vector3(0.5, floor_y + 1.1, 1.55)
	_camera.look_at(Vector3(0.5, floor_y + 0.25, 0.5))
	# The default rates are tuned for a board, where some unit is always mid-drip. One frame of one
	# unit may catch none in the air, so the probe raises them; the look it saves says so.
	StatusLook.wet_drip_rate = 8.0
	StatusLook.chill_mist_rate = 12.0


# A state thrown into the world for long enough to fill the air, grabbed twice: once with the
# sprite's own tint on (the look, saved) and once with it off (the particles alone, counted).
func _draws(label: String, level: Vector3, control: Image) -> int:
	_level = level
	await _wait(1.5)
	_sprite.show_status(level.x, level.y, level.z, _clock, 0.3)
	var look := await _grab()
	var path := "%s/%s.png" % [OUT_DIR, label]
	look.save_png(path)
	print("  saved %s" % ProjectSettings.globalize_path(path))
	_sprite.show_status(0.0, 0.0, 0.0, _clock, 0.3)
	var bare := await _grab()
	var lit := _diff(control, bare)
	var thrown: Array[String] = []
	for emitter in _world.emitters():
		thrown.append("%s %d" % [emitter.name, emitter.emitted])
	print("  %s: %d px of particles against the control (thrown so far: %s)" % [label, lit, ", ".join(thrown)])
	_level = Vector3.ZERO
	await _wait(2.0)   # let the last of it land and fade before the next case
	return 0 if lit > 0 else 1


# Particles in the air, then time stopped: two frames apart must be identical, and they must differ
# again once time runs -- or the hold proved nothing.
func _freezes() -> int:
	_level = Vector3(1.0, 1.0, 0.0)
	await _wait(1.0)
	Engine.time_scale = 0.0
	for i in 3:
		await RenderingServer.frame_post_draw   # a new time_scale reaches the frame late
	var held := await _grab()
	for i in 10:
		await RenderingServer.frame_post_draw
	var later := await _grab()
	Engine.time_scale = 1.0
	var frozen := _diff(held, later)
	await _wait(0.3)
	var moving := _diff(later, await _grab())
	_level = Vector3.ZERO
	print("  frozen: %d px moved while time was stopped; %d px moved once it ran" % [frozen, moving])
	return 0 if frozen == 0 and moving > 0 else 1


func _wait(seconds: float) -> void:
	var until := _clock + seconds
	while _clock < until:
		await get_tree().process_frame


func _grab() -> Image:
	for i in 3:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _diff(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			var d := a.get_pixel(x, y) - b.get_pixel(x, y)
			if maxf(maxf(absf(d.r), absf(d.g)), absf(d.b)) > 2.0 / 255.0:
				count += 1
	return count
