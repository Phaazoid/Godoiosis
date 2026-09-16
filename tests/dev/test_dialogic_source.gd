# DialogicSource (#982): creating and registering a Dialogic resource from the running overlay.
#
# EVERY CASE WRITES TO user://. project.godot is read as a REALISTIC FIXTURE and never written --
# CI's project-settings guard runs BEFORE the tests, so a suite that dirtied the committed file
# would go unseen there and dirty the dev's tree here. The two LIVE stores (ProjectSettings and
# the Engine meta Dialogic caches in) are process-global, so they are snapshotted and restored
# around every case.
extends GdUnitTestSuite

const SETTINGS_FIXTURE := "res://project.godot"
const SETTINGS_COPY := "user://test_dialogic_source_project.godot"
const SCRATCH_DIR := "user://test_dialogic_source"
const SCRATCH_DTL := "user://test_dialogic_source/scratch.dtl"
const SCRATCH_REFERRER := "user://test_dialogic_source/referrer.tres"

var _settings_before := {}
var _meta_before := {}


# has_meta before get_meta, and before remove_meta: Engine.get_meta(name, null) does NOT fall
# back to the default, it ERRORS, and removing an absent key errors too.
func before_test() -> void:
	for extension: String in ["dtl", "dch"]:
		_settings_before[extension] = DialogicSource.directory(extension).duplicate()
		var key := "%s_directory" % extension
		if Engine.has_meta(key):
			_meta_before[extension] = Engine.get_meta(key)
		else:
			_meta_before[extension] = null


func after_test() -> void:
	for extension: String in ["dtl", "dch"]:
		ProjectSettings.set_setting("dialogic/directories/%s_directory" % extension,
			_settings_before[extension])
		var key := "%s_directory" % extension
		if _meta_before[extension] == null:
			if Engine.has_meta(key):
				Engine.remove_meta(key)
		else:
			Engine.set_meta(key, _meta_before[extension])
	for path: String in [SETTINGS_COPY, SCRATCH_DTL, SCRATCH_DTL + ".uid", SCRATCH_REFERRER]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _fixture() -> String:
	return FileAccess.get_file_as_string(SETTINGS_FIXTURE)


func _settings_copy() -> String:
	var source := _fixture()
	var file := FileAccess.open(SETTINGS_COPY, FileAccess.WRITE)
	file.store_string(source)
	file.close()
	return source


# --- the registry block ---

# The whole point of the rewrite: one line changes and nothing else moves. Falsified by removing
# the entry again -- a rewrite that reflowed the block could not come back byte-identical.
func test_an_inserted_entry_leaves_every_other_byte_alone() -> void:
	var source := _fixture()
	var grown := DialogicSource.insert_entry(source, "dtl", "aaa_probe", "res://Scenarios/dialog/aaa_probe.dtl")
	assert_str(grown).is_not_equal("")
	assert_int(grown.length()).is_greater(source.length())
	assert_str(DialogicSource.remove_entry(grown, "dtl", "aaa_probe")).is_equal(source)


# APPENDS, never sorts -- plugin.gd's _build() appends on the editor's next Play, and matching
# that order is what keeps the file from churning. 'aaa_probe' would sort FIRST, so a sorting
# implementation cannot pass this.
func test_a_new_entry_lands_last_not_sorted() -> void:
	var grown := DialogicSource.insert_entry(_fixture(), "dtl", "aaa_probe",
		"res://Scenarios/dialog/aaa_probe.dtl")
	var block_start := grown.find("directories/dtl_directory=")
	var block := grown.substr(block_start, grown.find("}", block_start) - block_start)
	var names := PackedStringArray()
	for line: String in block.split("\n", false):
		if line.begins_with("\""):
			names.append(line.get_slice("\"", 1))
	assert_int(names.size()).is_greater(1)
	assert_str(names[names.size() - 1]).is_equal("aaa_probe")


func test_a_taken_name_is_refused_rather_than_overwritten() -> void:
	assert_str(DialogicSource.insert_entry(_fixture(), "dtl", "quarry_intro", "res://elsewhere.dtl")) \
		.is_equal("")


func test_removing_a_name_that_is_not_there_is_refused() -> void:
	assert_str(DialogicSource.remove_entry(_fixture(), "dtl", "no_such_timeline")).is_equal("")


# --- registration writes all three stores ---

func test_register_writes_the_file_the_settings_and_dialogics_cache() -> void:
	_settings_copy()
	var path := "res://Scenarios/dialog/aaa_probe.dtl"
	assert_bool(DialogicSource.register("dtl", "aaa_probe", path, SETTINGS_COPY)).is_true()

	assert_str(FileAccess.get_file_as_string(SETTINGS_COPY)).contains("\"aaa_probe\": \"%s\"" % path)
	assert_bool(DialogicSource.directory("dtl").has("aaa_probe")).is_true()
	var cached: Dictionary = Engine.get_meta("dtl_directory", {})
	assert_bool(cached.has("aaa_probe")).is_true()


func test_unregister_takes_it_back_out_of_all_three() -> void:
	var source := _settings_copy()
	DialogicSource.register("dtl", "aaa_probe", "res://Scenarios/dialog/aaa_probe.dtl", SETTINGS_COPY)
	assert_bool(DialogicSource.unregister("dtl", "aaa_probe", SETTINGS_COPY)).is_true()

	assert_str(FileAccess.get_file_as_string(SETTINGS_COPY)).is_equal(source)
	assert_bool(DialogicSource.directory("dtl").has("aaa_probe")).is_false()
	var cached: Dictionary = Engine.get_meta("dtl_directory", {})
	assert_bool(cached.has("aaa_probe")).is_false()


# --- timeline text ---

# THE ESCAPING CASE. The parser's name group runs to the first unescaped colon, so a narration
# line holding one would come back as a speaker named 'Look' -- a fabricated character at
# runtime and a red law suite. A "%s: %s" serializer cannot pass this.
func test_a_narration_line_holding_a_colon_round_trips_speakerless() -> void:
	var written := DialogicSource.timeline_text([{"speaker": "", "text": "Look: the bridge"}])
	var timeline := DialogicTimeline.new()
	timeline.from_text(written)
	var read := DialogicSource.read_timeline(timeline)

	assert_bool(read["editable"]).is_true()
	var lines: Array = read["lines"]
	assert_int(lines.size()).is_equal(1)
	assert_str(String(lines[0]["speaker"])).is_equal("")
	assert_str(String(lines[0]["text"])).is_equal("Look: the bridge")


func test_a_named_speaker_round_trips_as_itself() -> void:
	var written := DialogicSource.timeline_text([{"speaker": "torv", "text": "Mind the drop."}])
	var timeline := DialogicTimeline.new()
	timeline.from_text(written)
	var read := DialogicSource.read_timeline(timeline)

	assert_bool(read["editable"]).is_true()
	var lines: Array = read["lines"]
	assert_str(String(lines[0]["speaker"])).is_equal("torv")
	assert_str(String(lines[0]["text"])).is_equal("Mind the drop.")


# A speaker no .dch answers to is NOT editable: from_text fabricates a character for one, and
# re-saving a fabrication would write the invention to disk.
func test_an_unregistered_speaker_is_refused_rather_than_re_saved() -> void:
	var timeline := DialogicTimeline.new()
	timeline.from_text("nobody: Who am I.")
	var read := DialogicSource.read_timeline(timeline)

	assert_bool(read["editable"]).is_false()
	assert_str(String(read["reason"])).contains("nobody")


# --- the sidecar ---

func test_a_written_file_gets_a_uid_sidecar_ci_would_otherwise_fail_on() -> void:
	assert_bool(DialogicSource.write(SCRATCH_DTL, "torv: A line.")).is_true()
	assert_bool(FileAccess.file_exists(SCRATCH_DTL + ".uid")).is_true()
	assert_str(FileAccess.get_file_as_string(SCRATCH_DTL + ".uid").strip_edges()) \
		.starts_with("uid://")


# --- delete ---

# A timeline is an ext_resource BY PATH, so deleting a referenced one makes that mission a hard
# parse error.
#
# ENTIRELY SCRATCH, and that is the point rather than tidiness: the first version aimed a real
# delete at causeway_intro, which passed against the real code and DELETED THE SHIPPED TIMELINE
# the moment the guard was mutated out. A case whose failure mode is destroying authored content
# is not a test, so the referrer is stood up under user:// and `scan_dir` points the scan at it.
func test_delete_refuses_a_timeline_something_still_names() -> void:
	_settings_copy()
	DialogicSource.write(SCRATCH_DTL, "torv: A line.")
	ProjectSettings.set_setting("dialogic/directories/dtl_directory", {"probe": SCRATCH_DTL})
	var referrer := SCRATCH_REFERRER
	var file := FileAccess.open(referrer, FileAccess.WRITE)
	file.store_string('[ext_resource type="Resource" path="%s" id="1"]' % SCRATCH_DTL)
	file.close()

	var verdict := DialogicSource.delete("dtl", "probe", SETTINGS_COPY, SCRATCH_DIR)

	assert_bool(verdict["ok"]).is_false()
	assert_str(String(verdict["reason"])).contains(referrer.get_file())
	assert_bool(FileAccess.file_exists(SCRATCH_DTL)).is_true()


func test_delete_removes_an_unreferenced_timeline_with_its_sidecar_and_entry() -> void:
	_settings_copy()
	DialogicSource.write(SCRATCH_DTL, "torv: A line.")
	DialogicSource.register("dtl", "probe", SCRATCH_DTL, SETTINGS_COPY)

	var verdict := DialogicSource.delete("dtl", "probe", SETTINGS_COPY, SCRATCH_DIR)

	assert_bool(verdict["ok"]).is_true()
	assert_bool(FileAccess.file_exists(SCRATCH_DTL)).is_false()
	assert_bool(FileAccess.file_exists(SCRATCH_DTL + ".uid")).is_false()
	assert_bool(DialogicSource.directory("dtl").has("probe")).is_false()


# The real scan, READ-ONLY -- nothing here can write or remove. This is what pins that the
# default `scan_dir` actually reaches the missions folder, which the scratch cases cannot say.
func test_referencing_files_finds_the_mission_that_names_a_timeline() -> void:
	var found := DialogicSource.referencing_files("dtl", "causeway_intro")
	assert_int(found.size()).is_greater(0)
	assert_str(", ".join(found)).contains("TheCauseway.tres")


func test_an_unreferenced_timeline_has_no_blockers() -> void:
	_settings_copy()
	DialogicSource.register("dtl", "aaa_probe", "res://Scenarios/dialog/aaa_probe.dtl", SETTINGS_COPY)
	assert_int(DialogicSource.referencing_files("dtl", "aaa_probe").size()).is_equal(0)
