extends Object
class_name ContentRepair

# One answer to "load this content even though a reference in it is missing" (#608).
#
# Godot gives us no choice about WHERE this happens. A dangling `ext_resource` is a hard PARSE
# error -- measured, not assumed: the loader prints `[ext_resource] referenced non-existent
# resource` and `load()` returns null for the WHOLE file, then for everything referencing it. So
# there is no "let that property come back null" to reach for; the text has to be repaired before
# Godot parses it.
#
# Why it exists at all: the dev tools live INSIDE the running game. Content that refuses to load
# takes the Unit and Item Editors down with it, which are the only surfaces that could repair it --
# so a deleted .tres locked the dev out of fixing his own content (dev, 2026-08-27). Degraded-but-
# open beats correct-but-unreachable.
#
# The repaired copy is NOT a silent success. `dropped_properties()` is what DevWidgets.save_over
# refuses on and what BoardLint reports, because a resource that quietly lost a reference and then
# gets saved writes the loss into the file -- the same silent class this whole arc is about.

const REPAIR_DIR := "user://__repaired/"

# resource_path -> {"missing": Array[String], "properties": Array[String]}
static var _repairs: Dictionary = {}


# Paths currently being repaired, so a reference cycle cannot recurse forever.
static var _visiting: Dictionary = {}


# The normal path costs one load and nothing else: a file that parses is returned untouched.
#
# THE EXISTENCE QUESTION IS ResourceLoader'S, NOT FileAccess'S. An exported pack stores
# `Foo.tres.remap` and NO `Foo.tres`, so `FileAccess.file_exists` answers FALSE for every packed
# resource -- and this function returned null before ever trying to load one. That is #141's family
# one layer down (`ResourceDir` fixed the DirAccess half; this is the FileAccess half), and because
# `ResourceCatalog` and `ScenarioManager.load_scenario` both come through here, an exported build
# had EMPTY CATALOGS AND UNLOADABLE MISSIONS from #608 (2026-08-27) until this line changed.
# `ResourceLoader.exists` resolves the remap; `ResourceLoader.load` then returns the resource.
static func load_tolerant(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path)
	if res != null:
		_repairs.erase(path)   # a clean load supersedes any earlier repair of the same path
		return res

	# EVERYTHING BELOW REPAIRS BY READING THE FILE AS TEXT, which only a source tree can do: a pack
	# holds no `.tres` to parse and nothing a rewrite could land on. A packed resource that will not
	# load is broken content, not damaged content, so fail honestly rather than half-repair.
	if not FileAccess.file_exists(path):
		return null

	# #596's actual shape was a CHAIN -- Level_1 -> Noemie -> a weapon that was gone. The middle
	# file exists, so this file's own references all look fine while it still refuses to load.
	# Repair the children first: each one claims its real path (take_over_path), which puts it in
	# Godot's resource cache, so the retry below resolves it from memory instead of from disk.
	# Held until the retry completes: a repaired child is refcounted, and dropping the reference
	# frees it AND its cache entry, so the parent would re-read the broken file from disk.
	var kept: Array[Resource] = []
	if _repair_children(path, kept):
		res = ResourceLoader.load(path)
		if res != null:
			return res
	return _repair(path)


# WHY A LOAD FAILED, WITHOUT LOADING ANYTHING (#871). Every ext_resource in this file that will not
# resolve, whatever its type -- the diagnosis on its own, so a caller can NAME what is gone rather
# than report only that something was.
#
# Deliberately NOT _dangling(): that one answers the narrower "what can be STRIPPED", and returns
# nothing at all when the missing reference is a Script, because stripping a script would change
# what the resource IS. The script case is exactly the one a caller needs named.
#
# ResourceLoader.exists, never FileAccess.file_exists: an exported pack stores Foo.tres.remap and no
# Foo.tres, so the FileAccess question answers "missing" for every packed resource (#867), and
# Classes/dev/ is not in export_presets.cfg's exclude list -- the Replay tab ships. It is also the
# question a caller actually has: an unimported .png and a .dtl with no format loader are both ON
# DISK and still will not load, which is why this reports what CANNOT LOAD rather than what is gone.
#
# NOT NECESSARILY WHAT BROKE THE FILE, measured: an ext_resource nothing USES is tolerated -- Godot
# prints the load error and carries on. So a caller reporting these must say the file REFERENCES
# them, never that it lost them.
static func missing_references(path: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in FileAccess.get_file_as_string(path).split("
"):
		if not line.begins_with("[ext_resource"):
			continue
		var target := DevWidgets._quoted_attr(line, "path")
		if target != "" and not ResourceLoader.exists(target):
			out.append(target)
	return out

# Repairs every referenced file that EXISTS but will not load. True if any of them came back.
static func _repair_children(path: String, kept: Array[Resource]) -> bool:
	if _visiting.has(path):
		return false
	_visiting[path] = true
	var repaired := false
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		var target := DevWidgets._quoted_attr(line, "path")
		if target == "" or target == path or not FileAccess.file_exists(target):
			continue   # absent targets are this file's OWN damage, stripped by _repair below
		if DevWidgets._quoted_attr(line, "type") == "Script":
			continue
		if ResourceLoader.load(target) != null:
			continue   # loads fine; not what is breaking us
		var child := load_tolerant(target)
		if child != null:
			kept.append(child)
			repaired = true
	_visiting.erase(path)
	return repaired


# What this path lost, or an empty array. Keyed by path rather than carried on the resource: a
# `set_meta` marker would SERIALIZE into the .tres as metadata/, writing the repair into the file
# it exists to protect.
static func dropped_properties(path: String) -> Array[String]:
	if not _repairs.has(path):
		return []
	var record: Dictionary = _repairs[path]
	return record.get("properties", [] as Array[String])


static func missing_targets(path: String) -> Array[String]:
	if not _repairs.has(path):
		return []
	var record: Dictionary = _repairs[path]
	return record.get("missing", [] as Array[String])


static func repaired_paths() -> Array[String]:
	var paths: Array[String] = []
	for key in _repairs:
		paths.append(key)
	return paths


static func forget(path: String) -> void:
	_repairs.erase(path)


# ==============================================================================
#  The repair
# ==============================================================================

# Refuses rather than guesses in two cases. A file broken for some reason OTHER than a dangling
# reference gets no repaired copy -- we would be pretending to fix something we have not diagnosed.
# And a missing SCRIPT is a code fault, not content: stripping it would change what the resource IS,
# so that one stays as loud as it was.
static func _repair(path: String) -> Resource:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var dangling := _dangling(text)
	if dangling.is_empty():
		return null

	var properties: Array[String] = []
	var repaired := _without(text, dangling, properties)
	DirAccess.make_dir_recursive_absolute(REPAIR_DIR)
	var temp := REPAIR_DIR + path.md5_text() + ".tres"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		push_error("ContentRepair cannot write %s" % temp)
		return null
	f.store_string(repaired)
	f.close()

	var res: Resource = ResourceLoader.load(temp, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		return null   # the strip did not produce something loadable; do not claim a repair

	# It must identify as the REAL file. Without this every dev tool would write its edits into
	# user://__repaired/ and the actual content would never get fixed -- the opposite of the point.
	res.take_over_path(path)

	var missing: Array[String] = []
	for id in dangling:
		missing.append(dangling[id])
	_repairs[path] = {"missing": missing, "properties": properties}
	push_warning("%s loaded degraded -- lost %s (missing: %s)"
		% [path, ", ".join(properties), ", ".join(missing)])
	return res


# id -> missing target, over the ext_resource lines whose file is gone. Attribute reading is
# DevWidgets' (#481) rather than a third copy of it in this repo; it is dev-owned today only
# because that is where the uid work needed it first.
static func _dangling(text: String) -> Dictionary:
	var found := {}
	for line: String in text.split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		var target := DevWidgets._quoted_attr(line, "path")
		if target == "" or FileAccess.file_exists(target):
			continue
		if DevWidgets._quoted_attr(line, "type") == "Script":
			return {}
		found[DevWidgets._quoted_attr(line, "id")] = target
	return found


# The same text with every dangling reference taken out, and the names of what it cost appended to
# `properties` -- that list is the whole reason a repair is not a silent success.
static func _without(text: String, dangling: Dictionary, properties: Array[String]) -> String:
	var kept: Array[String] = []
	for line: String in text.split("\n"):
		if line.begins_with("[ext_resource") and dangling.has(DevWidgets._quoted_attr(line, "id")):
			continue
		var out := line
		for id in dangling:
			out = _strip(out, str(id), properties)
			if out == "":
				break
		if out == "" and line != "":
			continue   # the reference WAS the whole property; let it fall back to its default
		kept.append(out)
	return "\n".join(kept)


static func _strip(line: String, id: String, properties: Array[String]) -> String:
	var token := 'ExtResource("%s")' % id
	if not line.contains(token):
		return line
	var eq := line.find(" = ")
	if eq > 0:
		var name := line.substr(0, eq).strip_edges()
		if not properties.has(name):
			properties.append(name)
		if line.substr(eq + 3).strip_edges() == token:
			return ""
	# One element of a collection: take it out, then tidy the separators it leaves behind.
	return line.replace(token + ", ", "").replace(", " + token, "").replace(token, "") \
		.replace("([, ", "([").replace(", ])", "])")
