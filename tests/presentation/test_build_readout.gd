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

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")

var _scene: Node3D


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var packed := SCENE
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


# The readout is its OWN label, and #816 is what that bought. It was a field-of-the-help-line
# argument until then -- that line was rebuilt from live bindings and rewritten wholesale in
# demo_mode, so a checkout carried inside it would have vanished in the first case and needed
# re-appending in the second. The line is deleted now and this survived it untouched, which is the
# stronger form of the same claim: it answers to nothing but its own writer.
func test_the_readout_is_a_label_of_its_own() -> void:
	var checkout: Label = _scene.get_node("UI/Checkout")
	assert_object(checkout).is_not_null()
	assert_bool(_scene.has_node("UI/Help")).override_failure_message(
		"the top-bar help line came back -- #816 deleted it, its bindings live in Controls").is_false()


func test_a_demo_mode_launch_still_says_which_build_it_is() -> void:
	# demo_mode hides the 2D game entirely; the checkout is orthogonal to that, and a watch-only
	# build is exactly where "which build is this?" is hardest to answer by any other means.
	get_tree().root.remove_child(_scene)
	_scene.free()

	var packed := SCENE
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	_scene.demo_mode = true
	get_tree().root.add_child(_scene)
	await await_idle_frame()

	var label: Label = _scene.get_node("UI/Checkout")
	assert_str(label.text).is_equal(Checkout.describe())
	assert_bool(label.visible).is_true()
