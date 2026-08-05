extends Object
class_name ResourceDir

# One answer to "which resource files of this extension live in this folder?" (#141).
# DirAccess returns PACKED names in an exported build -- `Foo.tres.remap`, `Mage.png.import`
# -- so any scan filtering on a source extension matched nothing once exported.

const PACKED_SUFFIXES := [".remap", ".import"]

# Source-form filenames, de-duplicated and sorted; load() resolves them in both contexts.
# De-dup matters in the EDITOR, which holds both Mage.png and Mage.png.import.
static func files_with_extension(dir: String, extension: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return found
	for file: String in DirAccess.get_files_at(dir):
		var source_name := _source_name(file)
		if not source_name.ends_with(extension):
			continue
		if found.has(source_name):
			continue
		found.append(source_name)
	found.sort()
	return found

static func _source_name(file: String) -> String:
	for suffix: String in PACKED_SUFFIXES:
		if file.ends_with(suffix):
			return file.trim_suffix(suffix)
	return file
