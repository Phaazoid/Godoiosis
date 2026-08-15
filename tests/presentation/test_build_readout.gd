# The dev overlay says which checkout is on screen (#295).
#
# A WIRE suite, the same shape as test_report_view_stamp.gd and for the same reason: Checkout can
# resolve perfectly and the label can exist, while nothing puts one in the other. Delete the
# _show_checkout() call from battle3d._ready and every other suite in the tree still passes.
#
# The REAL scene, so what is asserted is the node that actually ships -- a Label authored into
# Battle3D.tscn under the UI CanvasLayer, not one this suite builds. That CanvasLayer draws above
# the 2D game's SubViewportContainer in every hosting view, which is why the readout survives F4
# into FLAT_2D; whether it is legible at that position is the dev's, by playing.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"

var _scene: Node3D


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func test_the_overlay_carries_the_checkout_the_one_reader_named() -> void:
	# Interpolated off Checkout.describe(), never a pinned branch or SHA: the branch and the SHA
	# are content and change every commit, while "the label shows what the one reader answered" is
	# the invariant. A second git read living in battle3d.gd is the Law #4 failure this forbids.
	assert_bool(DevTools.enabled()).is_true()   # the gate; without it the case passes on ""
	var expected := Checkout.describe()
	assert_str(expected).is_not_equal("")

	var label: Label = _scene.get_node("UI/Checkout")
	assert_str(label.text).is_equal(expected)
	assert_bool(label.visible).is_true()


func test_the_readout_is_a_label_of_its_own_and_not_a_field_of_the_help_line() -> void:
	# Structural, and load-bearing twice over: the help line is rewritten wholesale in demo_mode
	# and rebuilt on every binding change, so a checkout carried inside it would vanish in the
	# first case and have to be re-appended in the second.
	var help: Label = _scene.get_node("UI/Help")
	var checkout: Label = _scene.get_node("UI/Checkout")

	assert_object(checkout).is_not_same(help)
	assert_str(help.text).not_contains(Checkout.describe())
	assert_str(help.text).contains("Battle3D")   # the help line is still built, not displaced


func test_a_demo_mode_launch_still_says_which_build_it_is() -> void:
	# demo_mode replaces the help text and hides the 2D game entirely; the checkout is orthogonal
	# to both, and a watch-only build is exactly where "which build is this?" is hardest to answer
	# by any other means.
	get_tree().root.remove_child(_scene)
	_scene.free()

	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	_scene.demo_mode = true
	get_tree().root.add_child(_scene)
	await await_idle_frame()

	var label: Label = _scene.get_node("UI/Checkout")
	assert_str(label.text).is_equal(Checkout.describe())
	assert_bool(label.visible).is_true()
