# Guard for CameraController._process's glide: HEADLESS, THE CAMERA LANDS -- it never glides.
# Third member of the watched-pacing family (Pacing.beat returns in zero frames, pan_to snaps);
# until 2026-08-26 the _process lerp was the one glide WITHOUT the escape, and the SPACE spawn
# case in tests/dev/test_dev_tree.gd was red on CI only -- it sampled the hover cell off a
# mid-glide camera, so its target rode frame timing. A headless test reading any camera-derived
# value needs the camera settled by the frame after a move is asked for, which is what this pins.
#
# Asserts NOTHING about move_speed or where the camera goes (both tuned; the clamp owns "where")
# -- only that one frame suffices, which no tuning can move. test_pacing.gd's shape.
#
# Falsified: revert the headless branch to the bare lerp and this goes red -- one small-delta
# frame covers a fraction of the hop below.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func test_center_on_position_lands_within_one_headless_frame() -> void:
	# The premise, test_pacing's spelling: everything below is only true because nobody is watching.
	assert_str(DisplayServer.get_name()).is_equal("headless")

	var cam: CameraController = game.camera_controller
	# A hop the clamp will trim but cannot collapse -- the board spans ~1000px world. Whatever
	# survives the clamp is read back off target_position, so no bound is pinned here.
	cam.center_on_position(cam.global_position + Vector2(4000.0, 4000.0))
	assert_bool(cam.global_position.distance_to(cam.target_position) > 100.0) \
		.override_failure_message(
			"precondition: the clamp collapsed the hop -- nothing below proves anything") \
		.is_true()

	await await_idle_frame()
	assert_bool(cam.global_position.is_equal_approx(cam.target_position)) \
		.override_failure_message(
			("the camera is mid-glide in a headless run (at %s, target %s) -- every test sampling "
				+ "a camera-derived value is reading frame timing")
				% [str(cam.global_position), str(cam.target_position)]) \
		.is_true()
