# The diorama camera rig (#203, camera pass #176 stage 4d): the camera contract made
# drivable, and shared verbatim by the look-dev scene and Battle3D.
#
# Yaw ORBITS FREELY (drag orbit_button) and rests wherever you leave it; Q/E step to
# the next 90-degree detent, i.e. one press realigns from any angle. That repeals the
# original snap-only contract (dev ruling 2026-08-14): the sprite-facing seam already
# judges against the LIVE camera basis, so nothing structural depended on a quantized
# resting yaw -- what the detents buy is the crisp axis-aligned pose on demand.
#
# orbit_button is a knob because the choice is a feel call: MIDDLE leaves right-click
# free to mean cancel on PRESS (its meaning everywhere else), while RIGHT matches the
# 3D-app instinct at the cost of deferring cancel to release. The rig tracks how far
# a gesture travelled so its host can tell a click from a drag either way.
#
# frame() is the framing authority: only this node knows fov/aspect/pitch, so callers
# pass the volume they want seen and this solves the distance (Law #4 -- pass, don't
# look up). It also derives max_distance from that fit, so the fit can never be eaten
# by its own clamp -- which is exactly what shipped before it: a board span in CELLS
# was handed to set_zoom, which wants a camera DISTANCE, and clamped to 24 on boards
# needing 82. Its second volume is the SHOT/BOUNDS split (dev feel-check 2026-08-14:
# fitting the whole board opened the game unplayably far out): the first box is what
# to look at now, the second the box the view may never leave, which is what sets the
# zoom ceiling and the pan limit. One box means both, i.e. the original behaviour.
#
# align_to_detent() exists for the AI turn: an enemy phase plays out square-on however
# the player left the camera. It is the only realign the rig does not owe to a keypress.
#
# DoF focus TRACKS the zoom (dev note, 2026-08-12: static distances made the blur
# swallow the board at close zoom): every frame the near/far focus distances are
# re-derived as offsets around the camera's live distance to the rig, so the focus
# band stays glued to the diorama. The band widths are the exports below; blur
# AMOUNT stays a hand-tuned knob on the camera's CameraAttributes.
extends Node3D

# Feel knobs, every one (the tuning rule -- these were consts until 4d).
@export var yaw_step := 90.0
@export var min_distance := 6.0
@export var max_distance := 24.0   # frame() overwrites this from the board it fits
@export var zoom_step := 1.5
@export var pan_speed := 8.0
@export var smoothing := 8.0
@export var orbit_button := MOUSE_BUTTON_RIGHT
@export var orbit_sensitivity := 0.25        # degrees of yaw per pixel dragged
@export var orbit_click_slop_px := 4.0       # travel under this still counts as a click
@export var pan_margin_cells := 4.0          # how far past the board panning may stray
@export var fit_margin_cells := 1.0          # breathing room around a framed board
@export var zoom_out_slack := 1.0            # 1.0 = may not zoom out past the whole board

# Focus band offsets: in-focus from (distance - near) to (distance + far).
# Defaults reproduce the originally authored look at the default zoom of 14.
@export var focus_band_near := 5.0
@export var focus_band_far := 4.0

# False while something else owns the camera -- an AI turn, a menu. Deliberately NOT
# set_process(false): the host still drives position, and the smoothing and DoF
# tracking in _process have to keep running under it.
@export var manual_input_enabled := true

@onready var _camera: Camera3D = $Pitch/Camera
@onready var _attributes: CameraAttributesPractical = _camera.attributes as CameraAttributesPractical

var _target_yaw_degrees := 0.0
var _target_distance := 14.0
var _home_position := Vector3.ZERO
var _home_yaw_degrees := 0.0
var _home_distance := 14.0
# Empty = unbounded (the look-dev scene never frames, so it keeps free roam).
var pan_limit := Rect2()

var _orbiting := false
var _orbit_travel_px := 0.0


func _ready() -> void:
	_target_yaw_degrees = rotation_degrees.y
	_target_distance = _camera.position.z
	_home_position = position
	_home_yaw_degrees = _target_yaw_degrees
	_home_distance = _target_distance


func _unhandled_input(event: InputEvent) -> void:
	if not manual_input_enabled:
		return

	var button := event as InputEventMouseButton
	if button != null and button.button_index == orbit_button:
		_orbiting = button.pressed
		if button.pressed:
			_orbit_travel_px = 0.0
		return

	if _orbiting:
		var drag := event as InputEventMouseMotion
		if drag != null:
			_orbit_travel_px += drag.relative.length()
			_target_yaw_degrees -= drag.relative.x * orbit_sensitivity
			return

	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_Q:
				_target_yaw_degrees = _next_detent(1)
			KEY_E:
				_target_yaw_degrees = _next_detent(-1)
			KEY_R:
				position = _home_position
				_target_yaw_degrees = _home_yaw_degrees
				_target_distance = _home_distance
	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(_target_distance - zoom_step)
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(_target_distance + zoom_step)


# The next detent in `direction`. From an exact detent this is the old `+= yaw_step`
# bit-for-bit; from anywhere else it realigns, which is the whole point of Q/E now.
func _next_detent(direction: int) -> float:
	var steps := _target_yaw_degrees / yaw_step
	if direction > 0:
		return (floorf(steps) + 1.0) * yaw_step
	return (ceilf(steps) - 1.0) * yaw_step


func is_orbiting() -> bool:
	return _orbiting


# Did the gesture that just ended stay inside the click slop? Only meaningful to a
# host that shares orbit_button with a click verb (Battle3D's right-click cancel).
func last_gesture_was_click() -> bool:
	return _orbit_travel_px <= orbit_click_slop_px


func set_zoom(distance: float) -> void:
	_target_distance = clampf(distance, min_distance, max_distance)


# Frame `volume` (in cells/world units): aim at it, sit far enough back that all of it
# is inside THIS camera's frustum, adopt that as home, and bound panning. Callers supply
# the volume; the trigonometry is the rig's because only it knows fov, aspect and pitch.
#
# `bounds` is the larger box the view may never leave -- the whole board -- and it alone
# sets the zoom ceiling and the pan limit. That split is what lets the opening shot sit
# close on the player's own squad while zooming out still reaches the far corner. Omit it
# and `volume` serves as both, which is the original single-box behaviour.
func frame(volume: AABB, bounds := AABB()) -> void:
	var limits := bounds if bounds.size != Vector3.ZERO else volume
	var box := volume.grow(fit_margin_cells)
	var limit_box := limits.grow(fit_margin_cells)
	var ceiling := _fit_distance(limit_box)
	if ceiling <= 0.0:
		return   # no valid projection yet (a viewport with no size); keep the current framing

	position = _aim_at(box)
	# Derived from the BOUNDS, not from this shot: a ceiling solved off a close opening
	# volume would clamp the player out of ever seeing the rest of the board.
	max_distance = maxf(ceiling * zoom_out_slack, min_distance)
	set_zoom(_fit_distance(box))
	# Snap, never ease: a camera still lerping toward the fit unprojects at one distance
	# and picks at another, which desyncs every screen-space read taken on the way.
	_camera.position.z = _target_distance

	# R means "back to the opening shot". Position and distance are board facts and come
	# from the fit; yaw is a scene fact and stays whatever the scene authored.
	_home_position = position
	_home_distance = _target_distance

	pan_limit = Rect2(limit_box.position.x, limit_box.position.z, limit_box.size.x, limit_box.size.z).grow(pan_margin_cells)


# Where the rig sits to look at `box`: its centre, lifted to the top of the box so the
# pitch looks down at the surface rather than through it.
func _aim_at(box: AABB) -> Vector3:
	var center := box.get_center()
	return Vector3(center.x, box.end.y, center.z)


# How far back this camera must sit for every corner of `box` to be inside its frustum.
# Returns 0 when there is no valid projection yet, which is the caller's abort signal.
func _fit_distance(box: AABB) -> float:
	var proj := _camera.get_camera_projection()
	var tan_h := 1.0 / proj.x.x if proj.x.x > 0.0 else 0.0
	var tan_v := 1.0 / proj.y.y if proj.y.y > 0.0 else 0.0
	if not is_finite(tan_h) or not is_finite(tan_v) or tan_h <= 0.0 or tan_v <= 0.0:
		return 0.0

	# Solve per corner. With the camera at aim - d*forward, a corner's horizontal and
	# vertical offsets are independent of d while its depth is (q . forward) + d, so
	# each corner sets a lower bound on d directly.
	var aim := _aim_at(box)
	var basis := _camera.global_transform.basis
	var right := basis.x
	var up := basis.y
	var forward := -basis.z
	var distance := min_distance
	for i in 8:
		var q := box.get_endpoint(i) - aim
		var depth := q.dot(forward)
		distance = maxf(distance, absf(q.dot(right)) / tan_h - depth)
		distance = maxf(distance, absf(q.dot(up)) / tan_v - depth)
	return distance


# Snap the yaw to the NEAREST detent, unlike Q/E which always travel one. The AI turn is
# its caller: an enemy phase reads square-on however the player left the camera.
func align_to_detent() -> void:
	_target_yaw_degrees = roundf(_target_yaw_degrees / yaw_step) * yaw_step


func _process(delta: float):
	var blend := 1.0 - exp(-smoothing * delta)
	rotation_degrees.y = _lerp_angle_degrees(rotation_degrees.y, _target_yaw_degrees, blend)
	_camera.position.z = lerpf(_camera.position.z, _target_distance, blend)
	_attributes.dof_blur_near_distance = maxf(0.5, _camera.position.z - focus_band_near)
	_attributes.dof_blur_far_distance = _camera.position.z + focus_band_far

	if manual_input_enabled:
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
			pan = pan.normalized() * pan_speed * delta
			position += Vector3(pan.x, 0.0, pan.y).rotated(Vector3.UP, deg_to_rad(rotation_degrees.y))

	# Clamped unconditionally, not inside the pan branch: a host driving position (the
	# Battle3D camera mirror) writes it earlier in the same frame and must be bounded too.
	if pan_limit.has_area():
		position.x = clampf(position.x, pan_limit.position.x, pan_limit.end.x)
		position.z = clampf(position.z, pan_limit.position.y, pan_limit.end.y)


func _lerp_angle_degrees(from_degrees: float, to_degrees: float, weight: float) -> float:
	return rad_to_deg(lerp_angle(deg_to_rad(from_degrees), deg_to_rad(to_degrees), weight))
