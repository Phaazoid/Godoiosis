# The dev's key poses as a spec (#705 slice 2): what a keyframe holds, the report section it prints,
# the JSON that replays it, and the contact sheet of its screenshots. Scene-free -- the wire (N while
# paused fills it from the real rig; the bug report carries it) is test_playback_control's.
extends GdUnitTestSuite


func _pose(yaw: float, pitch: float, distance: float, aim: Vector3) -> Dictionary:
	return {"aim": aim, "yaw": yaw, "pitch": pitch, "distance": distance,
			"lift": Vector3(0.0, 40.0, 0.0), "drop": 0.25, "dolly": 1.5}


func _line(names: Array) -> Array[String]:
	var out: Array[String] = []
	for name: String in names:
		out.append(name)
	return out


func _image(color: Color) -> Image:
	var image := Image.create_empty(64, 36, false, Image.FORMAT_RGB8)
	image.fill(color)
	return image


func test_a_key_pose_keeps_both_frames_and_what_was_playing() -> void:
	var recording := CameraRecording.new()
	var yours := _pose(45.0, -25.0, 9.0, Vector3(1.0, 2.0, 3.0))
	var director := _pose(0.0, -30.0, 7.0, Vector3(1.5, 2.0, 3.5))
	var key := recording.add(10.25, "TRAINED", "Soldier2", _line(["Soldier1", "Soldier2"]), yours, director)
	assert_int(key.index).is_equal(1)
	yours["yaw"] = 999.0   # the recording keeps a COPY: the rig's next frame must not rewrite a key pose
	assert_float(recording.keyframes[0].yours["yaw"]).is_equal(45.0)
	assert_float(recording.keyframes[0].director["distance"]).is_equal(7.0)
	assert_float(key.pass_time).is_equal(10.25)
	assert_str(key.shot).is_equal("TRAINED")


func test_the_section_reads_as_a_table_and_replays_as_json() -> void:
	var recording := CameraRecording.new()
	recording.add(10.25, "TRAINED", "Soldier2", _line(["Soldier1", "Soldier2"]),
			_pose(45.0, -25.0, 9.0, Vector3(1.0, 2.0, 3.0)), _pose(0.0, -30.0, 7.0, Vector3(1.5, 2.0, 3.5)))
	recording.add(12.5, "STAGE", "", _line([]),
			_pose(90.0, -40.0, 12.0, Vector3.ZERO), _pose(0.0, -30.0, 11.0, Vector3.ZERO))
	var text := recording.render()
	assert_str(text).contains("| K1 | 10.25s | TRAINED (Soldier2) | Soldier1 → Soldier2 |")
	assert_str(text).contains("| K2 | 12.50s | STAGE | - |")
	var json_start := text.find("```json\n") + "```json\n".length()
	var json_end := text.find("\n```", json_start)
	var rows: Array = JSON.parse_string(text.substr(json_start, json_end - json_start))
	assert_int(rows.size()).override_failure_message("the JSON does not hold every key pose").is_equal(2)
	var first: Dictionary = rows[0]
	assert_float(first["yours"]["yaw"]).is_equal(45.0)
	assert_float(first["yours"]["pitch"]).is_equal(-25.0)
	assert_float(first["director"]["distance"]).is_equal(7.0)
	assert_array(first["yours"]["aim"]).is_equal([1.0, 2.0, 3.0])
	assert_array(first["yours"]["lift"]).override_failure_message(
			"the replay data lost the lift, so the camera's height cannot be rebuilt") \
		.is_equal([0.0, 40.0, 0.0])
	assert_array(first["line"]).is_equal(["Soldier1", "Soldier2"])


func test_nothing_recorded_prints_nothing_and_draws_no_sheet() -> void:
	var recording := CameraRecording.new()
	assert_str(recording.render()).is_empty()
	assert_object(recording.contact_sheet()).is_null()


func test_the_contact_sheet_keeps_every_key_pose_in_its_own_slot() -> void:
	var recording := CameraRecording.new()
	for i in 4:
		var key := recording.add(float(i), "TRAINED", "", _line([]), _pose(0, 0, 7, Vector3.ZERO), {})
		key.image = null if i == 1 else _image(Color(0.2 * i, 0.5, 0.5))
	var sheet := recording.contact_sheet()
	assert_object(sheet).is_not_null()
	var thumb := CameraRecording.THUMB_SIZE
	var gap := CameraRecording.SHEET_GAP
	assert_int(sheet.get_width()).is_equal(3 * thumb.x + 4 * gap)
	assert_int(sheet.get_height()).override_failure_message(
			"four key poses at three across is two rows").is_equal(2 * thumb.y + 3 * gap)
	# K2 has no picture, and its slot stays empty rather than K3 closing up into it.
	var k2_centre := Vector2i(gap + thumb.x + gap + thumb.x / 2, gap + thumb.y / 2)
	assert_bool(_is_background(sheet.get_pixelv(k2_centre))) \
		.override_failure_message("K3 slid into K2's slot, so the tiles no longer line up with K").is_true()
	var k3_centre := Vector2i(gap + 2 * (thumb.x + gap) + thumb.x / 2, gap + thumb.y / 2)
	assert_bool(_is_background(sheet.get_pixelv(k3_centre))).override_failure_message(
			"K3's own slot is empty -- its picture never reached the sheet").is_false()


# The sheet is 8-bit, so its background comes back quantised: compare within one step.
func _is_background(c: Color) -> bool:
	var bg := CameraRecording.SHEET_BACKGROUND
	return absf(c.r - bg.r) < 0.01 and absf(c.g - bg.g) < 0.01 and absf(c.b - bg.b) < 0.01


func test_no_pictures_means_no_sheet_and_a_full_recording_refuses() -> void:
	var recording := CameraRecording.new()
	for i in CameraRecording.MAX_KEYFRAMES:
		assert_object(recording.add(0.0, "WIDE", "", _line([]), {}, {})).is_not_null()
	assert_object(recording.contact_sheet()).override_failure_message(
			"a sheet of nothing but background was drawn").is_null()
	assert_object(recording.add(0.0, "WIDE", "", _line([]), {}, {})).override_failure_message(
			"a full recording took one more").is_null()
	recording.clear()
	assert_bool(recording.is_empty()).is_true()


# The Camera page's Delete (#705 slice 3). The rest move up a number, because a K number is also the
# key pose's slot on the contact sheet -- a gap would put K3's row beside the second picture.
func test_a_deleted_key_pose_closes_the_gap_and_every_change_moves_the_version() -> void:
	var recording := CameraRecording.new()
	var before := recording.version
	for yaw in [10.0, 20.0, 30.0]:
		recording.add(1.0, "WIDE", "", _line([]), _pose(yaw, -30.0, 8.0, Vector3.ZERO), {})
	assert_int(recording.version).override_failure_message("an add did not move the version") \
		.is_greater(before)
	var after_adds := recording.version
	assert_bool(recording.remove(2)).is_true()
	assert_int(recording.keyframes.size()).is_equal(2)
	assert_float(recording.keyframes[1].yours["yaw"]).override_failure_message(
			"Delete dropped the wrong key pose").is_equal(30.0)
	assert_int(recording.keyframes[1].index).override_failure_message(
			"the key pose after the deleted one kept its old number").is_equal(2)
	assert_int(recording.version).override_failure_message("a delete did not move the version") \
		.is_greater(after_adds)
	assert_bool(recording.remove(3)).override_failure_message("a K number past the end was deleted") \
		.is_false()
	assert_bool(recording.remove(0)).is_false()
	var after_remove := recording.version
	recording.clear()
	assert_int(recording.version).override_failure_message("a clear did not move the version") \
		.is_greater(after_remove)
