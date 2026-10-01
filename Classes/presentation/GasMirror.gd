extends Node3D
class_name GasMirror

# The 3D drawing of the gas store (#508's look harness). Owned by battle3d beside ArcLightning; reads
# GasField and draws it in whichever style Experiments' GAS_STYLE picks:
#   0 Realistic         the volume (GasVolumeEffect), billows over a pool that marks the cells
#   1 Pixel puffs       pixel puffs on an edged fog floor
#   2 Realistic + puffs the volume, with one pixel puff over each cell
#   3 Pixel volume      the volume marched per art-pixel block and posterized
# Each style is a separable part so the losers can be deleted when the experiment ends.
#
# Polls rather than listens: the gas, heights and grid versions, the staging, the style and the view.
# Any change rebuilds the board textures and the region boxes; every frame only re-sends the camera,
# the light and the clock. Gas is 3D only -- the flat 2D view has no drawing of it (#292 ledger).

enum Resolution { FULL, HALF, QUARTER }

const MASK_SCALE := 8
const FLASH_LIFT := 1.1             # how far above the ground a strike glows
const FLASH_SAFE_LEVEL := 0.15      # photosensitivity: every cloud holds a steady dim glow instead

@export_group("Volume")
@export var resolution := Resolution.HALF
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
@export var glint_size := 0.035
@export var glint_strength := 30.0
@export_group("Pixel volume")
@export var pixel_block := 3
@export var pixel_bands := 3.0
@export var pixel_cut := 0.35
@export var pixel_ink := 0.12

# Handed in by battle3d.
var field: GasField
var heights: BoardHeights
var grid: BoardGrid
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var lights_source := Callable()     # -> Array[OmniLight3D], the board's own lamps
var stands_down := Callable()       # -> bool, true in the flat 2D view

var _effect: GasVolumeEffect
var _shape_noise: NoiseTexture3D
var _detail_noise: NoiseTexture3D
var _time := 0.0
var _seen := []
var _rect := Rect2i()
var _textures: Array[Texture] = []
var _looks := PackedFloat32Array()
var _looks_version := 0
var _regions: Array[AABB] = []
var _region_floats := PackedFloat32Array()
var _regions_version := 0
var _flash_clusters: Dictionary[Vector2i, Vector3] = {}


func _ready() -> void:
	_shape_noise = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.05, 4, 64)
	_detail_noise = _noise(FastNoiseLite.TYPE_CELLULAR, 0.09, 2, 48)
	_pack_looks()
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


func style() -> int:
	return Experiments.choice_of(Experiments.Flag.GAS_STYLE)


func draws_volume() -> bool:
	return style() != 1


func region_boxes() -> Array[AABB]:
	return _regions


func volume_effect() -> GasVolumeEffect:
	return _effect


func _process(delta: float) -> void:
	_time += delta
	if field == null:
		return
	var key := [field.dirty.version, heights.dirty.version if heights != null else 0,
		grid.dirty.version if grid != null else 0, BoardSpace.staging_version,
		BoardSpace.flight_active()]
	if key != _seen:
		_seen = key
		_rebuild()
	_submit()


func _submit() -> void:
	if _effect == null:
		return
	var down: bool = stands_down.is_valid() and stands_down.call()
	if down or _regions.is_empty() or not draws_volume():
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
	snap.pixel = style() == 3
	snap.block = pixel_block if snap.pixel else [1, 2, 4][resolution]
	snap.screen_rect = _screen_rect()
	snap.params = _params()
	_effect.submit(snap)


# --- the board textures and the boxes, rebuilt whenever the gas or the ground under it moves -------

func _rebuild() -> void:
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
	return top


func _pack_looks() -> void:
	var f := PackedFloat32Array()
	for kind: Gas.Kind in Gas.Kind.values():
		var look := GasLook.for_kind(kind)
		f.append_array([look.albedo.r, look.albedo.g, look.albedo.b, look.extinction,
			look.emission.r, look.emission.g, look.emission.b, look.flash,
			look.base_height, look.column_height, look.top_softness, look.shape_scale,
			look.stretch, look.erosion, look.rise_speed, look.coverage_boost,
			look.pool_height, look.pool_density, look.sparkle, 0.0,
			look.wind.x, look.wind.y, 0.0, 0.0])
		if not look.changed.is_connected(_on_look_changed):
			look.changed.connect(_on_look_changed)
	_looks = f
	_looks_version += 1


func _on_look_changed() -> void:
	_pack_looks()
	_seen = []


# --- thunder: one CPU schedule, so the volume's glow and the pixel bolts strike together ----------

# Every 2x2 cluster of a flashing gas strikes on its own beat, glowing above the middle of its cells.
func _build_flash_clusters(shown: Dictionary[Vector2i, int]) -> void:
	var sums: Dictionary[Vector2i, Vector4] = {}
	for cell: Vector2i in shown:
		var flashes := false
		for kind in Gas.kinds_in(shown[cell]):
			flashes = flashes or GasLook.for_kind(kind).flash > 0.0
		if not flashes:
			continue
		var at := BoardSpace.surface_point(cell, heights) + BoardSpace.staged_offset(cell)
		var key := Vector2i(floori(cell.x / 2.0), floori(cell.y / 2.0))
		sums[key] = sums.get(key, Vector4.ZERO) + Vector4(at.x, at.y + FLASH_LIFT, at.z, 1.0)
	_flash_clusters.clear()
	for key: Vector2i in sums:
		var s := sums[key]
		_flash_clusters[key] = Vector3(s.x, s.y, s.z) / s.w


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
	p.march3 = Vector4(flash_energy, flash_radius, glint_size, upsample_tolerance)
	p.pixel = Vector4(pixel_bands, pixel_cut, pixel_ink, 0.0)
	p.flash_color = Vector3(flash_color.r, flash_color.g, flash_color.b)
	p.glint = glint_strength
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
