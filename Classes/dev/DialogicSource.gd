extends Object
class_name DialogicSource

# Creating, registering and removing a Dialogic resource from the RUNNING dev overlay (#982) --
# the half Dialogic's own editor owns and a game process cannot reach. DialogTool is the only
# caller; nothing here touches the tree, a page or a board.
#
# REGISTRATION IS OURS BECAUSE DIALOGIC'S IS EDITOR-ONLY: DialogicResourceUtil.set_directory
# writes project.godot only under Engine.is_editor_hint(), which is false in the running game.
# So register() writes THREE stores in one call -- the committed file, the live ProjectSettings
# the picker reads, and the Engine meta Dialogic caches a directory in on first read. A writer
# that updates fewer leaves the picker stale for the rest of the session.
#
# ENTRIES APPEND, NEVER SORT. plugin.gd's _build() runs DialogicResourceUtil.update() on every
# editor Play, against the editor's own stale in-memory copy: it scans, finds the new file and
# APPENDS it. Matching that order makes the editor's next save byte-identical, so the file does
# not churn -- and it means a registration written while the editor was open self-heals the
# moment the dev presses Play.

const SETTINGS_PATH := "res://project.godot"
const TIMELINE_DIR := "res://Scenarios/dialog"
const CHARACTER_DIR := "res://Scenarios/dialog/characters"
const SCENARIO_DIR := "res://Scenarios/missions"
const NARRATION := ""   # the speaker an unnamed line carries, which the law suite permits

# One registry line, as Godot emits it. A path cannot hold a quote, so this is total.
static var _entry_regex := RegEx.create_from_string('"(?<name>[^"]*)"\\s*:\\s*"(?<path>[^"]*)"')


# --- reading ---

# The live registry for an extension ("dtl"/"dch"), name -> path. ProjectSettings rather than
# DialogicResourceUtil: its getter caches into Engine meta, and a caller here wants the store
# register() actually wrote, not a cache that may predate it.
static func directory(extension: String) -> Dictionary:
	return ProjectSettings.get_setting("dialogic/directories/%s_directory" % extension, {})


static func timeline_path(name: String) -> String:
	return "%s/%s.dtl" % [TIMELINE_DIR, name]


static func character_path(name: String) -> String:
	return "%s/%s.dch" % [CHARACTER_DIR, name]


# --- timeline text ---

# Lines are [{speaker, text}] -- speaker NARRATION for an unnamed line. Serialized through real
# DialogicTextEvents rather than "%s: %s", which is not a style preference: the parser's name
# group runs to the first UNESCAPED colon, so "Look: the bridge" would come back as a speaker
# named Look, fabricate a throwaway character at runtime and red the law suite. to_text() is
# what escapes it (and what prefixes a line that would otherwise parse as another event).
static func timeline_text(lines: Array) -> String:
	var out := PackedStringArray()
	for line: Dictionary in lines:
		var event := DialogicTextEvent.new()
		var speaker := String(line.get("speaker", NARRATION))
		if speaker != NARRATION:
			event.character = DialogicResourceUtil.get_character_resource(speaker)
		event.text = String(line.get("text", ""))
		out.append(event.to_text())
	return "\n".join(out)


# {lines, editable, reason}. EDITABLE IS THE ROUND-TRIP GUARD: this page owns the "speaker: line"
# shape and Dialogic's tab owns everything else, so a timeline this cannot re-emit unchanged must
# be refused rather than silently flattened on save. A speaker no .dch answers to counts as not
# editable on purpose -- from_text() FABRICATES a character for one, and re-saving a fabrication
# would write the invention to disk.
static func read_timeline(timeline: DialogicTimeline) -> Dictionary:
	if timeline == null:
		return {"lines": [], "editable": false, "reason": "There is no timeline here."}
	timeline.process()
	var registered := directory("dch")
	var lines: Array[Dictionary] = []
	for event: Variant in timeline.events:
		if not event is DialogicTextEvent:
			return _refused("it holds a %s event" % _event_name(event))
		var text_event := event as DialogicTextEvent
		if not text_event.portrait.is_empty():
			return _refused("a line sets a portrait")
		if "\n" in text_event.text:
			return _refused("a line spans more than one line of text")
		# The event's OWN regex against its OWN raw line -- the one reading of the speaker with
		# no registry in it. character_identifier resolves THROUGH the registry, so using it here
		# would compare the registry with itself (the #447 shape, same reason the law suite does).
		var parsed: RegExMatch = text_event.regex.search(text_event.event_node_as_text)
		var speaker: String = ""
		if parsed != null:
			speaker = parsed.get_string("name").strip_edges()
		if speaker.begins_with("{"):
			return _refused("a line names its speaker with an expression")
		if speaker != NARRATION and not registered.has(speaker):
			return _refused("'%s' is not a character in dch_directory" % speaker)
		lines.append({"speaker": speaker, "text": text_event.text})
	return {"lines": lines, "editable": true, "reason": ""}


static func _refused(reason: String) -> Dictionary:
	return {"lines": [], "editable": false,
		"reason": "Edit this one in Dialogic's tab -- %s, which this page cannot write back." % reason}


static func _event_name(event: Variant) -> String:
	if event is DialogicEvent:
		return String((event as DialogicEvent).event_name)
	return "non-text"


# --- characters ---

# A .dch MINTED FROM THE CAST, so who a character is has one source: display name and portrait
# come off the UnitData, and colour is the one thing a speaker authors that a unit has no opinion
# on. Derived artifact, never a second character editor.
static func character_from_cast(unit_data: UnitData, color: Color) -> DialogicCharacter:
	var character := DialogicCharacter.new()
	character.display_name = unit_data.display_name
	character.color = color
	character.default_portrait = "default"
	if unit_data.portrait != null:
		character.portraits = {"default": {"image": unit_data.portrait.resource_path}}
	return character


static func identifier_for(display_name: String) -> String:
	return display_name.strip_edges().to_snake_case()


# --- writing ---

# Written exactly as CharacterResourceSaver does it -- the format is the addon's, not ours.
static func write_character(character: DialogicCharacter, path: String) -> bool:
	return write(path, var_to_str(inst_to_dict(character)))


# The file AND its .uid sidecar, which is not a nicety: CI's sidecar guard FAILS on an
# uncommitted .uid, and Godot mints one for every .dtl/.dch it imports -- so without this,
# create-commit-push reds the PR on a file the dev never saw.
static func write(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("DialogicSource: cannot write %s (%s)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	return _ensure_uid(path)


static func _ensure_uid(path: String) -> bool:
	var uid_path := path + ".uid"
	if FileAccess.file_exists(uid_path):
		return true
	var id := ResourceLoader.get_resource_uid(path)
	if id == ResourceUID.INVALID_ID:
		id = ResourceUID.create_id()
	if ResourceUID.has_id(id):
		ResourceUID.set_id(id, path)
	else:
		ResourceUID.add_id(id, path)
	var file := FileAccess.open(uid_path, FileAccess.WRITE)
	if file == null:
		push_error("DialogicSource: cannot write %s (%s)" % [uid_path, FileAccess.get_open_error()])
		return false
	file.store_line(ResourceUID.id_to_text(id))
	file.close()
	return true


# --- the registry block ---

# Where `directories/<ext>_directory={...}` sits in the committed text, as [start, end). A path
# cannot hold a brace, so the first `}` after the opening one closes it.
static func _block_range(source: String, extension: String) -> Vector2i:
	var key := "directories/%s_directory=" % extension
	var start := source.find(key)
	if start == -1:
		return Vector2i(-1, -1)
	var open_brace := source.find("{", start)
	if open_brace == -1:
		return Vector2i(-1, -1)
	var close_brace := source.find("}", open_brace)
	if close_brace == -1:
		return Vector2i(-1, -1)
	return Vector2i(start, close_brace + 1)


static func _parse_entries(block: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for found: RegExMatch in _entry_regex.search_all(block):
		entries.append({"name": found.get_string("name"), "path": found.get_string("path")})
	return entries


# Godot's own emission, byte for byte: `={` newline, entries joined by `,` newline, newline `}`.
# An empty directory is `={}` on one line, which is how project.godot carries style_directory.
static func _emit_block(extension: String, entries: Array[Dictionary]) -> String:
	var key := "directories/%s_directory=" % extension
	if entries.is_empty():
		return key + "{}"
	var lines := PackedStringArray()
	for entry: Dictionary in entries:
		lines.append('"%s": "%s"' % [entry["name"], entry["path"]])
	return key + "{\n" + ",\n".join(lines) + "\n}"


# APPENDS -- see the header. "" means refused: no such block, or the name is taken (a collision
# is the caller's to report, never a silent overwrite of somebody else's timeline).
static func insert_entry(source: String, extension: String, name: String, path: String) -> String:
	var span := _block_range(source, extension)
	if span.x == -1:
		return ""
	var entries := _parse_entries(source.substr(span.x, span.y - span.x))
	for entry: Dictionary in entries:
		if String(entry["name"]) == name:
			return ""
	entries.append({"name": name, "path": path})
	return source.substr(0, span.x) + _emit_block(extension, entries) + source.substr(span.y)


static func remove_entry(source: String, extension: String, name: String) -> String:
	var span := _block_range(source, extension)
	if span.x == -1:
		return ""
	var entries := _parse_entries(source.substr(span.x, span.y - span.x))
	var kept: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if String(entry["name"]) != name:
			kept.append(entry)
	if kept.size() == entries.size():
		return ""
	return source.substr(0, span.x) + _emit_block(extension, kept) + source.substr(span.y)


# --- registration: the three stores, in one place ---

static func register(extension: String, name: String, path: String,
		settings_path := SETTINGS_PATH) -> bool:
	var source := _read(settings_path)
	if source == "":
		return false
	var rewritten := insert_entry(source, extension, name, path)
	if rewritten == "" or not _write_text(settings_path, rewritten):
		return false
	_adopt(extension, name, path)
	return true


static func unregister(extension: String, name: String, settings_path := SETTINGS_PATH) -> bool:
	var source := _read(settings_path)
	if source == "":
		return false
	var rewritten := remove_entry(source, extension, name)
	if rewritten == "" or not _write_text(settings_path, rewritten):
		return false
	_disown(extension, name)
	return true


# The two LIVE stores. ProjectSettings is what directory() and the pickers read; the Engine meta
# is Dialogic's own cache, populated on its first get_directory() and never re-read after.
static func _adopt(extension: String, name: String, path: String) -> void:
	var live: Dictionary = directory(extension).duplicate()
	live[name] = path
	ProjectSettings.set_setting("dialogic/directories/%s_directory" % extension, live)
	Engine.set_meta("%s_directory" % extension, live.duplicate())


static func _disown(extension: String, name: String) -> void:
	var live: Dictionary = directory(extension).duplicate()
	live.erase(name)
	ProjectSettings.set_setting("dialogic/directories/%s_directory" % extension, live)
	Engine.set_meta("%s_directory" % extension, live.duplicate())


# --- deleting ---

# Every committed file that names this resource BY PATH. A mission holds its timeline as an
# ext_resource path, so deleting a referenced one turns that mission into a dangling ext_resource
# -- a hard parse error that kills the WHOLE .tres, not a degraded load. Text scan rather than
# load(): a mission that already fails to parse still has to be reported, not skipped.
#
# `scan_dir` overrides WHERE to look, and exists so a case exercising the refusal can stand up
# its own referrer instead of aiming a delete at shipped content -- which is not hypothetical:
# the mutant proving this guard has teeth removed causeway_intro.dtl the first time it ran.
static func referencing_files(extension: String, name: String, scan_dir := "") -> PackedStringArray:
	var path := String(directory(extension).get(name, ""))
	var found := PackedStringArray()
	if path == "":
		return found
	var dir := SCENARIO_DIR if extension != "dch" else TIMELINE_DIR
	var suffix := ".tres" if extension != "dch" else ".dtl"
	if scan_dir != "":
		dir = scan_dir
	for file: String in ResourceDir.files_with_extension(dir, suffix):
		var full := "%s/%s" % [dir, file]
		if path in FileAccess.get_file_as_string(full):
			found.append(full)
	return found


# {ok, reason}. Removes file, sidecar and registry entry, or refuses and names what stands in
# the way -- the caller shows the reason rather than guessing at one.
static func delete(extension: String, name: String, settings_path := SETTINGS_PATH,
		scan_dir := "") -> Dictionary:
	var path := String(directory(extension).get(name, ""))
	if path == "":
		return {"ok": false, "reason": "'%s' is not in the registry." % name}
	var blockers := referencing_files(extension, name, scan_dir)
	if not blockers.is_empty():
		var shown := PackedStringArray()
		for blocker: String in blockers:
			shown.append(blocker.get_file())
		return {"ok": false,
			"reason": "'%s' is still used by %s -- deleting it would break them." % [name, ", ".join(shown)]}
	if not unregister(extension, name, settings_path):
		return {"ok": false, "reason": "Could not take '%s' out of the registry." % name}
	DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + ".uid"):
		DirAccess.remove_absolute(path + ".uid")
	return {"ok": true, "reason": ""}


# --- small shared pieces ---

static func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DialogicSource: cannot read %s (%s)" % [path, FileAccess.get_open_error()])
		return ""
	var text := file.get_as_text()
	file.close()
	return text


static func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("DialogicSource: cannot write %s (%s)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	return true
