# The 3D camera during play (#176 stage 4d): does it follow the action, does it frame
# the board it loaded, and does it refuse the player at the right moments.
#
# The headline this pins: before 4d nothing moved the 3D rig during a battle at all —
# AIController panned the HIDDEN 2D camera and awaited the full beat, so an enemy turn
# in 3D was ~1.3s of dead air per squad in front of a motionless frame.
#
# The follow is a MIRROR of the 2D camera (which already knows where the action is),
# gated on playback_locked. Two cases below decide that gate, and both are written to fail
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
	await DialogFixtures.end_all_dialog(self)   # the mission door arms #182 dialog; end it or it leaks
	get_tree().root.remove_child(_scene)
	_scene.free()


# --- who owns the camera, and what the player keeps (#520) ------------------------------------

# The #484 exclusion as a LAW over the flag rather than a scenario: whenever the mirror's gate is
# open, _update_pointer's WRITE gate is shut. They read each other's target (the mirror READS the 2D
# camera, the pointer WRITES it), so a frame running both marches the view to the pan limit. #520
# widened the flag to cover a player's own pass, which is exactly when this could have broken.
func test_the_mirror_gate_and_the_pointer_gate_are_never_open_together() -> void:
	for locked in [false, true]:
		_cam().set_playback_locked(locked)
		await _settle()
		assert_bool(_cam().playback_locked and not _game._board_locked_for_player()) \
			.override_failure_message(
				"the mirror may read the 2D camera while the pointer may still write it (#484)") \
			.is_false()
	_cam().set_playback_locked(false)


# The dev's 2026-08-26 ruling: playback owns WHERE the camera looks, the player keeps HOW FAR OUT it
# sits. Before #520 one flag killed orbit and wheel together for a whole AI turn.
func test_the_player_keeps_the_zoom_wheel_while_playback_owns_the_camera() -> void:
	_game.game_state = _game.GameState.AI_TURN
	_cam().set_playback_locked(true)
	await _settle()
	assert_bool(_game._board_locked_for_player()).override_failure_message(
			"precondition: playback should own the board here").is_true()
	assert_bool(_rig.zoom_input_enabled).override_failure_message(
			"the zoom wheel died with the rest of the rig -- the split did not take").is_true()
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE


# A pass CLAIMS the camera and hands it back to whoever held it -- it does not simply unlock.
# An AI turn owns the camera for its whole length and runs a pass inside it, so a blind release
# would unlock the camera mid-turn and let the player drag the view out from under the enemy phase.
func test_a_pass_inside_an_ai_turn_leaves_the_camera_still_owned() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	_game.game_state = _game.GameState.AI_TURN
	_cam().set_playback_locked(true)

	await _game.order_executor.execute_orders(unit)   # empty queue: walks every phase, does nothing
	await _settle()

	assert_bool(_cam().playback_locked).override_failure_message(
			"the pass released the camera it borrowed -- an AI turn is unlocked mid-turn").is_true()
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE


# ...and the mirror image: a pass on the PLAYER's own turn gives the camera back when it ends, or
# the board would stay locked to clicks forever after one Execute.
func test_a_pass_on_the_players_own_turn_gives_the_camera_back() -> void:
	var unit := _player_unit()
	assert_bool(_cam().playback_locked).override_failure_message(
			"precondition: nothing should own the camera before the pass").is_false()

	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_bool(_cam().playback_locked).override_failure_message(
			"the pass kept the camera -- the board never unlocks after an Execute").is_false()


# ...and a MENU takes it, because the surface on screen wants the wheel for itself. This is the
# other half: a gate that never shuts is not a gate.
func test_a_menu_takes_the_zoom_wheel_back() -> void:
	_game.game_state = _game.GameState.MENU
	await _settle()
	assert_bool(_rig.zoom_input_enabled).override_failure_message(
			"a menu is up and the wheel still zooms the board behind it").is_false()
	_game.game_state = _game.GameState.IDLE


# The move phase gets a camera too (dev, 2026-08-26: "when I moved on my turn, the camera just
# kinda stared off into space"). #520 diff 1 wired only the volley beats, and it had ALSO taken the
# player's own scroll away for the length of a pass -- so the move phase went from unframed-but-
# scrollable to unframed-and-frozen.
#
# Asserted on follow_unit rather than a position: pan_to ends by handing over to follow(), and a
# position would depend on the 2D camera's clamp against the board's own extent, i.e. on authored
# content. Run inside a claimed camera (what an AI turn does) because the restore at the end of a
# PLAYER pass clears follow_unit -- here the claim is put back, so the last pan survives to be read.
#
# LIMIT, stated rather than implied: pan_to snaps headless, so this pins the WIRE, not the ordering.
# That the pan precedes the walk is structural -- the await sits above the phase.
func test_the_move_phase_takes_the_camera_to_whoever_is_walking() -> void:
	var mover := _mobile_player_unit()
	assert_object(mover).override_failure_message(
			"fixture: no player unit on this board can move").is_not_null()

	_cam().set_playback_locked(true)

	# Control first: the same pass with nothing queued must move the camera nowhere, or the case
	# below would pass on any pan at all rather than on the move's.
	await _game.order_executor.execute_orders(mover)
	await _settle()
	assert_object(_cam().follow_unit).override_failure_message(
			"an empty pass panned the camera somewhere").is_null()

	var moverange = _game.compute_move_range(mover)
	var destinations: Array[Vector2i] = _game.get_move_range(moverange, mover)
	var path := RulesService.reconstruct_path(moverange.came_from, mover.movement.cell, destinations[0])
	var move := MoveAction.new()
	move.init(mover, path, null)
	assert_bool(_game.squad_manager.queue_action(mover.squad, move)).override_failure_message(
			"fixture: the move was refused, so the pass would concede instead of playing").is_true()

	await _game.order_executor.execute_orders(mover)
	await _settle()

	assert_object(_cam().follow_unit).override_failure_message(
			"the move phase played with the camera pointed wherever it was left").is_same(mover)
	_cam().set_playback_locked(false)


# ...and so does the side-channel tail. ADDED BY FALSIFICATION, not by reasoning: deleting the
# subjects argument from execute_orders' side-channel call left 587 cases green across presentation
# and squad, because everything about codas was pinned at its two ENDS (the sheet builds them, the
# schedule reads them) and nothing drove the wire between. #103's shape exactly.
#
# The camera is parked on ANOTHER unit first, so "it ended up on the rallier" cannot pass by the
# camera simply never having moved. A rally is the cheapest coda to stage: no target, no terrain,
# and _queue_action is the raw door the beat sheet suite already uses.
func test_a_side_channel_verb_takes_the_camera_too() -> void:
	var unit := _player_unit()
	var elsewhere := _any_unit_besides(unit)
	assert_object(elsewhere).override_failure_message(
			"fixture: this board has only one unit").is_not_null()

	var rally := RallyAction.new()
	rally.init(unit)
	unit.squad._queue_action(rally)

	_cam().set_playback_locked(true)
	_cam().follow(elsewhere)
	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_object(_cam().follow_unit).override_failure_message(
			"the tail played with the camera still pointed at whatever it was watching before") \
		.is_same(unit)
	_cam().set_playback_locked(false)


func _any_unit_besides(other: Unit) -> Unit:
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit != null and unit != other:
			return unit
	return null


# A player unit that actually has somewhere to go -- a unit stranded on a terrace with no ramp off
# it is a legal board and produces no move at all (the content razor's second hazard).
func _mobile_player_unit() -> Unit:
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit == null or unit.get_faction() != Team.Faction.PLAYER:
			continue
		var reachable: Array[Vector2i] = _game.get_move_range(_game.compute_move_range(unit), unit)
		if not reachable.is_empty():
			return unit
	return null


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


# Where a thing STANDING on this cell sits, through the seam UnitMirror places sprites with
# (BoardSpace.surface_point). Never level 0: Level_1 carries eight raised cells since b057f6e, and
# the day one of them holds a player unit an of_cell(..., 0) frustum check silently asks about a
# point in the air below them.
func _stand(cell: Vector2i) -> Vector3:
	var heights: BoardHeights = _game.board_heights
	return BoardSpace.surface_point(cell, heights)


# The screen point for a cell, off the picker's own column tops — the twin of test_input_bridge's
# _screen_of, and correct for a ramp for the same reason.
func _screen_of(cell: Vector2i) -> Vector2:
	var tops: Dictionary[Vector2i, int] = _scene._tops
	var level: int = tops.get(cell, BoardSpace.FLAT_TOP_ROW)
	return _camera3d.unproject_position(Vector3((cell.x + 0.5) * BoardSpace.CELL_SIZE,
			level * BoardSpace.ROW_HEIGHT, (cell.y + 0.5) * BoardSpace.CELL_SIZE))


# Where the rig should SIT to look at a world x/z: on the surface there, never at the board's
# ceiling. Spelled from BoardSpace rather than asked of battle3d, so a case comparing against it is
# checking the rule and not the implementation against itself.
func _surface_aim(at: Vector3) -> Vector3:
	var heights: BoardHeights = _game.board_heights
	return Vector3(at.x, BoardSpace.surface_height_at(
			Vector2i(floori(at.x), floori(at.z)), at.x, at.z, heights), at.z)


# The mirror cell the 3D pointer reports for a 2D cell — the picker's answer, not an assumed level.
func _picked(cell: Vector2i) -> Vector3i:
	var tops: Dictionary[Vector2i, int] = _scene._tops
	return BoardSpace.of_cell(cell, tops.get(cell, BoardSpace.FLAT_TOP_ROW) - 1)


# --- Following the action ----------------------------------------------------------

func test_the_3d_camera_follows_the_ai_camera() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	# `playback_locked and not _board_locked_for_player()` is the pair that must never exist -- the poll
	# re-derives on CAMERA movement since #471, so a fixture holding it lets the hover snap drag the
	# 2D camera the mirror below is reading, and the two march the view to the pan limit.
	#
	# This comment used to say the pair was unreachable BECAUSE start_faction_turn writes AI_TURN and
	# the flag together. That was false: game_state is transient, and set_dev_mode rested it on
	# _base_state() mid-enemy-phase, which is #484. The predicate now READS playback_locked, so the line
	# below is what makes the pair impossible rather than a claim about who writes what.
	_game.game_state = _game.GameState.AI_TURN
	_cam().set_playback_locked(true)
	await _cam().pan_to(unit)   # headless: lands on the destination and hands to follow
	await _settle()
	# Where the 2D camera went, in the 3D metric. The 2D answers WHERE; the BOARD answers how high
	# (2026-08-23) — this used to read _rig.position.y, i.e. whatever the opening shot left there.
	var expected := _surface_aim(BoardSpace.of_pixels(_cam().global_position, 0.0))

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
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE


func test_hovering_does_not_drag_the_3d_camera() -> void:
	# The naive-mirror hazard. Pointing snaps the hidden 2D camera every time (it is what
	# parks the hover card), so a mirror that ran outside an AI turn would jerk the whole
	# diorama on every mouse move.
	var unit := _player_unit()
	var before := _rig.position
	var cell: Vector2i = unit.movement.cell
	var motion := InputEventMouseMotion.new()
	var screen := _screen_of(cell)
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _settle()

	# The 2D camera DID move (non-vacuous: the snap is what the hover card rides on)...
	assert_that(_scene._pointer_cell).is_equal(_picked(cell))
	# ...and the 3D did not.
	assert_that(_rig.position).override_failure_message(
			"a hover dragged the 3D camera — the mirror is not gated on playback_locked").is_equal(before)


func test_opening_a_menu_does_not_yank_the_3d_camera() -> void:
	# The case that decides the gate. MissionSelectScreen opts OUT of the modal lock, so
	# _board_locked_for_player() is true here while the game runs on — mirroring on that
	# predicate would snap the rig to wherever the 2D camera happens to be parked.
	var before := _rig.position
	_game.game_state = _game.GameState.MENU
	assert_bool(_game._board_locked_for_player()).is_true()
	assert_bool(_cam().playback_locked).is_false()
	_cam().snap_to_position(Vector2(-4000.0, -4000.0))
	await _settle()

	assert_that(_rig.position).override_failure_message(
			"the menu yanked the rig — the mirror is gated on the wrong predicate").is_equal(before)


# #484, reported in play: the mouse became welded to the camera and ran the view to its limit in
# whatever direction it moved. Toggling dev mode mid-enemy-phase rested game_state on _base_state(),
# which unlocked the board while playback_locked stayed true -- opening _update_pointer's gate (it writes
# the hidden 2D camera) at the same time as _mirror_camera's (it reads it).
#
# Drives the REAL door: set_dev_mode, not a game_state poke. The rig assertion is the point -- the
# predicate going false is the rule, but the camera running away is what the dev saw, and a case
# that only read the predicate would pass against a mirror wired straight to game_state.
func test_toggling_dev_mode_during_an_ai_turn_leaves_the_board_locked() -> void:
	_game.game_state = _game.GameState.AI_TURN
	_cam().set_playback_locked(true)
	await _settle()
	var before := _rig.position

	_game.set_dev_mode(true)
	assert_int(_game.game_state).override_failure_message(
			"set_dev_mode no longer rests game_state -- this case is asserting nothing"
			).is_equal(_game.GameState.DEV_MODE)
	assert_bool(_game._board_locked_for_player()).override_failure_message(
			"dev mode unlocked the board mid-AI-turn: game_state moved and the lock followed it"
			).is_true()

	# The runaway itself. A hover would snap the 2D camera and the mirror would drag the rig after it.
	var unit := _player_unit()
	var screen := _screen_of(unit.movement.cell)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _settle()

	assert_that(_rig.position).override_failure_message(
			"the mouse dragged the 3D camera -- the pointer and the mirror both ran in one frame"
			).is_equal(before)
	_game.set_dev_mode(false)
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE


# The second door onto the same pair (#484): clear_board rests game_state through exit_current_mode,
# so a reload mid-enemy-phase reaches it too. Now that the lock READS playback_locked, an interrupted AI
# turn leaving the flag standing would lock the FRESH board for good -- so clear_board drops it,
# beside the ai_factions reset it already does for the same "a new board inherits nothing" reason.
func test_clearing_the_board_during_an_ai_turn_drops_the_ai_camera_lock() -> void:
	_cam().set_playback_locked(true)
	await _settle()

	_game.scenario_manager.clear_board()
	await _settle()

	assert_bool(_cam().playback_locked).override_failure_message(
			"a cleared board kept the last turn's camera lock -- the new board is locked for good"
			).is_false()
	assert_bool(_game._board_locked_for_player()).override_failure_message(
			"the fresh board came up locked").is_false()


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
	# The precondition, stated rather than inherited. It used to arrive for free — nothing picked a
	# cell until the mouse moved — but since #471 the poll re-derives on CAMERA movement too, and
	# framing the loaded mission is exactly that, so before_test now leaves a cell under the cursor.
	# The rule here is that a MENU does not UPDATE the pointer, which is unchanged either way.
	_scene._pointer_cell = BoardSpace.NO_CELL
	var unit := _player_unit()
	var screen := _screen_of(unit.movement.cell)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _settle()
	assert_that(_scene._pointer_cell).override_failure_message(
			"the bracket painted over a board the click handler would refuse").is_equal(BoardSpace.NO_CELL)


# --- Framing a real mission --------------------------------------------------------

func test_both_authored_missions_open_where_they_say() -> void:
	# REPLACES "opens with the whole board in frame" (dev feel-check 2026-08-14: fitting all
	# 64x40 of Prolog was too far out to play from). The board is now what the view is
	# BOUNDED by — see the case below, which keeps that half honest.
	#
	# TWO answers since #234, so this forks on the SEAM and never on which mission it is:
	# a board that authors a camera start opens THERE, one that authors none opens on its own
	# squad. Naming which is which would pin authored content — the dev captured a start on
	# Level_1 the day the feature landed, and *that is the feature working*. The derivation's
	# content-independent pin lives in test_camera_start.gd, so this case going all-authored
	# is correct rather than vacuous.
	for path in [PROLOG, LEVEL_1]:
		_scene.load_mission(path)
		await _settle()
		var start: CameraPose = _game.scenario_manager.current_camera_start
		if start != null:
			_assert_opens_at_the_authored_pose(path, start)
		else:
			_assert_opens_on_the_player_squad(path)


# The authored half. Compared against the pose CLAMPED into the rig's own limits, not against
# the raw authored numbers: #234's ruling is that a stale start is clamped silently with no
# validity predicate, so asserting the raw value would red on exactly the content the dev is
# allowed to edit — and would contradict the rule it is meant to be checking.
func _assert_opens_at_the_authored_pose(path: String, start: CameraPose) -> void:
	var limit: Rect2 = _rig.pan_limit
	assert_float(_rig.position.x).override_failure_message(
			"%s authors a camera start and did not open at its aim" % path
			).is_equal_approx(clampf(start.aim.x, limit.position.x, limit.end.x), 0.01)
	assert_float(_rig.position.z).override_failure_message(
			"%s authors a camera start and did not open at its aim" % path
			).is_equal_approx(clampf(start.aim.z, limit.position.y, limit.end.y), 0.01)
	# Yaw is the one axis nothing clamps, so it is the sharpest single check here.
	assert_float(_rig.rotation_degrees.y).override_failure_message(
			"%s authors a camera start and did not open at its angle" % path
			).is_equal_approx(start.yaw_degrees, 0.01)
	assert_float(_camera3d.position.z).override_failure_message(
			"%s authors a camera start and did not open at its zoom" % path
			).is_equal_approx(minf(start.distance, _rig.max_distance), 0.01)   # no zoom-in floor since 2026-08-23


# The derived half — unchanged, and still the reason the shot/bounds split exists.
func _assert_opens_on_the_player_squad(path: String) -> void:
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
		var point := _stand(unit.movement.cell)
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
			# The corner's real surface, not an assumed floor — a corner standing on a terrace is
			# HIGHER, i.e. nearer the top of the frustum, which is exactly the case that would fail.
			var point := _stand(corner)
			assert_bool(_camera3d.is_position_in_frustum(point)).override_failure_message(
					"%s: board corner %s is off-camera even zoomed fully out" % [path, corner]).is_true()


func test_an_ai_turn_squares_the_camera_up() -> void:
	# Dev call 2026-08-14: whatever angle the player left the camera at, the enemy phase
	# plays out on an axis-aligned board.
	_rig._target_yaw_degrees = 37.0
	_cam().set_playback_locked(true)
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
	_cam().set_playback_locked(false)
	await _settle()
	_cam().set_playback_locked(true)
	await _settle()
	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"it squared up to zero rather than to the nearest detent").is_equal_approx(180.0, 0.001)
	_cam().set_playback_locked(false)


func test_space_recentres_the_diorama_on_the_pointer() -> void:
	var unit := _player_unit()
	var cell: Vector2i = unit.movement.cell
	_scene._update_pointer(_screen_of(cell))
	_rig.position = Vector3(_rig.position.x + 12.0, _rig.position.y, _rig.position.z + 12.0)
	var before := _rig.position

	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	_scene._unhandled_input(space)

	# The WHOLE point, height included (2026-08-23). It used to keep `before.y` — which is how the
	# rig came to sit at the board's ceiling for ever on any board with elevation.
	var point := BoardSpace.surface_point(BoardSpace.flat(_scene._pointer_cell), _game.board_heights)
	assert_that(_rig.position).is_equal(point)
	assert_bool(_rig.position.distance_to(before) > 1.0).is_true()


# --- Coming back to the acting unit (#471) ------------------------------------------

# The ring does NOT lock the board, so the player can pan the diorama anywhere while choosing --
# and then commit an order that plays out around a unit no longer on screen. Driven at
# game.focus_view_on rather than through a menu pick: the RING's half of this wire is pinned in
# tests/ui/test_radial_menu.gd, and this is the half only the 3D host can see. Kill battle3d's
# connect and this is what reds.
func test_a_committed_order_brings_the_rig_back_to_the_acting_unit() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	# The opening shot sits over the player's squad, i.e. over this very unit, so the rig has to be
	# shoved off first -- to a corner of its own pan limit, which the clamp will leave alone.
	_rig.position = Vector3(_rig.pan_limit.position.x, _rig.position.y, _rig.pan_limit.position.y)
	var before := _rig.position
	# The unit's PROJECTED cell, which is what focus_view_on means by "where this unit is acting
	# from" -- read through the same expression rather than assumed to be movement.cell.
	var target := BoardSpace.standing_point(BoardSpace.of_cell(unit.get_projected_destination(), 0))
	assert_bool(Vector2(before.x, before.z).distance_to(Vector2(target.x, target.z)) > 1.0) \
		.override_failure_message("the rig was already over the unit; the case proves nothing").is_true()

	_game.focus_view_on(unit)
	await _settle()

	assert_float(_rig.position.x).override_failure_message(
			"a committed order did not bring the rig back to the acting unit").is_equal_approx(target.x, 0.01)
	assert_float(_rig.position.z).override_failure_message(
			"a committed order did not bring the rig back to the acting unit").is_equal_approx(target.z, 0.01)


# The pointer poll re-derives on CAMERA movement, not only on mouse movement (#471). Without it the
# hover bracket sits on the cell the pointer LEFT until the mouse moves -- true of WASD and of SPACE
# long before this ticket, and this is what makes it frequent enough to notice.
func test_moving_the_camera_re_picks_the_cell_under_a_still_pointer() -> void:
	_game.game_state = _game.GameState.IDLE
	var unit := _player_unit()
	var cell: Vector2i = unit.movement.cell
	_scene._update_pointer(_screen_of(cell))
	await _settle()
	assert_that(_scene._pointer_cell).override_failure_message(
			"the fixture never got the pointer onto the unit's cell").is_equal(_picked(cell))

	# The mouse does not move; the world does.
	_rig.position = Vector3(_rig.position.x + 6.0, _rig.position.y, _rig.position.z + 6.0)
	await _settle()

	assert_that(_scene._pointer_cell).override_failure_message(
			"panning under a still cursor left the pointer on the cell it had left") \
		.is_not_equal(_picked(cell))


# --- The aim HEIGHT (dev report, 2026-08-23) ----------------------------------------

# THE rule: the rig aims ON the surface it is looking at, never at the board's CEILING.
# CameraRig3D._aim_at lifts the OPENING shot to the top of the whole board volume — right for
# framing a board, wrong for looking at something standing on one — and nothing ever re-derived it,
# because every recentre kept _rig.position.y. On Level_1 (columns to level 4, plus an authored
# start that froze aim.y = 5) that put the look-at point four cells in the air, so the unit rode
# off the top of the frame at close zoom. Prolog is flat, which is why it never showed there.
#
# The absurd height is SET here rather than inherited from a mission, so this is a claim about the
# RULE and not about what any board happens to be painted to (the content razor).
func test_the_return_aims_at_the_surface_not_at_the_board_ceiling() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	_rig.position = Vector3(_rig.position.x, 12.0, _rig.position.z)

	_game.focus_view_on(unit)
	await _settle()

	var wanted := BoardSpace.surface_point(unit.get_projected_destination(), _game.board_heights)
	assert_bool(absf(12.0 - wanted.y) > 1.0).override_failure_message(
			"the parked height IS the surface here; the case proves nothing").is_true()
	assert_float(_rig.position.y).override_failure_message(
			"the rig kept its inherited aim height, so it looks at a point in the air above the unit"
			).is_equal_approx(wanted.y, 0.01)


# The same rule at the OTHER surface that reads it, and the one the dev actually saw it on: an AI
# turn on Level_1. Pre-existing since 4d — the mirror kept _rig.position.y as deliberately as the
# recentre did, so fixing one without the other would have left the enemy phase aiming at the sky.
func test_the_ai_pan_aims_at_the_surface_too() -> void:
	var unit := _player_unit()
	assert_object(unit).is_not_null()
	_game.game_state = _game.GameState.AI_TURN
	_cam().set_playback_locked(true)
	await _cam().pan_to(unit)
	_rig.position = Vector3(_rig.position.x, 12.0, _rig.position.z)
	await _settle()

	var wanted := _surface_aim(BoardSpace.of_pixels(_cam().global_position, 0.0))
	assert_bool(absf(12.0 - wanted.y) > 1.0).override_failure_message(
			"the parked height IS the surface here; the case proves nothing").is_true()
	assert_float(_rig.position.y).override_failure_message(
			"the AI pan kept the rig's inherited aim height").is_equal_approx(wanted.y, 0.01)
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE
