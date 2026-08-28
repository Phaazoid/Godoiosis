class_name SpriteAnimator
extends RefCounted

# Plays a SpriteFrames as a CLOCK and a frame choice, and nothing else (#629).
#
# It is the project's first frame-animation anything -- before this a unit's visual was one still
# Texture2D swapped between three authored stills (map / move / downed), and #603, #358 and #414's
# declared deferral all name a layer that did not exist.
#
# It deliberately does NOT know about the node it drives. The caller asks `texture_now()` and
# assigns; that is what lets the frame maths be exercised with no scene, no viewport and no waiting
# on real frames -- `frame_at` is static and pure, so a test states an elapsed time and an expected
# frame instead of sleeping through 277 GBA frames of Attack.
#
# TIME ARRIVES AS A PARAMETER, and that is load-bearing rather than tidy: the caller passes its own
# `_process` delta, which Godot has already scaled by `Engine.time_scale` -- so #520's hitstop
# freezes the swing along with the world, for free and by construction. An animator holding its own
# Timer or Tween would have had to learn about the freeze separately, and would have drifted from it.
#
# A non-looping animation REPORTS being finished rather than clamping on its last frame, because the
# caller has something to hand the sprite back to (UnitSprite3D's authored still) and only it knows
# what that is.


# What the sheet declares, and what plays it.
var frames: SpriteFrames = null
var animation := &""

var _elapsed := 0.0
var _playing := false


# Which frame of `anim` is showing at `elapsed` seconds. -1 = the animation has ENDED (only reachable
# when it does not loop). Static and pure so it can be asked about a SpriteFrames built in a test.
#
# A frame's stored duration is a MULTIPLIER on the animation's frame time, so its real length is
# `duration / speed`. The Sage's sheet prints durations in GBA frames and the generator writes
# speed 60, which makes a printed 13 exactly 13/60 s -- but nothing here assumes that, and a sheet
# authored at another rate reads correctly.
static func frame_at(sheet: SpriteFrames, anim: StringName, elapsed: float) -> int:
	if sheet == null or not sheet.has_animation(anim):
		return -1
	var count := sheet.get_frame_count(anim)
	if count <= 0:
		return -1
	var speed := maxf(sheet.get_animation_speed(anim), 0.001)
	var total := 0.0
	for i in count:
		total += sheet.get_frame_duration(anim, i) / speed
	if total <= 0.0:
		return count - 1

	var t := maxf(elapsed, 0.0)
	if sheet.get_animation_loop(anim):
		t = fposmod(t, total)
	elif t >= total:
		return -1

	var reached := 0.0
	for i in count:
		reached += sheet.get_frame_duration(anim, i) / speed
		if t < reached:
			return i
	return count - 1


# Total length in seconds, or 0.0 for an animation that does not exist.
static func length_of(sheet: SpriteFrames, anim: StringName) -> float:
	if sheet == null or not sheet.has_animation(anim):
		return 0.0
	var speed := maxf(sheet.get_animation_speed(anim), 0.001)
	var total := 0.0
	for i in sheet.get_frame_count(anim):
		total += sheet.get_frame_duration(anim, i) / speed
	return total


# Start `anim` from its first frame. Refuses an animation the sheet does not carry rather than
# playing something else -- a silently wrong gesture is the failure worth being loud about.
func play(sheet: SpriteFrames, anim: StringName) -> bool:
	if sheet == null or not sheet.has_animation(anim) or sheet.get_frame_count(anim) <= 0:
		return false
	frames = sheet
	animation = anim
	_elapsed = 0.0
	_playing = true
	return true


func stop() -> void:
	_playing = false
	_elapsed = 0.0


func is_playing() -> bool:
	return _playing


func elapsed() -> float:
	return _elapsed


# Advance the clock. Ends the animation the moment it runs past its last frame.
func advance(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	if frame_at(frames, animation, _elapsed) < 0:
		_playing = false


# The frame to show right now, or null when nothing is playing -- which is the caller's cue to put
# its own art back.
func texture_now() -> Texture2D:
	if not _playing:
		return null
	var index := frame_at(frames, animation, _elapsed)
	if index < 0:
		return null
	return frames.get_frame_texture(animation, index)
