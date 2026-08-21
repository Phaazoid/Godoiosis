# Dialogic's registries in project.godot are the ONE thing that turns a name into a resource
# (#447): a timeline line reads `torv: ...` and `dch_directory` is what makes that Torv. Empty
# them and `get_character_resource` returns null, so `event_text.get_or_create_character`
# fabricates a throwaway character -- the prolog's speaker loses its display name, its colour
# and its portrait, while every other test stays green.
#
# A headless `--import` used to prune both registries to {} and save over the committed file,
# so a wipe was one `git add -A` away from shipping. Fixed at source in DialogicResourceUtil
# (see CLAUDE.md), but the addon is vendored -- an upgrade can drop that patch silently, and
# this suite is what catches the result before it merges.
#
# A failure here is fixed by RESTORING the file -- `git checkout -- project.godot` -- never by
# editing this suite. If a registry is legitimately empty, the dialog content is gone with it.
extends GdUnitTestSuite

const PROJECT_FILE := "res://project.godot"

# Extension -> what a missing entry costs, for the failure message.
const REGISTRIES := {
	"dch": "characters (a speaker loses its name, colour and portrait)",
	"dtl": "timelines (the dev-tools timeline picker goes empty)",
}


# THE COMMITTED FILE, deliberately not DialogicResourceUtil.get_directory() -- measured, not
# assumed. The running process REPAIRS the registry as a side effect of using it: parsing a
# timeline re-registers the characters it names, so a live read is circular. Falsified
# 2026-08-21 -- against a totally wiped project.godot, a live read passed every case here.
# The committed file is also the only surface that answers the question this suite asks, since
# the wipe is a thing that gets COMMITTED rather than anything the runtime ever sees.
func _committed_registry(extension: String) -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(PROJECT_FILE)
	assert_int(err) \
		.override_failure_message("could not read %s -- this suite cannot check anything" % PROJECT_FILE) \
		.is_equal(OK)
	var stored: Variant = config.get_value("dialogic", "directories/%s_directory" % extension, {})
	return stored if stored is Dictionary else {}


# Dialogic's own scanner, deliberately NOT ResourceDir (#141). The registry has to be compared
# against the same filesystem truth `update_directory` registers from; a second listing could
# disagree with what Dialogic actually writes. Being a plain DirAccess walk, it has nothing to
# repair, so the caveat above does not apply to it.
func _files_on_disk(extension: String) -> Array:
	return DialogicResourceUtil.list_resources_of_type("." + extension)


func test_both_registries_are_populated() -> void:
	for extension: String in REGISTRIES:
		assert_int(_committed_registry(extension).size()) \
			.override_failure_message("dialogic/directories/%s_directory is EMPTY in project.godot -- %s. Restore it with `git checkout -- project.godot` (#447)."
				% [extension, REGISTRIES[extension]]) \
			.is_greater(0)


func test_every_registered_path_points_at_a_file_that_exists() -> void:
	# FileAccess, not ResourceLoader: the .dch/.dtl format loaders are absent in some headless
	# contexts, and that wrong predicate is exactly what caused #447 -- do not reintroduce it.
	for extension: String in REGISTRIES:
		var registry: Dictionary = _committed_registry(extension)
		for identifier: String in registry:
			var path: String = str(registry[identifier])
			assert_bool(FileAccess.file_exists(path)) \
				.override_failure_message("%s_directory maps '%s' to '%s', which is not on disk"
					% [extension, identifier, path]) \
				.is_true()


func test_every_dialog_file_on_disk_is_registered() -> void:
	for extension: String in REGISTRIES:
		var registered: Array = _committed_registry(extension).values()
		var found: Array = _files_on_disk(extension)
		assert_int(found.size()) \
			.override_failure_message("no .%s files found at all -- the scan is broken, so this case would pass vacuously"
				% extension) \
			.is_greater(0)
		for path: Variant in found:
			assert_bool(registered.has(path)) \
				.override_failure_message("%s exists but is not in %s_directory -- nothing can reach it by name"
					% [path, extension]) \
				.is_true()


func test_every_speaker_in_a_timeline_is_a_registered_character() -> void:
	# The wire the registry exists to carry, and the one case that also catches an authoring
	# typo. Parsed through Dialogic's own text parser rather than a second one here -- via
	# from_text() rather than load(), because the .dtl format loader is absent headlessly.
	var characters: Dictionary = _committed_registry("dch")
	var checked := 0
	for path: Variant in _files_on_disk("dtl"):
		var timeline := DialogicTimeline.new()
		timeline.from_text(FileAccess.get_file_as_string(path))
		timeline.process()
		for event: Variant in timeline.events:
			if not event is DialogicTextEvent:
				continue
			var text_event := event as DialogicTextEvent
			# The event's OWN regex against its OWN raw line, which is the only reading of the
			# speaker with no registry in it. `character_identifier` cannot be used: outside the
			# editor its backing field is never set, and its getter answers from the resolved
			# character, which derives its name by finding its path in the LIVE registry -- so
			# it would compare the registry with itself.
			var parsed: RegExMatch = text_event.regex.search(text_event.event_node_as_text)
			var speaker: String = parsed.get_string("name") if parsed != null else ""
			if speaker.is_empty() or speaker.begins_with("{"):
				continue   # narration, or an expression resolved at runtime
			checked += 1
			assert_bool(characters.has(speaker)) \
				.override_failure_message("%s speaks as '%s', which no character in dch_directory answers to"
					% [path, speaker]) \
				.is_true()
	assert_int(checked) \
		.override_failure_message("no speaker lines parsed out of any timeline -- this case would pass vacuously") \
		.is_greater(0)
