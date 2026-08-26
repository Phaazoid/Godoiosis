extends Node3D
class_name CameraRig3D

# The diorama camera rig (#203, camera pass #176 stage 4d): the camera contract made
# drivable, and shared verbatim by Battle3D and the look-dev scene.
#
# It was `Scenes/LookDev/look_dev_camera.gd` until #393 -- shipping code wearing the scratch
# scene's name, in the scratch scene's folder, with no class_name, while Battle3D.tscn loaded
# this exact script. Same move LookKnobs made out of dev/, for the same reason: where a thing
# was first prototyped is not where it belongs once the game runs it. It sits beside CameraPose,
# which exists only to feed pose() below.
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
# a gesture travelled so its host can tell a click from a drag either way. Rebinding it --
# or losing manual input -- mid-drag RELEASES the orbit, because the matching release event
# would otherwise never arrive and a stranded gesture kills pointing permanently (#231).
#
# frame() is the framing authority: only this node knows fov/aspect/pitch, so callers
# pass the volume they want seen and this solves the distance (Law #4 -- pass, don't
# look up). rebound() is its BOARD half, split out for #231 -- how far you may zoom out
# and pan, with the camera left exactly where it is. Painting a tile grows the board and
# must move the limits without moving the view, which is what the 2D twin
# (CameraController.refresh_bounds) has always done; frame() calls it for that half, so
# the two can never disagree. It also derives max_distance from that fit, so the fit can never be eaten
# by its own clamp -- which is exactly what shipped before it: a board span in CELLS
# was handed to set_zoom, which wants a camera DISTANCE, and clamped to 24 on boards
# needing 82. Its second volume is the SHOT/BOUNDS split (dev feel-check 2026-08-14:
# fitting the whole board opened the game unplayably far out): the first box is what
# to look at now, the second the box the view may never leave, which is what sets the
# zoom ceiling and the pan limit. One box means both, i.e. the original behaviour.
# pose() is frame()'s AUTHORED twin (#234) -- same bounds half, but the shot is given as a pose
# instead of solved from a volume, which is the only way an authored yaw can be expressed.
#
# align_to_detent() exists for the AI turn: an enemy phase plays out square-on however
# the player left the camera. It is the only realign the rig does not owe to a keypress.
#
# DoF focus TRACKS the zoom (dev note, 2026-08-12: static distances made the blur
# swallow the board at close zoom): every frame the near/far focus distances are
# re-derived as offsets around the camera's live distance to the rig, so the focus
# band stays glued to the diorama. The band widths are the exports below; blur
# AMOUNT stays a hand-tuned knob on the camera's CameraAttributes.

# Feel knobs, every one (the tuning rule -- these were consts until 4d).
@export var yaw_step := 90.0
# There is NO zoom-in floor (dev, 2026-08-23, asked twice: "please remove it entirely"). It was
# min_distance, 6.0, and it was the whole of "I can't zoom in far enough to see what I'm brushing" --
# Ctrl+wheel had always handed notches back (battle3d's _handle_brush_zoom), they just hit this the
# instant they arrived. Lowering it to 1.0 first was not what he asked for and did not satisfy him.
#
# Consequence, stated rather than guarded: scrolling in past the aim point takes the distance through
# zero and negative, and the camera passes through its target and looks back. His call; a floor at 0
# is the one line that would stop it. Pinned by test_zooming_in_has_no_floor_while_the_ceiling_still_holds.
@export var max_distance := 24.0   # frame() overwrites this from the board it fits
@export var zoom_step := 1.5
@export var pan_speed := 8.0
@export var smoothing := 8.0
@export var orbit_button: MouseButton = MOUSE_BUTTON_RIGHT: set = _set_orbit_button
# Stood down by a host that needs the wheel for something else (#285: the elevation brush paints
# at the wheel's level). Declarative, exactly like orbit_button above -- and it has to be a knob
# rather than the host consuming the event, because this rig is a CHILD of the host and therefore
# sees _unhandled_input FIRST: a set_input_as_handled() up there lands after the zoom (measured).
@export var wheel_zoom_enabled := true
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
@export var manual_input_enabled := true: set = _set_manual_input_enabled

# The zoom wheel is gated SEPARATELY from everything else the player can do to the camera (#520,
# dev 2026-08-26). While a pass or an AI turn plays, playback owns WHERE the camera looks and the
# player keeps how far out it sits -- so manual_input_enabled goes false and this stays true. A
# menu takes both, because the surface on screen wants the wheel for itself.
@export var zoom_input_enabled := true

# Where playback frames from: the distance the rig resets to whenever something other than the
# player takes the camera. Without it you watch a whole enemy turn at whatever zoom you happened
# to leave the last one at, which is the awkwardness this closes -- the reset is a STARTING point,
# not a leash, and the wheel is live again immediately after.
@export var playback_distance := 11.0

@onready var _camera: Camera3D = $Pitch/Camera
@onready var _attributes: CameraAttributesPractical = _camera.attributes as CameraAttributesPractical

var _target_yaw_degrees := 0.0
var _target_distance := 14.0
var _home_position := Vector3.ZERO
var _home_yaw_degrees := 0.0
var _home_distance := 14.0

# The view playback BORROWED, put back when it gives the camera up (dev, 2026-08-26: "the camera
# should return home after a pass, and after the enemy turn"). NOT _home_* above, which is the
# OPENING SHOT and what R restores -- two different questions: home is where the BOARD starts,
# this is where the PLAYER was standing. Declared side by side per Law #4.
var _borrowed_position := Vector3.ZERO
var _borrowed_yaw_degrees := 0.0
var _borrowed_distance := 0.0
var _view_borrowed := false
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
	# ABOVE the manual gate, deliberately: zoom is the one thing the player keeps while playback
	# owns the camera (#520). Its own switch is zoom_input_enabled; wheel_zoom_enabled stays the
	# separate question of whether the WHEEL is this rig's to read at all (#285 hands it away).
	var notch := event as InputEventMouseButton
	if notch != null and notch.pressed and zoom_input_enabled and wheel_zoom_enabled:
		if notch.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(-1)
			return
		elif notch.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1)
			return

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


# One notch of zoom. Public so a host that has taken the wheel away can still hand a MODIFIED
# notch back (#285's Ctrl+wheel) without reaching into _target_distance or re-spelling the step.
func zoom_by(notches: int) -> void:
	set_zoom(_target_distance + zoom_step * notches)


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


# End an orbit gesture that will never get its own release event. _orbit_travel_px
# deliberately SURVIVES: the physical release is still coming, last_gesture_was_click()
# reads this on it, and zeroing here would report an abandoned drag as a click — firing a
# spurious cancel at whatever the pointer had wandered onto.
func release_orbit() -> void:
	_orbiting = false


# Rebinding mid-drag strands _orbiting TRUE for ever: the release arrives on the OLD button
# and never matches, so every later motion becomes yaw and is_orbiting() refuses pointing
# permanently. #231 makes this a live path rather than a hypothesis — the tile brush takes
# RIGHT while armed and hands orbit to MIDDLE, on a knob the host rewrites as the brush arms
# and disarms. Guarding at the property rather than that one caller also catches the
# inspector, which is where a feel call on this knob actually gets made.
func _set_orbit_button(value: MouseButton) -> void:
	if value == orbit_button:
		return
	orbit_button = value
	release_orbit()


# Same strand, second trigger: something else taking the camera (an AI turn, a menu) while
# the player is mid-drag. MUST early-out on an unchanged write — battle3d._process assigns
# this EVERY frame, and an unguarded release would cancel a live orbit sixty times a second.
func _set_manual_input_enabled(value: bool) -> void:
	if value == manual_input_enabled:
		return
	manual_input_enabled = value
	if not value:
		release_orbit()


func set_zoom(distance: float) -> void:
	_target_distance = minf(distance, max_distance)


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
	if not rebound(limits):
		return   # no valid projection yet (a viewport with no size); keep the current framing

	position = _aim_at(box)
	set_zoom(_fit_distance(box))
	# Snap, never ease: a camera still lerping toward the fit unprojects at one distance
	# and picks at another, which desyncs every screen-space read taken on the way.
	_camera.position.z = _target_distance

	# R means "back to the opening shot". Position and distance are board facts and come
	# from the fit; yaw is a scene fact and stays whatever the scene authored.
	_home_position = position
	_home_distance = _target_distance
	drop_stashed_view()


# The AUTHORED twin of frame()'s SHOT half (#234): a pose someone flew to, rather than a volume
# solved into one. frame() cannot express this -- it DERIVES position and distance from a box and
# deliberately never touches yaw ("yaw is a scene fact", below) -- so the shot half needs its own
# door. The bounds half is the same rebound() call, which is what keeps an authored start replacing
# the shot and nothing else: zoom ceiling and pan limit stay derived from the board.
#
# Nothing here validates the pose. An aim off the board is CLAMPED, silently, by the pan_limit
# clamp _process already runs on every frame, and the distance by set_zoom -- the same doors every
# other writer goes through (dev call 2026-08-15). There is deliberately no second answer to
# "where may the camera be".
func pose(aim: Vector3, yaw_degrees: float, distance: float, bounds: AABB) -> void:
	# YAW FIRST, and snapped, because rebound() solves the ceiling and the pan limit through the
	# CAMERA'S OWN BASIS (_fit_distance projects the box corners onto it) -- so a bounds fit taken
	# at the previous yaw is a fit for an orientation this shot will never be seen at. frame() never
	# meets this: it does not author yaw, so its rebound is always already at the viewing angle.
	var previous_yaw := rotation_degrees.y
	var previous_target_yaw := _target_yaw_degrees
	# Snapping is also frame()'s own rule, applied to the axis it never had to: a rig still lerping
	# unprojects at one basis and picks at another, desyncing every screen-space read on the way in.
	_target_yaw_degrees = yaw_degrees
	rotation_degrees.y = yaw_degrees

	if not rebound(bounds):
		# No valid projection yet; leave the current framing exactly as frame() does -- which means
		# putting back the yaw this function had already moved.
		rotation_degrees.y = previous_yaw
		_target_yaw_degrees = previous_target_yaw
		return

	position = aim
	set_zoom(distance)
	_camera.position.z = _target_distance

	# R means "back to the opening shot", and an authored opening shot INCLUDES its yaw -- so unlike
	# frame(), which leaves yaw to the scene, this adopts all three.
	_home_position = position
	_home_yaw_degrees = _target_yaw_degrees
	_home_distance = _target_distance
	drop_stashed_view()


# The half of frame() that is about the BOARD rather than the shot: how far out you may
# zoom and how far you may pan. Split out for #231, where painting a tile grows the board
# and the limits must follow WITHOUT the camera moving — the 2D twin
# (CameraController.refresh_bounds) has always updated limits and never re-aimed.
# False = no valid projection yet; the caller keeps what it has.
func rebound(bounds: AABB) -> bool:
	var limit_box := bounds.grow(fit_margin_cells)
	var ceiling := _fit_distance(limit_box)
	if ceiling <= 0.0:
		return false
	# Derived from the BOUNDS, not from any one shot: a ceiling solved off a close opening
	# volume would clamp the player out of ever seeing the rest of the board.
	max_distance = ceiling * zoom_out_slack
	set_zoom(_target_distance)   # re-clamp: a shrunken board can leave you outside the new ceiling
	pan_limit = Rect2(limit_box.position.x, limit_box.position.z, limit_box.size.x, limit_box.size.z).grow(pan_margin_cells)
	return true


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
	var distance := 0.0   # the fit only ever grows this; there is no floor to seed from
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


# --- the view playback borrows (#520 follow-up) ------------------------------------------------
#
# Called on the EDGE into playback, BEFORE the detent/zoom reset -- after it would stash the reset
# rather than the player's own framing.
func stash_view() -> void:
	_borrowed_position = position
	_borrowed_yaw_degrees = _target_yaw_degrees
	_borrowed_distance = _target_distance
	_view_borrowed = true


# ...and on the edge back out. A no-op unless something is actually borrowed, so a release with no
# claim behind it (a board clear, a fixture poking the flag) moves nothing.
#
# Restores exactly the way R does: position ASSIGNED, because the mirror writes it directly every
# frame and there is no target to ease toward; yaw and distance set as TARGETS so _process eases
# them. Distance goes through set_zoom rather than a raw assign so it lands in the same clamp every
# other writer uses -- the board may have been repainted while playback held the camera.
func restore_view() -> void:
	if not _view_borrowed:
		return
	_view_borrowed = false
	position = _borrowed_position
	_target_yaw_degrees = _borrowed_yaw_degrees
	set_zoom(_borrowed_distance)


# Anything that redefines the OPENING SHOT is a new board, and a view borrowed from the old one
# must never be flown back to -- ScenarioManager.clear_board releases the playback lock, which
# would otherwise fire the restore above on a board that no longer exists.
func drop_stashed_view() -> void:
	_view_borrowed = false


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
