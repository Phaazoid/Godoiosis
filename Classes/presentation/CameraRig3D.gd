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
# WHERE IT LOOKS is two channels summed, and `position` is DERIVED from them every frame (#520):
# _aim is the point on the board the rig sits over, _lift how far the torn-out diorama has risen
# under it (#521). Kept apart because they ease on different clocks -- board tracking under playback
# is HELD, since the 2D camera it mirrors already tweens its own travel and easing on top of an ease
# is lag, while the lift is the map-to-battle transition and is the one thing that pans. Nothing may
# write `position` directly; hold_at (the snap) and glide_to (the pan) are the doors, and a stray
# assignment is simply overwritten on the next frame rather than half-honoured.
#
# A THIRD addend joins them (#520 diff 2b): the FLOURISH, the impact shake plus the resting sway.
# It is summed last and is not one of the two above precisely because it is not where the camera
# LOOKS -- it is a displacement laid over that, so it sits outside pan_limit's clamp (a blow at the
# board's edge jolts as hard as one in the middle) and outside stash_view (the view handed back is
# the one the player left, never one caught mid-shake). It lives only while the view is BORROWED.
#
# glide_to exists because the dev's rule is that the camera never teleports (scratchpad, 2026-08-26:
# "the camera still has a few cases where it teleports - this should never happen, it should always
# be a pan"). Its scope is the BOARD -- his own narrowing, 2026-08-27: "that only applies while we're
# on the map", with the map-to-battle transition a declared exception that starts as a pan.
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
# How fast a GLIDE closes, in the same units as `smoothing` above -- which stays the YAW and ZOOM
# rate. Its own number because the two answer different questions: that one is how snappy the camera
# feels under your hand, this is how a shot TRAVELS when playback moves it. Shared by every pan (the
# view return, both recentres, R) AND by the tear-out lift, so the map-to-battle transition paces
# with them; the day the transition wants its own rate, this is the line that forks.
@export var glide_smoothing := 6.0
@export var orbit_button: MouseButton = MOUSE_BUTTON_RIGHT: set = _set_orbit_button
# Stood down by a host that needs the wheel for something else (#285: the elevation brush paints
# at the wheel's level). Declarative, exactly like orbit_button above -- and it has to be a knob
# rather than the host consuming the event, because this rig is a CHILD of the host and therefore
# sees _unhandled_input FIRST: a set_input_as_handled() up there lands after the zoom (measured).
@export var wheel_zoom_enabled := true
@export var orbit_sensitivity := 0.25        # degrees of yaw AND pitch per pixel dragged
@export var orbit_click_slop_px := 4.0       # travel under this still counts as a click

# How far the player's own drag may tilt, in degrees below the horizon (#586). Handling rather than
# mood, so they are GameKnobs rows and not a Look preset's business -- the board authors where the
# camera STARTS (board_pitch_degrees below), these say how far a hand may take it from there.
#
# The steep end is where the HD-2D conceit gives out: a billboard seen from overhead is being looked
# at from the one angle its art is not drawn for. The shallow end is where you start seeing along the
# board rather than at it. Both are feel values -- tune them, do not reason about them.
@export var min_pitch_degrees := -80.0
@export var max_pitch_degrees := -20.0
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

# The board's AUTHORED pitch (#586) -- what a mood carries and what R returns to. It moved OFF the
# Pitch node's own `rotation_degrees:x`, which the Look knob used to address directly, because that
# property is now DERIVED: _process eases it every frame, and a knob naming a property the game
# writes back per frame is the slider that moves and silently reverts -- the one failure
# tests/dev/test_moods_tool.gd exists to refuse.
#
# So the split is the same one #520 drew for position (`_aim + _lift`): the BASELINE is authored and
# owned here, the live angle is derived from it plus whatever the player's hand has done. The setter
# re-seeds that live angle, which is what keeps the Moods slider honest -- drag it and the camera
# moves, rather than the value landing somewhere nothing reads.
@export var board_pitch_degrees := -40.0: set = _set_board_pitch_degrees

@onready var _pitch: Node3D = $Pitch
@onready var _camera: Camera3D = $Pitch/Camera
@onready var _attributes: CameraAttributesPractical = _camera.attributes as CameraAttributesPractical

var _target_yaw_degrees := 0.0
var _target_distance := 14.0
# The live pitch the player's drag writes and _process eases the Pitch node onto (#586). Seeded from
# board_pitch_degrees and put back there by R -- so a tilt is a DEVIATION from what the board
# authored, never a replacement for it. Third eased channel, beside the yaw and the distance.
var _target_pitch_degrees := -40.0
# The LIVE angle, and the rig's OWN -- never read back off the Pitch node, which is a pure output.
# See _process for why that read is what stopped this channel settling.
var _pitch_degrees := -40.0
# The two position channels (see the header): where the rig looks NOW and where it is heading, plus
# the same pair for the diorama's rise. `position` is their sum and nothing else.
var _aim := Vector3.ZERO
var _target_aim := Vector3.ZERO
var _lift := Vector3.ZERO
var _target_lift := Vector3.ZERO
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
var _borrowed_pitch_degrees := 0.0
var _view_borrowed := false

# What a DIRECTED shot is measured from (#520): the detent align_to_detent squared playback up to.
# A third yaw beside the two above, and a third question -- _home_ is where the BOARD starts,
# _borrowed_ where the PLAYER was standing, and this is where THIS PASS started.
var _squared_up_yaw := 0.0

# The FLOURISH: a third position addend beside _aim and _lift (#520 diff 2b), and the same law --
# `position` is the sum and nothing writes it directly. Kept apart from the other two because these
# are not WHERE THE CAMERA LOOKS but a displacement laid over it, which has two consequences worth
# stating: they are summed AFTER pan_limit's clamp, so a blow at the board's edge jolts exactly as
# hard as one in the middle, and they are never stashed, so the view the player gets back is the one
# they left rather than one caught mid-shake.
var _shake_amplitude := 0.0
var _shake_elapsed := 0.0
var _sway_elapsed := 0.0
# How far the director has pushed the camera IN for the beat now playing (#520 diff 2c), in world
# units of distance. The flourish's shape on the ZOOM axis, and an ADDEND for the same reason: the
# wheel stays the player's through a pass, so a director may lean on their distance but must never
# assign over it. Re-solved from the published emphasis every frame, so the mirror's poll is
# idempotent and there is nothing to unwind when the beat ends.
var _dolly := 0.0
# Empty = unbounded (the look-dev scene never frames, so it keeps free roam).
var pan_limit := Rect2()

var _orbiting := false
var _orbit_travel_px := 0.0


func _ready() -> void:
	_target_yaw_degrees = rotation_degrees.y
	_target_distance = _camera.position.z
	# The EXPORT is the owner now (#586), not the Pitch node's own rotation -- so the node is written
	# from it here rather than read into it. The two agree in every shipped scene; if they ever
	# disagree, the one a mood can address is the one that should win.
	_target_pitch_degrees = board_pitch_degrees
	_pitch_degrees = board_pitch_degrees
	_pitch.rotation_degrees.x = board_pitch_degrees
	# Whatever the scene authored is where the rig already IS, so both channels start there rather
	# than gliding in from the origin on the first frame.
	_aim = position
	_target_aim = position
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
			# The same drag's OTHER axis, which this branch used to throw away (#586, dev: "I don't
			# see the harm in letting the player drag up/down too"). Grab-the-world in both, so
			# dragging DOWN pulls the far edge down and the camera looks further down with it.
			#
			# Clamped on the TARGET rather than after easing: a target parked past the limit would
			# drag the angle back out to it on every frame it eased in -- the same reasoning the
			# pan_limit clamp states for the aim.
			_target_pitch_degrees = clampf(_target_pitch_degrees - drag.relative.y * orbit_sensitivity,
					min_pitch_degrees, max_pitch_degrees)
			return

	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_Q:
				_target_yaw_degrees = _next_detent(1)
			KEY_E:
				_target_yaw_degrees = _next_detent(-1)
			KEY_R:
				# A PAN since #520, like the other three that used to cut. Yaw and distance were
				# already eased, so this is what makes all three axes of "back to the opening
				# shot" one movement instead of a jump with a lerp bolted to it.
				glide_to(_home_position)
				_target_yaw_degrees = _home_yaw_degrees
				_target_distance = _home_distance
				# ...and the tilt, to the BOARD's angle rather than a _home_ of its own (#586): pitch
				# is authored by the mood, so the board already says what "the opening shot" means
				# here and a second copy would only drift from it. R is the ONLY leveller -- Q/E
				# stays a yaw realign, so a tilt survives turning the board to look at the other
				# side of what you tilted for (dev, 2026-08-27).
				_target_pitch_degrees = board_pitch_degrees


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


# Re-seeds the live tilt, which is the whole reason this is a setter (#586). A mood applying its
# authored pitch, or the Moods slider moving under a dev's hand, has to MOVE THE CAMERA -- a baseline
# that only took effect on the next R would be a knob writing somewhere nothing reads, which is the
# no-placebo law's failure with the revert running slowly instead of instantly.
#
# It therefore also discards a player's tilt, and that is right at both call sites: applying a look is
# a board arriving, and a dev dragging the slider is asking to see THIS angle.
func _set_board_pitch_degrees(value: float) -> void:
	board_pitch_degrees = value
	_target_pitch_degrees = value
	_pitch_degrees = value
	# SNAPPED, not eased -- frame()'s "hold_at, not glide_to" reasoning, and for its exact reason:
	# pitch is part of the camera's basis, so a rig still lerping toward a newly applied mood
	# unprojects at one angle and picks at another, and every screen-space read taken on the way in
	# desyncs. A mood arriving is a board arriving. The player's own drag still eases, in _process.
	#
	# Guarded because an @export setter can fire while the scene is still being built, before
	# @onready has resolved anything; _ready writes the node itself for that first pass.
	if _pitch != null:
		_pitch.rotation_degrees.x = value


func set_zoom(distance: float) -> void:
	_target_distance = minf(distance, max_distance)


# Widen the DISTANCE alone until `volume` fits, leaving the aim, the yaw and the opening shot exactly
# where they are (#520). frame() cannot serve this: it re-aims, adopts _home_* and drops the borrowed
# view -- all three wrong inside a pass, the last of them fatal, which is the same reason a directed
# shot is aim_along rather than pose().
#
# WIDENS ONLY, never narrows. The ask is "show both their start and end position in the initial shot"
# (dev, scratchpad 2026-08-26), and a short hop already has both ends in frame at the playback
# distance -- pulling IN to fit one would answer a question nobody asked. set_zoom is the door, so the
# board's own ceiling still clamps it and a span too big to fit simply frames as much as it can,
# which is the ticket's own "should be doable unless super zoomed in".
func widen_to_fit(volume: AABB) -> void:
	var distance := _fit_distance(volume.grow(fit_margin_cells))
	if distance <= 0.0:
		return   # no valid projection yet -- the caller keeps what it has, as everywhere else here
	set_zoom(maxf(_target_distance, distance))


# --- Where the rig looks (#520) ---------------------------------------------------------------

# Move the aim OUTRIGHT: the snap. Every writer that already has the camera where it wants it comes
# through here -- WASD (a held key is already continuous, so easing it would only put lag between the
# press and the board moving), frame()/pose() (a rig still lerping unprojects at one distance and
# picks at another, desyncing every screen-space read on the way in), and the playback mirror, whose
# 2D twin is already tweening the travel it reports.
func hold_at(aim: Vector3) -> void:
	_target_aim = aim
	_aim = aim
	_apply_position()


# ...and the PAN: the target moves and _process closes the gap. The four places the camera used to
# teleport are its whole caller list -- the pass-end view return, both recentres (SPACE and #471's
# return to the acting unit), and R.
func glide_to(aim: Vector3) -> void:
	_target_aim = aim


# How far the ground under the rig has been torn out of the board (#521). POLLED rather than latched,
# with the staging's own offset, so the camera rides the diorama up and settles back down with it and
# a tear-out that clears mid-pass needs nobody to remember to undo this.
func lift_to(lift: Vector3) -> void:
	_target_lift = lift


# The ONE place the node's position is written. All three channels, summed -- see the header.
func _apply_position() -> void:
	position = _aim + _lift + flourish()


# The shake and the sway, summed, and ZERO unless playback has BORROWED the view. That flag is the
# gate because it already answers exactly this question for all three claimants -- a player pass, an
# AI turn and the burn phase each stash on the way in and restore on the way out -- and because the
# look-dev scene never stashes, so it never flourishes. A sway under the player's own hand is motion
# sickness rather than mood, and a jolt surviving the release would ride into the view just handed
# back.
func flourish() -> Vector3:
	if not _view_borrowed:
		return Vector3.ZERO
	var lift := shake_offset(_shake_amplitude, _shake_elapsed) \
			+ sway_offset(Pacing.sway_of(Pacing.active_profile()), _sway_elapsed)
	return Vector3(0.0, lift, 0.0)


# A damped oscillation, and PURE -- deterministic in its two arguments, so one blow reads the same
# every time it is replayed (Law #1: a curve over time, never a noise roll) and a case can pin the
# shape with no scene at all. WORLD Y only, no camera basis: a vertical jolt is the GBA-era hit this
# is being mocked against, it cannot fight pan_limit (which bounds X and Z), and it needs no
# re-derivation when the yaw turns under it.
static func shake_offset(amplitude: float, elapsed: float) -> float:
	if amplitude <= 0.0:
		return 0.0
	return amplitude * exp(-Pacing.SHAKE_DECAY * elapsed) * sin(Pacing.SHAKE_FREQUENCY * elapsed)


# ...and the resting drift, pure the same way. TWO sines at an irrational ratio, so the bob never
# repeats itself into a metronome -- still a curve over time, still no roll.
static func sway_offset(strength: float, elapsed: float) -> float:
	if strength <= 0.0:
		return 0.0
	var bob := sin(Pacing.SWAY_SPEED * elapsed) + 0.5 * sin(Pacing.SWAY_SPEED * 1.618 * elapsed)
	return Pacing.SWAY_AMPLITUDE * strength * bob / 1.5


# The impact door. STRONGEST WINS, measured against what is LEFT of a jolt in flight rather than
# against what it started at -- the holds' own rule ("the loudest single one wins, by value"),
# applied to an impulse. Summing would make a three-victim volley hit three times as hard as a duel,
# which is the opposite of "one blast is one moment".
func shake(amplitude: float) -> void:
	if amplitude <= _live_shake_amplitude():
		return
	_shake_amplitude = amplitude
	_shake_elapsed = 0.0


# The director's push-in for the beat now playing (#520 diff 2c), taking the published 0..1 weight.
# Re-solves rather than accumulating, so the mirror's per-frame poll lands on the same distance every
# time and a beat ending simply publishes 0 -- nothing to unwind, the same shape aim_along has.
func dolly_to(emphasis: float) -> void:
	_dolly = maxf(0.0, emphasis) * Pacing.DOLLY_IN * Pacing.direction_of(Pacing.active_profile())


# Where the zoom actually eases to: the player's distance, less whatever the director is leaning in.
#
# THE FLOOR IS ON THE DOLLY'S OWN CONTRIBUTION, NEVER ON THE TOTAL, and that is the whole care here.
# This rig has no zoom-in floor by dev ruling (asked twice) -- scrolling in past the aim point takes
# the camera through its target to look back, which is his call for HIS hand. A director subtracting
# from an already-close player would inherit that hole and fly the camera through a unit on the exact
# beat it most wants to be looking at one.
#
# So the effective floor is the lower of DOLLY_FLOOR and where the player already is: closer than the
# floor, and the push-in contributes nothing at all rather than the floor yanking them back OUT --
# which would be a leash on the wheel, the thing #520 refused.
func _dollied_distance() -> float:
	if _dolly <= 0.0 or not _view_borrowed:
		return _target_distance
	return maxf(_target_distance - _dolly, minf(_target_distance, Pacing.DOLLY_FLOOR))


# The envelope, not the offset: the offset crosses zero twice a cycle, so comparing against it would
# let any scratch win at a zero crossing.
func _live_shake_amplitude() -> float:
	return _shake_amplitude * exp(-Pacing.SHAKE_DECAY * _shake_elapsed)


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

	# Snap, never ease -- hold_at, not glide_to: a camera still lerping toward the fit unprojects at
	# one distance and picks at another, which desyncs every screen-space read taken on the way.
	hold_at(_aim_at(box))
	set_zoom(_fit_distance(box))
	_camera.position.z = _target_distance

	# R means "back to the opening shot". Position and distance are board facts and come
	# from the fit; yaw is a scene fact and stays whatever the scene authored.
	#
	# The AIM rather than `position`, which also carries the tear-out lift: home is a place on the
	# board, and flying back to one taken mid-diorama would put the opening shot in the sky.
	_home_position = _aim
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

	hold_at(aim)
	set_zoom(distance)
	_camera.position.z = _target_distance

	# R means "back to the opening shot", and an authored opening shot INCLUDES its yaw -- so unlike
	# frame(), which leaves yaw to the scene, this adopts all three.
	_home_position = _aim
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
	# ...and THAT is what a directed shot is measured from (#520). Captured here rather than read
	# live at aim_along below, because a live read would compound: beat two would lerp from where
	# beat one landed, so a partial strength would give the fifth beat more angle than the first.
	_squared_up_yaw = _target_yaw_degrees
	# THE TILT IS DELIBERATELY NOT SQUARED UP HERE, and it was for one run of this suite (#520 diff
	# 2b). It looked like the third of the same three squarings -- the yaw detent, the playback zoom
	# reset -- and the argument for it was that a player parked at max_pitch_degrees leaves a stoop
	# nowhere to go. Both halves are wrong. aim_along writes an ABSOLUTE target off
	# board_pitch_degrees and never reads the live angle, so wherever the player left the tilt the
	# stoop lands in the same place; and #586's rule is that a tilt survives everything but R, which
	# test_a_realign_keeps_the_tilt pins over this very function. A beat with no aim line therefore
	# keeps whatever tilt it found, which is already aim_along's stated idiom for the yaw.


# The camera DIRECTOR's door, and deliberately not pose() (#520): pose() snaps the yaw, adopts the
# result as the OPENING SHOT, and drops the borrowed view -- all three wrong for a shot inside a
# pass, the last of them fatal, since it is what the camera return is holding.
#
# So this writes the one thing a directed shot is: a yaw TARGET, eased by _process exactly as free
# orbit and Q/E are eased. It re-solves rather than latching, so the per-frame mirror poll may call
# it every frame with the same line and land on the same angle.
#
# An EMPTY line leaves the yaw alone rather than returning to square-on -- absence means "the camera
# does not move", which is already the schedule's idiom for a beat with nobody to frame.
func aim_along(line: Array[Vector2i]) -> void:
	if line.size() != 2:
		return
	var side_on := BoardSpace.side_on_yaw(line[0], line[1], _squared_up_yaw)
	if is_nan(side_on):
		return
	var strength := Pacing.direction_of(Pacing.active_profile())
	_target_yaw_degrees = _squared_up_yaw + rad_to_deg(
			angle_difference(deg_to_rad(_squared_up_yaw), deg_to_rad(side_on))) * strength
	# ...and the same published line drives the PITCH (#520 diff 2b). DERIVED here rather than
	# published as a second field: a directed beat IS the shot that earns both, so one fact answers
	# for two channels and there is nothing to keep in step.
	#
	# Measured from board_pitch_degrees -- the board's own AUTHORED angle, a value nothing in a pass
	# moves -- so re-solving every frame lands in the same place however the player had tilted.
	# Measuring from the LIVE pitch instead would creep to full over a few frames and the strength
	# would stop meaning anything, which is the idempotence failure the yaw's own mutant proved.
	# It is also why the claim edge does NOT square the tilt up: see align_to_detent.
	_target_pitch_degrees = clampf(board_pitch_degrees + Pacing.PITCH_DIVE * strength,
			min_pitch_degrees, max_pitch_degrees)


# --- the view playback borrows (#520 follow-up) ------------------------------------------------
#
# Called on the EDGE into playback, BEFORE the detent/zoom reset -- after it would stash the reset
# rather than the player's own framing.
#
# The AIM rather than `position`, and the TARGET rather than the live value: what is being put back
# is where the player was heading on the board, so a claim landing while a previous pass's lift is
# still settling must not bake that lift into the view it hands back.
func stash_view() -> void:
	_borrowed_position = _target_aim
	_borrowed_yaw_degrees = _target_yaw_degrees
	_borrowed_distance = _target_distance
	_borrowed_pitch_degrees = _target_pitch_degrees
	_view_borrowed = true
	# A pass opens STILL. The flourish gate below already zeroes the offset while nothing is
	# borrowed, so this is belt-and-braces only in the frame sense -- what it actually buys is that a
	# claim landing moments after a big hit does not inherit the tail of that hit's jolt.
	_shake_amplitude = 0.0
	_shake_elapsed = 0.0


# ...and on the edge back out. A no-op unless something is actually borrowed, so a release with no
# claim behind it (a board clear, a fixture poking the flag) moves nothing.
#
# Restores exactly the way R does, and since #520 that means all three axes are TARGETS the smoothing
# closes: this is the most visible of the four pans, firing at the end of every Execute and every
# enemy turn. Distance goes through set_zoom rather than a raw assign so it lands in the same clamp
# every other writer uses -- the board may have been repainted while playback held the camera.
func restore_view() -> void:
	if not _view_borrowed:
		return
	_view_borrowed = false
	glide_to(_borrowed_position)
	_target_yaw_degrees = _borrowed_yaw_degrees
	set_zoom(_borrowed_distance)
	# The tilt comes back with the rest (#586). A player who tilted to read a pit and then pressed
	# Execute is standing where they were standing; the pitch is part of that, exactly as the yaw is.
	_target_pitch_degrees = _borrowed_pitch_degrees


# Anything that redefines the OPENING SHOT is a new board, and a view borrowed from the old one
# must never be flown back to -- ScenarioManager.clear_board releases the playback lock, which
# would otherwise fire the restore above on a board that no longer exists.
func drop_stashed_view() -> void:
	_view_borrowed = false


func _process(delta: float):
	var blend := 1.0 - exp(-smoothing * delta)
	rotation_degrees.y = _lerp_angle_degrees(rotation_degrees.y, _target_yaw_degrees, blend)
	# ...toward the DOLLIED distance (#520 diff 2c), which is _target_distance untouched unless the
	# director is leaning in. The player's own value is never written, so the wheel keeps working
	# under a push-in and the view handed back at the release is the distance they chose.
	_camera.position.z = lerpf(_camera.position.z, _dollied_distance(), blend)
	# The third eased channel (#586), on the SAME rate as the yaw: they are two axes of one drag, and
	# a pitch that settled at a different speed would make a diagonal drag curve. Plain lerpf rather
	# than the angle helper -- pitch is a bounded band, never a circle, so there is no short way round.
	#
	# THE LIVE ANGLE IS THIS FLOAT AND THE NODE IS A PURE OUTPUT -- `position`'s shape (#520), and here
	# it is load-bearing rather than tidy.
	#
	# MEASURED, and the reason this is not the obvious `_pitch.rotation_degrees.x = lerpf(...)`:
	# reading the angle back off the node reds `tests/presentation/test_unit_health_bar.gd` (3 cases)
	# and `test_health_block_debris.gd`, on a branch that touches nothing but the camera -- one of them
	# reporting a wrong CUBE COUNT. Own-float, green; read-back, red; verified both ways.
	#
	# The MECHANISM is unconfirmed. What is known: the read-back round-trips through the basis, which
	# returns -39.999992 for an authored -40 (the number every LookPreset records), so the ease chases
	# a target it cannot express. The obvious story from there is `battle3d._poll_pointer`, which skips
	# its work only while `_camera.global_transform` compares EQUAL -- but two cases written to pin
	# that (a settling transform, and a synthetic pointer surviving) BOTH PASSED against the mutant,
	# so do not repeat it as fact. The suites above are the real guard; if this line is ever touched,
	# run them. Yaw survives the identical code only because the scenes author it at 0.
	var next_pitch := lerpf(_pitch_degrees, _target_pitch_degrees, blend)
	if not is_equal_approx(next_pitch, _pitch_degrees):
		_pitch_degrees = next_pitch
		_pitch.rotation_degrees.x = next_pitch
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
			hold_at(_target_aim + Vector3(pan.x, 0.0, pan.y).rotated(Vector3.UP, deg_to_rad(rotation_degrees.y)))

	# The two eased channels (#520). Headless, land now: nobody is watching, the asymptotic lerp
	# never settles, and a suite sampling the rig must read the DECISION rather than frame timing.
	# Fourth member of the escape Pacing.beat, CameraController.pan_to and CameraController._process
	# already keep, and kept for the same reason.
	var glide := 1.0 if DisplayServer.get_name() == "headless" else 1.0 - exp(-glide_smoothing * delta)
	_aim = _aim.lerp(_target_aim, glide)
	_lift = _lift.lerp(_target_lift, glide)

	# The flourish clocks (#520 diff 2b). The headless escape is HERE, on the clock, rather than on
	# the offsets -- both curves are naturally zero at t = 0 (a sine of nothing), so a headless run
	# leaves `position` bit-identical to what it was before this channel existed, and no case that
	# asserts a coordinate can be moved by a jolt it was never meant to see. Headless refuses to
	# SPEND time, exactly as Pacing.beat does; a case that wants to watch a curve supplies the
	# elapsed time itself and reads flourish().
	if DisplayServer.get_name() != "headless":
		_shake_elapsed += delta
		_sway_elapsed += delta

	# Clamped unconditionally, not inside the pan branch: a host driving the aim (the Battle3D camera
	# mirror) writes it earlier in the same frame and must be bounded too. On the AIM rather than on
	# the node, because `position` is derived below and a clamp written there would be undone on the
	# next frame -- and on the TARGET as well as the live value, or an aim parked off the board would
	# drag the camera back out to it every frame it eased in.
	if pan_limit.has_area():
		_target_aim.x = clampf(_target_aim.x, pan_limit.position.x, pan_limit.end.x)
		_target_aim.z = clampf(_target_aim.z, pan_limit.position.y, pan_limit.end.y)
		_aim.x = clampf(_aim.x, pan_limit.position.x, pan_limit.end.x)
		_aim.z = clampf(_aim.z, pan_limit.position.y, pan_limit.end.y)

	_apply_position()


func _lerp_angle_degrees(from_degrees: float, to_degrees: float, weight: float) -> float:
	return rad_to_deg(lerp_angle(deg_to_rad(from_degrees), deg_to_rad(to_degrees), weight))
