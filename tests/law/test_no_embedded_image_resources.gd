# Nothing committed may embed an Image sub-resource, and the generated ground atlas must import as a
# faithful passthrough (#540).
#
# An ImageTexture holding an Image cannot keep a stable sub-resource id: set_image() uploads to the
# RenderingServer and keeps no reference to what it was handed, so get_image() rebuilds an ANONYMOUS
# Image and the next save mints a fresh id. The file then goes dirty on any editor save that rewrites
# it -- which happened three times in lookdev_meshlib.tres's own history before the atlas moved out
# to a PNG referenced as an ext_resource. Only an ext_resource survives a save.
#
# The import half is the price of that fix: the atlas lives on disk now, so what keeps it faithful is
# authored in a .import file Godot is free to rewrite. detect_3d is the one that bites -- it arrives
# at 1 and silently rewrites compression AND mipmaps the first time the texture renders in 3D, and
# mipmaps on an atlas bleed neighbouring tiles into each other at distance. Art/LookDev/grass_top.png
# .import is what that looks like once it has fired.
extends GdUnitTestSuite

# The project's own content, matching tests/law/test_resource_uid_references.gd's roots: addons/ is
# vendored and .godot/ is cache.
const SCANNED_ROOTS: Array[String] = ["res://Scenes/", "res://Resources/", "res://Scenarios/"]

const ATLAS_DIR := "res://Art/LookDev"
const ATLAS_PREFIX := "ground_atlas_"
const MESHLIB_PATH := "res://Scenes/LookDev/lookdev_meshlib.tres"

# Every one of these is already the DEFAULT for a fresh PNG except detect_3d/compress_to, which
# arrives at 1. fix_alpha_border is here because it rewrites the RGB of transparent pixels: harmless
# on screen (the materials filter NEAREST and scissor their alpha, so those texels are never
# sampled), but it makes the imported atlas differ from the composed one, which is exactly what
# gen_lookdev_assets._write_atlas compares to catch a stale import.
const REQUIRED_IMPORT_PARAMS := {
	"compress/mode": "0",
	"mipmaps/generate": "false",
	"detect_3d/compress_to": "0",
	"process/fix_alpha_border": "false",
}


func test_no_committed_resource_embeds_an_Image_sub_resource() -> void:
	var scanned := 0
	var offenders: PackedStringArray = []
	for file: String in _scan():
		scanned += 1
		var text := FileAccess.get_file_as_string(file)
		for line: String in text.split("\n"):
			if line.begins_with("[sub_resource type=\"Image\"") \
					or line.begins_with("[sub_resource type=\"ImageTexture\""):
				offenders.append("%s: %s" % [file, line])
				break

	assert_array(offenders).override_failure_message(
		"These files embed an Image, so their sub-resource id is reminted on every save and the "
		+ "working tree goes dirty for no edit: %s. Write the pixels to a PNG and reference it as "
		% ", ".join(offenders)
		+ "an ext_resource, the way tools/lookdev/gen_lookdev_assets.gd writes the ground atlas."
	).is_empty()

	# Non-vacuity: an empty scan proves nothing, and SCANNED_ROOTS is the thing that would be wrong.
	assert_int(scanned).override_failure_message(
		"the scan found no resource files at all -- SCANNED_ROOTS is wrong, not the repo"
	).is_greater(0)


# The other half of "an editor save changes nothing": a uid the file is MISSING is one the editor
# would add, which dirties the tree exactly as a reminted sub-resource id does. Scoped to the
# generated library rather than the repo, deliberately -- 410 hand-authored ext_resource lines carry
# no uid, and whether those should is a different question from whether a REGENERATED artifact
# matches what the editor writes over it.
func test_every_reference_in_the_generated_meshlib_carries_its_uid() -> void:
	var checked := 0
	var bare: PackedStringArray = []
	for line: String in FileAccess.get_file_as_string(MESHLIB_PATH).split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		checked += 1
		if not line.contains(" uid=\""):
			bare.append(line)

	assert_array(bare).override_failure_message(
		"These references in %s carry no uid, so the editor will stamp one on its next save and "
		% MESHLIB_PATH
		+ "the tree goes dirty for no edit: %s. DevWidgets.restore_uids fills a reference the "
		% ", ".join(bare)
		+ "prior file never had from ResourceUID -- check that fallback still fires."
	).is_empty()

	assert_int(checked).override_failure_message(
		"%s has no ext_resource lines at all -- it did not load, or the atlas went back to being "
		% MESHLIB_PATH + "embedded"
	).is_greater(0)


func test_the_generated_ground_atlas_imports_as_a_faithful_passthrough() -> void:
	var checked := 0
	for name: String in ResourceDir.files_with_extension(ATLAS_DIR, ".png"):
		if not name.begins_with(ATLAS_PREFIX):
			continue
		var import_path := "%s/%s.import" % [ATLAS_DIR, name]
		assert_bool(FileAccess.file_exists(import_path)).override_failure_message(
			"%s has no committed .import, so Godot will author one with detect_3d on" % name
		).is_true()
		# \r stripped so a checkout under core.autocrlf cannot red every param at once, which is
		# what a CRLF rewrite of this file did while falsifying the case.
		var text := FileAccess.get_file_as_string(import_path).replace("\r", "")
		for key: String in REQUIRED_IMPORT_PARAMS:
			var want: String = REQUIRED_IMPORT_PARAMS[key]
			assert_str(text).override_failure_message(
				"%s must import with %s=%s. Without it the atlas stops being a faithful copy of "
				% [name, key, want]
				+ "what the generator composed -- and detect_3d in particular rewrites compression "
				+ "and mipmaps by itself the first time the texture renders in 3D."
			).contains("\n%s=%s\n" % [key, want])
		checked += 1

	# Non-vacuity, the same way: a renamed atlas would silently check nothing at all.
	assert_int(checked).override_failure_message(
		"no %s*.png found in %s -- the atlas moved or was renamed, and this law stopped asking "
		% [ATLAS_PREFIX, ATLAS_DIR]
		+ "about anything"
	).is_greater(0)


# Every .tscn/.tres under the scanned roots, recursively. Deliberately local rather than shared with
# test_resource_uid_references.gd: a directory listing is not a fact two answers can disagree about.
func _scan() -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = SCANNED_ROOTS.duplicate()
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub: String in dir.get_directories():
			pending.append(dir_path.path_join(sub) + "/")
		for file: String in dir.get_files():
			if file.ends_with(".tscn") or file.ends_with(".tres"):
				found.append(dir_path.path_join(file))
	return found
