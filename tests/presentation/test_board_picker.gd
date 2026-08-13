# BoardPicker (#205): pure ray-walk cases against synthetic column tops (the parallax
# skip, the cliff-side hit, misses), then the seam proven where it lives — the look-dev
# scene, via the unproject round-trip at all four yaw snaps, plus the occlusion case.
# Scene cases assert PROPERTIES (the blocker wins, the aimed cell comes back), never
# tuned camera values — pitch/FOV/zoom stay the dev's knobs and must not redden this.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/LookDev/LookDev.tscn"

# A short column, a 3-tall tower, a short column, all in row z=0.
var _tower_tops: Dictionary[Vector2i, int] = {
	Vector2i(0, 0): 1, Vector2i(1, 0): 3, Vector2i(2, 0): 1,
}


# --- Pure cases (no scene, authored rays) -------------------------------------

func test_straight_down_hits_the_top_face() -> void:
	var cell := BoardPicker.pick_cell(Vector3(0.5, 10.0, 0.5), Vector3.DOWN, _tower_tops)
	assert_that(cell).is_equal(Vector3i(0, 0, 0))


func test_parallax_ray_skips_the_short_column_and_hits_the_tower() -> void:
	# Passes 2.75+ units above the short column, crosses the tower's top plane inside it.
	var cell := BoardPicker.pick_cell(Vector3(-2.5, 5.0, 0.5), Vector3(4.0, -2.0, 0.0), _tower_tops)
	assert_that(cell).is_equal(Vector3i(1, 2, 0))


func test_cliff_side_hit_returns_the_column_top_cell() -> void:
	# Enters the tower's footprint at y 2.2 — below its top at 3 — striking the wall.
	var cell := BoardPicker.pick_cell(Vector3(-0.5, 2.5, 0.5), Vector3(1.0, -0.2, 0.0), _tower_tops)
	assert_that(cell).is_equal(Vector3i(1, 2, 0))


func test_shallow_approach_from_outside_the_board_hits_the_first_column() -> void:
	var cell := BoardPicker.pick_cell(Vector3(-3.5, 1.5, 0.5), Vector3(1.0, -0.15, 0.0), _tower_tops)
	assert_that(cell).is_equal(Vector3i(0, 0, 0))


func test_level_ray_above_everything_misses() -> void:
	var cell := BoardPicker.pick_cell(Vector3(-1.0, 5.0, 0.5), Vector3(1.0, 0.0, 0.0), _tower_tops)
	assert_that(cell).is_equal(BoardSpace.NO_CELL)


func test_descending_ray_beyond_the_board_walks_off_and_misses() -> void:
	var cell := BoardPicker.pick_cell(Vector3(5.0, 2.0, 0.5), Vector3(1.0, -1.0, 0.0), _tower_tops)
	assert_that(cell).is_equal(BoardSpace.NO_CELL)


func test_vertical_ray_over_an_empty_column_misses() -> void:
	var cell := BoardPicker.pick_cell(Vector3(10.5, 5.0, 10.5), Vector3.DOWN, _tower_tops)
	assert_that(cell).is_equal(BoardSpace.NO_CELL)


# --- The seam where it lives: the look-dev scene -------------------------------

var _scene: Node3D


func before_test() -> void:
	_scene = (load(SCENE_PATH) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func test_column_tops_read_the_painted_board() -> void:
	var board := _scene.get_node("Board") as GridMap
	var tops := BoardPicker.column_tops_from(board)
	assert_int(tops[Vector2i(0, 0)]).is_equal(1)   # plain
	assert_int(tops[Vector2i(8, 3)]).is_equal(3)   # plateau
	assert_int(tops[Vector2i(3, 10)]).is_equal(2)  # stone platform
	assert_int(tops[Vector2i(5, 3)]).is_equal(2)   # ramp counts as a full block (stage-1 approximation)


func test_unproject_round_trip_finds_the_cell_at_every_yaw_snap() -> void:
	var board := _scene.get_node("Board") as GridMap
	var rig := _scene.get_node("CameraRig") as Node3D
	var camera := _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	var tops := BoardPicker.column_tops_from(board)
	# A plain cell clear of the hill, and the plateau's own top: both visible from all sides.
	var cells: Array[Vector3i] = [Vector3i(2, 0, 6), Vector3i(8, 2, 3)]
	for yaw: float in [0.0, 90.0, 180.0, 270.0]:
		rig.rotation_degrees = Vector3(0.0, yaw, 0.0)
		rig._target_yaw_degrees = yaw  # keep the rig's smoothing from fighting the pose
		await await_idle_frame()
		for cell in cells:
			var aim := BoardSpace.standing_point(cell) + Vector3(0.0, -0.02, 0.0)
			var screen := camera.unproject_position(aim)
			var picked := BoardPicker.pick_cell(
					camera.project_ray_origin(screen), camera.project_ray_normal(screen), tops)
			assert_that(picked).is_equal(cell)


func test_occluded_cell_yields_the_blocker_not_the_hidden_cell() -> void:
	# From the default camera (south, pitched down), ground cell (8, 0, 0) hides behind
	# the 3-tall hill. Aiming at its standing point must pick a hill cell instead —
	# asserted as a property (the blocker wins), not an exact cell, so camera tuning
	# can't redden it.
	var board := _scene.get_node("Board") as GridMap
	var camera := _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	var tops := BoardPicker.column_tops_from(board)
	var hidden := Vector3i(8, 0, 0)
	var screen := camera.unproject_position(BoardSpace.standing_point(hidden))
	var picked := BoardPicker.pick_cell(
			camera.project_ray_origin(screen), camera.project_ray_normal(screen), tops)
	assert_that(picked).is_not_equal(hidden)
	assert_that(picked).is_not_equal(BoardSpace.NO_CELL)
	assert_bool(picked.y >= 1).is_true()                      # a raised cell took the ray
	assert_bool(picked.x >= 6 and picked.x <= 10).is_true()   # inside the hill's footprint
	assert_bool(picked.z >= 1 and picked.z <= 5).is_true()
