# The aim's travel-order flash (#1057 part 2, #1054 rulings 19 and 27-28): a footprint tile flashes
# white on the step the attack reaches it, and with the photosensitivity setting on it holds still,
# graded by step instead.
#
# The five timings are FEEL values, so each case sets its own and puts the authored ones back -- the
# assertions are about the RULE (which tile is lit when, in what order) and never about a number the
# dev tunes. The node is built bare: levels() is the whole model and needs no tree.
extends GdUnitTestSuite

const PHOTO := PlayerSettings.Setting.PHOTOSENSITIVITY
const A := Vector2i(0, 0)
const B := Vector2i(0, 1)
const C := Vector2i(0, 2)

var _saved: Array[float] = []
var _flash: AimFlash2D


func before_test() -> void:
	_saved = [AimFlash2D.STEP_SECONDS, AimFlash2D.FLASH_SECONDS, AimFlash2D.REST_SECONDS,
		AimFlash2D.FLASH_PEAK, AimFlash2D.STILL_PEAK]
	AimFlash2D.STEP_SECONDS = 0.2
	AimFlash2D.FLASH_SECONDS = 0.3
	AimFlash2D.REST_SECONDS = 1.0
	AimFlash2D.FLASH_PEAK = 0.8
	AimFlash2D.STILL_PEAK = 0.6
	PlayerSettings.reset_for_test()
	_flash = AimFlash2D.new()


func after_test() -> void:
	AimFlash2D.STEP_SECONDS = _saved[0]
	AimFlash2D.FLASH_SECONDS = _saved[1]
	AimFlash2D.REST_SECONDS = _saved[2]
	AimFlash2D.FLASH_PEAK = _saved[3]
	AimFlash2D.STILL_PEAK = _saved[4]
	PlayerSettings.reset_for_test()
	_flash.free()


func _steps(timed: Dictionary) -> Dictionary[Vector2i, Array]:
	var out: Dictionary[Vector2i, Array] = {}
	for cell: Vector2i in timed:
		out[cell] = timed[cell]
	return out


# The top of a flash that began at step `step`.
func _peak_of(step: int) -> float:
	return step * AimFlash2D.STEP_SECONDS + AimFlash2D.FLASH_SECONDS * AimFlash2D.RISE_SHARE


func _levels_at(t: float) -> Dictionary[Vector2i, float]:
	_flash.clock = t
	return _flash.levels()


# ==============================================================================
#  The travel order
# ==============================================================================

# THE property: tiles light in step order. At the top of step 0's flash, step 1 has not begun.
func test_a_later_step_is_dark_while_the_first_flashes() -> void:
	_flash.show_steps(_steps({A: [0], B: [1]}))
	var at := _levels_at(_peak_of(0))
	assert_float(at[A]).is_equal(AimFlash2D.FLASH_PEAK)
	assert_float(at[B]).is_equal(0.0)


func test_each_step_peaks_on_its_own_turn() -> void:
	_flash.show_steps(_steps({A: [0], B: [1], C: [2]}))
	assert_float(_levels_at(_peak_of(1))[B]).is_equal(AimFlash2D.FLASH_PEAK)
	assert_float(_levels_at(_peak_of(2))[C]).is_equal(AimFlash2D.FLASH_PEAK)
	assert_float(_levels_at(_peak_of(2))[A]).is_equal(0.0)


# A TRUE AoE is all step 0, so the whole footprint lights at once (ruling 19).
func test_a_true_aoe_lights_every_tile_together() -> void:
	_flash.show_steps(_steps({A: [0], B: [0], C: [0]}))
	var at := _levels_at(_peak_of(0))
	for cell: Vector2i in at:
		assert_float(at[cell]).is_equal(AimFlash2D.FLASH_PEAK)


# A revisited tile flashes on EACH visit, and is dark between them.
func test_a_revisit_flashes_twice_per_loop() -> void:
	_flash.show_steps(_steps({A: [0, 3], B: [1]}))
	var between := AimFlash2D.FLASH_SECONDS + 0.01   # the first flash is over, the second not begun
	assert_bool(between < 3 * AimFlash2D.STEP_SECONDS).is_true()   # the case's own premise
	assert_float(_levels_at(_peak_of(0))[A]).is_equal(AimFlash2D.FLASH_PEAK)
	assert_float(_levels_at(between)[A]).is_equal(0.0)
	assert_float(_levels_at(_peak_of(3))[A]).is_equal(AimFlash2D.FLASH_PEAK)


# One loop is the travel, the last flash and the rest -- then it plays again from the top.
func test_the_loop_repeats() -> void:
	_flash.show_steps(_steps({A: [0], B: [2]}))
	var loop := AimFlash2D.loop_seconds(2)
	assert_float(_levels_at(_peak_of(2) + loop)[B]).is_equal(AimFlash2D.FLASH_PEAK)
	assert_float(_levels_at(loop - 0.01)[A]).is_equal(0.0)   # the rest: nothing lit
	assert_float(_levels_at(loop - 0.01)[B]).is_equal(0.0)


# The same steps keep the running loop; new ones start it again from the top.
func test_the_same_steps_keep_the_clock_and_new_ones_restart_it() -> void:
	_flash.show_steps(_steps({A: [0], B: [1]}))
	_flash.clock = 0.5
	_flash.show_steps(_steps({A: [0], B: [1]}))
	assert_float(_flash.clock).is_equal(0.5)
	_flash.show_steps(_steps({A: [0]}))
	assert_float(_flash.clock).is_equal(0.0)


# ==============================================================================
#  Photosensitivity (#217): nothing moves, and the order is graded in white
# ==============================================================================

func test_with_photosensitivity_on_nothing_moves() -> void:
	PlayerSettings.set_on(PHOTO, true)
	_flash.show_steps(_steps({A: [0], B: [1], C: [2]}))
	var early := _levels_at(_peak_of(0))
	var late := _levels_at(_peak_of(2))
	assert_that(late).is_equal(early)


func test_the_still_is_graded_palest_first_and_plain_last() -> void:
	PlayerSettings.set_on(PHOTO, true)
	_flash.show_steps(_steps({A: [0], B: [1], C: [2]}))
	var still := _flash.levels()
	assert_float(still[A]).is_equal(AimFlash2D.STILL_PEAK)
	assert_float(still[A]).is_greater(still[B])
	assert_float(still[B]).is_greater(still[C])
	assert_float(still[C]).is_equal(0.0)


# A revisit is graded by its FIRST visit, the order it first appears in.
func test_a_revisit_is_graded_by_its_first_visit() -> void:
	PlayerSettings.set_on(PHOTO, true)
	_flash.show_steps(_steps({A: [0, 2], B: [1], C: [2]}))
	assert_float(_flash.levels()[A]).is_equal(AimFlash2D.STILL_PEAK)


# A true AoE has no order to show, so it holds today's plain footprint.
func test_a_true_aoe_holds_plain_with_photosensitivity_on() -> void:
	PlayerSettings.set_on(PHOTO, true)
	_flash.show_steps(_steps({A: [0], B: [0]}))
	for cell: Vector2i in _flash.levels():
		assert_float(_flash.levels()[cell]).is_equal(0.0)


# ==============================================================================
#  The diorama's colour
# ==============================================================================

# tint() whitens the LIVE footprint colour and keeps its alpha: nothing at 0, white at 1.
func test_tint_whitens_the_base_and_keeps_its_alpha() -> void:
	var base := Color(1, 0.5, 0, 0.7)
	assert_that(AimFlash2D.tint(base, 0.0)).is_equal(base)
	assert_that(AimFlash2D.tint(base, 1.0)).is_equal(Color(1, 1, 1, 0.7))
