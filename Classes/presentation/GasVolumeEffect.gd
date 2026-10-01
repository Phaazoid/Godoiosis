extends CompositorEffect
class_name GasVolumeEffect

# The gas volume's compositor half (#508): two compute passes on the Battle3D camera, fed by GasMirror.
# MARCH casts one ray per texel at the volume resolution through the region boxes; COMPOSITE runs at
# full resolution, upsamples the march depth-aware, lays the pool on in closed form and writes the
# colour buffer. Both run over the gas's projected screen rectangle only.
#
# Everything the passes read arrives from the main thread as one Snapshot, swapped in whole, so a
# frame never mixes two boards. The Frame block's layout is gas_volume.glsl's; frame_bytes and
# Params.pack are the one place this side spells it. Disabled where there is no RenderingDevice
# (headless, the dummy renderer).

const SHADER := "res://Classes/presentation/gas_volume.glsl"
const CONTEXT := &"gas_volume"
const MAX_LAMPS := 8
const MAX_FLASHES := 4
const LOOK_FLOATS := 24
const REGION_FLOATS := 8
# The Frame block, in floats: two matrices, raster, the dispatch rect, then Params.
const PARAM_FLOATS := 12 * 4 + (MAX_LAMPS * 2 + MAX_FLASHES) * 4
const FRAME_FLOATS := 32 + 8 + PARAM_FLOATS


# The Frame block after the camera: the board, the light, the knobs. GasMirror fills one per frame.
class Params:
	extends RefCounted
	var board_rect := Vector4()
	var sun_dir := Vector3.UP
	var ambient_strength := 1.0
	var sun_color := Vector3.ONE
	var time := 0.0
	var ambient := Vector3()
	var region_count := 0
	var march0 := Vector4()     # steps, light steps, first light step, min step
	var march1 := Vector4()     # g forward, g back, back mix, powder
	var march2 := Vector4()     # thin floor, contain softness, pool softness, detail scale
	var march3 := Vector4()     # flash energy, flash radius, glint size, upsample tolerance
	var pixel := Vector4()      # bands, cut, ink, 0
	var flash_color := Vector3.ONE
	var glint := 0.0
	var kind_count := 0
	var stage := Vector4()      # the diorama's offset, w = 1 while a fight is staged
	var lamps: Array[Vector4] = []        # xyz, range
	var lamp_colors: Array[Vector4] = []  # rgb x energy
	var flashes: Array[Vector4] = []      # xyz, strength now

	func pack() -> PackedFloat32Array:
		var f := PackedFloat32Array()
		_v4(f, board_rect)
		_v4(f, Vector4(sun_dir.x, sun_dir.y, sun_dir.z, ambient_strength))
		_v4(f, Vector4(sun_color.x, sun_color.y, sun_color.z, time))
		_v4(f, Vector4(ambient.x, ambient.y, ambient.z, region_count))
		_v4(f, march0)
		_v4(f, march1)
		_v4(f, march2)
		_v4(f, march3)
		_v4(f, pixel)
		_v4(f, Vector4(flash_color.x, flash_color.y, flash_color.z, glint))
		var lamp_count := mini(lamps.size(), MAX_LAMPS)
		var flash_count := mini(flashes.size(), MAX_FLASHES)
		_v4(f, Vector4(lamp_count, flash_count, kind_count, 0.0))
		_v4(f, stage)
		for list: Array[Vector4] in [lamps, lamp_colors]:
			for i in MAX_LAMPS:
				_v4(f, list[i] if i < lamp_count else Vector4.ZERO)
		for i in MAX_FLASHES:
			_v4(f, flashes[i] if i < flash_count else Vector4.ZERO)
		return f

	static func _v4(f: PackedFloat32Array, v: Vector4) -> void:
		f.append(v.x)
		f.append(v.y)
		f.append(v.z)
		f.append(v.w)


# One frame's worth of what the passes read. GasMirror fills it; the effect never writes it.
class Snapshot:
	extends RefCounted
	# cells, amounts, masks, ground corners, ground centre, shape noise, detail noise
	var textures: Array[Texture] = []
	var looks := PackedFloat32Array()
	var looks_version := 0
	var regions := PackedFloat32Array()
	var regions_version := 0
	var params: Params
	var screen_rect := Rect2()   # the regions' projection, as fractions of the viewport
	var block := 2               # full pixels per march texel
	var pixel := false


var _rd: RenderingDevice
var _march_shader := RID()
var _march_pipeline := RID()
var _composite_shader := RID()
var _composite_pipeline := RID()
var _nearest := RID()
var _linear := RID()
var _repeat := RID()
var _frame_ubo := RID()
var _looks_buffer := RID()
var _looks_bytes := 0
var _looks_version := -1
var _regions_buffer := RID()
var _regions_bytes := 0
var _regions_version := -1
var _mutex := Mutex.new()
var _snapshot: Snapshot = null


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		enabled = false
		return
	RenderingServer.call_on_render_thread(_build)


func is_ready() -> bool:
	return _march_pipeline.is_valid() and _composite_pipeline.is_valid()


# The main thread's one door: what the next frames draw. Null draws nothing.
func submit(snapshot: Snapshot) -> void:
	_mutex.lock()
	_snapshot = snapshot
	_mutex.unlock()


# What was last submitted -- the readable half of the contract when no device runs it (headless).
func current() -> Snapshot:
	_mutex.lock()
	var snap := _snapshot
	_mutex.unlock()
	return snap


func _build() -> void:
	var file := load(SHADER) as RDShaderFile
	if file == null:
		push_error("GasVolumeEffect: cannot load %s" % SHADER)
		return
	var march := file.get_spirv(&"march")
	var composite := file.get_spirv(&"composite")
	for spirv: RDShaderSPIRV in [march, composite]:
		if spirv.compile_error_compute != "":
			push_error("GasVolumeEffect: %s" % spirv.compile_error_compute)
			return
	_march_shader = _rd.shader_create_from_spirv(march)
	_march_pipeline = _rd.compute_pipeline_create(_march_shader)
	_composite_shader = _rd.shader_create_from_spirv(composite)
	_composite_pipeline = _rd.compute_pipeline_create(_composite_shader)
	_nearest = _sampler(RenderingDevice.SAMPLER_FILTER_NEAREST, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	_linear = _sampler(RenderingDevice.SAMPLER_FILTER_LINEAR, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	_repeat = _sampler(RenderingDevice.SAMPLER_FILTER_LINEAR, RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT)
	_frame_ubo = _rd.uniform_buffer_create(FRAME_FLOATS * 4)


func _sampler(filter: RenderingDevice.SamplerFilter, repeat: RenderingDevice.SamplerRepeatMode) -> RID:
	var state := RDSamplerState.new()
	state.min_filter = filter
	state.mag_filter = filter
	state.repeat_u = repeat
	state.repeat_v = repeat
	state.repeat_w = repeat
	return _rd.sampler_create(state)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for rid: RID in [_march_pipeline, _march_shader, _composite_pipeline, _composite_shader, _nearest,
				_linear, _repeat, _frame_ubo, _looks_buffer, _regions_buffer]:
			if rid.is_valid():
				_rd.free_rid(rid)


# The Frame block, whole. Static so its layout can be pinned without a device.
static func frame_bytes(inv_projection: Projection, camera: Transform3D, full: Vector2i, block: int,
		pixel: bool, screen_origin: Vector2i, march_origin: Vector2i, params: Params) -> PackedByteArray:
	var f := PackedFloat32Array()
	for column: Vector4 in [inv_projection.x, inv_projection.y, inv_projection.z, inv_projection.w]:
		Params._v4(f, column)
	var b := camera.basis
	Params._v4(f, Vector4(b.x.x, b.x.y, b.x.z, 0.0))
	Params._v4(f, Vector4(b.y.x, b.y.y, b.y.z, 0.0))
	Params._v4(f, Vector4(b.z.x, b.z.y, b.z.z, 0.0))
	Params._v4(f, Vector4(camera.origin.x, camera.origin.y, camera.origin.z, 1.0))
	Params._v4(f, Vector4(full.x, full.y, block, 1.0 if pixel else 0.0))
	Params._v4(f, Vector4(screen_origin.x, screen_origin.y, march_origin.x, march_origin.y))
	f.append_array(params.pack())
	return f.to_byte_array()


# The rectangles both passes cover: full-res pixels, and march texels grown by one each way so the
# upsample's taps never read a texel this frame did not write. Empty when the gas is off screen.
static func dispatch_rects(screen_rect: Rect2, full: Vector2i, block: int) -> Array[Rect2i]:
	var px_lo := Vector2i((screen_rect.position * Vector2(full)).floor()).max(Vector2i.ZERO)
	var px_hi := Vector2i((screen_rect.end * Vector2(full)).ceil()).min(full)
	var march_size := Vector2i(ceili(float(full.x) / block), ceili(float(full.y) / block))
	var m_lo := (px_lo / block - Vector2i.ONE).max(Vector2i.ZERO)
	var m_hi := (Vector2i(ceili(float(px_hi.x) / block), ceili(float(px_hi.y) / block)) + Vector2i.ONE).min(march_size)
	if px_hi.x <= px_lo.x or px_hi.y <= px_lo.y:
		return []
	return [Rect2i(px_lo, px_hi - px_lo), Rect2i(m_lo, m_hi - m_lo)]


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != effect_callback_type or not is_ready():
		return
	_mutex.lock()
	var snap := _snapshot
	_mutex.unlock()
	if snap == null or snap.regions.is_empty() or snap.textures.size() < 7:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or scene == null:
		return
	var full := buffers.get_internal_size()
	if full.x == 0 or full.y == 0:
		return
	var block := maxi(1, snap.block)
	var rects := dispatch_rects(snap.screen_rect, full, block)
	if rects.is_empty():
		return
	var textures: Array[RID] = []
	for texture: Texture in snap.textures:
		var rid := RenderingServer.texture_get_rd_texture(texture.get_rid()) if texture != null else RID()
		if not rid.is_valid():
			return
		textures.append(rid)
	var march_size := Vector2i(ceili(float(full.x) / block), ceili(float(full.y) / block))
	var targets := _march_targets(buffers, march_size)
	_sync_buffers(snap)
	var bytes := frame_bytes(scene.get_cam_projection().inverse(), scene.get_cam_transform(), full, block,
		snap.pixel, rects[0].position, rects[1].position, snap.params)
	_rd.buffer_update(_frame_ubo, 0, bytes.size(), bytes)
	for view in buffers.get_view_count():
		var shared: Array[RDUniform] = [
			_texture_uniform(0, _nearest, buffers.get_depth_layer(view)),
			_buffer_uniform(4, RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, _frame_ubo),
			_buffer_uniform(5, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, _looks_buffer),
			_texture_uniform(7, _nearest, textures[0]),
			_texture_uniform(8, _linear, textures[1]),
			_texture_uniform(9, _linear, textures[2]),
			_texture_uniform(10, _nearest, textures[3]),
			_texture_uniform(11, _nearest, textures[4]),
			_texture_uniform(12, _repeat, textures[5]),
		]
		var march := shared.duplicate()
		march.append(_image_uniform(1, targets[0]))
		march.append(_image_uniform(2, targets[1]))
		march.append(_buffer_uniform(6, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, _regions_buffer))
		march.append(_texture_uniform(13, _repeat, textures[6]))
		_dispatch(_march_pipeline, _march_shader, march, rects[1].size)
		var composite := shared.duplicate()
		composite.append(_image_uniform(1, buffers.get_color_layer(view)))
		composite.append(_texture_uniform(2, _nearest, targets[0]))
		composite.append(_texture_uniform(3, _nearest, targets[1]))
		_dispatch(_composite_pipeline, _composite_shader, composite, rects[0].size)


func _dispatch(pipeline: RID, shader: RID, uniforms: Array[RDUniform], size: Vector2i) -> void:
	var uniform_set := UniformSetCacheRD.get_cache(shader, 0, uniforms)
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, pipeline)
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	_rd.compute_list_end()


# The march's two targets, rebuilt when the volume resolution or the viewport changes.
func _march_targets(buffers: RenderSceneBuffersRD, size: Vector2i) -> Array[RID]:
	if buffers.has_texture(CONTEXT, &"color") and buffers.get_texture_slice_size(CONTEXT, &"color", 0) != size:
		buffers.clear_context(CONTEXT)
	if not buffers.has_texture(CONTEXT, &"color"):
		var usage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		buffers.create_texture(CONTEXT, &"color", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, usage,
			RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, true, false)
		buffers.create_texture(CONTEXT, &"depth", RenderingDevice.DATA_FORMAT_R32_SFLOAT, usage,
			RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, true, false)
	return [buffers.get_texture(CONTEXT, &"color"), buffers.get_texture(CONTEXT, &"depth")]


# The looks and the region boxes live in storage buffers, rewritten only when their version moves.
func _sync_buffers(snap: Snapshot) -> void:
	if snap.looks_version != _looks_version:
		_looks_version = snap.looks_version
		_looks_buffer = _write_storage(_looks_buffer, _looks_bytes, snap.looks.to_byte_array())
		_looks_bytes = maxi(_looks_bytes, snap.looks.size() * 4)
	if snap.regions_version != _regions_version:
		_regions_version = snap.regions_version
		_regions_buffer = _write_storage(_regions_buffer, _regions_bytes, snap.regions.to_byte_array())
		_regions_bytes = maxi(_regions_bytes, snap.regions.size() * 4)


func _write_storage(buffer: RID, capacity: int, bytes: PackedByteArray) -> RID:
	if bytes.is_empty():
		bytes.resize(16)
	if buffer.is_valid() and bytes.size() <= capacity:
		_rd.buffer_update(buffer, 0, bytes.size(), bytes)
		return buffer
	if buffer.is_valid():
		_rd.free_rid(buffer)
	return _rd.storage_buffer_create(bytes.size(), bytes)


func _texture_uniform(binding: int, sampler: RID, texture: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(sampler)
	u.add_id(texture)
	return u


func _image_uniform(binding: int, texture: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(texture)
	return u


func _buffer_uniform(binding: int, type: RenderingDevice.UniformType, buffer: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = binding
	u.add_id(buffer)
	return u
