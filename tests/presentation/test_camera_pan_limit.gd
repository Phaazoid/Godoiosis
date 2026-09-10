# THE PAN LIMIT IS NEVER NEAR THE STAGE, ON ANY BOARD, AT ANY CLOSE ZOOM (dev, 2026-09-09).
#
# His report: pressing S at a close zoom did nothing, the aim parked exactly on the limit. The wall
# was `pan_margin_cells := 4.0` -- a CELL COUNT, five cells out once the fit margin went under it.
# A cell count is generous zoomed out and useless zoomed in, because headroom is wanted in
# SCREENFULS; raising the number would only have moved where it is wrong, which is why he asked for
# a rule rather than a fix for one level.
#
# The rule is one screenful at the ZOOM CEILING (CameraRig3D.pan_stray). The ceiling is the widest
# view a player can ever have, so that stray is at least one screen at every closer zoom and more
# screens the further in they go.
#
# WHAT MAKES THESE CASES NON-VACUOUS is the yardstick: the stray is measured against the BOARD'S OWN
# SPAN, which the camera cannot move. A case comparing the limit against the frustum alone would be
# a budget that grows to fit whatever it measures -- scale the screen and both sides move together.
#
# Content razor: every mission on disk is loaded to exercise the real derivation, and nothing is
# asserted about what any of them CONTAIN. Each expectation is derived from that board's own bounds.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")

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


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)   # the mission door arms #182 dialog; end it or it leaks
	get_tree().root.remove_child(_scene)
	_scene.free()


func _missions() -> Array[String]:
	var manager: ScenarioManager = auto_free(ScenarioManager.new())
	return manager.get_missions()


# The board's longer horizontal span -- the yardstick these cases measure the limit against, and a
# fact about the BOARD rather than about the camera.
func _board_span(volume: AABB) -> float:
	return maxf(volume.size.x, volume.size.z)


func test_the_scan_finds_missions_to_measure() -> void:
	# Guards every case below against passing vacuously over an empty list.
	assert_array(_missions()).is_not_empty()


func test_the_pan_limit_clears_every_board_by_at_least_its_own_span() -> void:
	var problems: Array[String] = []
	for path: String in _missions():
		_scene.load_mission(path)
		await await_idle_frame()
		var volume: AABB = _scene._board_volume()
		if volume.size == Vector3.ZERO:
			continue   # a board with no standable column has no span to measure against
		var stray: float = _rig.pan_stray(_rig.max_distance)
		var span := _board_span(volume)
		if stray < span:
			problems.append("%s: stray %.1f is under its own board span %.1f"
				% [path.get_file(), stray, span])
	assert_array(problems).override_failure_message(
		"The pan wall sits within a board's own span of it -- that is 'near the stage':\n  %s"
		% "\n  ".join(problems)).is_empty()


func test_the_pan_limit_is_never_tighter_than_it_was_before_the_rule() -> void:
	# The no-regression floor. A board small enough that one screenful is under five cells must not
	# come out TIGHTER than the cell count this replaced (fit_margin 1 + the old pan_margin 4).
	var problems: Array[String] = []
	for path: String in _missions():
		_scene.load_mission(path)
		await await_idle_frame()
		var stray: float = _rig.pan_stray(_rig.max_distance)
		if stray < CameraRig3D.MIN_PAN_STRAY_CELLS:
			problems.append("%s: stray %.1f" % [path.get_file(), stray])
	assert_array(problems).override_failure_message(
		"Tighter than the wall this replaced:\n  %s" % "\n  ".join(problems)).is_empty()


func test_the_ceiling_still_frames_the_whole_board_from_the_centre() -> void:
	# The other half of the pair: the stray got looser, and the ceiling must not have moved. Asked
	# through the engine's own frustum test rather than by re-deriving the projection.
	var problems: Array[String] = []
	for path: String in _missions():
		_scene.load_mission(path)
		await await_idle_frame()
		var volume: AABB = _scene._board_volume()
		if volume.size == Vector3.ZERO:
			continue
		_rig.hold_at(Vector3(volume.get_center().x, volume.end.y, volume.get_center().z))
		_rig.set_zoom(_rig.max_distance)
		for i in 240:
			await await_idle_frame()
		for i in 8:
			if not _camera3d.is_position_in_frustum(volume.get_endpoint(i)):
				problems.append("%s: corner %s off screen at the ceiling" % [path.get_file(), volume.get_endpoint(i)])
	assert_array(problems).override_failure_message(
		"The zoom ceiling no longer frames the board:\n  %s" % "\n  ".join(problems)).is_empty()
