# The WIRE from the board to the rig's ground probe (#1280). The re-seat itself is pinned next door in
# test_camera_rig.gd against a flat test plane; what this hunts is #103's shape -- a rig that re-seats
# correctly and a board that answers correctly, with nothing handing one to the other.
#
# Content razor: a real mission is LOADED to exercise the real path, and the expected height is the
# board picker's own answer for the centre of the screen, never a number about Prolog.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const PROLOG := "res://Scenarios/missions/Prolog.tres"

var _scene: Node3D
var _rig: CameraRig3D
var _camera3d: Camera3D


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_rig = _scene.get_node("CameraRig") as CameraRig3D
	_camera3d = _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	_scene.load_mission(PROLOG)
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)   # the mission door arms #182 dialog; end it or it leaks
	get_tree().root.remove_child(_scene)
	_scene.free()


func test_an_orbit_press_seats_the_pivot_on_the_board_under_the_centre_of_the_screen() -> void:
	# Lift the pivot clear of every column first, so where it ends up is the probe's answer and only
	# that. The camera rides up with it, which keeps the centre of the screen on the board.
	_rig.hold_at(_rig.position + Vector3(0.0, 5.0, 0.0))
	var centre: Vector2 = _camera3d.get_viewport().get_visible_rect().size * 0.5
	var tops: Dictionary[Vector2i, int] = _scene._tops
	var cell := BoardPicker.pick_at(_camera3d, centre, tops, Rect2i())
	assert_bool(cell != BoardSpace.NO_CELL).override_failure_message(
			"precondition: the centre of the opening shot is off the board, so this proves nothing").is_true()
	var lens_before := _camera3d.global_transform.origin

	# The board takes the player's input away while it is locked, and a re-seat past the zoom ceiling
	# is refused; this case is about the probe, so both are set aside by hand (the ceiling refusal is
	# pinned next door). The press is the rig's own handler, as the player's would be.
	_rig.manual_input_enabled = true
	_rig.max_distance = 1000.0
	var press := InputEventMouseButton.new()
	press.button_index = _rig.orbit_button
	press.pressed = true
	_rig._unhandled_input(press)

	assert_float(_rig.position.y).override_failure_message(
			"the pivot stayed %.2f in the air: nothing handed the rig the board's ground"
			% (_rig.position.y - BoardSpace.surface_y(cell.y))) \
		.is_equal_approx(BoardSpace.surface_y(cell.y), 0.001)
	assert_vector(_camera3d.global_transform.origin).override_failure_message(
			"seating the pivot moved the camera").is_equal_approx(lens_before, Vector3(0.001, 0.001, 0.001))
