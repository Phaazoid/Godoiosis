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
