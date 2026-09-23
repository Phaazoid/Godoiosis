extends Node3D

# The parity probe for the status shader (#358). unit_status.gdshaderinc carries a HAND COPY of the
# engine's own Sprite3D material, and nothing headless can check a copy of a renderer: the dummy
# renderer draws nothing. This renders each case twice -- the engine's material, then the status
# material with every state at zero -- and diffs the frames. Zero differing pixels is the pass.
#
# Re-run it after ANY engine upgrade, and after touching the replica half of the include:
#
#     godot --path . res://tools/sprite_parity/sprite_parity.tscn
#
# It needs a real window (it is not a test for that reason), prints one verdict line per case, and
# also saves what a Wet and a Chilled sprite look like to user://sprite_parity/ for an eye check.
# It writes nothing under res://.

const ART := preload("res://Art/Units/MapSprites/Knight Templar.png")
const OUT_DIR := "user://sprite_parity"

var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_stage()
	var failures := 0
	failures += await _parity("real sprite (prepass, shadow, flip, faction tint)", _real_sprite())
	failures += await _parity("ghost (alpha, priority)", _ghost())
	failures += await _parity("atlas frame", _atlas_frame())
	for clock: float in [0.3, 1.9]:
		await _look("wet", 1.0, 0.0, 0.0, clock)
		await _look("chilled", 0.0, 1.0, 1.0, clock)
	print("SPRITE PARITY: %s" % ("OK" if failures == 0 else "%d CASE(S) DIFFER" % failures))
	get_tree().quit(1 if failures > 0 else 0)


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
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	ground.mesh = plane
	add_child(ground)
	_camera = Camera3D.new()
	add_child(_camera)
	_frame(Vector3(0.6, 1.4, 2.2))


func _frame(from: Vector3) -> void:
	_camera.position = from
	_camera.look_at(Vector3(0, 0.4, 0))


func _real_sprite() -> UnitSprite3D:
	var sprite := UnitSprite3D.new()
	sprite.show_still(ART)
	sprite.flip_h = true
	sprite.modulate = Color(1, 0.6, 0.6)
	return sprite


# UnitMirror.set_ghosts' own recipe for a pooled ghost.
func _ghost() -> UnitSprite3D:
	var ghost := UnitSprite3D.new()
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	ghost.show_still(ART)
	ghost.modulate = Color(1, 1, 1, 0.75)
	return ghost


func _atlas_frame() -> UnitSprite3D:
	var frame := AtlasTexture.new()
	frame.atlas = ART
	frame.region = Rect2(8, 16, 48, 48)
	var sprite := UnitSprite3D.new()
	sprite.show_still(frame)
	return sprite


# Returns 1 when the two renders differ, so the verdict can count cases.
func _parity(label: String, sprite: UnitSprite3D) -> int:
	add_child(sprite)
	var engine := await _grab()
	var material := ShaderMaterial.new()
	if sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISABLED:
		material.shader = UnitSprite3D.STATUS_GHOST_SHADER
		material.render_priority = sprite.render_priority
	else:
		material.shader = UnitSprite3D.STATUS_SHADER
	material.set_shader_parameter("texture_albedo", sprite.texture)
	material.set_shader_parameter("status_map", StatusArt.map_for(sprite.texture).texture)
	StatusLook.push(material, 0.0, 0.0, 0.0, 0.0, 0.0)
	sprite.material_override = material
	var replica := await _grab()
	sprite.queue_free()
	var diff := _diff(engine, replica)
	print("  %s: %d differing px, max %.1f/255" % [label, diff.x, diff.y])
	return 0 if diff.x == 0 else 1


# A close look at a state on the real art, through the one door the game uses. An untinted sprite,
# unlike the parity cases: a faction tint is a parity question, and here it only muddies the look.
func _look(name_stem: String, wet: float, chill: float, icicles: float, clock: float) -> void:
	var sprite := UnitSprite3D.new()
	sprite.show_still(ART)
	add_child(sprite)
	_frame(Vector3(0.15, 0.55, 0.75))
	sprite.show_status(wet, chill, icicles, clock, 0.3)
	var image := await _grab()
	var path := "%s/%s_%.1f.png" % [OUT_DIR, name_stem, clock]
	image.save_png(path)
	print("  saved %s" % ProjectSettings.globalize_path(path))
	sprite.queue_free()
	_frame(Vector3(0.6, 1.4, 2.2))


func _grab() -> Image:
	for i in 3:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# x = differing pixels, y = the largest channel difference in 0..255.
func _diff(a: Image, b: Image) -> Vector2:
	var count := 0
	var worst := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var d := a.get_pixel(x, y) - b.get_pixel(x, y)
			var m := maxf(maxf(absf(d.r), absf(d.g)), absf(d.b))
			if m > 0.5 / 255.0:
				count += 1
				worst = maxf(worst, m * 255.0)
	return Vector2(count, worst)
