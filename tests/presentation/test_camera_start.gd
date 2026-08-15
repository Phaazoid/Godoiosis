# The AUTHORED camera start (#234): does a board's own opening pose survive the round trip and
# actually reach the live rig, and does a board that authors none still open on its squad.
#
# The WIRE is the whole point here. pose() itself is pinned next door in test_camera_rig.gd; what
# these cases hunt is #103's shape — both ends correct while nothing connects them — across four
# hops: capture_scenario writes it, apply_scenario reads it back BEFORE board_loaded fires,
# battle3d's fit_camera prefers it over the derivation, and the rig lands on it.
#
# Round-tripped IN MEMORY via capture_scenario/apply_scenario, the #87 shape. Writing a test .tres
# into Scenarios/ would be picked up by Mission Select and by #9's folder scan.
#
# Content razor: a real mission is LOADED to exercise the real path, and nothing is asserted about
# what it contains. Every expected number here is one this file supplied.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"

# Deliberately off-detent: free orbit is the contract (#176 stage 4d), so an authored 37 degrees
# must survive the round trip rather than being tidied square somewhere along it.
const AUTHORED_YAW := 37.0
const AUTHORED_DISTANCE := 15.5

var _scene: Node3D
var _game: Node2D
var _rig: Node3D
var _camera3d: Camera3D


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_game = _scene.game
	_rig = _scene.get_node("CameraRig") as Node3D
	_camera3d = _scene.get_node("CameraRig/Pitch/Camera") as Camera3D
	_scene.load_mission(PROLOG)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func _manager() -> ScenarioManager:
	return _game.scenario_manager


# An aim well inside any board, so the pan clamp is not what this case is measuring.
func _authored_pose(aim := Vector3(12.0, 1.0, 9.0)) -> CameraPose:
	var pose := CameraPose.new()
	pose.aim = aim
	pose.yaw_degrees = AUTHORED_YAW
	pose.distance = AUTHORED_DISTANCE
	return pose


# Capture the live board with an authored start on it, then load it straight back — the real
# writer and the real reader, no file involved.
func _round_trip(start: CameraPose) -> void:
	_manager().current_camera_start = start
	var captured := _manager().capture_scenario("test_camera_start")
	_manager().apply_scenario(captured)
	await await_idle_frame()


# --- The wire ----------------------------------------------------------------------

func test_an_authored_start_survives_the_round_trip_and_reaches_the_rig() -> void:
	await _round_trip(_authored_pose())

	assert_that(_rig.position).override_failure_message(
			"the authored aim never reached the rig").is_equal(Vector3(12.0, 1.0, 9.0))
	assert_float(_rig.rotation_degrees.y).override_failure_message(
			"the authored yaw was lost or squared up somewhere in the round trip" \
			).is_equal_approx(AUTHORED_YAW, 0.001)
	assert_float(_camera3d.position.z).is_equal_approx(AUTHORED_DISTANCE, 0.001)


func test_capture_scenario_writes_the_authored_start_onto_the_board() -> void:
	# The persistence hop on its own: without this the pose lives only in the session and every
	# reload of the mission silently reverts to the derivation.
	_manager().current_camera_start = _authored_pose()
	var captured := _manager().capture_scenario("test_camera_start")

	assert_object(captured.camera_start).override_failure_message(
			"capture_scenario dropped the camera start — it would never persist").is_not_null()
	assert_float(captured.camera_start.yaw_degrees).is_equal_approx(AUTHORED_YAW, 0.001)


func test_the_start_is_readable_the_moment_board_loaded_fires() -> void:
	# ORDERING, and it is the reason this case exists: battle3d frames off board_loaded, so a
	# current_camera_start assigned AFTER the emit is a pose that arrives one board too late. A
	# case that only checked the settled end state would pass against exactly that bug.
	_manager().current_camera_start = _authored_pose()
	var captured := _manager().capture_scenario("test_camera_start")
	_manager().current_camera_start = null

	var seen_at_emit: Array[CameraPose] = []
	var probe := func() -> void: seen_at_emit.append(_manager().current_camera_start)
	_manager().board_loaded.connect(probe)
	_manager().apply_scenario(captured)
	_manager().board_loaded.disconnect(probe)
	await await_idle_frame()   # let the rebuild's queue_free'd units actually go

	assert_int(seen_at_emit.size()).override_failure_message("board_loaded never fired").is_equal(1)
	assert_object(seen_at_emit[0]).override_failure_message(
			"board_loaded fired before the camera start was set — battle3d reads it from there" \
			).is_not_null()


# --- The derivation is still the fallback ------------------------------------------

func test_a_board_that_authors_nothing_still_opens_on_its_own_units() -> void:
	# Law #4's declared other half. Asserted as the PROPERTY the derivation exists to give —
	# every player unit on camera — never as a distance or a cell, both of which are content.
	_manager().current_camera_start = null
	var captured := _manager().capture_scenario("test_camera_start")
	assert_object(captured.camera_start).override_failure_message(
			"an unauthored board captured a camera start anyway").is_null()

	_manager().apply_scenario(captured)
	await await_idle_frame()

	var seen := 0
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit == null or unit.get_faction() != Team.Faction.PLAYER:
			continue
		seen += 1
		var at: Vector3 = BoardSpace.surface_point(unit.movement.cell, _game.board_heights)
		assert_bool(_camera3d.is_position_in_frustum(at)).override_failure_message(
				"the derived opening shot left a player unit off-camera").is_true()
	assert_int(seen).override_failure_message(
			"no player units on the loaded board — this case proved nothing").is_greater(0)


func test_clearing_the_board_forgets_the_last_missions_start() -> void:
	# spawn_sandbox() lands in clear_board with no ScenarioData, so without the zeroing it would
	# open on whatever the last mission authored — the same trap #253 and #150 each had to close.
	_manager().current_camera_start = _authored_pose()
	_manager().clear_board()
	await await_idle_frame()   # let the cleared units actually go

	assert_object(_manager().current_camera_start).override_failure_message(
			"a cleared board still wears the last mission's camera start").is_null()


# --- Capture, the authoring half ---------------------------------------------------

func test_capture_reads_the_live_rig_rather_than_where_it_is_heading() -> void:
	# You are storing the shot you are LOOKING at. Set the targets away from the live values and
	# the captured pose must follow the live ones — the same rule _describe_view (#240) follows.
	_rig.position = Vector3(7.0, 1.0, 5.0)
	_rig.rotation_degrees.y = 20.0
	_camera3d.position.z = 11.0
	_rig._target_yaw_degrees = 200.0
	_rig._target_distance = 22.0

	var captured: CameraPose = _scene.capture_camera_start()

	assert_that(captured.aim).is_equal(Vector3(7.0, 1.0, 5.0))
	assert_float(captured.yaw_degrees).override_failure_message(
			"capture stored the yaw the smoothing was heading toward, not the one on screen" \
			).is_equal_approx(20.0, 0.001)
	assert_float(captured.distance).override_failure_message(
			"capture stored the target zoom, not the live one").is_equal_approx(11.0, 0.001)


func test_a_captured_pose_reloads_as_the_shot_it_was_captured_from() -> void:
	# The authoring loop end to end: fly the camera, press Capture, save, load, and be back where
	# you were. This is the one case that would catch a capture and an apply that each work but
	# disagree about what the three numbers MEAN.
	_rig.position = Vector3(9.0, 1.0, 6.0)
	_rig.rotation_degrees.y = 63.0
	_camera3d.position.z = 13.0

	await _round_trip(_scene.capture_camera_start())

	assert_that(_rig.position).is_equal(Vector3(9.0, 1.0, 6.0))
	assert_float(_rig.rotation_degrees.y).is_equal_approx(63.0, 0.001)
	assert_float(_camera3d.position.z).is_equal_approx(13.0, 0.001)
