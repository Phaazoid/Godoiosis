# #1343: DevWidgets.save_over keeps the [sub_resource] ids the file it overwrites already uses.
#
# The text saver seeds its id generator from the save PATH and draws an id for every sub-resource that
# carries none -- which is everything save_over writes, since capture_scenario builds fresh objects
# and _adopt copies through duplicate(true). So an id held only while the number of draws did: a file
# whose ids were drawn anywhere else renumbered on its first Update (every committed mission, 329-694
# lines), and one new reference renumbered every id after it.
#
# A save to the SAME path with NO change draws the same ids again and passes with or without the fix,
# so each case stages one of the two real ways the draws move: a different path (a different seed),
# and a new ext_resource (an earlier draw). The boards are built here, shaped like a capture (entries
# holding an inline UnitData and an inline StatEffect array), and written only under user://.
extends GdUnitTestSuite

const FIRST := "user://__test_sub_ids_a.tres"
const COPY := "user://__test_sub_ids_b.tres"
const EXTRA := "user://__test_sub_ids_extra.tres"

# The loaded file, held so its path stays CACHED: save_over then writes through _adopt, the route a
# loaded mission's Update takes.
var _held: Resource


func after_test() -> void:
	_held = null
	for path: String in [FIRST, COPY, EXTRA]:
		var uid: String = DevWidgets.uid_map_in_file(path).get("_header", "")
		if uid != "" and ResourceUID.has_id(ResourceUID.text_to_id(uid)):
			ResourceUID.remove_id(ResourceUID.text_to_id(uid))
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# A fresh board every call, the way capture_scenario builds one: same values, no ids.
func _board(entries: int) -> ScenarioData:
	var scenario := ScenarioData.new()
	scenario.scenario_name = "__sub_ids"
	for i in entries:
		var entry := ScenarioUnitEntry.new()
		entry.cell = Vector2i(i, 0)
		entry.unit_data = UnitData.new()
		entry.unit_data.display_name = "Unit %d" % i
		var effect := StatEffect.new()
		effect.source_name = "effect %d" % i
		entry.stat_effects.append(effect)
		scenario.unit_entries.append(entry)
	return scenario


func _copy(from: String, to: String) -> void:
	var f := FileAccess.open(to, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(from))
	f.close()


func _sub_ids(text: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in text.split("\n"):
		if line.begins_with("[sub_resource"):
			out.append(line.get_slice(' id="', 1).get_slice('"', 0))
	return out


func test_an_unchanged_save_keeps_every_sub_resource_id_whoever_drew_them() -> void:
	assert_bool(DevWidgets.save_over(_board(3), FIRST)).is_true()
	_copy(FIRST, COPY)   # ids drawn under FIRST's seed, now in a file whose own seed would draw others
	var before := FileAccess.get_file_as_string(COPY)
	assert_int(_sub_ids(before).size()).override_failure_message(
			"the board serialized no sub-resources, so this case would prove nothing").is_equal(9)
	_held = load(COPY)

	assert_bool(DevWidgets.save_over(_board(3), COPY)).is_true()

	assert_str(FileAccess.get_file_as_string(COPY)).is_equal(before)


func test_a_new_reference_does_not_renumber_the_ids_before_it() -> void:
	assert_bool(DevWidgets.save_over(_board(3), COPY)).is_true()
	var before := _sub_ids(FileAccess.get_file_as_string(COPY))
	_held = load(COPY)
	assert_int(ResourceSaver.save(UnitData.new(), EXTRA)).is_equal(OK)
	var edited := _board(3)
	var cast := ScenarioUnitEntry.new()   # a reference entry: a new ext_resource, which draws FIRST
	cast.unit_data = load(EXTRA)
	cast.state_saved = false
	cast.cell = Vector2i(9, 0)
	edited.unit_entries.append(cast)

	assert_bool(DevWidgets.save_over(edited, COPY)).is_true()

	var text := FileAccess.get_file_as_string(COPY)
	assert_str(text).contains('path="%s"' % EXTRA)   # the edit really added a reference
	var after := _sub_ids(text)
	assert_int(after.size()).is_equal(before.size() + 1)
	assert_array(after.slice(0, before.size())).is_equal(before)


# The two rules that keep a carry from breaking a file or another file's content: an id a
# sub-resource already holds is never overwritten, and an id in use is never handed out again.
# The path is NOT held cached here, so save_over writes `edited` itself (the live-object route the
# family and template editors take) and the id set on it reaches the saver; _adopt would copy it away.
func test_a_held_id_is_neither_overwritten_nor_handed_out_twice() -> void:
	assert_bool(DevWidgets.save_over(_board(2), COPY)).is_true()
	var prior := ResourceLoader.load(COPY, "", ResourceLoader.CACHE_MODE_IGNORE) as ScenarioData
	var first_id: String = prior.unit_entries[0].get_scene_unique_id()
	assert_str(first_id).is_not_empty()
	var edited := _board(2)
	edited.unit_entries[1].set_scene_unique_id(first_id)   # the SECOND entry already holds the first's id

	assert_bool(DevWidgets.save_over(edited, COPY)).is_true()

	var text := FileAccess.get_file_as_string(COPY)
	var ids := _sub_ids(text)
	var unique := {}
	for id in ids:
		unique[id] = true
	assert_int(unique.size()).is_equal(ids.size())
	var saved := ResourceLoader.load(COPY, "", ResourceLoader.CACHE_MODE_IGNORE) as ScenarioData
	assert_str(saved.unit_entries[1].get_scene_unique_id()).is_equal(first_id)
	assert_str(saved.unit_entries[0].get_scene_unique_id()).is_not_equal(first_id)
