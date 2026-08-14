# The 3D camera during play (#176 stage 4d): does it follow the action, does it frame
# the board it loaded, and does it refuse the player at the right moments.
#
# The headline this pins: before 4d nothing moved the 3D rig during a battle at all —
# AIController panned the HIDDEN 2D camera and awaited the full beat, so an enemy turn
# in 3D was ~1.3s of dead air per squad in front of a motionless frame.
#
# The follow is a MIRROR of the 2D camera (which already knows where the action is),
# gated on ai_locked. Two cases below decide that gate, and both are written to fail
# loudly if the gate is widened to _board_locked_for_player(): that predicate also
# covers MENU, where Mission Select opts out of the modal lock.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"
const LEVEL_1 := "res://Scenarios/missions/Level_1.tres"

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


func _cam() -> CameraController:
	return _game.camera_controller


func _player_unit() -> Unit:
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit != null and unit.get_faction() == Team.Faction.PLAYER:
			return unit
	return null


# The rig's own settle: process_frame resumes coroutines BEFORE node _process, so one
# frame is stale.
func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


# --- Following the action ----------------------------------------------------------

func test_the_3d_camera_follows_the_ai_camera() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	var away := _rig.position
	_cam().set_ai_locked(true)
	await _cam().pan_to(unit)   # headless: lands on the destination and hands to follow
	await _settle()

	# The rig sits over the unit the 2D camera went to, in the 3D metric.
	var expected := BoardSpace.of_pixels(_cam().global_position, _rig.position.y)
	assert_that(_rig.position).override_failure_message(
			"the 3D camera never followed the AI's pan").is_equal(expected)
	assert_bool(_rig.position.distance_to(away) > 1.0) \
		.override_failure_message("the rig was already there; the case proves nothing").is_true()
	_cam().set_ai_locked(false)


func test_hovering_does_not_drag_the_3d_camera() -> void:
	# The naive-mirror hazard. Pointing snaps the hidden 2D camera every time (it is what
	# parks the hover card), so a mirror that ran outside an AI turn would jerk the whole
	# diorama on every mouse move.
	var unit := _player_unit()
	var before := _rig.position
	var cell: Vector2i = unit.movement.cell
	var motion := InputEventMouseMotion.new()
	var screen := _camera3d.unproject_position(BoardSpace.standing_point(BoardSpace.of_flat(cell)))
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _settle()

	# The 2D camera DID move (non-vacuous: the snap is what the hover card rides on)...
	assert_that(_scene._pointer_cell).is_equal(BoardSpace.of_flat(cell))
	# ...and the 3D did not.
	assert_that(_rig.position).override_failure_message(
			"a hover dragged the 3D camera — the mirror is not gated on ai_locked").is_equal(before)


func test_opening_a_menu_does_not_yank_the_3d_camera() -> void:
	# The case that decides the gate. MissionSelectScreen opts OUT of the modal lock, so
	# _board_locked_for_player() is true here while the game runs on — mirroring on that
	# predicate would snap the rig to wherever the 2D camera happens to be parked.
	var before := _rig.position
	_game.game_state = _game.GameState.MENU
	assert_bool(_game._board_locked_for_player()).is_true()
	assert_bool(_cam().ai_locked).is_false()
	_cam().snap_to_position(Vector2(-4000.0, -4000.0))
	await _settle()

	assert_that(_rig.position).override_failure_message(
			"the menu yanked the rig — the mirror is gated on the wrong predicate").is_equal(before)


func test_a_locked_board_refuses_the_players_camera_but_keeps_the_rig_running() -> void:
	_game.game_state = _game.GameState.AI_TURN
	await _settle()
	assert_bool(_rig.manual_input_enabled).is_false()
	assert_bool(_rig.is_processing()).override_failure_message(
			"the rig was frozen, not merely input-gated — the mirror could not drive it").is_true()

	_game.game_state = _game.GameState.IDLE
	await _settle()
	assert_bool(_rig.manual_input_enabled).is_true()


func test_a_menu_leaves_the_pointer_alone() -> void:
	_game.game_state = _game.GameState.MENU
	var unit := _player_unit()
	var screen := _camera3d.unproject_position(
			BoardSpace.standing_point(BoardSpace.of_flat(unit.movement.cell)))
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _settle()
	assert_that(_scene._pointer_cell).override_failure_message(
			"the bracket painted over a board the click handler would refuse").is_equal(BoardSpace.NO_CELL)


# --- Framing a real mission --------------------------------------------------------

func test_both_authored_missions_open_with_the_whole_board_in_frame() -> void:
	# Before 4d this was impossible: a board span in CELLS went to set_zoom, which wants a
	# camera DISTANCE, and the clamp ate it — Prolog needed ~82 and got 24.
	for path in [PROLOG, LEVEL_1]:
		_scene.load_mission(path)
		await _settle()
		var rect: Rect2i = _game.grid.get_used_rect()
		var corners: Array[Vector2i] = [
			rect.position,
			rect.position + Vector2i(rect.size.x - 1, 0),
			rect.position + Vector2i(0, rect.size.y - 1),
			rect.position + rect.size - Vector2i.ONE,
		]
		for corner in corners:
			var point := BoardSpace.standing_point(BoardSpace.of_flat(corner))
			assert_bool(_camera3d.is_position_in_frustum(point)).override_failure_message(
					"%s: board corner %s is off-camera at load" % [path, corner]).is_true()


func test_space_recentres_the_diorama_on_the_pointer() -> void:
	var unit := _player_unit()
	var cell: Vector2i = unit.movement.cell
	_scene._update_pointer(_camera3d.unproject_position(
			BoardSpace.standing_point(BoardSpace.of_flat(cell))))
	_rig.position = Vector3(_rig.position.x + 12.0, _rig.position.y, _rig.position.z + 12.0)
	var before := _rig.position

	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	_scene._unhandled_input(space)

	var point := BoardSpace.standing_point(_scene._pointer_cell)
	assert_that(_rig.position).is_equal(Vector3(point.x, before.y, point.z))
	assert_bool(_rig.position.distance_to(before) > 1.0).is_true()
