# The dev-tools Camera page (#705 slice 3): the wire from the running Battle3D to the page, and the
# page's buttons acting on the real recording.
#
# The leaf laws (test_dev_tree) and the width law (test_dev_window_fit) already cover the page as a
# LEAF. Neither can see a page that is built but not WIRED -- no host, a table nothing feeds, a View
# line read from a string of its own -- which is what these cases are for. Every case refreshes by
# hand: the page's own poll only runs while the window is up, and the suite never shows it.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"

var _board := SharedBoard.new(SCENE_PATH, PROLOG)
var _scene: Node3D
var _game: Node2D
var _tool: CameraTool
var _rig: CameraRig3D


func before() -> void:
	await _board.open(self)


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	_game = _board.scene.game
	var overlay: DevOverlay = _game.dev_overlay
	_tool = overlay.camera_tool
	_rig = _scene.get_node("CameraRig") as CameraRig3D
	(_game.playback_control as PlaybackControl).set_process(false)


func after_test() -> void:
	_tool.attach_host(_scene)
	_scene.clear_keyframes()
	Pacing.reset_playback()
	(_game.camera_controller as CameraController).set_playback_locked(false)
	_scene._mirror_camera()
	(_game.playback_control as PlaybackControl).set_process(true)
	_game.game_state = _game.GameState.IDLE
	await _board.check(self)


func after() -> void:
	_board.close()


func test_the_page_is_wired_to_the_host_and_crowns_the_shot_that_owns_the_camera() -> void:
	assert_object(_tool._host).override_failure_message(
			"the 3D host never reached the Camera page -- DevOverlay.attach_3d_host does not forward it") \
		.is_same(_scene)
	_claim()
	_tool.refresh()
	assert_str(_tool._status.text).is_equal(CameraTool.PLAYING)
	var active: ShotDirector.Shot = _scene.shots().active
	assert_int(active).override_failure_message("precondition: playback owns no shot").is_not_equal(
			ShotDirector.Shot.NONE)
	var crowned := _crowned()
	assert_array(crowned).override_failure_message(
			"the page crowns %s, the camera is in %s" % [crowned, ShotDirector.Shot.keys()[active]]) \
		.contains_exactly([ShotDirector.Shot.keys()[active]])
	assert_bool(_tool._shot_labels[ShotDirector.Shot.NONE].modulate == CameraTool.DARK_COLOR) \
		.override_failure_message("NONE is lit while playback owns the camera").is_true()
	Pacing.set_dev_paused(true)
	_tool.refresh()
	assert_str(_tool._status.text).is_equal(CameraTool.PAUSED)


func test_the_view_and_trace_are_what_a_report_filed_now_would_carry() -> void:
	_claim()
	_tool._trace_due_msec = 0
	_tool.refresh()
	var reporter: BugReporter = _game.bug_reporter
	var view: String = reporter.view_source.call()
	assert_str(_tool._view.text).override_failure_message(
			"the page's View line is not the report's -- it no longer reads the pushed source") \
		.is_equal(view)
	assert_str(_tool._trace.text).override_failure_message("the trace never reached the page") \
		.is_not_empty()
	assert_bool(_tool._trace.text.contains("```")).override_failure_message(
			"the trace still wears its report fences on the page").is_false()


func test_delete_renumbers_and_clear_all_empties_the_recording() -> void:
	_pause()
	for i in 3:
		_scene.add_keyframe()
	_tool.refresh()
	assert_int(_key_rows().size()).override_failure_message("the page does not list the key poses") \
		.is_equal(3)
	_button(_key_rows()[1], "Delete").pressed.emit()
	_tool.refresh()
	assert_int(_scene.recording().keyframes.size()).override_failure_message(
			"Delete did not reach the recording").is_equal(2)
	var rows := _key_rows()
	assert_int(rows.size()).override_failure_message("the page did not redraw after a Delete").is_equal(2)
	assert_str(_row_text(rows[1])).override_failure_message(
			"the key pose after the deleted one kept its old number").starts_with("K2")
	assert_str(_scene.dev_pause_label().text).override_failure_message(
			"the PAUSED label still counts the deleted key pose") \
		.contains("2/%d" % CameraRecording.MAX_KEYFRAMES)
	_tool._clear_all.pressed.emit()
	_tool.refresh()
	assert_bool(_scene.recording().is_empty()).override_failure_message("Clear all cleared nothing") \
		.is_true()
	assert_bool(_tool._clear_all.disabled).is_true()


func test_jump_cuts_to_the_pose_and_only_while_paused() -> void:
	_pause()
	var director_yaw: float = _scene._held_frame["yaw"]
	var wanted := director_yaw + 77.0
	_rig._target_yaw_degrees = wanted
	_rig.rotation_degrees.y = wanted
	_scene.add_keyframe()
	_rig._target_yaw_degrees = director_yaw - 50.0   # the dev looks somewhere else
	_rig.rotation_degrees.y = director_yaw - 50.0
	_tool.refresh()
	var jump := _button(_key_rows()[0], "Jump to")
	assert_bool(jump.disabled).override_failure_message("Jump is off while paused").is_false()
	jump.pressed.emit()
	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"Jump did not put the camera back on the key pose").is_equal_approx(wanted, 0.01)
	Pacing.set_dev_paused(false)
	_scene._mirror_camera()
	_tool.refresh()
	assert_bool(_button(_key_rows()[0], "Jump to").disabled).override_failure_message(
			"Jump is offered with the director back in charge").is_true()
	assert_bool(_scene.jump_to_keyframe(1)).override_failure_message(
			"a jump went through while the pass was playing").is_false()


func test_with_no_host_the_page_says_so_and_lights_nothing() -> void:
	_tool.attach_host(null)
	_tool.refresh()
	assert_str(_tool._status.text).is_equal(CameraTool.NO_HOST)
	assert_array(_crowned()).is_empty()
	assert_bool(_tool._clear_all.disabled).is_true()


# --- helpers --------------------------------------------------------------------------------------

func _claim() -> void:
	_game.game_state = _game.GameState.AI_TURN
	(_game.camera_controller as CameraController).set_playback_locked(true)
	_scene._mirror_camera()


func _pause() -> void:
	_claim()
	Pacing.set_dev_paused(true)
	_scene._mirror_camera()   # the pause's edge: the director's frame is held


func _crowned() -> Array[String]:
	var out: Array[String] = []
	for value: int in ShotDirector.Shot.values():
		if _tool._shot_labels[value].text.begins_with("▶"):
			out.append(ShotDirector.Shot.keys()[value])
	return out


func _key_rows() -> Array[HBoxContainer]:
	var rows: Array[HBoxContainer] = []
	for child in _tool._keys.get_children():
		if child is HBoxContainer and not child.is_queued_for_deletion():
			rows.append(child)
	return rows


func _button(row: HBoxContainer, text: String) -> Button:
	for child in row.get_children():
		if child is Button and (child as Button).text == text:
			return child
	return null


func _row_text(row: HBoxContainer) -> String:
	return (row.get_child(0) as Label).text
