# The look-dev camera rig (#203): the camera contract made drivable. Yaw orbits in
# 90-degree snaps only (Q/E) -- free orbit would misrepresent the contract the real
# game camera will honor. Wheel zooms, WASD pans the focus point, R resets. Pitch
# and FOV are authored on the Pitch/Camera nodes and tuned in the inspector.
extends Node3D

const YAW_STEP := 90.0
const ZOOM_MIN := 6.0
const ZOOM_MAX := 24.0
const ZOOM_STEP := 1.5
const PAN_SPEED := 8.0
const SMOOTHING := 8.0

@onready var _camera: Camera3D = $Pitch/Camera

var _target_yaw_degrees := 0.0
var _target_distance := 14.0
var _home_position := Vector3.ZERO
var _home_yaw_degrees := 0.0
var _home_distance := 14.0


func _ready() -> void:
	_target_yaw_degrees = rotation_degrees.y
	_target_distance = _camera.position.z
	_home_position = position
	_home_yaw_degrees = _target_yaw_degrees
	_home_distance = _target_distance


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_Q:
				_target_yaw_degrees += YAW_STEP
			KEY_E:
				_target_yaw_degrees -= YAW_STEP
			KEY_R:
				position = _home_position
				_target_yaw_degrees = _home_yaw_degrees
				_target_distance = _home_distance
	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = maxf(ZOOM_MIN, _target_distance - ZOOM_STEP)
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = minf(ZOOM_MAX, _target_distance + ZOOM_STEP)


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-SMOOTHING * delta)
	rotation_degrees.y = _lerp_angle_degrees(rotation_degrees.y, _target_yaw_degrees, blend)
	_camera.position.z = lerpf(_camera.position.z, _target_distance, blend)

	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		pan.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		pan.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		pan.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		pan.x += 1.0
	if pan != Vector2.ZERO:
		pan = pan.normalized() * PAN_SPEED * delta
		position += Vector3(pan.x, 0.0, pan.y).rotated(Vector3.UP, deg_to_rad(rotation_degrees.y))


func _lerp_angle_degrees(from_degrees: float, to_degrees: float, weight: float) -> float:
	return rad_to_deg(lerp_angle(deg_to_rad(from_degrees), deg_to_rad(to_degrees), weight))
