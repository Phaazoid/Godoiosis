# ForeignResource (#1555): may a file from outside the project be handed to Godot's loader? That
# loader runs code WHILE it parses, so the file is read first and anything not fully understood is
# refused.
#
# Two halves. The REFUSALS hand text to refusal_of: each is a way into the loader found in the 4.7.1
# source. The DOORS write a real file carrying the inert payload (tests/support/foreign_payload.gd,
# which only raises a flag) and hand it to the door that would load it, because whether code runs at
# parse time is the loader's behaviour and only the loader can show it. Every fixture lives under
# this suite's own user:// folder.
extends GdUnitTestSuite

const P := preload("res://tests/support/foreign_payload.gd")
const SCRATCH := "user://__test_foreign_resource/"
const SD := "res://Classes/flow/ScenarioData.gd"
const GONE := "res://Scenarios/__test_1555_no_such_file.tres"
const HEAD := ('[gd_resource type="Resource" script_class="ScenarioData" format=3]\n\n'
	+ '[ext_resource type="Script" path="res://Classes/flow/ScenarioData.gd" id="1_sd"]\n')
const BODY := '\n[resource]\nscript = ExtResource("1_sd")\nscenario_name = "Fixture"\n'


func before_test() -> void:
	P.lower()
	_wipe(SCRATCH)
	DirAccess.make_dir_recursive_absolute(SCRATCH)


func after_test() -> void:
	if DirAccess.dir_exists_absolute(SCRATCH):
		for file in DirAccess.get_files_at(SCRATCH):
			ContentRepair.forget(SCRATCH + file)
			_drop_repair_copy(SCRATCH + file)
	_wipe(SCRATCH)
	P.lower()


func _refusal(text: String) -> String:
	return ForeignResource.refusal_of(text.to_utf8_buffer())


func _assert_refused(text: String, why: String) -> void:
	assert_str(_refusal(text)).override_failure_message(
		"accepted a file that %s:\n%s" % [why, text]).is_not_empty()


func _write(name: String, text: String) -> String:
	P.write(SCRATCH + name, text)
	return SCRATCH + name


# res:// plus enough "../" to reach the filesystem root, then the target's absolute path: how a
# traversal names any file on the machine.
static func _climb_to(path: String) -> String:
	var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var target := ProjectSettings.globalize_path(path)
	var depth := project.substr(project.find("/") + 1).split("/", false).size()
	return "res://" + "../".repeat(depth) + target.substr(target.find("/") + 1)


static func _drop_repair_copy(path: String) -> void:
	var copy := ContentRepair.REPAIR_DIR + path.md5_text() + ".tres"
	if FileAccess.file_exists(copy):
		DirAccess.remove_absolute(copy)


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir + sub + "/")
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + file)
	DirAccess.remove_absolute(dir)


# ==============================================================================
#  What it accepts: what the saver writes
# ==============================================================================

# Every committed board, read as if it had arrived from outside: a capture of any of them is what a
# pulled run or a save slot carries, so one refused here is one the dev could not replay.
func test_every_committed_board_is_accepted() -> void:
	var boards: Array[String] = []
	_collect("res://Scenarios/", boards)
	assert_int(boards.size()).override_failure_message("fixture: found no boards to read").is_greater(0)
	for path in boards:
		assert_str(ForeignResource.refusal_of(FileAccess.get_file_as_bytes(path))).override_failure_message(
			"%s was refused" % path).is_empty()


func _collect(dir: String, out: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir + sub + "/", out)
	for file in ResourceDir.files_with_extension(dir, ".tres"):
		out.append(dir + file)


# The writer itself, over the value kinds a board can hold, and a string built to trip a boundary.
func test_what_resource_saver_writes_is_accepted() -> void:
	var board := ScenarioData.new()
	board.scenario_name = 'a "quoted" name\n[resource]\nscript = Object(GDScript); and \\ a backslash'
	var typed: Array[Vector2i] = [Vector2i(1, 2)]
	var keyed: Dictionary[String, int] = {"a": 1}
	board.set_meta("kinds", {
		"vec": Vector2i(3, -4), "vecs": [Vector3(1.5, -2e-7, 1e20)], "color": Color(0.1, 0.2, 0.3, 0.4),
		"name": &"a_name", "node": NodePath("a/b:c"), "bytes": PackedByteArray([0, 1, 255]),
		"xform": Transform3D.IDENTITY, "low": -INF, "nan": NAN, "rect": Rect2i(1, 2, 3, 4),
		"strings": PackedStringArray(["x", "y"]), "nested": {"a": [true, false, null]},
		"typed": typed, "keyed": keyed,
	})
	board.set_meta("embedded", ScenarioUnitEntry.new())
	var path := SCRATCH + "saved.tres"
	assert_int(ResourceSaver.save(board, path)).is_equal(OK)
	assert_str(ForeignResource.refusal(path)).override_failure_message(
		"refused what ResourceSaver wrote:\n%s" % FileAccess.get_file_as_string(path)).is_empty()


func test_only_a_plain_res_path_is_inside_the_project() -> void:
	assert_bool(ForeignResource.inside_project("res://Scenarios/missions/x.tres")).is_true()
	for path: String in ["user://x.tres", "C:/x.tres", "/x.tres", "res://../x.tres",
			"res://Scenarios/../../x.tres", "res:///x.tres", "res://C:/x.tres", "res://a\\..\\x.tres",
			"res://a//b.tres", "x.tres"]:
		assert_bool(ForeignResource.inside_project(path)).override_failure_message(
			"%s counted as the project's own" % path).is_false()


# ==============================================================================
#  What it refuses: the six shapes the repro ran
# ==============================================================================

func test_an_embedded_script_is_refused() -> void:
	_assert_refused(HEAD + '\n[sub_resource type="GDScript" id="g"]\nscript/source = "%s"\n' % P.escaped()
		+ '\n[resource]\nscript = SubResource("g")\n', "embeds a GDScript")


func test_an_inline_object_is_refused() -> void:
	_assert_refused(HEAD + BODY + "metadata/p = %s\n" % P.object_value(), "constructs an Object")


func test_an_inline_resource_path_is_refused() -> void:
	_assert_refused(HEAD + BODY + 'metadata/p = Resource("user://x.gd")\n', "loads a path inline")
	_assert_refused(HEAD + BODY + 'metadata/p = Array[Resource("user://x.gd")]([])\n',
		"loads a path as an array's type")


func test_an_ext_resource_outside_the_project_is_refused() -> void:
	for path: String in [ProjectSettings.globalize_path(SCRATCH + "x.gd"), "user://x.tres",
			_climb_to(SCRATCH + "x.tres"), "x.tres"]:
		_assert_refused(HEAD + '[ext_resource type="Resource" path="%s" id="2"]\n' % path + BODY,
			"references %s" % path)


func test_a_script_outside_classes_is_refused() -> void:
	_assert_refused(HEAD + '[ext_resource type="Script" path="res://game.gd" id="2"]\n' + BODY
		+ 'metadata/p = ExtResource("2")\n', "references a script outside Classes/")


# The loader prefers a registered uid over path=, so a good path cannot vouch for it.
func test_a_uid_that_leads_outside_classes_is_refused() -> void:
	var uid := ResourceLoader.get_resource_uid("res://game.gd")
	assert_bool(uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid)).override_failure_message(
		"fixture: game.gd has no registered uid, so nothing here is redirected").is_true()
	_assert_refused(HEAD + '[ext_resource type="Script" uid="%s" path="%s" id="2"]\n'
		% [ResourceUID.id_to_text(uid), SD] + BODY + 'metadata/p = ExtResource("2")\n',
		"redirects through a uid")


# ==============================================================================
#  What it refuses: what the engine's tokenizer reads differently from a naive one
# ==============================================================================

func test_what_could_move_a_string_boundary_is_refused() -> void:
	_assert_refused(HEAD + BODY + 'metadata/p = 1 ;"\n', "carries a comment")
	_assert_refused(HEAD + '\n[sub_resource type="GDScr\\ipt" id="g"]\n' + BODY, "escapes a type")
	_assert_refused(HEAD + '\n[sub_resource type=&"GDScript" id="g"]\n' + BODY, "names a type as a StringName")
	_assert_refused(HEAD + BODY.replace("scenario_name", "\u00e9"), "has a non-ASCII property name")
	_assert_refused(HEAD + BODY + "metadata/p = [1eObject(GDScript, {})]\n", "hides a constructor behind a number")
	var with_nul := (HEAD + BODY + "metadata/p = 1").to_utf8_buffer()
	with_nul.append(0)
	assert_str(ForeignResource.refusal_of(with_nul)).override_failure_message("accepted a NUL").is_not_empty()


# The engine skips whitespace inside a property name and takes a quoted one, so neither may hide a
# `script` from the check.
func test_a_disguised_script_property_is_refused() -> void:
	var sub := '\n[sub_resource type="Resource" id="s"]\n'
	_assert_refused(HEAD + sub + BODY.replace('script = ExtResource("1_sd")', 'scr ipt = SubResource("s")'),
		"splits the script key")
	_assert_refused(HEAD + sub + BODY.replace('script = ExtResource("1_sd")', '"script" = SubResource("s")'),
		"quotes the script key")


func test_what_the_loader_would_not_read_is_refused() -> void:
	_assert_refused(HEAD + '\n[sub_resource type="Gradient" id="g"]\n' + BODY, "embeds a non-Resource")
	_assert_refused(HEAD + BODY + 'resource_path = "res://Scenarios/x.tres"\n', "claims a project path")
	_assert_refused(BODY, "has no header")
	_assert_refused(HEAD + HEAD + BODY, "has two headers")
	_assert_refused(HEAD + BODY + '[sub_resource type="Resource" id="late"]\n', "has a section after [resource]")
	# The loader never reads a property after an ext_resource; a line reader would.
	_assert_refused(HEAD + '[ext_resource type="Resource" path="%s" id="2"] path="user://x.tres"\n' % GONE
		+ BODY, "puts a property where the loader expects a section")


# ==============================================================================
#  The doors: the payload never runs
# ==============================================================================

func test_load_tolerant_refuses_a_file_from_outside() -> void:
	var path := _write("board.tres", HEAD + BODY + "metadata/p = %s\n" % P.object_value())
	assert_object(ContentRepair.load_tolerant(path)).is_null()
	assert_bool(P.ran()).override_failure_message("the board's payload ran").is_false()


# The repair reads ext_resource LINES, not the grammar, so a line inside a multi-line string reads as a
# reference to it. A file can pass the guard, fail its first load on a missing file, and hand that
# reader a path outside the project.
func test_the_repair_never_loads_a_line_outside_the_project() -> void:
	var smuggled := _write("smuggled.tres", P.resource_text())
	var path := _write("board.tres", HEAD + '[ext_resource type="Resource" path="%s" id="9_g"]\n' % GONE
		+ BODY + 'camera_start = ExtResource("9_g")\n'
		+ 'metadata/note = "\n[ext_resource type=" path="%s"\n' % smuggled)
	assert_str(ForeignResource.refusal(path)).override_failure_message(
		"fixture: the guard refuses this file, so the repair is never reached").is_empty()
	ContentRepair.load_tolerant(path)
	assert_bool(P.ran()).override_failure_message("the repair loaded a file named only inside a string").is_false()


# Taking a reference out is a text edit, and a tag split across lines loses its opening quote with the
# line: every quote after it changes sides. What would be loaded is asked again, and never written.
func test_a_repair_that_moves_a_string_boundary_is_not_loaded() -> void:
	var path := _write("board.tres", HEAD
		+ '[ext_resource type="Resource" path="%s" id="9_g" uid="\n"]\n' % GONE
		+ BODY + 'camera_start = ExtResource("9_g")\n')
	assert_str(ForeignResource.refusal(path)).override_failure_message(
		"fixture: the guard refuses this file, so the repair is never reached").is_empty()
	_drop_repair_copy(path)
	assert_object(ContentRepair.load_tolerant(path)).is_null()
	assert_bool(FileAccess.file_exists(ContentRepair.REPAIR_DIR + path.md5_text() + ".tres")) \
		.override_failure_message("the repaired text was written out to be loaded").is_false()


# A board names its look preset; the name composes a path, and "../" leaves the presets folder.
func test_a_look_preset_name_cannot_climb_out() -> void:
	var target := _write("preset.tres", P.resource_text())
	var name := "../../" + _climb_to(target).trim_prefix("res://").trim_suffix(".tres")
	assert_bool(ResourceLoader.exists(LookKnobs.preset_path(name))).override_failure_message(
		"fixture: the climb does not reach the file, so resolve stops before the guard").is_true()
	assert_object(LookKnobs.resolve(name)).is_same(LookKnobs.default_preset())
	assert_bool(P.ran()).override_failure_message("the preset's payload ran").is_false()
