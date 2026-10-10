extends Node3D
class_name AuroraLights

# What an aurora draws (#1298), built and driven by WeatherMirror while the board's weather is an aurora
# (WeatherLook.Fall.AURORA) -- Faint Aurora, Aurora and the Aetheric Storm, looks only:
#
#   - CURTAINS: a full-screen pass (aurora_curtain.gdshader) adding bands of coloured light to the ground,
#     sorted under the clouds' slot, the fog and every piece of markup.
#   - LIGHT: a DirectionalLight3D in the curtains' colours, coming in from in front of the camera at the
#     look's elevation, since units and plants are camera-facing sprites that a light from overhead would
#     miss. No shadows, and kept out of the volumetric fog and the sky.
#   - MOTES: one particle system (aurora_mote.gdshader) rising off the ground in the weather's own view
#     box and on its own ground mask, drawn as dots or streaks (WeatherLook.MoteShape).
#
# ONE colour cycle drives all three (scheme_at): each scheme holds, then blends into the next. The light
# and the curtains share one slow pulse, which #217's photosensitivity setting holds at its mean; the
# cycle and the ripple stay, being gradual. The whole aurora eases in and out with the weather over the
# look's grade_fade, as the grade does. The storm's discharges are WeatherMirror's strike, not this node's.

const MAX_MOTES := 20000
# A mote's sideways wander, as a share of its rise: a dot drifts, a streak rises nearly straight.
const DOT_WANDER := 0.3
const STREAK_WANDER := 0.07
# The share of the board's wind a mote drifts with.
const MOTE_WIND := 0.5
# How far a mote's colour is eased from the cycle's fringe toward white.
const MOTE_WHITEN := 0.35
# The pulse's two slow swings, a second apart in period so it never repeats exactly.
const PULSE_RATES := Vector2(0.9, 0.37)
# How fast the light's colour swings between the scheme's two.
const LIGHT_SWING := 0.31

var weather: WeatherMirror            # the view box, the camera, the board rect and the wind

var _curtains: MeshInstance3D
var _curtain_material: ShaderMaterial
var _light: DirectionalLight3D
var _motes: GPUParticles3D
var _mote_process: ShaderMaterial
var _mote_draw: ShaderMaterial
var _look: WeatherLook = null         # the aurora being drawn, kept while it fades out
var _fade := 0.0
var _clock := 0.0
var _ripple := 0.0
var _pulse := 1.0
var _colours: Array[Color] = [Color.WHITE, Color.WHITE]


func _ready() -> void:
	_curtain_material = WeatherMirror.draw_material("res://Classes/presentation/aurora_curtain.gdshader")
	_curtain_material.render_priority = BoardOverlays.AURORA_RENDER_PRIORITY
	_curtains = BoardOverlays.make_screen_pass(self, _curtain_material)
	_light = DirectionalLight3D.new()
	_light.shadow_enabled = false
	_light.light_volumetric_fog_energy = 0.0
	_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_light.visible = false
	add_child(_light)
	_mote_process = WeatherMirror.process_material("res://Classes/presentation/aurora_mote.gdshader")
	_mote_draw = WeatherMirror.draw_material("res://Classes/presentation/aurora_mote_draw.gdshader")
	_mote_draw.render_priority = BoardOverlays.MOTE_RENDER_PRIORITY
	_motes = WeatherMirror.particles(self, _mote_process, _mote_draw, PlaneMesh.FACE_Z)


# The particle systems this node draws, for WeatherMirror.emitters' cull sweep.
func emitters() -> Array[GPUParticles3D]:
	return [_motes]


# The materials that read the weather's ground mask, for WeatherMirror._sync_mask.
func masked() -> Array[ShaderMaterial]:
	return [_mote_process]


# How far in the aurora is, 0..1.
func level() -> float:
	return _fade


# The colour pair the cycle shows now: [heart, fringe].
func colours() -> Array[Color]:
	return _colours


# Every frame, with the aurora look the board wears or null: eases in toward the one it is given and
# out from the last one it had, so leaving an aurora fades it rather than popping it.
func drive(look: WeatherLook, delta: float) -> void:
	if look != null:
		_look = look
	if _look == null:
		return
	var span := maxf(_look.grade_fade, 0.0)
	var step := 1.0 if span <= 0.0 else delta / span
	_fade = move_toward(_fade, 1.0 if look != null else 0.0, step)
	var on := _fade > 0.0001
	_curtains.visible = on
	_light.visible = on and _look.light_energy > 0.0
	var rising := look != null and _look.mote_rate > 0.0
	_motes.emitting = rising
	_motes.visible = on and _look.mote_rate > 0.0
	if not on:
		_look = null
		return
	_clock += delta
	_ripple += delta * _look.ripple_speed
	var safe: bool = PlayerSettings.is_on(PlayerSettings.Setting.PHOTOSENSITIVITY)
	_pulse = pulse_at(_look, _clock, safe)
	_colours = scheme_at(_look, _clock)
	_style_curtains()
	_style_light()
	_style_motes(rising)


# The colour pair the cycle shows `seconds` in, [heart, fringe]: scheme A, B, C and round again, each
# holding and then blending into the next over the last `scheme_blend` of its time. Pure.
static func scheme_at(look: WeatherLook, seconds: float) -> Array[Color]:
	var schemes: Array[Array] = [[look.scheme_a_low, look.scheme_a_fringe],
			[look.scheme_b_low, look.scheme_b_fringe], [look.scheme_c_low, look.scheme_c_fringe]]
	var t := seconds / maxf(look.scheme_seconds, 0.01)
	var index := posmod(int(floor(t)), schemes.size())
	var now: Array = schemes[index]
	var next: Array = schemes[(index + 1) % schemes.size()]
	var blend := clampf(look.scheme_blend, 0.0, 1.0)
	var mix := 0.0 if blend <= 0.0 else smoothstep(1.0 - blend, 1.0, t - floor(t))
	return [(now[0] as Color).lerp(next[0], mix), (now[1] as Color).lerp(next[1], mix)]


# The slow swell the light and the curtains share, around 1. Under the photosensitivity setting it
# holds at its mean. Pure.
static func pulse_at(look: WeatherLook, seconds: float, safe: bool) -> float:
	if safe:
		return 1.0
	var swing := 0.6 * sin(seconds * PULSE_RATES.x) + 0.4 * sin(seconds * PULSE_RATES.y + 1.3)
	return 1.0 + clampf(look.light_pulse, 0.0, 1.0) * swing


func _style_curtains() -> void:
	var m := _curtain_material
	m.set_shader_parameter("noise_tex", WeatherArt.fog_noise())
	m.set_shader_parameter("color_low", _colours[0])
	m.set_shader_parameter("color_high", _colours[1])
	m.set_shader_parameter("strength", _look.glow_strength * _fade)
	m.set_shader_parameter("bands", clampi(_look.bands, 1, 6))
	m.set_shader_parameter("spacing", _look.band_spacing)
	m.set_shader_parameter("band_width", _look.band_width)
	m.set_shader_parameter("wave", _look.band_wave)
	m.set_shader_parameter("wave_length", _look.wave_length)
	m.set_shader_parameter("time", _ripple)
	m.set_shader_parameter("rays", _look.ray_strength)
	m.set_shader_parameter("ray_spacing", _look.ray_spacing)
	m.set_shader_parameter("pulse", _pulse)
	m.set_shader_parameter("angle", deg_to_rad(_look.band_angle))
	m.set_shader_parameter("pixel_steps", 1.0 if _look.curtain_pixels else 0.0)
	m.set_shader_parameter("art_pixels", BoardOverlays.ART_PIXELS_PER_CELL)
	m.set_shader_parameter("cell_size", BoardSpace.CELL_SIZE)
	if weather != null:
		var rect := weather.board_rect()
		var centre := (Vector2(rect.position) + Vector2(rect.size) * 0.5) * BoardSpace.CELL_SIZE
		m.set_shader_parameter("centre", centre)


func _style_light() -> void:
	var swing := 0.5 + 0.5 * sin(_clock * LIGHT_SWING)
	_light.light_color = _colours[0].lerp(_colours[1], swing)
	_light.light_energy = _look.light_energy * _pulse * _fade
	var camera := weather.camera if weather != null else null
	var forward := Vector3.FORWARD
	if camera != null and camera.is_inside_tree():
		forward = -camera.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var down := deg_to_rad(clampf(_look.light_elevation, 1.0, 89.0))
	_light.basis = Basis.looking_at(forward * cos(down) + Vector3.DOWN * sin(down), Vector3.UP)


func _style_motes(rising: bool) -> void:
	var streaks := _look.mote_shape == WeatherLook.MoteShape.STREAKS
	var tint := _colours[1].lerp(Color.WHITE, MOTE_WHITEN)
	_mote_draw.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, _fade))
	_mote_draw.set_shader_parameter("texel", 1.0 / UnitSprite3D.texels_per_unit)
	_mote_draw.set_shader_parameter("shape", 1.0 if streaks else 0.0)
	if not rising or weather == null:
		return
	var life := maxf(_look.mote_life, 0.2)
	var wind := weather.board_wind() * MOTE_WIND
	var box := weather.view_box(1.0, Vector2.ZERO, 0.5)
	if box.is_empty():
		return
	var lo: Vector2 = box["lo"]
	var hi: Vector2 = box["hi"]
	var carry := wind * life
	lo = lo.min(lo - carry)
	hi = hi.max(hi - carry)
	_mote_process.set_shader_parameter("box_min", Vector3(lo.x, 0.0, lo.y))
	_mote_process.set_shader_parameter("box_max", Vector3(hi.x, 0.0, hi.y))
	_mote_process.set_shader_parameter("rise", _look.mote_rise)
	_mote_process.set_shader_parameter("wander", STREAK_WANDER if streaks else DOT_WANDER)
	_mote_process.set_shader_parameter("wind", wind)
	_mote_process.set_shader_parameter("height", _look.mote_height)
	WeatherMirror.size_emitter(_motes, _mote_process, _look.mote_rate * (hi.x - lo.x) * (hi.y - lo.y), life,
			MAX_MOTES)
