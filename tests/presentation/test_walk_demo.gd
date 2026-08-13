# The stage-2 walk demo (#210): the DEMO-ONLY BFS pinned pure (the height-step rule,
# blocking, routing around a blocker), the spawn-and-walk wire through the real scene,
# and the facing seam's one property — the SAME world step flips opposite when the
# camera stands on the opposite side (camera-relativity, not an art convention).
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/LookDev/LookDev.tscn"
const UnitWalkDemo := preload("res://Scenes/LookDev/unit_walk_demo.gd")

var _scene: Node3D


func before_test() -> void:
	_scene = (load(SCENE_PATH) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(_scene)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


# --- The demo BFS, pure -----------------------------------------------------------

var _stair_tops: Dictionary[Vector2i, int] = {
	Vector2i(0, 0): 1, Vector2i(1, 0): 2, Vector2i(2, 0): 3,
}


func test_bfs_climbs_a_legal_stair() -> void:
	var path := UnitWalkDemo.find_path(
			Vector3i(0, 0, 0), Vector3i(2, 2, 0), _stair_tops, {})
	assert_int(path.size()).is_equal(3)
	assert_that(path[2]).is_equal(Vector3i(2, 2, 0))


func test_bfs_refuses_a_two_high_step() -> void:
	var cliff: Dictionary[Vector2i, int] = {Vector2i(0, 0): 1, Vector2i(1, 0): 3}
	var path := UnitWalkDemo.find_path(Vector3i(0, 0, 0), Vector3i(1, 2, 0), cliff, {})
	assert_int(path.size()).is_equal(0)


func test_bfs_routes_around_a_blocking_unit() -> void:
	var flat: Dictionary[Vector2i, int] = {}
	for x in 3:
		for z in 2:
			flat[Vector2i(x, z)] = 1
	var blocked: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
	var path := UnitWalkDemo.find_path(Vector3i(0, 0, 0), Vector3i(2, 0, 0), flat, blocked)
	assert_int(path.size()).is_equal(5)  # the detour through the z=1 row


func test_bfs_refuses_an_occupied_destination() -> void:
	var flat: Dictionary[Vector2i, int] = {Vector2i(0, 0): 1, Vector2i(1, 0): 1}
	var blocked: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
	var path := UnitWalkDemo.find_path(Vector3i(0, 0, 0), Vector3i(1, 0, 0), flat, blocked)
	assert_int(path.size()).is_equal(0)


# --- The wire: spawn, select, walk in the real scene -------------------------------

func test_cast_spawns_under_the_units_node() -> void:
	var demo := _scene.get_node("WalkDemo")
	var spawned: Array[UnitSprite3D] = demo.units()
	assert_bool(spawned.size() >= 4).is_true()
	for unit in spawned:
		assert_bool(unit.cell != BoardSpace.NO_CELL).is_true()
		assert_object(unit.texture).is_not_null()


func test_order_walk_moves_a_unit_to_the_target() -> void:
	var demo := _scene.get_node("WalkDemo")
	var unit: UnitSprite3D = demo.units()[0]  # spawns on the plain
	unit.move_speed = 1000.0
	demo._select(unit)
	var target := Vector3i(7, 0, 8)  # open plain, two cells east of the first spawn
	var monitor := assert_signal(unit)
	demo.order_walk(target)
	await monitor.is_emitted("walk_finished")
	assert_that(unit.cell).is_equal(target)
	assert_that(unit.position).is_equal(BoardSpace.standing_point(target))


func test_facing_flip_is_camera_relative() -> void:
	var rig := _scene.get_node("CameraRig") as Node3D
	var demo := _scene.get_node("WalkDemo")
	var unit: UnitSprite3D = demo.units()[0]
	unit.move_speed = 1000.0

	rig.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	rig._target_yaw_degrees = 0.0
	await await_idle_frame()
	var start := unit.cell
	var east := start + Vector3i(1, 0, 0)
	var monitor := assert_signal(unit)
	unit.walk_path([start, east])
	await monitor.is_emitted("walk_finished")
	var flip_at_yaw_0 := unit.flip_h

	rig.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	rig._target_yaw_degrees = 180.0
	await await_idle_frame()
	var monitor_back := assert_signal(unit)
	unit.walk_path([east, east + Vector3i(1, 0, 0)])  # the same world direction again
	await monitor_back.is_emitted("walk_finished")
	assert_bool(unit.flip_h).is_not_equal(flip_at_yaw_0)
