extends Node3D
class_name WeatherMirror

# What the board's weather LOOKS like (#1260), resident under battle3d like GasMirror and ArcLightning.
# It reads the weather the host hands it each frame (ScenarioManager.current_weather, the RULE store,
# so the board can never look like one weather and soak like another) and that kind's WeatherLook:
#
#   - RAIN: one GPUParticles3D on rain.gdshader. Drops are born in a box fitted to the camera's own
#     frustum every frame, so the rain fills the view at any zoom, and die on the surface under them
#     (WeatherMask) or below the frame -- never in mid-air on screen (dev, 2026-10-08).
#   - SPLASHES: a second system on splash.gdshader, rings born on the ground in the same box at their
#     own rate, lying on the slope.
#   - THE GROUND: two board-sized decals painted by WetGround -- darkened and glossy, and puddles.
#   - THE STORM: bolts beyond the board (StormBolts), a screen flash this node only REPORTS (battle3d's
#     white-out composes it with the others), a light from the strike's side, and the sky's glow.
#   - SNOW (#1269): flakes on snow.gdshader, born in the rain's box, wandering as they fall and lying a
#     moment where they land, and a third ground decal painted by SnowGround. A blizzard adds DRIFT,
#     loose snow streaming along the ground (snow_drift.gdshader, drawn as rain's streak). Snow that
#     settles on props: a decal masked to PROP_RENDER_LAYER caps the block props' upward faces, and
#     prop_caps tells BoardMirror to lay its overlays on the billboards. Which of the two a look draws
#     is its FALL; every rain path is gated on it.
#   - THE GRADE (#1269): WeatherGrade, the weather's own grade and whiteout over the finished 3D frame,
#     easing between weathers. Either fall may author one; every shipped rain leaves it at identity.
#
# 3D only, declared on #292: the flat view's WET icons are its readout of the rule.

# How far past the board the particles may be drawn and still not be culled (#656's trap: a
# GPUParticles3D culls its WHOLE system to its own visibility_aabb). The rain box follows the camera
# off the board's edge and falls well below it, so this is generous on purpose; a big box costs nothing.
const COVER_MARGIN := 120.0
# A fresh amount is only taken when the wanted one strays this far: setting amount or lifetime
# restarts a particle system, so a zoom must not reshuffle the rain every frame.
const AMOUNT_SLACK := 0.35
const MAX_DROPS := 60000
const MAX_SPLASHES := 12000
const MAX_FLAKES := 200000
const MAX_DRIFT := 20000
# How far above the camera drops are born, so none ever appears inside the frame.
const SPAWN_ABOVE := 2.0
# The decals' height: from well under the board to well over the tear-out's stage, which shares the
# board's x and z, so one projection wets both.
const DECAL_BELOW := 40.0
const DECAL_ABOVE := 40.0
# How far below where the camera looks a sky bolt reaches: past the bottom of any frame.
const BOLT_BELOW := 80.0
# The snow cover is painted per art pixel, a fraction of a second on a big board, so once it is up a
# change waits until it has held this long: a slider drag repaints once, when it stops.
const COVER_SETTLE := 0.15

var weather_source: Callable          # () -> Weather.Kind
var grid: BoardGrid
var heights: BoardHeights
var camera: Camera3D
var aim_source: Callable              # () -> Vector3, where the camera is looking
var sky: ProceduralSkyMaterial
var stands_down: Callable             # () -> bool: the flat view is up, draw nothing
var prop_caps: Callable               # (shown: bool, color: Color) -> void: BoardMirror.set_prop_caps

var _kind := Weather.Kind.CLEAR
var _look: WeatherLook = null
var _rain: GPUParticles3D
var _rain_process: ShaderMaterial
var _rain_draw: ShaderMaterial
var _splash: GPUParticles3D
var _splash_process: ShaderMaterial
var _splash_draw: ShaderMaterial
var _snow: GPUParticles3D
var _snow_process: ShaderMaterial
var _snow_draw: ShaderMaterial
var _drift: GPUParticles3D
var _drift_process: ShaderMaterial
var _drift_draw: ShaderMaterial
var _wet: Decal
var _puddles: Decal
var _snow_cover: Decal
var _caps: Decal
var _bolts: StormBolts
var _grade: WeatherGrade
var _side: DirectionalLight3D

var _rect := Rect2i()
var _mask_versions := []
var _ground_key := 0
var _streak_texels := -1
var _strip_built := false
var _flakes_built := false
var _drift_texels := -1
var _wet_roughness := -1.0
var _puddle_roughness := -1.0
var _snow_key := 0
var _snow_wanted := 0
var _snow_wanted_at := 0.0
var _snow_roughness := -1.0
var _volume := AABB()
var _aim_y := 0.0

var _clock := 0.0
var _strikes := 0
var _next_strike := -1.0
var _strike_at := -INF
var _bearing := Vector3.RIGHT
var _level := 0.0
var _sky_base := -1.0


func _ready() -> void:
	_rain_process = _process_material("res://Classes/presentation/rain.gdshader")
	_rain_draw = _draw_material("res://Classes/presentation/rain_drop.gdshader")
	_rain = _particles(_rain_process, _rain_draw, PlaneMesh.FACE_Z)
	_splash_process = _process_material("res://Classes/presentation/splash.gdshader")
	_splash_draw = _draw_material("res://Classes/presentation/splash_draw.gdshader")
	_splash_draw.set_shader_parameter("frames", float(WeatherArt.SPLASH_FRAMES))
	_splash = _particles(_splash_process, _splash_draw, PlaneMesh.FACE_Y)
	_snow_process = _process_material("res://Classes/presentation/snow.gdshader")
	_snow_draw = _draw_material("res://Classes/presentation/snow_flake.gdshader")
	_snow = _particles(_snow_process, _snow_draw, PlaneMesh.FACE_Z)
	_drift_process = _process_material("res://Classes/presentation/snow_drift.gdshader")
	_drift_draw = _draw_material("res://Classes/presentation/rain_drop.gdshader")
	_drift_draw.set_shader_parameter("age_fade", 1.0)
	_drift = _particles(_drift_process, _drift_draw, PlaneMesh.FACE_Z)
	_wet = _decal()
	_puddles = _decal()
	_snow_cover = _decal()
	_caps = _decal()
	_caps.cull_mask = BoardOverlays.PROP_RENDER_LAYER   # the block props' own bit, and nothing else
	var white := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	white.set_pixel(0, 0, Color.WHITE)
	_caps.texture_albedo = ImageTexture.create_from_image(white)
	_caps.albedo_mix = 1.0
	_bolts = StormBolts.new()
	add_child(_bolts)
	_grade = WeatherGrade.new()
	add_child(_grade)
	_side = DirectionalLight3D.new()
	_side.shadow_enabled = true
	_side.visible = false
	add_child(_side)
	if _volume.has_volume():
		cover_volume(_volume)


# The cull box (#656): every emitter's, swept by battle3d._cover_effects whenever the board's extent
# moves -- an emitter that forgets to subscribe draws NOTHING.
func cover(board: AABB) -> void:
	cover_volume(BoardSpace.effect_volume(board, COVER_MARGIN))


# Kept as well as applied: battle3d can sweep before this node has built its emitters.
func cover_volume(volume: AABB) -> void:
	_volume = volume
	if _rain != null:
		for system: GPUParticles3D in emitters():
			system.visibility_aabb = volume


# Every particle system this node draws: the one list the cull sweep walks, so a new one cannot be
# left out of it.
func emitters() -> Array[GPUParticles3D]:
	return [_rain, _splash, _snow, _drift]


# The snow's colour on the units (#1269), its alpha 1 while this weather caps them and 0 otherwise --
# UnitMirror.snow_source. Read off the look the mirror is drawing, so a flat view caps nobody.
func unit_snow() -> Color:
	if not _snowing() or not _look.caps_units:
		return Color(1.0, 1.0, 1.0, 0.0)
	return Color(_look.snow_color.r, _look.snow_color.g, _look.snow_color.b, 1.0)


# The grade drawn over the board right now (#1269).
func grade() -> WeatherGrade:
	return _grade


# Whether every standing unit's breath fogs (#1269) -- UnitMirror.breath_source.
func breathes() -> bool:
	return _snowing() and _look.breath


# The storm's screen flash, 0..1, for battle3d's white-out -- a DRIVER, never a writer (#887's rule).
func flash_level() -> float:
	return _level * _look.flash_peak if _look != null and _look.lightning else 0.0


func _process(delta: float) -> void:
	_clock += delta
	var kind: Weather.Kind = weather_source.call() if weather_source.is_valid() else Weather.Kind.CLEAR
	var down: bool = stands_down.is_valid() and stands_down.call()
	var look := WeatherLook.for_kind(kind) if kind != Weather.Kind.CLEAR and not down else null
	if look != _look or kind != _kind:
		_switch(kind, look)
	# Every frame, the clear ones too: a grade eases OUT as well as in.
	_grade.drive(_look, Vector2(_look.wind_x, _look.wind_z) if _look != null else Vector2.ZERO, delta)
	if _look == null:
		return
	_sync_mask()
	if _raining():
		_sync_ground()
		_place_rain()
		_style()
	elif _snowing():
		_sync_snow_ground()
		_place_snow()
		_style_snow()
	_storm()


func _raining() -> bool:
	return _look != null and _look.fall == WeatherLook.Fall.RAIN


func _snowing() -> bool:
	return _look != null and _look.fall == WeatherLook.Fall.SNOW


func _switch(kind: Weather.Kind, look: WeatherLook) -> void:
	_kind = kind
	_look = look
	var rain := _raining()
	_rain.emitting = rain
	_rain.visible = rain
	_splash.emitting = rain and look.splashes
	_splash.visible = rain and look.splashes
	_wet.visible = rain
	_puddles.visible = rain and look.puddles
	var snow := _snowing()
	_snow.emitting = snow
	_snow.visible = snow
	_snow_cover.visible = snow
	_caps.visible = snow and look.caps_props
	if prop_caps.is_valid():
		prop_caps.call(snow and look.caps_props, look.snow_color if snow else Color.WHITE)
	_drift.emitting = snow and look.drift_rate > 0.0
	_drift.visible = _drift.emitting
	_drift_texels = -1
	_snow_key = 0
	_snow_roughness = -1.0
	_mask_versions = []
	_ground_key = 0
	_streak_texels = -1
	_wet_roughness = -1.0
	_puddle_roughness = -1.0
	_next_strike = -1.0
	_strike_at = -INF
	_level = 0.0
	_side.visible = false
	_bolts.clear()
	_glow(0.0)


# ---- Where drops land --------------------------------------------------------------------------

func _sync_mask() -> void:
	if grid == null:
		return
	var rect := grid.get_used_rect()
	var versions := [rect, grid.dirty.version, heights.dirty.version if heights != null else 0,
			BoardSpace.staging_version, BoardSpace.basin_version]
	# A tear-out moves cells between announcements (#521 slice B), and only placing it is cheap -- the
	# mask is one texel per cell, so it is re-read every frame the flight is in the air.
	if versions == _mask_versions and not BoardSpace.flight_active():
		return
	_mask_versions = versions
	_rect = rect
	var image := WeatherMask.build(grid, heights, rect, drawn_offset)
	var texture := ImageTexture.create_from_image(image)
	for material: ShaderMaterial in [_rain_process, _splash_process, _snow_process, _drift_process]:
		material.set_shader_parameter("mask", texture)
		material.set_shader_parameter("mask_origin", Vector2(rect.position))
		material.set_shader_parameter("cell_size", BoardSpace.CELL_SIZE)


# Where a cell is DRAWN relative to its rules surface: lifted onto the stage by a tear-out (#521), and
# lowered into its basin when the water experiment is on (#654) -- that experiment's rule is that every
# reader which lays something on a water cell subtracts the drop, and a raindrop lands on one.
static func drawn_offset(cell: Vector2i) -> Vector3:
	return BoardSpace.staged_offset(cell) - Vector3(0.0, BoardSpace.basin_drop(cell), 0.0)


# The two ground decals, rebuilt when the board or the look they paint changes. A decal's texture is
# REASSIGNED, never update()d: the renderer's decal atlas copies it once, on assignment (#358).
func _sync_ground() -> void:
	var key := hash([_mask_versions.slice(0, 3), _look.wet_tint, _look.puddles, _look.puddle_coverage,
			_look.puddle_color])
	if key == _ground_key:
		return
	_ground_key = key
	_fit(_wet)
	_fit(_puddles)
	_wet.texture_albedo = ImageTexture.create_from_image(WetGround.paint_wet(grid, _rect, _look.wet_tint))
	_puddles.visible = _look.puddles
	if _look.puddles:
		_puddles.texture_albedo = ImageTexture.create_from_image(
				WetGround.paint_puddles(grid, heights, _rect, _look.puddle_coverage, _look.puddle_color))


# The snow's own ground decal, on the same rule: rebuilt when the board or the cover it paints changes.
func _sync_snow_ground() -> void:
	if grid == null:
		return
	var key := hash([_mask_versions.slice(0, 3), _look.snow_cover, _look.snow_frost, _look.snow_flecks,
			_look.snow_color])
	if key == _snow_key:
		return
	if _snow_key != 0:
		if key != _snow_wanted:
			_snow_wanted = key
			_snow_wanted_at = _clock
		if _clock - _snow_wanted_at < COVER_SETTLE:
			return
	_snow_key = key
	_fit(_snow_cover)
	_fit(_caps)
	_snow_cover.texture_albedo = ImageTexture.create_from_image(SnowGround.paint_cover(grid, _rect,
			_look.snow_cover, _look.snow_frost, _look.snow_flecks, _look.snow_color))


# A ground decal spans the board's rect, from well under the board to well over the tear-out's stage.
func _fit(decal: Decal) -> void:
	var size := Vector3(_rect.size.x * BoardSpace.CELL_SIZE, DECAL_BELOW + DECAL_ABOVE + BoardSpace.lift_offset().y,
			_rect.size.y * BoardSpace.CELL_SIZE)
	decal.size = size
	decal.position = Vector3(_rect.position.x * BoardSpace.CELL_SIZE + size.x * 0.5,
			-DECAL_BELOW + size.y * 0.5, _rect.position.y * BoardSpace.CELL_SIZE + size.z * 0.5)


# ---- The birth box -----------------------------------------------------------------------------

# Fit the birth box to what the camera can see, every frame: the four frustum corners on the plane
# the camera looks at, plus the camera's own column, grown by how far the wind carries a particle on
# its way down and by `wander` either way. The floor is below where the LOWEST frame edge leaves the
# farthest particle's fall, so one over the void leaves the screen before it dies. Empty with no camera.
# Keys: lo, hi (Vector2, x/z), top, floor_y, fall (seconds from top to floor), area.
func _view_box(speed: float, wind: Vector2, wander: float) -> Dictionary:
	if camera == null or not camera.is_inside_tree():
		return {}
	var eye := camera.global_position
	var aim: Vector3 = aim_source.call() if aim_source.is_valid() else Vector3.ZERO
	var rise := maxf(eye.y - aim.y, 2.0)
	_aim_y = aim.y
	var view := camera.get_viewport().get_visible_rect().size
	var lo := Vector2(eye.x, eye.z)
	var hi := lo
	var far := 0.0
	var slope := INF
	for corner: Vector2 in [Vector2.ZERO, Vector2(view.x, 0.0), Vector2(0.0, view.y), view]:
		var ray := camera.project_ray_normal(corner)
		var reach := rise * 6.0 if ray.y > -0.05 else (aim.y - eye.y) / ray.y
		var at := eye + ray * minf(reach, rise * 6.0)
		lo = lo.min(Vector2(at.x, at.z))
		hi = hi.max(Vector2(at.x, at.z))
		far = maxf(far, Vector2(at.x - eye.x, at.z - eye.z).length())
		if corner.y > 0.0:
			var flat := Vector2(ray.x, ray.z).length()
			if ray.y < 0.0 and flat > 0.0001:
				slope = minf(slope, -ray.y / flat)
	var top := eye.y + SPAWN_ABOVE
	var floor_y := aim.y - rise * 4.0 if slope == INF else eye.y - far * slope - 1.0
	var fall := (top - floor_y) / maxf(speed, 0.5)
	var drift := wind * fall
	var pad := Vector2.ONE * (1.0 + maxf(wander, 0.0))
	lo = lo.min(lo - drift) - pad
	hi = hi.max(hi - drift) + pad
	return {"lo": lo, "hi": hi, "top": top, "floor_y": floor_y, "fall": fall,
			"area": (hi.x - lo.x) * (hi.y - lo.y)}


func _place_rain() -> void:
	var speed := maxf(_look.fall_speed, 0.5)
	var box := _view_box(speed, Vector2(_look.wind_x, _look.wind_z), 0.0)
	if box.is_empty():
		return
	var lo: Vector2 = box["lo"]
	var hi: Vector2 = box["hi"]
	var top: float = box["top"]
	var area: float = box["area"]
	_rain_process.set_shader_parameter("box_min", Vector3(lo.x, top - 0.5, lo.y))
	_rain_process.set_shader_parameter("box_max", Vector3(hi.x, top, hi.y))
	_rain_process.set_shader_parameter("floor_y", box["floor_y"])
	_rain_process.set_shader_parameter("velocity", Vector3(_look.wind_x, -speed, _look.wind_z))
	_size(_rain, _rain_process, _look.density * area, float(box["fall"]) + 0.25, MAX_DROPS)
	_splash_process.set_shader_parameter("box_min", Vector3(lo.x, 0.0, lo.y))
	_splash_process.set_shader_parameter("box_max", Vector3(hi.x, 0.0, hi.y))
	_splash_process.set_shader_parameter("floor_y", box["floor_y"])
	if _look.splashes:
		_size(_splash, _splash_process, _look.splash_rate * area, maxf(_look.splash_life, 0.02), MAX_SPLASHES)


# Flakes fall slowly and wander, so they get a longer life than their fall -- an eddy can hold one up --
# and the settle on top. The box is padded by an eddy's width either way.
func _place_snow() -> void:
	var speed := maxf(_look.fall_speed, 0.5)
	var wind := Vector2(_look.wind_x, _look.wind_z)
	var box := _view_box(speed, wind, _look.swirl_scale + _look.flake_sway)
	if box.is_empty():
		return
	var lo: Vector2 = box["lo"]
	var hi: Vector2 = box["hi"]
	var top: float = box["top"]
	_snow_process.set_shader_parameter("box_min", Vector3(lo.x, top - 0.5, lo.y))
	_snow_process.set_shader_parameter("box_max", Vector3(hi.x, top, hi.y))
	_snow_process.set_shader_parameter("floor_y", box["floor_y"])
	_snow_process.set_shader_parameter("velocity", Vector3(wind.x, -speed, wind.y))
	_snow_process.set_shader_parameter("sway", _look.flake_sway)
	_snow_process.set_shader_parameter("swirl", _look.flake_swirl)
	_snow_process.set_shader_parameter("swirl_scale", _look.swirl_scale)
	_snow_process.set_shader_parameter("settle", _look.flake_settle)
	_snow_process.set_shader_parameter("big", _look.big_flakes)
	_snow_process.set_shader_parameter("lift", 1.5 / UnitSprite3D.texels_per_unit)
	var life := float(box["fall"]) * 1.3 + maxf(_look.flake_settle, 0.0) + 0.25
	_size(_snow, _snow_process, _look.density * float(box["area"]), life, MAX_FLAKES)
	_place_drift(lo, hi, box["floor_y"], wind)


# The ground drift streams along the wind, born on the ground over the same box at its own rate.
func _place_drift(lo: Vector2, hi: Vector2, floor_y: float, wind: Vector2) -> void:
	var on := _look.drift_rate > 0.0
	_drift.emitting = on
	_drift.visible = on
	if not on:
		return
	var along := wind.normalized() if wind.length() > 0.001 else Vector2.RIGHT
	_drift_process.set_shader_parameter("box_min", Vector3(lo.x, 0.0, lo.y))
	_drift_process.set_shader_parameter("box_max", Vector3(hi.x, 0.0, hi.y))
	_drift_process.set_shader_parameter("floor_y", floor_y)
	_drift_process.set_shader_parameter("velocity", Vector3(along.x, 0.0, along.y) * _look.drift_speed)
	_drift_process.set_shader_parameter("hover", 1.0 / UnitSprite3D.texels_per_unit)
	_size(_drift, _drift_process, _look.drift_rate * (hi.x - lo.x) * (hi.y - lo.y), maxf(_look.drift_life, 0.05),
			MAX_DRIFT)


# Births per second -> an amount and a lifetime, with slack: either property restarts the system, so
# they move only when the wanted value strays far, and `keep` trims the births in between so the
# density on screen is the authored one whatever the box is doing. PURE in its arithmetic -- see
# amount_for -- so a case can pin it with no renderer.
func _size(system: GPUParticles3D, material: ShaderMaterial, per_second: float, life: float,
		cap: int) -> void:
	var wanted := amount_for(per_second, life)
	var stale := system.lifetime < life or wanted > system.amount \
			or float(wanted) < float(system.amount) * (1.0 - AMOUNT_SLACK)
	if stale and wanted > 0:
		system.lifetime = life * 1.15
		system.amount = mini(int(ceil(float(wanted) * 1.2)), cap)
		system.preprocess = system.lifetime
	material.set_shader_parameter("keep", keep_for(per_second, system.lifetime, system.amount))


# How many particles a system needs to carry `per_second` births that each live `life` seconds.
static func amount_for(per_second: float, life: float) -> int:
	return maxi(int(ceil(maxf(per_second, 0.0) * maxf(life, 0.0))), 1)


# The share of a system's births to keep so it carries `per_second`: it births amount/lifetime a second.
static func keep_for(per_second: float, lifetime: float, amount: int) -> float:
	if amount <= 0 or lifetime <= 0.0:
		return 0.0
	return clampf(per_second * lifetime / float(amount), 0.0, 1.0)


# ---- The look, every frame (so the Weather page's sliders show at once) ---------------------------

func _style() -> void:
	var texel := 1.0 / UnitSprite3D.texels_per_unit
	if _look.streak_texels != _streak_texels:
		_streak_texels = _look.streak_texels
		_rain_draw.set_shader_parameter("streak", ImageTexture.create_from_image(
				WeatherArt.streak(_streak_texels, Color.WHITE)))
	_rain_draw.set_shader_parameter("size", Vector2(texel, texel * float(_streak_texels)))
	_rain_draw.set_shader_parameter("tint", _look.drop_color)
	if not _strip_built:
		_strip_built = true
		_splash_draw.set_shader_parameter("strip", ImageTexture.create_from_image(
				WeatherArt.splash_strip(Color.WHITE)))
	_splash_draw.set_shader_parameter("tint", _look.splash_color)
	var ring := (_splash.draw_pass_1 as QuadMesh)
	ring.size = Vector2.ONE * texel * float(WeatherArt.SPLASH_SIDE)
	_splash.emitting = _look.splashes
	_splash.visible = _look.splashes
	_wet.albedo_mix = _look.wet_darkness
	_puddles.albedo_mix = 1.0
	# Assigned only when it moves: a decal texture assignment re-copies it into the atlas.
	if not is_equal_approx(_look.wet_roughness, _wet_roughness):
		_wet_roughness = _look.wet_roughness
		_wet.texture_orm = _orm(_wet_roughness)
	if not is_equal_approx(_look.puddle_roughness, _puddle_roughness):
		_puddle_roughness = _look.puddle_roughness
		_puddles.texture_orm = _orm(_puddle_roughness)


func _style_snow() -> void:
	if not _flakes_built:
		_flakes_built = true
		_snow_draw.set_shader_parameter("flakes", ImageTexture.create_from_image(WeatherArt.flakes(Color.WHITE)))
	_snow_draw.set_shader_parameter("size", float(WeatherArt.FLAKE_SIDE) / UnitSprite3D.texels_per_unit)
	_snow_draw.set_shader_parameter("tint", _look.flake_color)
	_snow_cover.albedo_mix = 1.0
	if _look.drift_texels != _drift_texels:
		_drift_texels = _look.drift_texels
		_drift_draw.set_shader_parameter("streak", ImageTexture.create_from_image(
				WeatherArt.streak(_drift_texels, Color.WHITE)))
	var texel := 1.0 / UnitSprite3D.texels_per_unit
	_drift_draw.set_shader_parameter("size", Vector2(texel, texel * float(maxi(_drift_texels, 1))))
	_drift_draw.set_shader_parameter("tint", _look.drift_color)
	if not is_equal_approx(_look.snow_roughness, _snow_roughness):
		_snow_roughness = _look.snow_roughness
		_snow_cover.texture_orm = _orm(_snow_roughness)
		_caps.texture_orm = _snow_cover.texture_orm
	_caps.visible = _look.caps_props
	_caps.modulate = _look.snow_color
	if prop_caps.is_valid():
		prop_caps.call(_look.caps_props, _look.snow_color)   # the door returns at once when nothing moved


# A one-texel ORM: occlusion 1, the roughness, no metal. It is masked in by the albedo's alpha, so one
# value covers the whole decal.
var _orm_cache := {}
func _orm(roughness: float) -> ImageTexture:
	var key := snappedf(roughness, 0.001)
	if not _orm_cache.has(key):
		var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		image.set_pixel(0, 0, Color(1.0, key, 0.0, 1.0))
		_orm_cache[key] = ImageTexture.create_from_image(image)
	return _orm_cache[key]


# ---- The storm ---------------------------------------------------------------------------------

func _storm() -> void:
	if not _look.lightning:
		if _level > 0.0 or _side.visible:
			_level = 0.0
			_side.visible = false
			_glow(0.0)
		return
	if _next_strike < 0.0:
		_next_strike = _clock + _wait(_strikes)
	if _clock >= _next_strike:
		_strike()
	var safe: bool = PlayerSettings.is_on(PlayerSettings.Setting.PHOTOSENSITIVITY)
	_level = strike_level(_clock - _strike_at, safe)
	_side.visible = _level > 0.001
	_side.light_energy = _level * _look.side_light_energy * (0.5 if safe else 1.0)
	_side.light_color = _look.side_light_color
	_glow(_level)


# Seconds until strike number `count`: seeded by the strike's own number (an OCCURRENCE seed), so a
# storm is reproducible and never re-rolled by a frame.
func _wait(count: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([count, "storm-wait"])
	var shortest := maxf(_look.strike_every_min, 0.1)
	return rng.randf_range(shortest, maxf(_look.strike_every_max, shortest))


func _strike() -> void:
	_strikes += 1
	_strike_at = _clock
	_next_strike = _clock + _wait(_strikes)
	# Measured from where the camera looks, so a bolt over the tear-out's stage falls past the stage
	# rather than from under it.
	var plan := StormBolts.plan_strike(_rect, _strikes, _look.bolt_distance, _look.bolt_height, _aim_y,
			_aim_y - BOLT_BELOW)
	_bearing = plan["bearing"]
	_bolts.strike(plan["path"], _rect, _strikes, _look.bolt_life, _look.bolt_width_scale)
	# The strike's own light comes in from its side, low, toward the board's centre.
	var tilt := deg_to_rad(clampf(_look.side_light_elevation, 1.0, 85.0))
	var travel := -_bearing * cos(tilt) + Vector3.DOWN * sin(tilt)
	_side.basis = Basis.looking_at(travel, Vector3.UP)


# The strike's brightness `age` seconds after it, 0..1: a hard flash and a second, smaller one (a
# lightning stroke's re-strike), or under #217's setting one soft swell with no flicker.
static func strike_level(age: float, safe: bool) -> float:
	if age < 0.0 or age > 0.8:
		return 0.0
	if safe:
		return 0.5 * sin(clampf(age / 0.6, 0.0, 1.0) * PI)
	var first := exp(-age / 0.06)
	var second := 0.75 * exp(-(age - 0.14) / 0.08) if age >= 0.14 else 0.0
	return clampf(maxf(first, second), 0.0, 1.0)


# The sky's own brightness at a strike. ProceduralSkyMaterial.energy_multiplier is a property no Look
# knob names (tests/presentation/test_weather_mirror.gd keeps it that way), so a preset can never
# fight this; when #278's stack exists the glow becomes one of its interrupts. Written only on change.
func _glow(level: float) -> void:
	if sky == null:
		return
	if _sky_base < 0.0:
		_sky_base = sky.energy_multiplier
	var cloud := _look.cloud_glow if _look != null else 0.0
	var energy := _sky_base * (1.0 + cloud * level)
	if not is_equal_approx(sky.energy_multiplier, energy):
		sky.energy_multiplier = energy


# ---- Construction ------------------------------------------------------------------------------

func _process_material(path: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(path) as Shader
	return material


func _draw_material(path: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(path) as Shader
	material.render_priority = BoardOverlays.EFFECT_RENDER_PRIORITY
	return material


func _particles(process: ShaderMaterial, draw: ShaderMaterial, facing: PlaneMesh.Orientation) -> GPUParticles3D:
	var system := GPUParticles3D.new()
	system.process_material = process
	system.local_coords = false
	system.amount = 1
	system.lifetime = 1.0
	system.emitting = false
	system.visible = false
	system.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	system.layers = BoardOverlays.WORLD_RENDER_LAYER   # the wet decal must never paint a drop
	var quad := QuadMesh.new()
	quad.orientation = facing
	quad.material = draw
	system.draw_pass_1 = quad
	add_child(system)
	return system


func _decal() -> Decal:
	var decal := Decal.new()
	decal.cull_mask = BoardOverlays.GROUND_RENDER_LAYER
	decal.upper_fade = 0.0
	decal.lower_fade = 0.0
	decal.normal_fade = 0.35   # a cliff's side stays dry rather than wearing a smear of the top
	decal.visible = false
	add_child(decal)
	return decal
