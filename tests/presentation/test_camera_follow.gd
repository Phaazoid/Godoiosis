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
	_cam().set_ai_locked(true)
	await _cam().pan_to(unit)   # headless: lands on the destination and hands to follow
	await _settle()
	# Where the 2D camera went, in the 3D metric.
	var expected := BoardSpace.of_pixels(_cam().global_position, _rig.position.y)

	# Now prove the mirror DRIVES the rig rather than that it happened to be parked there.
	# The opening shot sits over the player's squad, i.e. over this very unit, so the rig
	# has to be shoved off first — to a corner of its own pan limit, which the clamp will
	# leave alone.
	_rig.position = Vector3(_rig.pan_limit.position.x, _rig.position.y, _rig.pan_limit.position.y)
	assert_bool(_rig.position.distance_to(expected) > 1.0) \
		.override_failure_message("the rig was already there; the case proves nothing").is_true()
	await _settle()

	assert_that(_rig.position).override_failure_message(
			"the 3D camera never followed the AI's pan").is_equal(expected)
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

func test_both_authored_missions_open_on_the_players_own_squad() -> void:
	# REPLACES "opens with the whole board in frame" (dev feel-check 2026-08-14: fitting all
	# 64x40 of Prolog was too far out to play from). The board is now what the view is
	# BOUNDED by — see the case below, which keeps that half honest — and the opening shot
	# frames the units you actually command.
	for path in [PROLOG, LEVEL_1]:
		_scene.load_mission(path)
		await _settle()
		var seen := 0
		var lo := Vector2.INF
		var hi := -Vector2.INF
		for child in _game.units_root.get_children():
			var unit := child as Unit
			if unit == null or unit.get_faction() != Team.Faction.PLAYER:
				continue
			seen += 1
			lo = lo.min(Vector2(unit.movement.cell))
			hi = hi.max(Vector2(unit.movement.cell))
			var point := BoardSpace.standing_point(BoardSpace.of_flat(unit.movement.cell))
			assert_bool(_camera3d.is_position_in_frustum(point)).override_failure_message(
					"%s: player unit at %s is off-camera at load" % [path, unit.movement.cell]).is_true()
		assert_int(seen).override_failure_message(
				"%s spawns no player units; the case proves nothing" % path).is_greater(0)

		# The rig is AIMED at them, not merely wide enough to contain them. Measured: both
		# authored squads start near enough to the middle that the frustum loop above passes
		# against a window centred on the BOARD — so without this clause the "opens on your
		# squad" claim would be pinned by nothing.
		var board: AABB = _scene._board_volume()
		var focus := (lo + hi + Vector2.ONE) * 0.5
		assert_bool(focus.distance_to(Vector2(board.get_center().x, board.get_center().z)) > 1.0) \
			.override_failure_message(
				"%s starts its squad on the board's centre; aim cannot be told from framing here" % path
				).is_true()
		assert_float(_rig.position.x).override_failure_message(
				"%s: the rig is not aimed at the player squad" % path).is_equal_approx(focus.x, 0.01)
		assert_float(_rig.position.z).override_failure_message(
				"%s: the rig is not aimed at the player squad" % path).is_equal_approx(focus.y, 0.01)
		# Non-vacuous wherever it can be. A board narrower than the opening window legitimately
		# opens at the whole-board distance, so only assert "closer" where closer exists.
		if maxf(board.size.x, board.size.z) > _scene.opening_view_cells + 2.0:
			assert_float(_rig._target_distance).override_failure_message(
					"%s opened at the whole-board distance — the shot/bounds split did nothing" % path
					).is_less(_rig.max_distance)


func test_zooming_fully_out_still_shows_the_whole_board() -> void:
	# The other half, and what still pins the shipped bug: a board span in CELLS went to
	# set_zoom, which wants a camera DISTANCE, and the clamp ate it — Prolog needed ~82 and
	# got 24, so the far corners were unreachable at ANY zoom, not merely unframed at load.
	for path in [PROLOG, LEVEL_1]:
		_scene.load_mission(path)
		await _settle()
		var board: AABB = _scene._board_volume()
		var center := board.get_center()
		_rig.position = Vector3(center.x, _rig.position.y, center.z)
		_rig.set_zoom(_rig.max_distance)
		_camera3d.position.z = _rig._target_distance   # settle the exponential lerp outright
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
					"%s: board corner %s is off-camera even zoomed fully out" % [path, corner]).is_true()


func test_an_ai_turn_squares_the_camera_up() -> void:
	# Dev call 2026-08-14: whatever angle the player left the camera at, the enemy phase
	# plays out on an axis-aligned board.
	_rig._target_yaw_degrees = 37.0
	_cam().set_ai_locked(true)
	await _settle()
	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"the AI turn did not square the camera up").is_equal_approx(0.0, 0.001)

	# It is an EDGE, not a per-frame clamp — so a yaw driven mid-turn is left alone. That
	# matters the day free orbit is allowed under an AI turn: a per-frame snap would fight
	# the drag every frame instead of squaring up once.
	_rig._target_yaw_degrees = 200.0
	await _settle()
	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"the realign re-fires every frame, not on entry").is_equal_approx(200.0, 0.001)

	# And on the NEXT turn it takes the nearest detent, not zero.
	_cam().set_ai_locked(false)
	await _settle()
	_cam().set_ai_locked(true)
	await _settle()
	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"it squared up to zero rather than to the nearest detent").is_equal_approx(180.0, 0.001)
	_cam().set_ai_locked(false)


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
