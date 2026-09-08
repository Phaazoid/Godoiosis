# TelemetryStore (#53) -- the anonymous install id and the file a run writes to. Pure statics
# over a scratch folder; every case starts from reset_for_test() and the disk cases opt back in.
extends GdUnitTestSuite

const SCRATCH_ROOT := "user://__telemetry_store_test/"


func before_test() -> void:
	TelemetryStore.reset_for_test()
	TelemetryStore.root = SCRATCH_ROOT
	_wipe(SCRATCH_ROOT)


func after_test() -> void:
	_wipe(SCRATCH_ROOT)
	TelemetryStore.reset_for_test()


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir + sub + "/")
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + file)
	DirAccess.remove_absolute(dir)


func test_a_new_id_is_sixteen_hex_characters_and_never_repeats() -> void:
	var a := TelemetryStore.new_id()
	var b := TelemetryStore.new_id()
	assert_int(a.length()).is_equal(16)
	assert_bool(a.is_valid_hex_number(false)).is_true()
	assert_str(a).is_not_equal(b)


func test_the_install_id_is_stable_within_a_process() -> void:
	assert_str(TelemetryStore.install_id()).is_equal(TelemetryStore.install_id())


func test_the_install_id_survives_a_relaunch_when_persisted() -> void:
	TelemetryStore.persistence_enabled = true
	var first := TelemetryStore.install_id()
	TelemetryStore._install_id = ""   # the next process starts with nothing in memory
	assert_str(TelemetryStore.install_id()).override_failure_message(
		"the id is generated ONCE per install and read back from disk").is_equal(first)


func test_with_persistence_off_the_id_lives_only_in_memory() -> void:
	var id := TelemetryStore.install_id()
	assert_str(id).is_not_equal("")
	assert_bool(FileAccess.file_exists(TelemetryStore.config_path())).is_false()


func test_a_run_file_opens_under_pending_and_is_null_without_persistence() -> void:
	assert_object(TelemetryStore.open_run_file("run")).is_null()
	TelemetryStore.persistence_enabled = true
	var file := TelemetryStore.open_run_file("run")
	assert_object(file).is_not_null()
	file.store_line("{}")
	file.close()
	assert_bool(FileAccess.file_exists(TelemetryStore.run_dir("run") + "events.jsonl")).is_true()
