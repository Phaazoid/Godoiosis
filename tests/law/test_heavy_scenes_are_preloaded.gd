# A test suite must PRELOAD Battle3D/LookDev, never load() them per test (#621).
#
# Both scenes hang off lookdev_meshlib.tres, which #427's corner forms grew to 5 MB / 2089
# ArrayMesh sub-resources. A suite that load()s the scene in before_test and frees it in
# after_test drops the library's last reference every case, so it reloads for the next one.
# Measured cost of that: 19.7s -> 6.0s on test_camera_rig alone, and it applied to 30 suites.
#
# WHY THIS IS A LAW AND NOT A COMMENT: the failure is INVISIBLE. Reverting a preload back to
# load() reds nothing -- every case still passes, the suite is just slower. #427 shipped this
# regression on 2026-08-24 and it went unnoticed for two weeks; it surfaced only because
# someone asked how long CI takes. Nothing in a green suite can notice lost speed, so the
# spelling is the only surface left to guard.
#
# It IS a spelling check and not a property check, deliberately. The direct version -- assert
# the library is still ResourceLoader.has_cached() after a scene free -- depends on what ran
# before it, and #620 made test order vary by shard. That test would be flaky for exactly the
# reason sharding was worth doing.
extends GdUnitTestSuite

# The scenes that carry the mesh library. A third scene reaching it belongs in this list.
const HEAVY_SCENES: Array[String] = [
	"res://Scenes/LookDev/LookDev.tscn",
	"res://Scenes/Battle3D/Battle3D.tscn",
]

# test_boot_scene asserts that run/main_scene RESOLVES to the boot scene, which is a runtime
# question about a project setting -- preloading would answer a different one, and it loads
# once for the whole suite rather than per test, so it never pays the reload anyway.
const EXEMPT: Array[String] = ["res://tests/law/test_boot_scene.gd"]

# This file names the heavy paths as DATA, so scanning it would let the non-vacuity guard below
# satisfy ITSELF -- caught by mutant: with HEAVY_SCENES pointed at paths nothing uses, the law
# still passed green because it found its own constants.
const SELF := "res://tests/law/test_heavy_scenes_are_preloaded.gd"

# A #622 SharedBoard suite passes this law WITHOUT an exemption, and that is the right outcome
# rather than a loophole: it hands SCENE_PATH to SharedBoard, which loads once per SUITE instead
# of once per case, so the rule -- do not re-read a heavy scene per case -- is satisfied. Sharing
# also kills the _ready cascade this law cannot touch, so it is the STRONGER fix where a suite has
# been converted; preloading is the floor for the ones that have not.
#
# THAT ARGUMENT HAS A HOLE THIS SCANNER CANNOT SEE, and SharedBoard closes it at its own end rather
# than here. It holds the path in a VARIABLE, so the literal-load check below never looks at it --
# and IOSIS_FRESH_FIXTURE=1 makes the same file rebuild PER CASE, which is exactly the pattern this
# law exists to forbid. Measured: board_mirror fresh 63.9s +/- 0.6, i.e. unmoved by #621, against
# 12.5s shared. SharedBoard now keeps a process-lifetime PackedScene cache (its `_packed`), which
# is what a preload does, and fresh fell to 19.4s +/- 0.1. Two consequences worth carrying: the
# TRUE cost of sharing over preloading is 1.56x rather than the 5.11x the uncached comparison
# showed, and a load() whose argument is not a literal is a blind spot of this check by
# construction -- widening the match to catch it would flag every legitimate dynamic load in the
# suite, so the guard is the reviewer knowing this paragraph exists.


func test_no_suite_load_s_a_heavy_scene_per_test() -> void:
	var scanned := 0
	var referencing := 0
	var offenders: PackedStringArray = []

	for file: String in _test_scripts("res://tests"):
		if EXEMPT.has(file) or file == SELF:
			continue
		scanned += 1
		var text := FileAccess.get_file_as_string(file)

		var mentions := false
		for scene: String in HEAVY_SCENES:
			if text.contains(scene):
				mentions = true
				if _has_bare_load(text, "\"%s\"" % scene):
					offenders.append("%s: load(\"%s\")" % [file, scene])
		for name: String in _const_names_holding_a_heavy_path(text):
			if _has_bare_load(text, name):
				offenders.append("%s: load(%s)" % [file, name])
		if mentions:
			referencing += 1

	assert_array(offenders).override_failure_message(
		"These suites load() a heavy scene, so its 5 MB mesh library reloads on every case: %s. "
		% ", ".join(offenders)
		+ "Hold it instead -- `const SCENE: PackedScene = preload(\"res://...\")` -- so the "
		+ "library survives after_test's free(). See #621."
	).is_empty()

	# Non-vacuity, both halves. A scan that found no files, or no file mentioning a heavy scene,
	# means HEAVY_SCENES or the root is wrong -- not that the repo is clean.
	assert_int(scanned).override_failure_message(
		"scanned no test scripts at all -- the res://tests walk is broken, not the repo"
	).is_greater(0)
	assert_int(referencing).override_failure_message(
		"no suite mentions any of %s -- those paths moved, so this law now guards nothing"
		% str(HEAVY_SCENES)
	).is_greater(0)


func test_the_exempt_suite_still_exists() -> void:
	# An exemption naming a file that moved stops applying SILENTLY: the renamed file becomes an
	# offender and reds the case above with a reason that is not the real one.
	for file: String in EXEMPT:
		assert_bool(FileAccess.file_exists(file)).override_failure_message(
			"%s is exempt from the preload law but does not exist -- it moved; update EXEMPT"
			% file).is_true()


# `preload(` ends in `load(` too, and the difference between them is the entire law -- so a match
# whose three preceding characters are "pre" is the CORRECT spelling, not an offender.
func _has_bare_load(text: String, argument: String) -> bool:
	var needle := "load(%s)" % argument
	var at := text.find(needle)
	while at != -1:
		if at < 3 or text.substr(at - 3, 3) != "pre":
			return true
		at = text.find(needle, at + 1)
	return false


# Which const names in this file hold a heavy scene PATH, so `load(THAT_NAME)` can be caught as
# well as the literal. Spelling the path into a constant is the common shape, not the exception.
func _const_names_holding_a_heavy_path(text: String) -> PackedStringArray:
	var names: PackedStringArray = []
	for line: String in text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("const "):
			continue
		for scene: String in HEAVY_SCENES:
			if not trimmed.contains("\"%s\"" % scene):
				continue
			var rest := trimmed.substr(6).strip_edges()
			var cut := rest.length()
			for separator: String in [":=", ":", "="]:
				var found := rest.find(separator)
				if found != -1 and found < cut:
					cut = found
			var name := rest.substr(0, cut).strip_edges()
			if not name.is_empty() and not names.has(name):
				names.append(name)
	return names


func _test_scripts(root: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var pending: PackedStringArray = [root]
	while not pending.is_empty():
		var current := pending[pending.size() - 1]
		pending.remove_at(pending.size() - 1)
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := current.path_join(entry)
			if dir.current_is_dir():
				pending.append(full)
			elif entry.ends_with(".gd"):
				found.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	return found
