# The HD-2D look-dev scene controller (#203 / #176 Stage 0): lighting presets and
# per-ingredient toggles, so each layer of the post stack can be judged alone and
# the relighting trick (same board, four moods) can be demoed live. This scene is
# the permanent lighting/grading playground; nothing in the game references it.
#
# Keys: 1-4 presets (Day/Sunset/Night/Overcast) - Q/E orbit - wheel zoom - WASD pan
#       R reset cam - F fog - G glow - C depth of field - V vignette - T torch - H help
extends Node3D

const PRESET_NAMES: Array[String] = ["Day", "Sunset", "Night", "Overcast"]
const PRESETS: Array[Dictionary] = [
	{
		"sun_rotation": Vector3(-50.0, -35.0, 0.0),
		"sun_color": Color(1.0, 0.985, 0.94),
		"sun_energy": 1.3,
		"fog_density": 0.015,
		"fog_albedo": Color(0.85, 0.88, 0.92),
		"saturation": 1.05,
		"sky_top": Color(0.32, 0.5, 0.78),
		"sky_horizon": Color(0.68, 0.74, 0.82),
	},
	{
		"sun_rotation": Vector3(-14.0, -62.0, 0.0),
		"sun_color": Color(1.0, 0.62, 0.32),
		"sun_energy": 1.1,
		"fog_density": 0.03,
		"fog_albedo": Color(0.98, 0.75, 0.55),
		"saturation": 1.12,
		"sky_top": Color(0.36, 0.28, 0.5),
		"sky_horizon": Color(0.98, 0.6, 0.35),
	},
	{
		"sun_rotation": Vector3(-48.0, 24.0, 0.0),
		"sun_color": Color(0.55, 0.65, 0.95),
		"sun_energy": 0.22,
		"fog_density": 0.045,
		"fog_albedo": Color(0.5, 0.56, 0.72),
		"saturation": 0.9,
		"sky_top": Color(0.04, 0.06, 0.13),
		"sky_horizon": Color(0.1, 0.13, 0.22),
	},
	{
		"sun_rotation": Vector3(-65.0, -25.0, 0.0),
		"sun_color": Color(0.86, 0.89, 0.93),
		"sun_energy": 0.55,
		"fog_density": 0.055,
		"fog_albedo": Color(0.75, 0.77, 0.8),
		"saturation": 0.72,
		"sky_top": Color(0.45, 0.48, 0.52),
		"sky_horizon": Color(0.62, 0.64, 0.66),
	},
]

const TORCH_FLICKER := 0.12

@onready var _sun: DirectionalLight3D = $Sun
@onready var _env: Environment = $WorldEnvironment.environment
@onready var _camera: Camera3D = $CameraRig/Pitch/Camera
@onready var _torch_light: OmniLight3D = $Props/Torch/TorchLight
@onready var _flame: MeshInstance3D = $Props/Torch/Flame
@onready var _vignette: ColorRect = $UI/Vignette
@onready var _help: Label = $UI/Help

var _torch_base_energy := 2.5
var _time := 0.0


func _ready() -> void:
	_torch_base_energy = _torch_light.light_energy
	apply_preset(0)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1:
			apply_preset(0)
		KEY_2:
			apply_preset(1)
		KEY_3:
			apply_preset(2)
		KEY_4:
			apply_preset(3)
		KEY_F:
			toggle_fog()
		KEY_G:
			toggle_glow()
		KEY_C:
			toggle_dof()
		KEY_V:
			toggle_vignette()
		KEY_T:
			toggle_torch()
		KEY_H:
			_help.visible = not _help.visible


func _process(delta: float) -> void:
	_time += delta
	if _torch_light.visible:
		var flicker := 1.0 + TORCH_FLICKER * sin(_time * 13.0) * sin(_time * 7.3)
		_torch_light.light_energy = _torch_base_energy * flicker


func apply_preset(index: int) -> void:
	var preset := PRESETS[clampi(index, 0, PRESETS.size() - 1)]
	_sun.rotation_degrees = preset["sun_rotation"]
	_sun.light_color = preset["sun_color"]
	_sun.light_energy = preset["sun_energy"]
	_env.volumetric_fog_density = preset["fog_density"]
	_env.volumetric_fog_albedo = preset["fog_albedo"]
	_env.adjustment_saturation = preset["saturation"]
	var sky_material := _env.sky.sky_material as ProceduralSkyMaterial
	sky_material.sky_top_color = preset["sky_top"]
	sky_material.sky_horizon_color = preset["sky_horizon"]
	sky_material.ground_horizon_color = preset["sky_horizon"]


func toggle_fog() -> void:
	_env.volumetric_fog_enabled = not _env.volumetric_fog_enabled


func toggle_glow() -> void:
	_env.glow_enabled = not _env.glow_enabled


func toggle_dof() -> void:
	var attributes := _camera.attributes as CameraAttributesPractical
	var enabled := not attributes.dof_blur_far_enabled
	attributes.dof_blur_far_enabled = enabled
	attributes.dof_blur_near_enabled = enabled


func toggle_vignette() -> void:
	_vignette.visible = not _vignette.visible


func toggle_torch() -> void:
	_torch_light.visible = not _torch_light.visible
	_flame.visible = _torch_light.visible
