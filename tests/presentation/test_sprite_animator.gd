# Playing a frame animation on a unit sprite (#629): the clock, and the BORROW.
#
# The frame maths is exercised with no scene and no waiting, because `SpriteAnimator.frame_at` is
# static and pure -- a case states an elapsed time and an expected frame rather than sleeping
# through 277 GBA frames of Attack. Durations here are deliberately IRREGULAR: a reader that
# multiplied elapsed time by a frame rate instead of walking the per-frame durations passes a
# uniform fixture and fails every one of these.
#
# The other half is ownership. `UnitSprite3D.texture` had five writers before this, all spelling one
# decision from the sprite triple plus downed/walking, and an animation is a sixth with nothing to
# arbitrate between them. The gate -- not the assignment -- is what makes that safe, so the cases
# that matter here drive the REAL walk and downed paths against a playing animation rather than
# checking the animator in isolation.
extends GdUnitTestSuite

# 10 + 30 + 20 GBA frames at speed 60, so the boundaries land at 1/6 s, 2/3 s and 1 s.
const HELD: Array = [10.0, 30.0, 20.0]


func test_frame_at_walks_the_per_frame_durations_rather_than_a_frame_rate() -> void:
	var sheet := _sheet(false)
	assert_int(SpriteAnimator.frame_at(sheet, &"swing", 0.0)).is_equal(0)
	assert_int(SpriteAnimator.frame_at(sheet, &"swing", 0.16)).is_equal(0)
	assert_int(SpriteAnimator.frame_at(sheet, &"swing", 0.17)).is_equal(1)
	assert_int(SpriteAnimator.frame_at(sheet, &"swing", 0.66)).is_equal(1)
	assert_int(SpriteAnimator.frame_at(sheet, &"swing", 0.67)).is_equal(2)
	assert_int(SpriteAnimator.frame_at(sheet, &"swing", 0.99)).is_equal(2)


func test_a_gesture_that_does_not_loop_reports_ending_rather_than_clamping() -> void:
	# The caller has something to hand the sprite back to and only it knows what; clamping on the
	# last frame would leave a unit frozen mid-swing forever.
	var sheet := _sheet(false)
	assert_float(SpriteAnimator.length_of(sheet, &"swing")).is_equal_approx(1.0, 0.0001)
	assert_int(SpriteAnimator.frame_at(sheet, &"swing", 1.0)).is_equal(-1)
	assert_int(SpriteAnimator.frame_at(sheet, &"swing", 99.0)).is_equal(-1)


func test_a_looping_animation_wraps_instead() -> void:
	var sheet := _sheet(true)
	assert_int(SpriteAnimator.frame_at(sheet, &"swing", 1.2)).is_equal(1)
	assert_int(SpriteAnimator.frame_at(sheet, &"swing", 2.0)).is_equal(0)


func test_a_frozen_clock_holds_the_frame() -> void:
	# What #520's hitstop does to a swing: Engine.time_scale of 0 makes every _process delta 0, and
	# the animation must simply stop where it is rather than needing to be told about the freeze.
	var anim := SpriteAnimator.new()
	assert_bool(anim.play(_sheet(false), &"swing")).is_true()
	anim.advance(0.5)
	var held := anim.texture_now()
	for i in 10:
		anim.advance(0.0)
	assert_object(anim.texture_now()).is_same(held)
	assert_bool(anim.is_playing()).is_true()


func test_playing_an_animation_the_set_does_not_carry_is_refused() -> void:
	var anim := SpriteAnimator.new()
	assert_bool(anim.play(_sheet(false), &"nope")).is_false()
	assert_bool(anim.is_playing()).is_false()
	assert_object(anim.texture_now()).is_null()


# --- the borrow ----------------------------------------------------------------------------------


func test_an_animation_borrows_the_texture_and_stopping_gives_it_back() -> void:
	var sprite := _sprite()
	var still := sprite.texture
	assert_object(still).is_not_null()

	assert_bool(sprite.play_animation(_sheet(false), &"swing")).is_true()
	assert_bool(sprite.is_animating()).is_true()
	assert_object(sprite.texture).is_not_same(still)

	sprite.stop_animation()
	assert_bool(sprite.is_animating()).is_false()
	assert_object(sprite.texture).is_same(still)


func test_the_walk_swap_cannot_steal_the_texture_from_a_playing_animation() -> void:
	# The gate, driven through the real path rather than by poking a flag: #215's mirror calls
	# set_walking_visual every time the 2D game reports movement, so without the gate a walking
	# unit's swing would be overwritten on the very next frame.
	var sprite := _sprite()
	sprite.play_animation(_sheet(false), &"swing")
	var frame := sprite.texture

	sprite.set_walking_visual(true)
	assert_object(sprite.texture).override_failure_message(
			"the walk swap wrote over a playing animation").is_same(frame)

	# ...and the state it recorded while blocked is what it wears once the borrow ends.
	sprite.stop_animation()
	assert_object(sprite.texture).is_same(sprite._move_texture)


func test_running_off_the_end_hands_the_texture_back_without_being_told() -> void:
	var sprite := _sprite()
	var still := sprite.texture
	sprite.play_animation(_sheet(false), &"swing")
	sprite._process(0.5)
	assert_bool(sprite.is_animating()).is_true()
	sprite._process(0.6)   # past the 1.0s total
	assert_bool(sprite.is_animating()).is_false()
	assert_object(sprite.texture).is_same(still)


func test_going_down_interrupts_a_swing() -> void:
	# Without the interrupt the borrow gate holds the animation's frame until it runs out, so a unit
	# killed mid-gesture finishes the gesture before falling.
	var sprite := _sprite()
	sprite.play_animation(_sheet(false), &"swing")
	sprite.set_downed(true)
	assert_bool(sprite.is_animating()).is_false()
	assert_object(sprite.texture).is_same(sprite._downed_texture)


func test_an_idle_sprite_spends_no_frame_time() -> void:
	# Every unit on the board owns an animator; only one mid-gesture should be ticking.
	var sprite := _sprite()
	assert_bool(sprite.is_processing()).is_false()
	sprite.play_animation(_sheet(false), &"swing")
	assert_bool(sprite.is_processing()).is_true()
	sprite.stop_animation()
	assert_bool(sprite.is_processing()).is_false()

# --- where a frame hangs from (#634) --------------------------------------------------------------


func test_a_frame_hangs_from_the_stand_point_its_set_carries() -> void:
	# A 20x12 card whose character stands at (6, 11) -- left of centre and one row off the bottom,
	# the shape a card sheet actually has. The origin must land THERE, which means offset
	# (20/2 - 6, 11 - 12/2) = (4, 5). Both components differ from the still pivot and from each
	# other, so a swapped axis or a missed correction cannot pass.
	var sprite := _sprite()
	assert_vector(sprite.offset).is_equal(UnitSprite3D.STILL_PIVOT)
	sprite.play_animation(_carded_sheet(Vector2(6, 11)), &"swing")
	assert_vector(sprite.offset).is_equal(Vector2(4, 5))


func test_a_left_facing_unit_hangs_from_the_mirrored_stand_point() -> void:
	# flip_h leaves the QUAD where it is and mirrors only the UVs, so the ink that stood at column 6
	# now stands at column 14 and the correction has to invert with it. Without this a fixed
	# correction is right in one facing and nearly a full cell out in the other -- worse than the
	# symmetric error it replaced.
	var sprite := _sprite()
	sprite.flip_h = true
	sprite.play_animation(_carded_sheet(Vector2(6, 11)), &"swing")
	assert_vector(sprite.offset).is_equal(Vector2(-4, 5))


func test_the_pivot_comes_back_when_a_gesture_is_stopped() -> void:
	var sprite := _sprite()
	sprite.play_animation(_carded_sheet(Vector2(6, 11)), &"swing")
	assert_vector(sprite.offset).is_not_equal(UnitSprite3D.STILL_PIVOT)
	sprite.stop_animation()
	assert_vector(sprite.offset).is_equal(UnitSprite3D.STILL_PIVOT)


func test_the_pivot_comes_back_when_a_gesture_runs_off_its_own_end() -> void:
	# The restore lives in _apply_state_texture, the one door, rather than beside stop_animation --
	# so a gesture nobody stopped gets it too. A restore written per call site passes the case above
	# and leaves a unit that finished swinging hanging from a card pivot forever.
	var sprite := _sprite()
	sprite.play_animation(_carded_sheet(Vector2(6, 11)), &"swing")
	sprite._process(2.0)   # past the 1s the fixture lasts
	assert_bool(sprite.is_animating()).is_false()
	assert_vector(sprite.offset).is_equal(UnitSprite3D.STILL_PIVOT)


func test_a_set_that_carries_no_stand_point_hangs_from_the_still_pivot() -> void:
	# Loud, not silent: the warning is the point. A set generated before #634 keeps working and says
	# it needs regenerating, rather than quietly reproducing the bug.
	var sprite := _sprite()
	sprite.play_animation(_sheet(false), &"swing")
	assert_bool(sprite.is_animating()).is_true()
	assert_vector(sprite.offset).is_equal(UnitSprite3D.STILL_PIVOT)


# --- helpers -------------------------------------------------------------------------------------


func _sheet(loops: bool) -> SpriteFrames:
	var sheet := SpriteFrames.new()
	sheet.remove_animation(&"default")
	sheet.add_animation(&"swing")
	sheet.set_animation_speed(&"swing", 60.0)
	sheet.set_animation_loop(&"swing", loops)
	for held: float in HELD:
		sheet.add_frame(&"swing", _texture(), held)
	return sheet


func _sprite() -> UnitSprite3D:
	var data := UnitData.new()
	data.display_name = "Probe"
	data.map_sprite = _texture()
	data.move_sprite = _texture()
	data.downed_sprite = _texture()
	return auto_free(UnitSprite3D.for_unit_data(data))


# A fresh texture per call: the cases compare IDENTITY, and a headless ImageTexture reads back its
# first image forever, so sharing one object would make every comparison trivially true.
func _texture() -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


# A sheet whose frames are a real card SIZE and that says where its character stands, which the
# 4x4 fixture above deliberately does not -- the two answer different questions and sharing one
# would make the no-measurement case untestable.
func _carded_sheet(ground: Vector2) -> SpriteFrames:
	var sheet := SpriteFrames.new()
	sheet.remove_animation(&"default")
	sheet.add_animation(&"swing")
	sheet.set_animation_speed(&"swing", 60.0)
	sheet.set_animation_loop(&"swing", false)
	for held: float in HELD:
		var img := Image.create(20, 12, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		sheet.add_frame(&"swing", ImageTexture.create_from_image(img), held)
	sheet.set_meta(&"ground_point", ground)
	return sheet
