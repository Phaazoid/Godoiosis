# THE ARTIFACT WE SHIP WORKS (#868) -- the one property no other suite in this project can see.
#
# Everything else here runs from SOURCE, where `addons/` is present, `Foo.tres` is a real file and
# DirAccess returns source names. Three export-only breaks shipped in the three weeks to
# 2026-09-09 because every assumption they violated holds in the tree and fails only in the pack:
#
#   * #141   -- catalogs empty: scans filtered on source extensions the pack does not have
#   * PR #866 -- `addons/*` excluded, but Dialogic is the project's one RUNTIME autoload, so the
#               main scene's own script would not compile and the game had no title screen
#   * PR #867 -- load_tolerant asked FileAccess about a packed resource, so NOTHING authored loaded
#
# So this suite exports a real pack and runs it, in two shapes that catch different classes:
#
#   BOOT  -- start the pack's own main scene and require a clean log. Catches #866, which is loud
#            at startup (the autoload fails before anything else runs).
#   SMOKE -- run Scenes/Smoke/smoke.tscn, which loads every authored mission inside that pack.
#            Catches #867 and #141, which a BOOT CANNOT SEE: measured on the #867 build, a boot
#            exits 0 with a two-line log while the smoke reports 0 units and exits 1.
#
# NO EXPORT TEMPLATES ARE NEEDED, which is what makes this cheap enough to run every push:
# `--export-pack` writes resources only, never a platform executable, so CI needs just the engine
# binary it already caches. Measured with the templates directory hidden: exit 0, same pack size.
#
# THE COST OF THAT: a pack booted by the ENGINE binary answers TRUE to OS.has_feature("editor"),
# so DevTools.enabled() is true and #860's shipped-build branch is NOT exercised here. Closing that
# needs a real platform binary and therefore the templates; deliberately deferred, and named on
# #868 rather than left for someone to discover.
extends GdUnitTestSuite

const PRESET := "Windows Desktop"
const SMOKE_SCENE := "res://Scenes/Smoke/smoke.tscn"

# Dot-prefixed and already gitignored, so the pack can never dirty the tree and Godot's own scanner
# skips the directory. The CI job uploads it from here.
const OUT_DIR := "res://.export/"
const OUT_PACK := OUT_DIR + "smoke.pck"

# WHERE THE PACKED RUN IS TOLD TO STAND, and it is load-bearing rather than tidiness. OS.execute
# gives the child THIS process's working directory -- the project root -- and a Godot that finds a
# project.godot beside it mounts THAT as res://, source tree and all, even with --main-pack given.
# The pack is then window dressing: every packed-vs-source difference this suite exists to catch
# reads as absent. Caught by falsification, not by review -- the #867 mutant PASSED until this
# landed, because the child was reading the fixed source off disk. An empty directory has no
# project to prefer, so the pack is the only res:// there is.
const HOST_DIR := "user://.export_smoke_host/"

# A hard frame backstop on the driven run. SAFE only because the driver must print its contract
# line: a process that hangs and is then cut off prints neither OK nor FAIL, so the assertions
# below fail rather than passing on a quiet exit.
const QUIT_AFTER_FRAMES := "3000"

# Error text a clean run legitimately prints. SHORT and justified by construction, never a
# wildcard -- a growing list here is the signal that something real is being tolerated.
const ALLOWED_ERRORS: Array[String] = [
	# Authored on purpose: the two-knob rune rules reject this combination, and the rejection is
	# the feature. It is a push_error rather than a warning by the rune system's own convention.
	"steam: illegal under the two-knob rune rules",
]


func _project_dir() -> String:
	return ProjectSettings.globalize_path("res://")


func _run(args: PackedStringArray) -> Dictionary:
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	return {"code": code, "out": "\n".join(out)}


# An empty directory for a packed run to stand in -- see HOST_DIR. Made fresh and left empty:
# anything with a project.godot in it defeats the whole suite.
func _host_dir() -> String:
	var dir := ProjectSettings.globalize_path(HOST_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	assert_bool(FileAccess.file_exists(HOST_DIR + "project.godot")).override_failure_message(
		"%s contains a project.godot, so a packed run would mount IT instead of the pack."
		% HOST_DIR).is_false()
	return dir


# Boot the exported pack, standing somewhere that is not this project.
func _run_pack(extra: PackedStringArray) -> Dictionary:
	var args := PackedStringArray([
		"--headless", "--path", _host_dir(),
		"--main-pack", ProjectSettings.globalize_path(OUT_PACK)])
	args.append_array(extra)
	return _run(args)


# Every ERROR line the output carries, minus the allowlist.
func _errors(text: String) -> Array[String]:
	var found: Array[String] = []
	for line: String in text.split("\n"):
		if not (line.contains("ERROR:") or line.contains("SCRIPT ERROR:")):
			continue
		var allowed := false
		for ok: String in ALLOWED_ERRORS:
			if line.contains(ok):
				allowed = true
				break
		if not allowed:
			found.append(line.strip_edges())
	return found


# ONE export, reused by both cases: it is the slow step (~40s) and the two shapes are questions
# about the SAME artifact, so exporting twice would also weaken the claim.
static var _pack_ready := false


func before_test() -> void:
	if _pack_ready:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var pack := ProjectSettings.globalize_path(OUT_PACK)
	var result := _run(PackedStringArray([
		"--headless", "--path", _project_dir(), "--export-pack", PRESET, pack]))
	assert_int(result["code"] as int).override_failure_message(
		"Export failed:\n%s" % result["out"]).is_equal(0)
	assert_bool(FileAccess.file_exists(OUT_PACK)).override_failure_message(
		"Export reported success but wrote no pack at %s" % OUT_PACK).is_true()
	_pack_ready = true


func test_the_packed_build_boots_its_own_main_scene_cleanly() -> void:
	var result := _run_pack(PackedStringArray(["--quit-after", "400"]))
	assert_array(_errors(result["out"] as String)).override_failure_message(
		"The exported build logs errors on a plain boot. This is the shape that catches an "
		+ "excluded runtime addon (PR #866).\n%s" % result["out"]).is_empty()
	assert_int(result["code"] as int).is_equal(0)


func test_every_authored_mission_loads_inside_the_packed_build() -> void:
	var result := _run_pack(PackedStringArray([SMOKE_SCENE, "--quit-after", QUIT_AFTER_FRAMES]))
	var text: String = result["out"]

	# The contract line FIRST: without it a hang cut off by --quit-after would exit 0 and read as
	# a pass. Its absence is a failure whatever the exit code says.
	assert_bool(text.contains(ExportSmoke.OK_LINE)).override_failure_message(
		"The packed build did not report '%s'. A boot alone cannot catch this class -- see the "
		% ExportSmoke.OK_LINE + "suite header.\n%s" % text).is_true()
	assert_int(result["code"] as int).override_failure_message(
		"The smoke driver exited %s.\n%s" % [result["code"], text]).is_equal(0)
