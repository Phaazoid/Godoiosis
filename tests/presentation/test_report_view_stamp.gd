# A bug report filed from the 3D view names the angle it was seen from (#240).
#
# This is a WIRE suite, and it exists because both ends can be right while nothing connects them
# -- #103's shape. BugReporter cannot reach the 3D scene (the game subtree deliberately keeps no
# upward path, and an absolute /root/... lookup is forbidden by CLAUDE.md), so battle3d PUSHES a
# describe-callable at it in _ready, the same idiom as DevOverlay.attach_3d_host and
# HoverPresenter.pointer_source. Delete that one line and both ends still pass their own tests.
#
# Deliberately NOT here: the screenshot. capture_frame() returns null headless because
# RenderingServer.frame_post_draw never fires without a draw, so the viewport CHOICE is pinned in
# tests/ui/test_report_flow.gd, and whether the resulting PNG looks right is the dev's, by playing.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")

var _scene: Node3D
var _game: Node2D
var _written: Array[String] = []


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var packed := SCENE
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_game = _scene.game


func after_test() -> void:
	for dir: String in _written:
		_delete_recursive(dir)
	_written.clear()
	get_tree().root.remove_child(_scene)
	_scene.free()


func _delete_recursive(dir: String) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	for file: String in access.get_files():
		access.remove(file)
	DirAccess.remove_absolute(dir)


func test_the_3d_host_tells_the_reporter_what_it_is_showing() -> void:
	var source: Callable = _game.bug_reporter.view_source
	assert_bool(source.is_valid()).is_true()

	var note: String = source.call()
	# The hosting mode, and the camera state that makes two reports comparable. Asserted by
	# SUBSTRING rather than whole-string, so retuning the wording of one field cannot red this.
	assert_str(note).contains("HD_2D")
	assert_str(note).contains("yaw")
	assert_str(note).contains("zoom")


func test_the_view_the_host_named_reaches_report_md() -> void:
	# The whole wire, end to end: push -> _view_note -> build_report_text -> the file on disk.
	# report() is driven directly (the card is the #131 funnel and has its own suite); what this
	# adds is that the stamp survives the trip through a real hosted game.
	#
	# The expectation comes off the HOST's own composer, deliberately not off view_source: read
	# through the wire and a broken wire would take the expectation down with it, so the case
	# would die fetching it instead of reporting what landed in the file. Sourced here, the wire
	# is the only thing standing between the two ends -- which is the whole point of the case.
	var expected: String = _scene._describe_view()
	var result: Dictionary = await _game.bug_reporter.report(
		"IDLE", BugReporter.Kind.BUG, "the tree is floating", null)
	_written.append(result["dir"])

	assert_str(result["dir"]).is_not_equal("")
	var text := FileAccess.get_file_as_string(result["dir"] + "report.md")
	assert_str(text).contains("View: **%s**" % expected)
	# Not vacuous by way of the fallback: the flat-launch sentence must NOT be what got written.
	assert_str(text).not_contains(BugReporter.NO_3D_VIEW)


func test_the_view_note_carries_the_camera_channels() -> void:
	# The diagnostic half (#602 round 6): five reports of grey void took a session to decode from
	# pixels because no report said where the rig's channels WERE. A stuck lift, a held drop or a
	# frozen clock is a number in this line now -- so the line losing them is a finding.
	var note: String = _scene._describe_view()
	for key in ["lift", "drop", "tscale", "staged", "flight"]:
		assert_str(note).override_failure_message(
				"the view note lost its '%s' channel -- reports stop self-diagnosing" % key
		).contains(key)


func test_the_view_note_says_which_holds_are_live_and_where_the_frame_ends() -> void:
	# The channels say where the camera IS; these say WHY it is there (#669). Every #602 round
	# opened on "why is it stuck", and a report that answers it costs nobody a play-check round.
	# The floor is a PAIR: settled alone hides how far the frame still has to descend, and live
	# alone is the reading round 8 proved nothing may be anchored to.
	var note: String = _scene._describe_view()
	for key in ["lock", "death show", "following", "floor", "live", "settled"]:
		assert_str(note).override_failure_message(
				"the view note lost its '%s' hold -- a report can say where the camera is but "
				% key + "not why it is held there, which is the question every round opened with"
		).contains(key)


func test_the_camera_trace_reaches_report_md() -> void:
	# The wire, end to end, for the SECOND push (#669) -- battle3d composes, BugReporter renders,
	# and delete the one line in _ready and both ends still pass their own suites (#103's shape).
	var result: Dictionary = await _game.bug_reporter.report(
		"IDLE", BugReporter.Kind.BUG, "the camera would not let go", null)
	_written.append(result["dir"])

	var text := FileAccess.get_file_as_string(result["dir"] + "report.md")
	assert_str(text).contains("## Camera trace")
	# Not vacuous by way of the fallback: a hosted game must not file the flat-launch sentence.
	assert_str(text).override_failure_message(
			"the trace section fell back to its no-host sentence inside a real 3D host -- the "
			+ "push in _ready is not landing").not_contains(BugReporter.NO_CAMERA_TRACE)
	# The opening shot poses or frames the rig, so a hosted board has always moved its camera.
	assert_str(text).not_contains("nothing recorded")
