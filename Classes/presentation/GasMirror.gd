extends Node3D
class_name GasMirror

# The 3D drawing of the gas store (#508). Owned by battle3d beside ArcLightning; reads GasField and
# draws it as the realistic volume (GasVolumeEffect: billows over a pool that marks the cells) with
# pixel puffs in and over it, in whichever MIX Experiments' GAS_STYLE picks (the MIXES table). An
# edged pixel fog floor shows only while the floor key is held, and the cloud fades and the puffs
# hide under it so the board reads.
#
# Polls rather than listens: the gas, heights and grid versions, the staging, the mix and the view.
# Any change rebuilds the board textures and the region boxes; every frame only re-sends the camera,
# the light, the clock and the key. Gas is 3D only -- the flat 2D view has no drawing of it (#292).

# The volume's march resolution, by index: full, half, quarter (one ray per 1, 2x2 or 4x4 pixels).
const RESOLUTION_DIVISORS: Array[int] = [1, 2, 4]

const MASK_SCALE := 8
const FLASH_LIFT := 1.1             # how far above the ground a strike glows
const FLASH_SAFE_LEVEL := 0.15      # photosensitivity: every cloud holds a steady dim glow instead
const FLOOR_SHADER := "res://Classes/presentation/gas_floor.gdshader"
const PUFF_SHADER := "res://Classes/presentation/gas_puff.gdshader"
const PIXEL_SIZE := 1.0 / 32.0      # one art pixel, in world units -- the sprites' density
const ART_PIXELS_PER_CELL := 32.0
const FLOOR_ACTION := &"show_gas_floor"
# A cell's puff slots: which way it leans, the least gas that shows it, its biggest size, its lift in
# world units, and its rise as a share of the gas's column height.
const FIELD_SLOTS := [
	[Vector2(0, 0), 1, 2, 0.0, 0.0],
	[Vector2(-1, -1), 6, 1, 0.0, 0.0], [Vector2(1, 1), 6, 1, 0.0, 0.0],
	[Vector2(1, -1), 9, 1, 0.0, 0.0], [Vector2(-1, 1), 9, 1, 0.0, 0.0],
	[Vector2(0, 0), 12, 1, 0.36, 0.0],
]
const CLOUD_SLOTS := [
	[Vector2(0, 0), 1, 2, 0.0, 0.1],
	[Vector2(1, -1), 5, 1, 0.0, 0.45],
	[Vector2(-1, 1), 10, 1, 0.0, 0.75],
]
# The Gas style experiment's options, in its order. Each differs from the first in one way: the slot
# table, how far a puff wanders (world units), or the volume's height and density.
const MIXES := [
	{"slots": FIELD_SLOTS, "drift": 0.0, "height": 1.0, "density": 1.0},    # Puff field
	{"slots": FIELD_SLOTS, "drift": 0.15, "height": 1.0, "density": 1.0},   # Drifting puffs
	{"slots": FIELD_SLOTS, "drift": 0.0, "height": 0.45, "density": 0.5},   # Haze + puffs
	{"slots": CLOUD_SLOTS, "drift": 0.0, "height": 1.0, "density": 1.0},    # Puffs in the cloud
]
# Extra roles, as gas_puff.gdshader numbers them (0 is a puff).
const EXTRA_ROLES := {GasLook.Extra.WISP: 1, GasLook.Extra.SOOT: 2, GasLook.Extra.BUBBLE: 3,
	GasLook.Extra.SNOW: 4, GasLook.Extra.BOLT: 5, GasLook.Extra.CURL: 6}

@export_group("Volume")
@export var resolution := 1   # an index into RESOLUTION_DIVISORS
@export var steps := 32
@export var light_steps := 4
@export var light_step := 0.15
@export var min_step := 0.03
@export var thin_floor := 0.45
@export var contain_softness := 0.1
@export var pool_softness := 0.03
@export var detail_scale := 1.3
@export var upsample_tolerance := 0.03
@export_group("Light")
@export var forward_scatter := 0.6
@export var back_scatter := 0.3
@export var back_mix := 0.25
@export var powder := 0.4
@export var ambient_strength := 1.0
@export var flash_color := Color(0.78, 0.82, 1.0)
@export var flash_energy := 10.0
@export var flash_radius := 1.7
@export_group("Puffs and floor")
@export var held_cloud_strength := 0.25   # how much of the cloud stays while the floor key is held
@export var floor_corner_radius := 10.0   # art pixels
@export var puff_lean := 0.3: set = _set_puff_lean
@export var puff_tuck := 0.12: set = _set_puff_tuck

# Handed in by battle3d.
var field: GasField
var heights: BoardHeights
var grid: BoardGrid
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var lights_source := Callable()     # -> Array[OmniLight3D], the board's own lamps
var stands_down := Callable()       # -> bool, true in the flat 2D view
var overlays: BoardOverlays          # the markup stack the fog floor lies in

var _effect: GasVolumeEffect
var _shape_noise: NoiseTexture3D
var _detail_noise: NoiseTexture3D
var _time := 0.0
var _seen := []
var _rect := Rect2i()
var _textures: Array[Texture] = []
var _looks := PackedFloat32Array()
var _looks_version := 0
var _packed_mix := -1
var _regions: Array[AABB] = []
var _region_floats := PackedFloat32Array()
var _regions_version := 0
var _flash_clusters: Dictionary[Vector2i, Vector3] = {}
var _flash_kinds: Dictionary[Vector2i, Gas.Kind] = {}
var _floor: MeshInstance3D
var _floor_material: ShaderMaterial
var _puffs: MultiMeshInstance3D
var _puff_material: ShaderMaterial
# Instances whose gas flashes: [index, cluster, tint], re-lit every frame from the flash schedule.
var _flash_instances: Array = []
# What the puffs' MultiMesh was last handed, one [position, kind, role, phase, slot, cluster] each.
var _puff_entries: Array = []


func _ready() -> void:
	_shape_noise = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.05, 4, 64)
	_detail_noise = _noise(FastNoiseLite.TYPE_CELLULAR, 0.09, 2, 48)
	_pack_looks()
	_build_nodes()
	if camera != null:
		_effect = GasVolumeEffect.new()
		if camera.compositor == null:
			camera.compositor = Compositor.new()
		var effects := camera.compositor.compositor_effects
		effects.append(_effect)
		camera.compositor.compositor_effects = effects


func _exit_tree() -> void:
	if _effect != null and camera != null and camera.compositor != null:
		var effects := camera.compositor.compositor_effects
		effects.erase(_effect)
		camera.compositor.compositor_effects = effects


func mix() -> int:
	return clampi(Experiments.choice_of(Experiments.Flag.GAS_STYLE), 0, MIXES.size() - 1)


func _mix() -> Dictionary:
	return MIXES[mix()]


func floor_held() -> bool:
	return Input.is_action_pressed(FLOOR_ACTION)


func region_boxes() -> Array[AABB]:
	return _regions


func volume_effect() -> GasVolumeEffect:
	return _effect


# cells, amounts, masks, ground corners, ground centre -- as the volume and the floor read them.
func board_textures() -> Array[Texture]:
	return _textures


func _process(delta: float) -> void:
	_time += delta
	if field == null:
		return
	var key := [field.dirty.version, heights.dirty.version if heights != null else 0,
		grid.dirty.version if grid != null else 0, BoardSpace.staging_version,
		BoardSpace.flight_active(), mix(), _sun_light()]
	if key != _seen:
		_seen = key
		_rebuild()
	_submit()
	_animate_pixels()


func _submit() -> void:
	if _effect == null:
		return
	var down: bool = stands_down.is_valid() and stands_down.call()
	if down or _regions.is_empty():
		_effect.submit(null)
		return
	var over_units := Experiments.is_on(Experiments.Flag.GAS_OVER_UNITS)
	_effect.effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT if over_units \
		else CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	var snap := GasVolumeEffect.Snapshot.new()
	snap.textures = _textures.duplicate()
	snap.textures.append(_shape_noise)
	snap.textures.append(_detail_noise)
	snap.looks = _looks
	snap.looks_version = _looks_version
	snap.regions = _region_floats
	snap.regions_version = _regions_version
	snap.block = RESOLUTION_DIVISORS[clampi(resolution, 0, 2)]
	snap.screen_rect = _screen_rect()
	snap.params = _params()
	_effect.submit(snap)


# --- the board textures and the boxes, rebuilt whenever the gas or the ground under it moves -------

func _rebuild() -> void:
	if _packed_mix != mix():
		_pack_looks()
	_rect = grid.get_used_rect() if grid != null else Rect2i()
	var hidden := BoardSpace.flight_active()
	var board_cells: Array[Vector2i] = []
	var lifted_cells: Array[Vector2i] = []
	var shown: Dictionary[Vector2i, int] = {}
	for cell in field.cells():
		if not _rect.has_point(cell):
			continue
		if BoardSpace.is_staged(cell):
			if hidden:
				continue
			lifted_cells.append(cell)
		else:
			board_cells.append(cell)
		shown[cell] = field.packed_at(cell)
	if shown.is_empty():
		# Nothing to draw, so no textures: a terrain stroke moves the grid version every frame of a drag.
		_regions = []
		_region_floats = PackedFloat32Array()
		_regions_version += 1
		_flash_clusters.clear()
		_flash_kinds.clear()
		_build_floor(shown)
		_build_puffs(shown)
		return
	_build_textures(shown)
	var span := func(cell: Vector2i) -> Vector2: return _ground_span(cell)
	var top := func(cell: Vector2i) -> float: return _column_top(shown.get(cell, 0))
	_regions = GasRegions.boxes(board_cells, span, top)
	var lifted := GasRegions.boxes(lifted_cells, span, top, BoardSpace.stage_offset())
	var floats := PackedFloat32Array()
	for i in _regions.size() + lifted.size():
		var is_lifted := i >= _regions.size()
		var box: AABB = lifted[i - _regions.size()] if is_lifted else _regions[i]
		floats.append_array([box.position.x, box.position.y, box.position.z, 1.0 if is_lifted else 0.0,
			box.end.x, box.end.y, box.end.z, 0.0])
	_regions.append_array(lifted)
	_region_floats = floats
	_regions_version += 1
	_build_flash_clusters(shown)
	_build_floor(shown)
	_build_puffs(shown)


func _build_textures(shown: Dictionary[Vector2i, int]) -> void:
	var size := _rect.size.max(Vector2i.ONE)
	var kinds := Gas.Kind.size()
	var cells := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var ground := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBAF)
	var mid := Image.create_empty(size.x, size.y, false, Image.FORMAT_RF)
	var amounts: Array[Image] = []
	var masks: Array[Image] = []
	for k in kinds:
		amounts.append(Image.create_empty(size.x, size.y, false, Image.FORMAT_R8))
		masks.append(Image.create_empty(size.x, size.y, false, Image.FORMAT_R8))
	var staged := BoardSpace.staging_active()
	for y in size.y:
		for x in size.x:
			var cell := _rect.position + Vector2i(x, y)
			var corners := heights.corners_at(cell) if heights != null else Vector4i.ZERO
			ground.set_pixel(x, y, Color(BoardSpace.world_y_of_height(corners.x),
				BoardSpace.world_y_of_height(corners.y), BoardSpace.world_y_of_height(corners.z),
				BoardSpace.world_y_of_height(corners.w)))
			mid.set_pixel(x, y, Color(BoardSpace.world_y_of_height(Terrain.height_at_uv(corners, 0.5, 0.5)), 0, 0))
			var near := 0
			var neighbours := 0
			var bit := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var packed: int = shown.get(cell + Vector2i(dx, dy), 0)
					near |= Gas.kind_mask(packed)
					if dx != 0 or dy != 0:
						if packed != 0:
							neighbours |= 1 << bit
						bit += 1
			var own: int = shown.get(cell, 0)
			var lifted := 255 if staged and BoardSpace.is_staged(cell) else 0
			cells.set_pixel(x, y, Color8(Gas.kind_mask(own), near, neighbours, lifted))
			for kind in Gas.kinds_in(own):
				var amount := float(Gas.amount_in(own, kind)) / Gas.MAX_AMOUNT
				amounts[kind].set_pixel(x, y, Color(amount, 0, 0))
				masks[kind].set_pixel(x, y, Color(1, 0, 0))
	for mask in masks:
		mask.resize(size.x * MASK_SCALE, size.y * MASK_SCALE, Image.INTERPOLATE_CUBIC)
	var amount_array := Texture2DArray.new()
	amount_array.create_from_images(amounts)
	var mask_array := Texture2DArray.new()
	mask_array.create_from_images(masks)
	_textures = [ImageTexture.create_from_image(cells), amount_array, mask_array,
		ImageTexture.create_from_image(ground), ImageTexture.create_from_image(mid)]


func _ground_span(cell: Vector2i) -> Vector2:
	var corners := heights.corners_at(cell) if heights != null else Vector4i.ZERO
	var lo := mini(mini(corners.x, corners.y), mini(corners.z, corners.w))
	var hi := maxi(maxi(corners.x, corners.y), maxi(corners.z, corners.w))
	return Vector2(BoardSpace.world_y_of_height(lo), BoardSpace.world_y_of_height(hi))


func _column_top(packed: int) -> float:
	var top := 0.0
	for kind in Gas.kinds_in(packed):
		var look := GasLook.for_kind(kind)
		top = maxf(top, look.base_height + look.column_height)
	return top * float(_mix().height)


# How tall a kind's volume stands over a cell holding this much of it, as the march draws it.
func _column_at(kind: Gas.Kind, amount: int) -> float:
	var look := GasLook.for_kind(kind)
	var a := maxf(float(amount) / Gas.MAX_AMOUNT, thin_floor)
	return (look.base_height + look.column_height * a) * float(_mix().height)


# The mix's height and density are folded in here, so the march, the region boxes and the puffs that
# rise with the column all read one scaled look.
func _pack_looks() -> void:
	_packed_mix = mix()
	var height := float(_mix().height)
	var density := float(_mix().density)
	var f := PackedFloat32Array()
	for kind: Gas.Kind in Gas.Kind.values():
		var look := GasLook.for_kind(kind)
		f.append_array([look.albedo.r, look.albedo.g, look.albedo.b, look.extinction * density,
			look.emission.r, look.emission.g, look.emission.b, look.flash,
			look.base_height * height, look.column_height * height, look.top_softness, look.shape_scale,
			look.stretch, look.erosion, look.rise_speed, look.coverage_boost,
			look.pool_height, look.pool_density, 0.0, 0.0,
			look.wind.x, look.wind.y, 0.0, 0.0])
		if not look.changed.is_connected(_on_look_changed):
			look.changed.connect(_on_look_changed)
	_looks = f
	_looks_version += 1


func _on_look_changed() -> void:
	_pack_looks()
	if _puff_material != null:
		_puff_material.set_shader_parameter("art", GasPuffArt.build())
	_push_look_uniforms()
	_seen = []


# --- thunder: one CPU schedule, so the volume's glow and the pixel bolts strike together ----------

# Every 2x2 cluster of a flashing gas strikes on its own beat, glowing above the middle of its cells.
func _build_flash_clusters(shown: Dictionary[Vector2i, int]) -> void:
	var sums: Dictionary[Vector2i, Vector4] = {}
	_flash_kinds.clear()
	for cell: Vector2i in shown:
		var flashing := -1
		for kind in Gas.kinds_in(shown[cell]):
			if flashing < 0 and GasLook.for_kind(kind).flash > 0.0:
				flashing = kind
		if flashing < 0:
			continue
		var at := BoardSpace.surface_point(cell, heights) + BoardSpace.staged_offset(cell)
		var key := _cluster_of(cell)
		sums[key] = sums.get(key, Vector4.ZERO) + Vector4(at.x, at.y + FLASH_LIFT, at.z, 1.0)
		if not _flash_kinds.has(key):
			_flash_kinds[key] = flashing as Gas.Kind
	_flash_clusters.clear()
	for key: Vector2i in sums:
		var s := sums[key]
		_flash_clusters[key] = Vector3(s.x, s.y, s.z) / s.w


# Where each strike glows, by cluster -- the point the volume lights and the bolt stands under.
func strike_points() -> Dictionary[Vector2i, Vector3]:
	return _flash_clusters


static func _hash01(v: Vector2i) -> float:
	return float(posmod(hash(v), 10007)) / 10007.0


# How lit a cluster's strike is at gas time t: a double pulse on a per-cluster beat, skipping some.
static func flash_level(cluster: Vector2i, t: float) -> float:
	var ph := _hash01(cluster)
	var period := 1.4 + ph
	var u := t / period + ph
	var beat := floorf(u)
	var local := (u - beat) * period
	if _hash01(cluster * 7 + Vector2i(int(beat) * 13, int(beat) * 5)) < 0.4:
		return 0.0
	var p := exp(-local * 16.0)
	if local >= 0.14:
		p += 0.7 * exp(-(local - 0.14) * 12.0)
	return p


static func flashes_allowed() -> bool:
	return not PlayerSettings.is_on(PlayerSettings.Setting.PHOTOSENSITIVITY)


func _flashes_now() -> Array[Vector4]:
	var lit: Array[Vector4] = []
	var animated := flashes_allowed()
	for key: Vector2i in _flash_clusters:
		var level := flash_level(key, _time) if animated else FLASH_SAFE_LEVEL
		if level > 0.02:
			var at := _flash_clusters[key]
			lit.append(Vector4(at.x, at.y, at.z, level))
	lit.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.w > b.w)
	return lit.slice(0, GasVolumeEffect.MAX_FLASHES)


# --- per frame ------------------------------------------------------------------------------------

func _params() -> GasVolumeEffect.Params:
	var p := GasVolumeEffect.Params.new()
	p.board_rect = Vector4(_rect.position.x, _rect.position.y, maxi(_rect.size.x, 1), maxi(_rect.size.y, 1))
	if sun != null:
		p.sun_dir = sun.global_transform.basis.z.normalized()
		var c := sun.light_color * sun.light_energy if sun.visible else Color.BLACK
		p.sun_color = Vector3(c.r, c.g, c.b)
	if environment != null:
		var a := environment.ambient_light_color * environment.ambient_light_energy
		p.ambient = Vector3(a.r, a.g, a.b)
	p.ambient_strength = ambient_strength
	p.time = _time
	p.region_count = _region_floats.size() / GasVolumeEffect.REGION_FLOATS
	p.march0 = Vector4(steps, light_steps, light_step, min_step)
	p.march1 = Vector4(forward_scatter, back_scatter, back_mix, powder)
	p.march2 = Vector4(thin_floor, contain_softness, pool_softness, detail_scale)
	p.march3 = Vector4(flash_energy, flash_radius, upsample_tolerance, cloud_strength())
	p.flash_color = Vector3(flash_color.r, flash_color.g, flash_color.b)
	p.kind_count = Gas.Kind.size()
	var offset := BoardSpace.stage_offset()
	p.stage = Vector4(offset.x, offset.y, offset.z, 1.0 if BoardSpace.staging_active() else 0.0)
	_add_lamps(p)
	p.flashes = _flashes_now()
	return p


# The lamps nearest the gas, at most the shader's eight.
func _add_lamps(p: GasVolumeEffect.Params) -> void:
	if not lights_source.is_valid() or _regions.is_empty():
		return
	var centre := Vector3.ZERO
	for box in _regions:
		centre += box.get_center()
	centre /= _regions.size()
	var lights: Array = lights_source.call()
	lights.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool:
		return a.global_position.distance_squared_to(centre) < b.global_position.distance_squared_to(centre))
	for light: OmniLight3D in lights.slice(0, GasVolumeEffect.MAX_LAMPS):
		var at := light.global_position
		var c := light.light_color * light.light_energy
		p.lamps.append(Vector4(at.x, at.y, at.z, light.omni_range))
		p.lamp_colors.append(Vector4(c.r, c.g, c.b, 0.0))


# Where the boxes land on screen, as fractions of the viewport; the whole screen when any corner is
# behind the camera.
func _screen_rect() -> Rect2:
	if camera == null or not camera.is_inside_tree():
		return Rect2(0, 0, 1, 1)
	var size := camera.get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for box in _regions:
		for i in 8:
			var corner := box.get_endpoint(i)
			if camera.is_position_behind(corner):
				return Rect2(0, 0, 1, 1)
			var at := camera.unproject_position(corner)
			lo = lo.min(at)
			hi = hi.max(at)
	var rect := Rect2(lo / size, (hi - lo) / size)
	return rect.intersection(Rect2(0, 0, 1, 1))


func _noise(type: FastNoiseLite.NoiseType, frequency: float, octaves: int, size: int) -> NoiseTexture3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = type
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	if type == FastNoiseLite.TYPE_CELLULAR:
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var texture := NoiseTexture3D.new()
	texture.width = size
	texture.height = size
	texture.depth = size
	texture.seamless = true
	texture.seamless_blend_skirt = 0.1
	texture.normalize = true
	texture.noise = noise
	return texture


# --- the pixel half: the puffs, and the fog floor the key shows ------------------------------------

func _build_nodes() -> void:
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = load(FLOOR_SHADER) as Shader
	_floor_material.render_priority = BoardOverlays.GAS_FLOOR_SORT
	_floor = MeshInstance3D.new()
	_floor.name = "GasFloor"
	_floor.material_override = _floor_material
	_floor.layers = BoardOverlays.WORLD_RENDER_LAYER
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor.visible = false
	add_child(_floor)
	_puff_material = ShaderMaterial.new()
	_puff_material.shader = load(PUFF_SHADER) as Shader
	_puff_material.set_shader_parameter("art", GasPuffArt.build())
	_puff_material.set_shader_parameter("pixel_size", PIXEL_SIZE)
	_puff_material.set_shader_parameter("canvas_height", float(GasPuffArt.LAYER_SIZE.y))
	_puff_material.set_shader_parameter("stride", float(GasPuffArt.STRIDE))
	_puff_material.set_shader_parameter("extra_base", float(GasPuffArt.EXTRA_BASE))
	var quad := QuadMesh.new()
	quad.size = Vector2(GasPuffArt.LAYER_SIZE) * PIXEL_SIZE
	quad.center_offset = Vector3(0.0, quad.size.y * 0.5, 0.0)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	_puffs = MultiMeshInstance3D.new()
	_puffs.name = "GasPuffs"
	_puffs.multimesh = multimesh
	_puffs.material_override = _puff_material
	_puffs.layers = BoardOverlays.WORLD_RENDER_LAYER
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puffs.visible = false
	add_child(_puffs)
	_push_look_uniforms()


# What every kind's pixel half looks like, as the two shaders read it. Colours go in linear, because
# a plain vec4 uniform is not converted the way a texture's sRGB texels are.
func _push_look_uniforms() -> void:
	if _floor_material == null:
		return
	var palettes: Array[Color] = []
	var patterns := PackedInt32Array()
	var boil := PackedFloat32Array()
	var bob: Array[Vector2] = []
	var sway := PackedFloat32Array()
	for kind: Gas.Kind in Gas.Kind.values():
		var look := GasLook.for_kind(kind)
		for tone in look.palette():
			palettes.append(tone.srgb_to_linear())
		patterns.append(look.floor_pattern)
		boil.append(look.boil_seconds)
		bob.append(look.bob)
		sway.append(look.sway)
	_floor_material.set_shader_parameter("palettes", palettes)
	_floor_material.set_shader_parameter("patterns", patterns)
	_floor_material.set_shader_parameter("kind_count", Gas.Kind.size())
	_floor_material.set_shader_parameter("art_pixels", ART_PIXELS_PER_CELL)
	_puff_material.set_shader_parameter("boil_seconds", boil)
	_puff_material.set_shader_parameter("bob", bob)
	_puff_material.set_shader_parameter("sway", sway)


# How much of the volume and its pool draws right now: all of it, or what the floor key leaves.
func cloud_strength() -> float:
	return held_cloud_strength if floor_held() else 1.0


func floor_node() -> MeshInstance3D:
	return _floor


func puff_node() -> MultiMeshInstance3D:
	return _puffs


# The puff instances as built -- the readable half when no renderer keeps a MultiMesh's instance data
# (headless). Each is [position, kind, role, phase, slot, cluster]; role 0 is a puff, the rest are
# EXTRA_ROLES.
func puff_entries() -> Array:
	return _puff_entries


# The sun as the puffs are lit by it: part of the rebuild key, since a puff's tint is baked.
func _sun_light() -> Color:
	return sun.light_color * sun.light_energy if sun != null and sun.visible else Color.BLACK


# The light a flat-shaded pixel gets at a point, in sRGB: a floor of sky, the sun, and nearby lamps.
func _tint_at(at: Vector3) -> Color:
	var t := Color(0.42, 0.45, 0.52) + _sun_light() * 0.55
	if lights_source.is_valid():
		for light: OmniLight3D in lights_source.call():
			var att := pow(clampf(1.0 - light.global_position.distance_to(at) / light.omni_range, 0.0, 1.0), 2.0)
			t += light.light_color * light.light_energy * att * 0.35
	return Color(minf(t.r, 1.0), minf(t.g, 1.0), minf(t.b, 1.0), 1.0)


# One fan of four triangles per gas cell, every vertex on the true surface, lifted into the markup
# stack. Each vertex carries the light there.
func _build_floor(shown: Dictionary[Vector2i, int]) -> void:
	if shown.is_empty():
		_floor.mesh = null
		return
	var lift := overlays.gas_floor_lift() if overlays != null else 0.008
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fan: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for cell: Vector2i in shown:
		var corners := heights.corners_at(cell) if heights != null else Vector4i.ZERO
		var offset := BoardSpace.staged_offset(cell) + Vector3(0.0, lift, 0.0)
		var centre := _floor_point(cell, corners, Vector2(0.5, 0.5), offset)
		st.set_color(_tint_at(centre).srgb_to_linear())
		for i in 4:
			st.add_vertex(centre)
			st.add_vertex(_floor_point(cell, corners, fan[i], offset))
			st.add_vertex(_floor_point(cell, corners, fan[(i + 1) % 4], offset))
	_floor.mesh = st.commit()
	_floor_material.set_shader_parameter("cells_tex", _textures[0])
	_floor_material.set_shader_parameter("amount_tex", _textures[1])
	_floor_material.set_shader_parameter("board_rect", Vector4(_rect.position.x, _rect.position.y,
		maxi(_rect.size.x, 1), maxi(_rect.size.y, 1)))


static func _floor_point(cell: Vector2i, corners: Vector4i, uv: Vector2, offset: Vector3) -> Vector3:
	return Vector3(cell.x + uv.x, BoardSpace.world_y_of_height(Terrain.height_at_uv(corners, uv.x, uv.y)),
		cell.y + uv.y) + offset


# Each cell lays out its puffs by its neighbours and the mix's slot table: a slot facing gas leans out
# to meet it, one facing an empty cell tucks inside the border, and a slot that rises stands that share
# of the way up its gas's column. A mixed cell picks each slot's gas by the amounts, so the mix reads as
# both shapes side by side. One moving extra per cell (two for snow and soot). A bolt belongs to a
# strike, not a cell: one stands under each glow, lit by the same schedule.
func _build_puffs(shown: Dictionary[Vector2i, int]) -> void:
	_flash_instances.clear()
	_puff_entries = []
	var multimesh := _puffs.multimesh
	_puff_material.set_shader_parameter("drift", float(_mix().drift))
	if shown.is_empty():
		multimesh.instance_count = 0
		return
	var slots: Array = _mix().slots
	var instances: Array = []   # [position, kind, role, phase, slot, cluster]
	for cell: Vector2i in shown:
		var packed: int = shown[cell]
		var kinds := Gas.kinds_in(packed)
		var total := 0
		for kind in kinds:
			total += Gas.amount_in(packed, kind)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(cell)
		var offset := BoardSpace.staged_offset(cell)
		for slot: Array in slots:
			var kind := _weighted_kind(packed, kinds, total, rng)
			var dir: Vector2 = slot[0]
			var off := Vector2.ZERO
			for axis in 2:
				var sgn: float = dir[axis]
				if sgn == 0.0:
					continue
				var n: Vector2i = cell + (Vector2i(int(sgn), 0) if axis == 0 else Vector2i(0, int(sgn)))
				off[axis] = sgn * (puff_lean if shown.has(n) else puff_tuck)
			off += Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03))
			var phase := rng.randf() * TAU
			var variant := rng.randi() % 3
			if total < int(slot[1]):
				continue
			var size := mini(0 if total < 4 else (1 if total < 9 else 2), int(slot[2]))
			var lift := float(slot[3]) + float(slot[4]) * _column_at(kind, Gas.amount_in(packed, kind))
			var x := cell.x + 0.5 + off.x
			var z := cell.y + 0.5 + off.y
			var at := Vector3(x, BoardSpace.surface_height_at(cell, x, z, heights) + lift, z) + offset
			instances.append([at, kind, 0, phase, size * 3 + variant, _cluster_of(cell)])
		if total < 3:
			continue
		var lead: Gas.Kind = kinds[0]
		for kind in kinds:
			if Gas.amount_in(packed, kind) > Gas.amount_in(packed, lead):
				lead = kind
		var extra := GasLook.for_kind(lead).extra
		if extra == GasLook.Extra.BOLT:
			continue
		var count := 2 if extra == GasLook.Extra.SNOW or extra == GasLook.Extra.SOOT else 1
		for k in count:
			var x := cell.x + 0.5 + rng.randf_range(-0.25, 0.25)
			var z := cell.y + 0.5 + rng.randf_range(-0.25, 0.25)
			var at := Vector3(x, BoardSpace.surface_height_at(cell, x, z, heights), z) + offset
			instances.append([at, lead, EXTRA_ROLES[extra], rng.randf(), 0, _cluster_of(cell)])
	for key: Vector2i in _flash_clusters:
		var kind: Gas.Kind = _flash_kinds[key]
		if GasLook.for_kind(kind).extra != GasLook.Extra.BOLT:
			continue
		var glow := _flash_clusters[key]
		var ground := Vector3(glow.x, glow.y - FLASH_LIFT, glow.z)
		instances.append([ground, kind, EXTRA_ROLES[GasLook.Extra.BOLT], _hash01(key), 0, key])
	_puff_entries = instances
	multimesh.instance_count = instances.size()
	var bounds := AABB()
	for i in instances.size():
		var entry: Array = instances[i]
		var at: Vector3 = entry[0]
		var kind: Gas.Kind = entry[1]
		var tint := _tint_at(at).srgb_to_linear()
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
		multimesh.set_instance_custom_data(i, Color(float(kind), float(entry[2]), entry[3], float(entry[4])))
		multimesh.set_instance_color(i, Color(tint.r, tint.g, tint.b, 0.0))
		if GasLook.for_kind(kind).flash > 0.0:
			_flash_instances.append([i, entry[5], tint])
		bounds = AABB(at, Vector3.ZERO) if i == 0 else bounds.expand(at)
	_puffs.custom_aabb = bounds.grow(2.0)


static func _cluster_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / 2.0), floori(cell.y / 2.0))


static func _weighted_kind(packed: int, kinds: Array[Gas.Kind], total: int, rng: RandomNumberGenerator) -> Gas.Kind:
	var pick := rng.randf() * total
	for kind in kinds:
		pick -= Gas.amount_in(packed, kind)
		if pick < 0.0:
			return kind
	return kinds[kinds.size() - 1]


# Per frame: which pixel parts show, the clock, and the lightning on the puffs that carry it. Holding
# the floor key swaps the puffs for the floor.
func _animate_pixels() -> void:
	var down: bool = stands_down.is_valid() and stands_down.call()
	var held := floor_held()
	_floor.visible = not down and held and _floor.mesh != null
	_puffs.visible = not down and not held and _puffs.multimesh.instance_count > 0
	if _floor.visible:
		_floor_material.set_shader_parameter("corner_radius", floor_corner_radius)
	if not _puffs.visible:
		return
	_puff_material.set_shader_parameter("gas_time", _time)
	var animated := flashes_allowed()
	for entry: Array in _flash_instances:
		var level := flash_level(entry[1], _time) if animated else FLASH_SAFE_LEVEL
		var tint: Color = entry[2]
		_puffs.multimesh.set_instance_color(entry[0], Color(tint.r, tint.g, tint.b, level))


func _set_puff_lean(value: float) -> void:
	puff_lean = value
	_seen = []


func _set_puff_tuck(value: float) -> void:
	puff_tuck = value
	_seen = []
