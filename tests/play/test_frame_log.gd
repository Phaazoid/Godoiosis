# Frame persistence for the Play API bridge (#46): every rendered view lands as a numbered
# file under the run directory, so a playtest is replayable/auditable after the fact.
extends GdUnitTestSuite

const FrameLog := preload("res://play/frame_log.gd")

const BASE := "user://frame_log_test"

func after_test() -> void:
	var base_abs: String = ProjectSettings.globalize_path(BASE)
	var base := DirAccess.open(base_abs)
	if base == null:
		return
	for run in base.get_directories():
		var run_abs: String = base_abs.path_join(run)
		var run_dir := DirAccess.open(run_abs)
		for f in run_dir.get_files():
			DirAccess.remove_absolute(run_abs.path_join(f))
		DirAccess.remove_absolute(run_abs)
	DirAccess.remove_absolute(base_abs)

func test_frames_numbered_in_write_order() -> void:
	var frames := FrameLog.new(BASE, "t1")
	var p1: String = frames.record(1, true, "new", "board A")
	var p2: String = frames.record(2, true, "move", "board B")
	assert_str(p1).contains("0001-new.txt")
	assert_str(p2).contains("0002-move.txt")
	assert_bool(FileAccess.file_exists(p1)).is_true()
	assert_bool(FileAccess.file_exists(p2)).is_true()

func test_frame_carries_handshake_header_and_view() -> void:
	var frames := FrameLog.new(BASE, "t2")
	var path: String = frames.record(7, false, "attack", "the rendered view")
	var text: String = FileAccess.get_file_as_string(path)
	assert_str(text).contains("@@ frame=1 id=7 ok=0 cmd=attack @@")
	assert_str(text).contains("the rendered view")

func test_command_names_are_filename_safe() -> void:
	var frames := FrameLog.new(BASE, "t3")
	var path: String = frames.record(1, true, "weird cmd!", "x")
	assert_str(path).contains("0001-weird_cmd_.txt")
	assert_bool(FileAccess.file_exists(path)).is_true()

func test_runs_are_isolated_by_stamp() -> void:
	var a := FrameLog.new(BASE, "t4a")
	var b := FrameLog.new(BASE, "t4b")
	var pa: String = a.record(1, true, "new", "A")
	var pb: String = b.record(1, true, "new", "B")
	assert_str(pa).is_not_equal(pb)
	assert_str(FileAccess.get_file_as_string(pa)).contains("A")
	assert_str(FileAccess.get_file_as_string(pb)).contains("B")
