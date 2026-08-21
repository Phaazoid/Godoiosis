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

# Extension -> what a missing entry costs, for the failure message.
const REGISTRIES := {
	"dch": "characters (a speaker loses its name, colour and portrait)",
	"dtl": "timelines (the dev-tools timeline picker goes empty)",
}


# The addon's own accessor -- every production lookup resolves through it, so the law reads the
# same dictionary the game does rather than re-reading ProjectSettings beside it.
func _registry(extension: String) -> Dictionary:
	return DialogicResourceUtil.get_directory(extension)


# The addon's own scanner, deliberately NOT ResourceDir (#141). This has to compare the registry
# against the same filesystem truth `update_directory` registers from; a second listing could
# disagree with what Dialogic actually writes, and then the law would police its own answer.
func _files_on_disk(extension: String) -> Array:
	return DialogicResourceUtil.list_resources_of_type("." + extension)


func test_both_registries_are_populated() -> void:
	for extension: String in REGISTRIES:
		assert_int(_registry(extension).size()) \
			.override_failure_message("dialogic/directories/%s_directory is EMPTY in project.godot -- %s. Restore it with `git checkout -- project.godot` (#447)."
				% [extension, REGISTRIES[extension]]) \
			.is_greater(0)


func test_every_registered_path_points_at_a_file_that_exists() -> void:
	# FileAccess, not ResourceLoader: the .dch/.dtl format loaders are not registered in a
	# headless run, so `ResourceLoader.exists` is false for every one of them here. That wrong
	# predicate is what caused #447 in the first place -- do not reintroduce it.
	for extension: String in REGISTRIES:
		var registry: Dictionary = _registry(extension)
		for identifier: String in registry:
			var path: String = str(registry[identifier])
			assert_bool(FileAccess.file_exists(path)) \
				.override_failure_message("%s_directory maps '%s' to '%s', which is not on disk"
					% [extension, identifier, path]) \
				.is_true()


func test_every_dialog_file_on_disk_is_registered() -> void:
	for extension: String in REGISTRIES:
		var registered: Array = _registry(extension).values()
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
	# The wire the registry exists to carry. Parsed through Dialogic's own text parser rather
	# than a second one here -- and via from_text() rather than load(), because the .dtl format
	# loader is absent headlessly (see above).
	var characters: Dictionary = _registry("dch")
	var checked := 0
	for path: Variant in _files_on_disk("dtl"):
		var timeline := DialogicTimeline.new()
		timeline.from_text(FileAccess.get_file_as_string(path))
		timeline.process()
		for event: Variant in timeline.events:
			if not event is DialogicTextEvent:
				continue
			var speaker: String = (event as DialogicTextEvent).character_identifier
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
