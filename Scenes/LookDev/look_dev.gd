# The HD-2D look-dev scene controller (#203 / #176 Stage 0): named moods and per-ingredient
# toggles, so each layer of the post stack can be judged alone and the relighting trick
# (same board, four moods) can be demoed live. The permanent lighting/grading playground.
#
# NOT a scratch scene, whatever "LookDev" suggests (#393). Five presentation suites fixture
# on LookDev.tscn -- test_board_overlays, test_board_picker, test_camera_rig, test_look_dev,
# test_walk_demo -- Battle3D.tscn loads its MeshLibrary, BoardMirror and BoardOverlays read
# textures out of Art/LookDev/, and its camera rig IS the shipping one (CameraRig3D, which
# lived here until #393). Editing it freely reds the presentation area; deleting it does worse.
#
# THE MOODS ARE NOT HERE. They were `const PRESETS`, a hardcoded copy of four of the twelve
# LookPresets #253 shipped -- a second answer to "what is Day?", free to drift from the files
# the game itself renders. PRESET_NAMES now holds only the key BINDINGS; LookKnobs.resolve +
# LookKnobs.apply do the rest, the same applier battle3d._apply_board_look calls, so a mood
# cannot mean one thing in the diorama and another on a board.
#
# Two consequences of applying a WHOLE mood, both #253's own ruling arriving here:
#   - a mood key RESTORES an ingredient you toggled off (F then 1 brings fog back), because a
#     mood you cannot fully re-enter is not a mood;
#   - `opening_view_cells` has no home in this scene (the rig never frames here, it free-roams),
#     so that one knob is silently skipped -- the tolerance LookKnobs.write already gives a
#     knob whose NODE is missing, one level down.
#
# Keys: 1-4 moods (Day/Sunset/Night/Overcast) - Q/E orbit - wheel zoom - WASD pan
#       R reset cam - F fog - G glow - C depth of field - V vignette - T torch - H help
extends Node3D

# Key bindings, not content: each name is resolved through LookKnobs against Resources/LookPresets/.
const PRESET_NAMES: Array[String] = ["Day", "Sunset", "Night", "Overcast"]
const TORCH_FLICKER := 0.12

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


# The whole mood, resolved by NAME. A name that no longer resolves falls back to the default
# loudly rather than leaving whatever was on screen -- LookKnobs owns that, here as on a board.
func apply_preset(index: int) -> void:
	var preset_name: String = PRESET_NAMES[clampi(index, 0, PRESET_NAMES.size() - 1)]
	LookKnobs.apply(self, LookKnobs.resolve(preset_name))


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
