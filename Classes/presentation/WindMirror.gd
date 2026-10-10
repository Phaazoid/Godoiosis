extends Node3D
class_name WindMirror

# What the board's wind LOOKS like on its own (#1286), resident under battle3d beside WeatherMirror.
# The wind is a look only and blows under any weather; this node draws the two halves of it that are
# nobody else's:
#
#   - SPECKS: leaves and dust blown across the board, one GPUParticles3D on wind_speck.gdshader, born
#     in the weather's own view box (WeatherMirror.view_box) on the weather's own ground mask
#     (WeatherMirror.mask), so the wind adds no second answer to where the camera looks or where the
#     ground is. Drawn at the sprites' art density, under every piece of markup.
#   - CLOUD SHADOWS: a full-screen pass (cloud_shadow.gdshader) darkening the ground under passing
#     clouds that drift at a small share of the wind (dev, 2026-10-10: clouds are far off, so their
#     shadows move slower than the specks), sorted under the fog and the markup.
#
# Both halves draw under a CLEAR sky only (dev, 2026-10-10): rain, snow and fog already fill the air,
# and an overcast sky casts no cloud shadows.
#
# What the wind does to everything else is read where that thing is drawn: the rain, snow and fog off
# WeatherMirror, the gas's drift off GasMirror, the plants' sway off BoardMirror -- all from the one
# wind_source battle3d composes (WindLook.vector). A calm board draws nothing here.

const MAX_SPECKS := 20000

var wind_kind_source: Callable        # () -> Wind.Kind
var wind_source: Callable             # () -> Vector2: the board's wind, world units a second on x / z
var weather: WeatherMirror            # the view box and the ground mask
var stands_down: Callable             # () -> bool: the flat view is up, draw nothing

var _kind := Wind.Kind.CALM
var _look: WindLook = null
var _specks: GPUParticles3D
var _speck_process: ShaderMaterial
var _speck_draw: ShaderMaterial
var _clouds: MeshInstance3D
var _cloud_material: ShaderMaterial
var _mask: ImageTexture = null
var _art_built := false
var _clock := 0.0
var _cloud_drift := Vector2.ZERO
var _volume := AABB()


func _ready() -> void:
	_speck_process = ShaderMaterial.new()
	_speck_process.shader = load("res://Classes/presentation/wind_speck.gdshader") as Shader
	_speck_draw = ShaderMaterial.new()
	_speck_draw.shader = load("res://Classes/presentation/wind_speck_draw.gdshader") as Shader
	_speck_draw.render_priority = BoardOverlays.SPECK_RENDER_PRIORITY
	_specks = GPUParticles3D.new()
	_specks.process_material = _speck_process
	_specks.local_coords = false
	_specks.amount = 1
	_specks.lifetime = 1.0
	_specks.emitting = false
	_specks.visible = false
	_specks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_specks.layers = BoardOverlays.WORLD_RENDER_LAYER   # the wet decal must never paint a speck
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Z
	quad.material = _speck_draw
	_specks.draw_pass_1 = quad
	add_child(_specks)
	_cloud_material = ShaderMaterial.new()
	_cloud_material.shader = load("res://Classes/presentation/cloud_shadow.gdshader") as Shader
	_cloud_material.render_priority = BoardOverlays.CLOUD_RENDER_PRIORITY
	_clouds = MeshInstance3D.new()
	var screen := QuadMesh.new()
	screen.size = Vector2(2.0, 2.0)   # the vertex stage pins it to the whole screen
	_clouds.mesh = screen
	_clouds.material_override = _cloud_material
	_clouds.extra_cull_margin = 16384.0
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clouds.layers = BoardOverlays.WORLD_RENDER_LAYER
	_clouds.visible = false
	add_child(_clouds)
	if _volume.has_volume():
		cover_volume(_volume)


# The cull box (#656), swept by battle3d._cover_effects with the weather's: an emitter that forgets to
# subscribe draws NOTHING.
func cover(board: AABB) -> void:
	cover_volume(BoardSpace.effect_volume(board, WeatherMirror.COVER_MARGIN))


func cover_volume(volume: AABB) -> void:
	_volume = volume
	if _specks != null:
		for system: GPUParticles3D in emitters():
			system.visibility_aabb = volume


# Every particle system this node draws: the one list the cull sweep walks.
func emitters() -> Array[GPUParticles3D]:
	return [_specks]


func _process(delta: float) -> void:
	_clock += delta
	var kind: Wind.Kind = wind_kind_source.call() if wind_kind_source.is_valid() else Wind.Kind.CALM
	var down: bool = stands_down.is_valid() and stands_down.call()
	var look := WindLook.for_kind(kind) if not down else null
	if look != _look or kind != _kind:
		_kind = kind
		_look = look
	var blowing := _look != null
	var clear_sky := weather == null or weather.kind() == Weather.Kind.CLEAR
	_clouds.visible = blowing and clear_sky and _look.cloud_cover > 0.0 and _look.cloud_darkness > 0.0
	var specks := blowing and clear_sky and _look.speck_rate > 0.0
	_specks.emitting = specks
	_specks.visible = specks
	if not blowing:
		return
	var wind := _wind() * gust_at(_look, _clock)
	_place_clouds(wind, delta)
	if specks:
		_sync_mask()
		_place_specks(wind)


# How far the wind stands above or below its speed at `t`: 1 on average, rising and falling by the
# look's gust over its gust period. Pure, so the plants (BoardMirror) and the specks blow as one.
static func gust_at(look: WindLook, t: float) -> float:
	if look == null:
		return 1.0
	var phase := TAU * t / maxf(look.gust_period, 0.1)
	return 1.0 + look.gust * (0.65 * sin(phase) + 0.35 * sin(phase * 2.3 + 1.7))


# The board's wind, or still air with no source.
func _wind() -> Vector2:
	return wind_source.call() if wind_source.is_valid() else Vector2.ZERO


func _place_clouds(wind: Vector2, delta: float) -> void:
	_cloud_drift += wind * _look.cloud_speed * delta
	_cloud_material.set_shader_parameter("cloud_noise", WeatherArt.fog_noise())
	_cloud_material.set_shader_parameter("drift", _cloud_drift)
	_cloud_material.set_shader_parameter("cover", _look.cloud_cover)
	_cloud_material.set_shader_parameter("darkness", _look.cloud_darkness)
	_cloud_material.set_shader_parameter("cloud_size", _look.cloud_size * BoardSpace.CELL_SIZE)
	_cloud_material.set_shader_parameter("softness", _look.cloud_softness)
	_cloud_material.set_shader_parameter("pixel_steps", 1.0 if _look.cloud_pixels else 0.0)
	_cloud_material.set_shader_parameter("art_pixels", BoardOverlays.ART_PIXELS_PER_CELL)
	_cloud_material.set_shader_parameter("cell_size", BoardSpace.CELL_SIZE)


# The weather's ground mask, handed on whenever it is rebuilt.
func _sync_mask() -> void:
	var texture: ImageTexture = weather.mask() if weather != null else null
	if texture == _mask:
		return
	_mask = texture
	_speck_process.set_shader_parameter("mask", texture)
	_speck_process.set_shader_parameter("mask_origin", weather.mask_origin())
	_speck_process.set_shader_parameter("cell_size", BoardSpace.CELL_SIZE)


# Specks are born over the view and upwind of it by as far as one flies, so the view fills from its
# upwind edge rather than thinning toward it.
func _place_specks(wind: Vector2) -> void:
	if weather == null:
		return
	var box := weather.view_box(1.0, Vector2.ZERO, _look.speck_flutter)
	if box.is_empty():
		return
	var life := maxf(_look.speck_life, 0.1)
	var carry := wind * _look.speck_speed * life
	var lo: Vector2 = box["lo"]
	var hi: Vector2 = box["hi"]
	lo = lo.min(lo - carry)
	hi = hi.max(hi - carry)
	if not _art_built:
		_art_built = true
		_speck_draw.set_shader_parameter("specks", ImageTexture.create_from_image(WeatherArt.specks()))
	_speck_process.set_shader_parameter("box_min", Vector3(lo.x, 0.0, lo.y))
	_speck_process.set_shader_parameter("box_max", Vector3(hi.x, 0.0, hi.y))
	_speck_process.set_shader_parameter("wind", wind * _look.speck_speed)
	_speck_process.set_shader_parameter("flutter", _look.speck_flutter)
	_speck_process.set_shader_parameter("height", _look.speck_height)
	_speck_process.set_shader_parameter("leaves", _look.speck_leaves)
	_speck_process.set_shader_parameter("leaf_frames", float(WeatherArt.LEAF_FRAMES))
	_speck_process.set_shader_parameter("dust_frames", float(WeatherArt.DUST_FRAMES))
	_speck_draw.set_shader_parameter("leaf_tint", _look.leaf_color)
	_speck_draw.set_shader_parameter("dust_tint", _look.dust_color)
	_speck_draw.set_shader_parameter("size", float(WeatherArt.SPECK_SIDE) / UnitSprite3D.texels_per_unit)
	_speck_draw.set_shader_parameter("leaf_frames", float(WeatherArt.LEAF_FRAMES))
	_speck_draw.set_shader_parameter("dust_frames", float(WeatherArt.DUST_FRAMES))
	_speck_draw.set_shader_parameter("tumbles", life * 3.0)
	# Sized for the peak of a gust, so the count never re-deals as the wind rises and falls; keep carries
	# the gust itself.
	var per_second := _look.speck_rate * (hi.x - lo.x) * (hi.y - lo.y)
	WeatherMirror.size_emitter(_specks, _speck_process, per_second * (1.0 + _look.gust), life, MAX_SPECKS)
	_speck_process.set_shader_parameter("keep", WeatherMirror.keep_for(per_second * gust_at(_look, _clock),
			_specks.lifetime, _specks.amount))

